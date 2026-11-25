-- =============================================================================
-- 第四步（加固）：价目表 AI 的用量和占位、卡住的导入、通知放回队列
-- 规格见 docs/04-seller-spec.md 第 2.5、2.6、2.8、3 节。
--
--   A. price_list_runs：parse-price-list 每跑一次记一笔（只有服务器碰得到，批发商删不掉、改不了）
--   B. reserve_price_list_run（服务器）：成员、停权、状态、在跑、用量都在一个交易里检查完再占位
--      （取代以前放在 Storage 的用量记录，和 Edge Function 自己做的「有条件 PATCH」占位）。
--      用量按批发商算，也按「人」算（叫的人、建这家批发商的人），所以一直注册新的批发商也没有多的用量；
--      register_wholesaler 也改成一个人同时只能有一家待审核的
--   C. price_list_imports 的保护：批发商只能新增 processing 的导入、只能把 processing 标成 failed
--   D. fail_stuck_price_list_imports（服务器 / 定时任务）：卡在 processing 的导入标成失败
--   E. 通知：领的时候记下是哪个 dispatcher 领的（claim id），release_notification（放回队列）、
--      complete_notification 要对得上才改
--   F. 定时任务（有 pg_cron 才建）
--   G. 函数权限
-- =============================================================================

-- =============================================================================
-- A. price_list_runs
-- =============================================================================

create table public.price_list_runs (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  import_id uuid references public.price_list_imports (id) on delete set null,
  run_id uuid not null unique,
  user_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index price_list_runs_wholesaler_idx on public.price_list_runs (wholesaler_id, created_at desc);
create index price_list_runs_user_idx on public.price_list_runs (user_id, created_at desc);
create index price_list_runs_import_idx on public.price_list_runs (import_id);
-- 「同一个人建的批发商」加起来算用量（reserve_price_list_run）、一个人只能有一家待审核的（register_wholesaler）
create index wholesalers_created_by_idx on public.wholesalers (created_by);
comment on table public.price_list_runs is
  'parse-price-list 每跑一次记一笔，用来算用量（reserve_price_list_run 写）。只给服务器：开了 RLS、没有规则';
comment on column public.price_list_runs.run_id is '这一次跑的 id（ai_raw.run_id 也是它）';
comment on column public.price_list_runs.user_id is '谁叫的（App 登录的人；用量也按这个人算）';

-- 只给服务器：开 RLS、不写规则，再把权限收回（Supabase 默认会开放给 anon / authenticated）
alter table public.price_list_runs enable row level security;
revoke all on table public.price_list_runs from public, anon, authenticated;

-- =============================================================================
-- B. 价目表 AI：用量和占位
-- =============================================================================

-- 用量限制（每段时间最多跑几次）。要改数字就改这里，Edge Function 不再自己算。
-- 每家批发商各算各的，每个「人」也一样（见 reserve_price_list_run）：上限都照这家批发商的状态。
--   burst = 10 分钟（一次最多跑大约 400 秒，这个数字差不多就是同时在跑的上限）、hour = 1 小时、day = 1 天
--   active（审核通过）：3 / 10 / 30
--   pending（还没审核）：2 / 4 / 8
--   其他状态（suspended 停权）：没有限制可用 = 不能跑（reserve_price_list_run 回 suspended）
create or replace function public._price_list_run_limits(p_status public.wholesaler_status)
returns table (window_name text, window_len interval, max_runs int)
language sql
immutable
set search_path = ''
as $$
  select w.window_name, w.window_len,
         case p_status when 'active' then w.active_max else w.pending_max end
  from (values
    ('burst', interval '10 minutes', 3, 2),
    ('hour', interval '1 hour', 10, 4),
    ('day', interval '1 day', 30, 8)
  ) as w(window_name, window_len, active_max, pending_max)
  where p_status in ('active', 'pending')
  order by w.window_len;
$$;

-- ai_raw 里的时间（文字）→ timestamptz；不是正确的时间就回 null（一行坏资料不会让整个函数出错）
create or replace function public._try_timestamptz(p_text text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  return p_text::timestamptz;
exception when others then
  return null;
end;
$$;

-- parse-price-list 开始跑之前调用（p_user_id = 验过 JWT 的用户，p_run_id = 这一次的新 id）。
-- 一个交易里按顺序检查，第一个不符合的就回传（都不改任何东西）：
--   {"result":"not_found"}                         没有这份导入
--   {"result":"not_member"}                        p_user_id 不是这家批发商的成员（owner / staff），也不是客服
--                                                  （跟 price_list_imports 的 RLS 一样：成员看得到自己的，客服看得到全部）
--   {"result":"suspended"}                         批发商停权（只有 active、pending 可以跑）；
--                                                  或者「人」是某一家停权批发商的老板、或是建那一家的人
--   {"result":"not_processing","status":"review"}  导入已经不是 processing
--   {"result":"already_running"}                   有人在跑（ai_raw.state = running，claimed_at 10 分钟内）；
--                                                  超过 10 分钟的当成死掉了，可以重新占位
--   {"result":"quota","window":"burst|hour|day","retry_after_sec":N}
--                                                  用量满了（price_list_runs 算，限制见 _price_list_run_limits）。
--                                                  N = 要等几秒才有位置（至少 1）；几段都满的话回传要等最久的那一段，
--                                                  等 N 秒后再叫就不会被另一段挡住
-- 「人」= 叫的人（p_user_id）和建这家批发商的人（wholesalers.created_by）；客服不算（客服替很多家操作）。
-- 用量有三份，每一份、每一段时间各算各的，上限都照这家批发商的状态，哪一份满了都不能跑：
--   这家批发商跑了几次、叫的人（在每一家批发商）跑了几次、建这家批发商的人建的每一家加起来跑了几次。
-- 所以一个人一直注册新的批发商（register_wholesaler），也不会多出用量；停权的老板注册一家新的也不能跑。
-- 都通过：占位（ai_raw = {version:1, state:running, run_id, claimed_at, claimed_by}，error_message 清掉）、
-- 记一笔 price_list_runs，回传
--   {"result":"ok","run_id","claimed_at","wholesaler_id","wholesaler_status","import_id","file_path","file_type"}
-- 之后 Edge Function 写回结果时要用 run_id 过滤（.eq("ai_raw->>run_id", run_id)），claimed_at 照这里回传的写回 ai_raw。
-- 同时进来的请求会排队（一个一个数，所以不会多放）：同一个人的在 advisory lock 排，同一家批发商的在批发商那一行排。
-- p_run_id 是空的 → INVALID_RUN_ID；用过的 → RUN_ID_USED。
create or replace function public.reserve_price_list_run(p_import_id uuid, p_user_id uuid, p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_wholesaler_id uuid;
  v_creator uuid;
  v_user_scope uuid;
  v_creator_scope uuid;
  v_key bigint;
  v_w public.wholesalers%rowtype;
  v_import public.price_list_imports%rowtype;
  v_claimed_at timestamptz;
  l record;
  v_wait int;
  v_window text;
  v_retry int;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if p_run_id is null then
    raise exception 'INVALID_RUN_ID' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.price_list_runs r where r.run_id = p_run_id) then
    raise exception 'RUN_ID_USED' using errcode = 'P0001';
  end if;

  select i.wholesaler_id, w.created_by into v_wholesaler_id, v_creator
  from public.price_list_imports i
  join public.wholesalers w on w.id = i.wholesaler_id
  where i.id = p_import_id;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- 「人」：叫的人、建这家批发商的人（客服、没有记录的不算）
  select p.id into v_user_scope from public.profiles p where p.id = p_user_id and p.role <> 'admin';
  select p.id into v_creator_scope from public.profiles p where p.id = v_creator and p.role <> 'admin';

  -- 排队：先锁「人」（同一个人同时在几家批发商叫，批发商那一行挡不住；advisory lock 按数字从小到大锁，
  -- 不会互相等到死锁），再锁批发商那一行（同一家同时进来的几个请求排队，一个一个数用量），最后锁这份导入。
  for v_key in
    select distinct pg_catalog.hashtextextended('public.price_list_runs:' || x::text, 0)
    from unnest(array[v_user_scope, v_creator_scope]) as t(x)
    where x is not null
    order by 1
  loop
    perform pg_catalog.pg_advisory_xact_lock(v_key);
  end loop;
  -- 批发商用 for no key update（不是 for update）：一样会互相排队，但不会挡住这家批发商的新订单、新商品、新导入
  -- （外键只要 key share），也不会跟 apply_price_list_import（先锁导入、再新增商品）互相等到死锁
  select * into v_w from public.wholesalers w where w.id = v_wholesaler_id for no key update;
  select * into v_import from public.price_list_imports i
  where i.id = p_import_id and i.wholesaler_id = v_wholesaler_id
  for update;
  if v_w.id is null or v_import.id is null then
    return jsonb_build_object('result', 'not_found');
  end if;

  if p_user_id is null or not (
    exists (select 1 from public.wholesaler_members m where m.wholesaler_id = v_w.id and m.user_id = p_user_id)
    or exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'admin')
  ) then
    return jsonb_build_object('result', 'not_member');
  end if;

  -- 停权（suspended，以后加的其他状态也一样）不能跑；还没审核（pending）可以跑，但次数比较少。
  -- 「人」是某一家停权批发商的老板（或建了那一家）也不能跑：不然停权的老板注册一家新的就又能用
  if v_w.status not in ('active', 'pending') or exists (
    select 1 from public.wholesalers x
    where x.status not in ('active', 'pending')
      and (x.created_by in (v_user_scope, v_creator_scope)
           or exists (select 1 from public.wholesaler_members m
                      where m.wholesaler_id = x.id and m.member_role = 'owner'
                        and m.user_id in (v_user_scope, v_creator_scope)))
  ) then
    return jsonb_build_object('result', 'suspended');
  end if;

  if v_import.status <> 'processing' then
    return jsonb_build_object('result', 'not_processing', 'status', v_import.status);
  end if;

  if v_import.ai_raw ->> 'state' = 'running' then
    v_claimed_at := public._try_timestamptz(v_import.ai_raw ->> 'claimed_at');
    if v_claimed_at > v_now - interval '10 minutes' then
      return jsonb_build_object('result', 'already_running');
    end if;
  end if;

  -- 用量：每一段时间里，三份（这家批发商、叫的人、建这家批发商的人）各跑了几次。哪一份满了 →
  -- 要等那一份「第 (已跑 - 上限 + 1) 旧」的那一次离开这段时间（刚好满的时候就是最旧的那一次）；
  -- 几份、几段都满 → 回传要等最久的
  for l in select * from public._price_list_run_limits(v_w.status) loop
    with runs as (
      select 'wholesaler' as scope, r.id, r.created_at
      from public.price_list_runs r
      where r.wholesaler_id = v_w.id and r.created_at > v_now - l.window_len
      union all
      select 'user', r.id, r.created_at
      from public.price_list_runs r
      where r.user_id = v_user_scope and r.created_at > v_now - l.window_len
      union all
      select 'creator', r.id, r.created_at
      from public.price_list_runs r
      join public.wholesalers x on x.id = r.wholesaler_id
      where x.created_by = v_creator_scope and r.created_at > v_now - l.window_len
    ),
    ranked as (
      select r.created_at,
             count(*) over (partition by r.scope) as n,
             row_number() over (partition by r.scope order by r.created_at, r.id) as k
      from runs r
    )
    select max(greatest(1, ceil(extract(epoch from (x.created_at + l.window_len - v_now)))::int)) into v_wait
    from ranked x
    where x.n >= l.max_runs and x.k = x.n - l.max_runs + 1;
    if v_wait is not null and (v_retry is null or v_wait > v_retry) then
      v_window := l.window_name;
      v_retry := v_wait;
    end if;
  end loop;
  if v_window is not null then
    return jsonb_build_object('result', 'quota', 'window', v_window, 'retry_after_sec', v_retry);
  end if;

  update public.price_list_imports set
    ai_raw = jsonb_build_object(
      'version', 1, 'state', 'running', 'run_id', p_run_id, 'claimed_at', v_now, 'claimed_by', p_user_id),
    error_message = null
  where id = v_import.id;

  insert into public.price_list_runs (wholesaler_id, import_id, run_id, user_id, created_at)
  values (v_w.id, v_import.id, p_run_id, p_user_id, v_now);

  return jsonb_build_object(
    'result', 'ok',
    'run_id', p_run_id,
    'claimed_at', v_now,
    'wholesaler_id', v_w.id,
    'wholesaler_status', v_w.status,
    'import_id', v_import.id,
    'file_path', v_import.file_path,
    'file_type', v_import.file_type
  );
end;
$$;

-- 批发商自己注册（第二步的函数，这里加一条）：一个人同时只能有一家「待审核」的批发商
-- （自己建的、或自己是老板的）→ 不然一直注册新的，每一家都是新的用量、新的 Storage 文件夹。
-- 有了 → WHOLESALER_ALREADY_PENDING（detail = 那一家的 id）；那一家不再是待审核（审核通过、停权）之后才能再注册。
-- 客服不限制。同一个人同时叫两次：锁住自己的 profile 那一行排队，不会多建一家。
create or replace function public.register_wholesaler(
  p_name text,
  p_region_id uuid,
  p_industry_id uuid,
  p_address text default null,
  p_contact_name text default null,
  p_whatsapp_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_pending uuid;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  select * into v_profile from public.profiles where id = v_uid for no key update;
  if v_profile.role = 'buyer' and exists (select 1 from public.shop_members m where m.user_id = v_uid) then
    raise exception 'ROLE_MISMATCH' using errcode = '42501';
  end if;
  if v_profile.role is distinct from 'admin' then
    select w.id into v_pending
    from public.wholesalers w
    where w.status = 'pending'
      and (w.created_by = v_uid
           or exists (select 1 from public.wholesaler_members m
                      where m.wholesaler_id = w.id and m.user_id = v_uid and m.member_role = 'owner'))
    order by w.created_at
    limit 1;
    if v_pending is not null then
      raise exception 'WHOLESALER_ALREADY_PENDING' using errcode = 'P0001', detail = v_pending::text;
    end if;
  end if;

  insert into public.wholesalers (name, industry_id, region_id, address, contact_name, phone, whatsapp_phone, locale, status, created_by)
  values (
    trim(p_name), p_industry_id, p_region_id, p_address,
    coalesce(p_contact_name, v_profile.full_name),
    v_profile.phone,
    coalesce(p_whatsapp_phone, v_profile.phone),
    v_profile.locale,
    'pending',
    v_uid
  )
  returning id into v_id;

  insert into public.wholesaler_members (wholesaler_id, user_id, member_role) values (v_id, v_uid, 'owner');
  update public.profiles set role = 'seller' where id = v_uid and role = 'buyer';
  return v_id;
end;
$$;

-- =============================================================================
-- C. price_list_imports 的保护（批发商自己可以读写这张表，RLS 是 for all）
-- =============================================================================

-- 批发商（App，authenticated）只能：
--   新增：status = processing，ai_raw、error_message、applied_at 都是空的，created_by 是空的或自己
--         （设成自己；created_at、updated_at 设成现在，不能自己填以前的时间）
--   修改：只能把 processing 改成 failed，而且 error_message 是 App 自己会写的代码
--         （START_FAILED、NETWORK、AUTH：叫不到 parse-price-list 时 markImportFailed 写的）；
--         wholesaler_id、file_path、file_type、ai_raw、applied_at、created_by、created_at（和 id）不能改；
--         其他状态变化（例如 failed → processing 重跑、自己标 review / applied）、单独改 error_message 都不行
--   不符合 → COLUMN_PROTECTED（42501），detail 是哪一栏
-- 服务器（service_role）、security definer 函数（apply_price_list_import、reserve_price_list_run……）、
-- 迁移、定时任务不检查（current_user 不是 authenticated / anon，跟 protect_columns 一样）。
-- 客服也不检查（跟 protect_columns 一样：客服要能手动修好卡住的导入）；用量记在 price_list_runs，客服改这张表也不影响。
-- 删除不管（删掉自己的导入不会影响用量：price_list_runs 留着）。
create or replace function public.price_list_imports_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_new jsonb;
  v_old jsonb;
  col text;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status is distinct from 'processing' then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'status';
    end if;
    if new.ai_raw is not null then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'ai_raw';
    end if;
    if new.error_message is not null then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'error_message';
    end if;
    if new.applied_at is not null then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'applied_at';
    end if;
    if new.created_by is not null and new.created_by is distinct from auth.uid() then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'created_by';
    end if;
    new.created_by := auth.uid();
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  v_new := to_jsonb(new);
  v_old := to_jsonb(old);
  foreach col in array array['id', 'wholesaler_id', 'file_path', 'file_type', 'ai_raw', 'applied_at', 'created_by', 'created_at'] loop
    if (v_new -> col) is distinct from (v_old -> col) then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = col;
    end if;
  end loop;

  if new.status is distinct from old.status then
    if not (old.status = 'processing' and new.status = 'failed') then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'status';
    end if;
    if new.error_message is null or new.error_message not in ('START_FAILED', 'NETWORK', 'AUTH') then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'error_message';
    end if;
  elsif new.error_message is distinct from old.error_message then
    raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = 'error_message';
  end if;
  return new;
end;
$$;

-- 名字排在 price_list_imports_updated_at 前面（同一种 trigger 按名字顺序跑）
create trigger price_list_imports_guard before insert or update on public.price_list_imports
  for each row execute function public.price_list_imports_guard();

-- =============================================================================
-- D. 卡住的导入（每 5 分钟跑一次）
-- =============================================================================

-- 还是 processing 的导入：
--   有人在跑（ai_raw.state = running）而且 claimed_at 超过 15 分钟 → failed、AI_TIMEOUT
--     （worker 被平台杀掉、beforeunload 也没跑到；claimed_at 读不懂就看 updated_at）
--   没人在跑（ai_raw 是空的：App 建好导入后没叫到 AI）而且 15 分钟没人动过（updated_at；
--     没人改过的就是 created_at）→ failed、START_FAILED
-- ai_raw 原来的资料（run_id、claimed_at、claimed_by……）留着，加上 state = failed、error、
-- interrupted = 'sweep'、finished_at；那份导入跑到一半写进去的行删掉。
-- 另外删掉两天前的 price_list_runs（用量只看最近一天）。回传标成失败的导入有几份。
-- 15 分钟比 parse-price-list 的「在跑超过 10 分钟可以重跑」长，正常在跑的不会被标失败。
create or replace function public.fail_stuck_price_list_imports()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  with stuck as (
    select i.id,
           case when i.ai_raw ->> 'state' = 'running' then 'AI_TIMEOUT' else 'START_FAILED' end as code
    from public.price_list_imports i
    where i.status = 'processing'
      and case when i.ai_raw ->> 'state' = 'running'
               then coalesce(public._try_timestamptz(i.ai_raw ->> 'claimed_at'), i.updated_at)
               else i.updated_at
          end < now() - interval '15 minutes'
    for update skip locked
  ),
  marked as (
    update public.price_list_imports i set
      status = 'failed',
      error_message = s.code,
      ai_raw = jsonb_build_object('version', 1)
        || case when jsonb_typeof(i.ai_raw) = 'object' then i.ai_raw else '{}'::jsonb end
        || jsonb_build_object('state', 'failed', 'error', s.code, 'interrupted', 'sweep', 'finished_at', now())
    from stuck s
    where i.id = s.id
    returning i.id
  ),
  removed as (
    delete from public.price_list_import_rows r
    using marked m
    where r.import_id = m.id
    returning r.id
  )
  select count(*)::int into v_count from marked;

  delete from public.price_list_runs r where r.created_at < now() - interval '2 days';

  return v_count;
end;
$$;

-- =============================================================================
-- E. 通知：claim id、放回队列
-- =============================================================================

-- 每个 dispatcher（dispatch-notifications 的一次执行）带一个自己的 id（claim id）：
-- claim_notifications 领的时候记在 claim_id；release_notification、complete_notification 要带同一个 id。
-- 为什么：dispatcher A 放回去（release）之后回应在路上断了，A 以为没放回去，改用 complete 标失败；
-- 但那条可能已经被 dispatcher B 领走、正在发 → A 会把 B 的领取改成 failed（B 发完记不到「已发」，
-- 过几分钟又被领、再发一次）。有了 claim id，A 的 complete 对不上就不改。
alter table public.notifications add column claim_id uuid;
comment on column public.notifications.claim_id is
  '领走这条的 dispatcher（claim_notifications 的 p_claim_id；放回队列时清掉）。release_notification、complete_notification 要对得上';

-- claim_notifications 加一个参数 p_claim_id：领到的每一条记下 claim_id = p_claim_id（不给就是 null）。
-- 领哪几条、回传什么都跟原来一样（原来的函数改名 _claim_notifications_batch，这里叫它，再记下 claim_id；
-- 领到的行在同一个交易里已经锁住了，别人改不了）。
alter function public.claim_notifications(int) rename to _claim_notifications_batch;

create or replace function public.claim_notifications(p_limit int default 50, p_claim_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_out jsonb;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  v_out := public._claim_notifications_batch(p_limit);
  update public.notifications n set claim_id = p_claim_id
  where n.id in (select (e ->> 'id')::uuid from jsonb_array_elements(v_out) e);
  return v_out;
end;
$$;

-- 发完了：sent / failed / skipped（第四步的函数，加一个参数 p_claim_id）。只改「发送中」的那条（回传 true）；
-- 不是发送中（例如卡住后被别的 dispatcher 重新领走、已经发完、已经放回队列）就不改（回传 false）。
-- p_claim_id：failed / skipped 只有领着这条的 dispatcher（claim_id 对得上，都是 null 也算）才能记，
-- 对不上 → 不改、回 false（那是别人的领取，结果由别人记）。sent 不看 claim id：已经发出去是事实，
-- 照样记下来（领着的那个 dispatcher 之后记不进去，也不会再重试一次）。
-- failed：p_retry 时 next_attempt_at = 现在 + 2^attempts 分钟（attempts 是加 1 之后的：2、4、8、16 分钟）；
-- p_retry = false 是永久失败（号码不在 WhatsApp、模板没批准……），attempts 设为 5，不再重试。
-- WhatsApp 发出去的写一行 whatsapp_messages（按钮回传要用 context id 对回这张订单；不改通知的时候也写）。
-- 送达状态可能比这里先到：那一行已经是 failed（例如号码不在 WhatsApp）的话，错误也写进这条通知的 last_error。
drop function public.complete_notification(
  uuid, public.notification_status, public.notification_channel, text, text, boolean);

create function public.complete_notification(
  p_id uuid,
  p_status public.notification_status,
  p_channel public.notification_channel,
  p_error text default null,
  p_wa_message_id text default null,
  p_retry boolean default true,
  p_claim_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  n public.notifications%rowtype;
  v_attempts int;
  v_retry boolean := coalesce(p_retry, true);
  v_wa_id text := nullif(trim(p_wa_message_id), '');
  v_order uuid;
  v_wa_status text;
  v_wa_code int;
  v_wa_raw jsonb;
  v_wa_error text;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if p_status is null or p_status::text not in ('sent', 'failed', 'skipped') then
    raise exception 'INVALID_STATUS' using errcode = 'P0001', detail = coalesce(p_status::text, 'null');
  end if;

  select * into n from public.notifications where id = p_id for update;
  if not found then
    raise exception 'NOTIFICATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  if p_status = 'sent' and p_channel = 'whatsapp' then
    if coalesce(n.payload ->> 'order_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select o.id into v_order from public.orders o where o.id = (n.payload ->> 'order_id')::uuid;
    end if;
    insert into public.whatsapp_messages (
      direction, wa_message_id, phone, shop_id, wholesaler_id, message_type, order_id
    )
    values (
      'outbound',
      v_wa_id,
      coalesce(
        (select coalesce(w.whatsapp_phone, w.phone) from public.wholesalers w where w.id = n.wholesaler_id),
        (select coalesce(s.whatsapp_phone, s.phone) from public.shops s where s.id = n.shop_id)),
      n.shop_id,
      n.wholesaler_id,
      'template',
      v_order
    )
    on conflict (wa_message_id) do update set
      direction = 'outbound',
      message_type = 'template',
      phone = coalesce(public.whatsapp_messages.phone, excluded.phone),
      shop_id = coalesce(public.whatsapp_messages.shop_id, excluded.shop_id),
      wholesaler_id = coalesce(public.whatsapp_messages.wholesaler_id, excluded.wholesaler_id),
      order_id = coalesce(public.whatsapp_messages.order_id, excluded.order_id)
    returning delivery_status, error_code, raw into v_wa_status, v_wa_code, v_wa_raw;

    -- 「failed」状态比这里先到（update_whatsapp_status 先建了那一行）：照它的写法记进通知
    if v_wa_status = 'failed' then
      v_wa_error := coalesce(case when jsonb_typeof(v_wa_raw) = 'object' then v_wa_raw ->> 'status_error' end, 'WHATSAPP_FAILED')
        || coalesce(' (' || v_wa_code || ')', '');
    end if;
  end if;

  if n.status::text <> 'sending' then
    return false;
  end if;
  if p_status <> 'sent' and n.claim_id is distinct from p_claim_id then
    return false;
  end if;

  v_attempts := n.attempts + 1;
  update public.notifications set
    status = p_status,
    channel = p_channel,
    attempts = case when p_status = 'failed' and not v_retry then greatest(v_attempts, 5) else v_attempts end,
    next_attempt_at = case
      when p_status = 'failed' and v_retry and v_attempts < 5
        then now() + make_interval(mins => power(2, v_attempts)::int)
    end,
    last_error = case when p_status = 'sent' then coalesce(v_wa_error, last_error) else coalesce(p_error, last_error) end,
    sent_at = case when p_status = 'sent' then now() else sent_at end,
    wa_message_id = case when p_status = 'sent' then coalesce(v_wa_id, wa_message_id) else wa_message_id end
  where id = p_id;
  return true;
end;
$$;

-- dispatch-notifications 领走了（claim_notifications）、但时间不够还没开始发的那几条（DISPATCH_TIME_BUDGET），
-- 用这个放回去：状态改回 queued、claimed_at 和 claim_id 清掉，下一次 claim_notifications 马上就会再领
-- （按 created_at 排，还是排在原来的位置），不算失败、不用掉一次 attempts。
-- attempts：claim_notifications 领 queued / 到时间的 failed 时不加，所以放回去之后跟领之前一样。
-- 只有「发送中超过 10 分钟、当成卡住重新领」时 claim 会加 1 —— 那是算之前卡住的那一次（那次可能已经发出去了），
-- 不是这一次用掉的，所以不扣回去（不然卡住的那一次就不见了）。
-- 只改「发送中」而且 claim_id 对得上（p_claim_id；都是 null 也算）的那条（回传 true）；
-- 不是发送中（已经发完、排队中……）或是别人领的就不改，回传 false。没有这条 → NOTIFICATION_NOT_FOUND。
-- 先锁那一行（同时有人在 complete 的话等它做完再看），update 本身也再检查一次状态和 claim_id。
create or replace function public.release_notification(p_id uuid, p_claim_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  perform 1 from public.notifications n where n.id = p_id for update;
  if not found then
    raise exception 'NOTIFICATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  update public.notifications n
  set status = 'queued', claimed_at = null, next_attempt_at = null, claim_id = null
  where n.id = p_id and n.status = 'sending' and n.claim_id is not distinct from p_claim_id;
  return found;
end;
$$;

-- =============================================================================
-- F. 定时任务（有 pg_cron 才建；同名的会更新，可以重复跑）
-- =============================================================================

create or replace function public._schedule_seller_hardening_jobs()
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return false;
  end if;
  perform cron.schedule('fail-stuck-price-list-imports', '*/5 * * * *', 'select public.fail_stuck_price_list_imports()');
  return true;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform public._schedule_seller_hardening_jobs();
  else
    raise notice 'pg_cron 不可用，跳过定时任务（卡住的导入要等 App 或客服处理）';
  end if;
end;
$$;

-- =============================================================================
-- G. 函数权限：先全部收回，再只开放需要的
-- =============================================================================

revoke execute on function
  public._price_list_run_limits(public.wholesaler_status),
  public._try_timestamptz(text),
  public.reserve_price_list_run(uuid, uuid, uuid),
  public.price_list_imports_guard(),
  public.fail_stuck_price_list_imports(),
  public._claim_notifications_batch(int),
  public.claim_notifications(int, uuid),
  public.complete_notification(uuid, public.notification_status, public.notification_channel, text, text, boolean, uuid),
  public.release_notification(uuid, uuid),
  public._schedule_seller_hardening_jobs()
from public, anon, authenticated;

-- 部署用的：只有迁移（postgres）能跑；trigger 函数不能直接叫；
-- 原来的 claim_notifications 只给新的 claim_notifications 叫（直接叫的话不会记 claim_id）
revoke execute on function
  public._schedule_seller_hardening_jobs(),
  public.price_list_imports_guard(),
  public._claim_notifications_batch(int)
from service_role;

-- 服务器（Edge Functions、定时任务）用的
grant execute on function
  public._price_list_run_limits(public.wholesaler_status),
  public._try_timestamptz(text),
  public.reserve_price_list_run(uuid, uuid, uuid),
  public.fail_stuck_price_list_imports(),
  public.claim_notifications(int, uuid),
  public.complete_notification(uuid, public.notification_status, public.notification_channel, text, text, boolean, uuid),
  public.release_notification(uuid, uuid)
to service_role;
