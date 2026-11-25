-- =============================================================================
-- 第四步（加固）：价目表 AI 的用量和占位、卡住的导入、通知放回队列
-- 规格见 docs/04-seller-spec.md 第 2.5、2.6、2.8、3 节。
--
--   A. price_list_runs：parse-price-list 每跑一次记一笔（只有服务器碰得到，批发商删不掉、改不了）
--   B. reserve_price_list_run（服务器）：成员、停权、状态、在跑、用量都在一个交易里检查完再占位
--      （取代以前放在 Storage 的用量记录，和 Edge Function 自己做的「有条件 PATCH」占位）
--   C. price_list_imports 的保护：批发商只能新增 processing 的导入、只能把 processing 标成 failed
--   D. fail_stuck_price_list_imports（服务器 / 定时任务）：卡在 processing 的导入标成失败
--   E. release_notification（服务器）：dispatcher 领了、来不及发的通知放回队列
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
create index price_list_runs_import_idx on public.price_list_runs (import_id);
comment on table public.price_list_runs is
  'parse-price-list 每跑一次记一笔，用来算用量（reserve_price_list_run 写）。只给服务器：开了 RLS、没有规则';
comment on column public.price_list_runs.run_id is '这一次跑的 id（ai_raw.run_id 也是它）';
comment on column public.price_list_runs.user_id is '谁叫的（App 登录的人）';

-- 只给服务器：开 RLS、不写规则，再把权限收回（Supabase 默认会开放给 anon / authenticated）
alter table public.price_list_runs enable row level security;
revoke all on table public.price_list_runs from public, anon, authenticated;

-- =============================================================================
-- B. 价目表 AI：用量和占位
-- =============================================================================

-- 用量限制（每家批发商、每段时间最多跑几次）。要改数字就改这里，Edge Function 不再自己算。
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
--   {"result":"suspended"}                         批发商停权（只有 active、pending 可以跑）
--   {"result":"not_processing","status":"review"}  导入已经不是 processing
--   {"result":"already_running"}                   有人在跑（ai_raw.state = running，claimed_at 10 分钟内）；
--                                                  超过 10 分钟的当成死掉了，可以重新占位
--   {"result":"quota","window":"burst|hour|day","retry_after_sec":N}
--                                                  用量满了（price_list_runs 算，限制见 _price_list_run_limits）。
--                                                  N = 要等几秒才有位置（至少 1）；几段都满的话回传要等最久的那一段，
--                                                  等 N 秒后再叫就不会被另一段挡住
-- 都通过：占位（ai_raw = {version:1, state:running, run_id, claimed_at, claimed_by}，error_message 清掉）、
-- 记一笔 price_list_runs，回传
--   {"result":"ok","run_id","claimed_at","wholesaler_id","wholesaler_status","import_id","file_path","file_type"}
-- 之后 Edge Function 写回结果时要用 run_id 过滤（.eq("ai_raw->>run_id", run_id)），claimed_at 照这里回传的写回 ai_raw。
-- 同一家批发商同时进来的请求在批发商那一行排队（一个一个数），所以不会多放。
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
  v_w public.wholesalers%rowtype;
  v_import public.price_list_imports%rowtype;
  v_claimed_at timestamptz;
  l record;
  v_count int;
  v_oldest timestamptz;
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

  select i.wholesaler_id into v_wholesaler_id from public.price_list_imports i where i.id = p_import_id;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- 先锁批发商那一行（同一家同时进来的几个请求排队，一个一个数用量），再锁这份导入。
  -- 用 for no key update（不是 for update）：一样会互相排队，但不会挡住这家批发商的新订单、新商品
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

  -- 停权（suspended，以后加的其他状态也一样）不能跑；还没审核（pending）可以跑，但次数比较少
  if v_w.status not in ('active', 'pending') then
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

  -- 用量：每一段时间里已经跑了几次。满了 → 要等「第 (已跑 - 上限 + 1) 旧」的那一次离开这段时间
  -- （刚好满的时候就是最旧的那一次）
  for l in select * from public._price_list_run_limits(v_w.status) loop
    select count(*)::int into v_count
    from public.price_list_runs r
    where r.wholesaler_id = v_w.id and r.created_at > v_now - l.window_len;
    if v_count >= l.max_runs then
      select r.created_at into v_oldest
      from public.price_list_runs r
      where r.wholesaler_id = v_w.id and r.created_at > v_now - l.window_len
      order by r.created_at, r.id
      offset v_count - l.max_runs
      limit 1;
      v_wait := greatest(1, ceil(extract(epoch from (v_oldest + l.window_len - v_now)))::int);
      if v_retry is null or v_wait > v_retry then
        v_window := l.window_name;
        v_retry := v_wait;
      end if;
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
-- E. 通知放回队列
-- =============================================================================

-- dispatch-notifications 领走了（claim_notifications）、但时间不够还没开始发的那几条（DISPATCH_TIME_BUDGET），
-- 用这个放回去：状态改回 queued、claimed_at 清掉，下一次 claim_notifications 马上就会再领
-- （按 created_at 排，还是排在原来的位置），不算失败、不用掉一次 attempts。
-- attempts：claim_notifications 领 queued / 到时间的 failed 时不加，所以放回去之后跟领之前一样。
-- 只有「发送中超过 10 分钟、当成卡住重新领」时 claim 会加 1 —— 那是算之前卡住的那一次（那次可能已经发出去了），
-- 不是这一次用掉的，所以不扣回去（不然卡住的那一次就不见了）。
-- 只改「发送中」的那条（回传 true）；不是发送中（已经发完、排队中……）就不改，回传 false。
-- 没有这条 → NOTIFICATION_NOT_FOUND。
create or replace function public.release_notification(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.notification_status;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  select n.status into v_status from public.notifications n where n.id = p_id for update;
  if not found then
    raise exception 'NOTIFICATION_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_status::text <> 'sending' then
    return false;
  end if;

  update public.notifications
  set status = 'queued', claimed_at = null, next_attempt_at = null
  where id = p_id;
  return true;
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
  public.release_notification(uuid),
  public._schedule_seller_hardening_jobs()
from public, anon, authenticated;

-- 部署用的：只有迁移（postgres）能跑；trigger 函数不能直接叫
revoke execute on function public._schedule_seller_hardening_jobs(), public.price_list_imports_guard() from service_role;

-- 服务器（Edge Functions、定时任务）用的
grant execute on function
  public._price_list_run_limits(public.wholesaler_status),
  public._try_timestamptz(text),
  public.reserve_price_list_run(uuid, uuid, uuid),
  public.fail_stuck_price_list_imports(),
  public.release_notification(uuid)
to service_role;
