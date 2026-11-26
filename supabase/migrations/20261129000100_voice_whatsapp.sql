-- =============================================================================
-- 第六步：语音下单、WhatsApp 下单（AI 订单草稿）
-- 规格：docs/06-voice-whatsapp.md
--
--   A. 结构：order_draft_items（草稿每一行）、order_drafts 加栏位、voice_order_runs（用量 / 每次处理）
--   B. 共用：这家店可以下单的商品、草稿的报价（用购物车算、算完退回）、WhatsApp 回复文字
--   C. 服务器（Edge Functions voice-order / whatsapp-webhook）：占位 + 用量、AI 要的商品资料、建草稿、失败
--   D. App / 客服：看草稿、改草稿、送出（走 place_order）、不要了；客服的 WhatsApp 订单列表
--   E. 通知：WhatsApp 回复（24 小时客服窗口内才发）、推送优先（买家有 App 就不发 WhatsApp）、不通知自己做的事
--   F. Storage：voice-orders（录音）
--   G. 函数权限
--
-- 本机测试环境没有 storage：有才建 bucket 和规则。
-- =============================================================================

-- =============================================================================
-- A. 结构
-- =============================================================================

alter table public.order_drafts
  add column unmatched jsonb not null default '[]',
  add column language text,
  add column ai_meta jsonb,
  add column reject_reason text,
  add column run_id uuid;
comment on column public.order_drafts.unmatched is 'AI 对不上商品的说法：[{"said": "...", "reason": "..."}]';
comment on column public.order_drafts.ai_meta is '语音转文字、Claude 的资料（模型、用量、错误代码），不给买家看';
comment on column public.order_drafts.parsed_lines is 'AI 原始结果（存档）；可以改的是 order_draft_items';

-- 草稿的每一行（老板 / 客服可以改数量、换商品、删掉、加）
create table public.order_draft_items (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.order_drafts (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  qty int not null check (qty > 0 and qty <= 100000),
  said text,                                       -- 老板原本怎么说（「两箱十六安士杯」）
  confidence numeric(3, 2) check (confidence between 0 and 1), -- AI 有多确定；人加的是空的
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index order_draft_items_draft_idx on public.order_draft_items (draft_id, sort_order);

-- 每处理一次（App 录音 / WhatsApp 一条消息）一行：用量、处理中、失败原因。只有服务器和客服看得到
create table public.voice_order_runs (
  id bigint generated always as identity primary key,
  run_id uuid not null unique,
  shop_id uuid not null references public.shops (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete set null,
  source public.draft_source not null,
  audio_path text,
  whatsapp_message_id uuid references public.whatsapp_messages (id) on delete set null,
  status text not null default 'running' check (status in ('running', 'done', 'failed')),
  error_code text,
  draft_id uuid references public.order_drafts (id) on delete set null,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index voice_order_runs_shop_idx on public.voice_order_runs (shop_id, created_at desc);

alter table public.order_draft_items enable row level security;
alter table public.voice_order_runs enable row level security;

create policy "buyer: read own order draft items" on public.order_draft_items for select to authenticated
  using (draft_id in (select d.id from public.order_drafts d where d.shop_id in (select public.my_shop_ids())));
create policy "admin: full access" on public.order_draft_items for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin: read voice order runs" on public.voice_order_runs for select to authenticated
  using ((select public.is_admin()));

-- 录音路径：<店的 id>/<uuid>.<副档名>（App 照这个格式上传到 voice-orders；服务器用自己的身份下载，
-- 所以要确定路径在这家店的文件夹里）
create or replace function public._voice_path_ok(p_shop_id uuid, p_path text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_path ~ ('^' || p_shop_id::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(wav|m4a|aac|mp4|ogg|opus|webm|mp3)$'), false);
$$;

alter table public.order_drafts
  add constraint order_drafts_audio_path_check
  check (audio_path is null or shop_id is null or public._voice_path_ok(shop_id, audio_path));

-- 用量上限（每家店，App 录音和 WhatsApp 一起算）
create or replace function public._voice_run_limits()
returns table (window_name text, window_len interval, max_runs int)
language sql
immutable
set search_path = ''
as $$
  values ('10m', interval '10 minutes', 6), ('1h', interval '1 hour', 20), ('1d', interval '1 day', 60);
$$;

-- =============================================================================
-- B. 共用
-- =============================================================================

-- 这家店现在可以下单的商品：上架、批发商审核过、送这一区；未付费只算免费的那几家（跟 _quote_cart 一样的规则）
create or replace function public._orderable_products(p_shop_id uuid)
returns table (product_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.shops s
  join public.wholesaler_delivery_zones dz on dz.zone_id = s.zone_id and dz.is_active
  join public.wholesalers w on w.id = dz.wholesaler_id and w.status = 'active'
  join public.products p on p.wholesaler_id = w.id and p.status = 'active'
  where s.id = p_shop_id
    and (public.has_full_access(s.id) or exists (
      select 1 from public.unlocked_wholesalers u where u.shop_id = s.id and u.wholesaler_id = w.id));
$$;

-- 把草稿放进这家店的购物车（先清空）。叫的地方自己先存好、之后放回原来的购物车
create or replace function public._load_draft_into_cart(p_draft_id uuid, p_shop_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.cart_items c where c.shop_id = p_shop_id;
  insert into public.cart_items (shop_id, product_id, qty, added_by)
  select p_shop_id, i.product_id, least(sum(i.qty), 100000)::int, auth.uid()
  from public.order_draft_items i
  where i.draft_id = p_draft_id
  group by i.product_id;
$$;

-- 草稿的报价：借用购物车算（规则只有 _quote_cart 一份），算完整个退回，原来的购物车不动
create or replace function public._draft_quote(p_draft_id uuid, p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote jsonb;
begin
  begin
    perform public._load_draft_into_cart(p_draft_id, p_shop_id);
    v_quote := public._quote_cart(p_shop_id);
    raise exception 'DRAFT_QUOTE_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> 'DRAFT_QUOTE_ROLLBACK' then
      raise;
    end if;
  end;
  return v_quote;
end;
$$;

-- 这个号码 / 这家店最近 24 小时有没有发消息给我们（WhatsApp 客服窗口：窗口里才可以发普通文字）
create or replace function public._whatsapp_window_phone(p_shop_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.phone from public.whatsapp_messages m
  where m.shop_id = p_shop_id and m.direction = 'inbound' and m.phone is not null
    and m.created_at > now() - interval '24 hours'
  order by m.created_at desc limit 1;
$$;

-- WhatsApp 回复的文字（按店的语言）
create or replace function public._draft_reply_text(p_kind text, p_locale public.app_locale, p_vars jsonb default '{}')
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text;
  k text;
begin
  v := case p_kind || ':' || coalesce(p_locale, 'zh')
    when 'received:zh' then '收到您的订单（{n} 样）。客服确认后会帮您下单，请稍等。'
    when 'received:en' then 'We got your order ({n} item(s)). Our team will check it and place it for you shortly.'
    when 'received:ms' then 'Pesanan anda diterima ({n} barang). Pasukan kami akan menyemak dan membuat pesanan untuk anda.'
    when 'received_unclear:zh' then '收到您的消息。客服会看一下，需要的话会联系您。'
    when 'received_unclear:en' then 'We got your message. Our team will take a look and contact you if needed.'
    when 'received_unclear:ms' then 'Mesej anda diterima. Pasukan kami akan menyemak dan menghubungi anda jika perlu.'
    when 'placed:zh' then '已经帮您下单：{orders}。总额 {total}。批发商确认后会通知您。'
    when 'placed:en' then 'Your order has been placed: {orders}. Total {total}. We will let you know when the wholesaler confirms.'
    when 'placed:ms' then 'Pesanan anda telah dibuat: {orders}. Jumlah {total}. Kami akan maklumkan apabila pemborong mengesahkan.'
    when 'rejected:zh' then '很抱歉，这张订单没办法处理：{reason}。有问题请直接回复这条消息。'
    when 'rejected:en' then 'Sorry, we could not process this order: {reason}. Just reply to this message if you have questions.'
    when 'rejected:ms' then 'Maaf, pesanan ini tidak dapat diproses: {reason}. Balas sahaja mesej ini jika ada pertanyaan.'
  end;
  for k in select jsonb_object_keys(coalesce(p_vars, '{}')) loop
    v := replace(v, '{' || k || '}', coalesce(p_vars ->> k, ''));
  end loop;
  return v;
end;
$$;

-- 排一条 WhatsApp 回复（dispatcher 在 24 小时窗口内用普通文字发；窗口过了就 skipped，客服要打电话）
create or replace function public._queue_whatsapp_reply(p_shop_id uuid, p_text text, p_draft_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (shop_id, event_type, payload)
  values (p_shop_id, 'whatsapp_reply', jsonb_build_object('text', left(p_text, 1000), 'draft_id', p_draft_id));
$$;

-- =============================================================================
-- C. 服务器（只给 Edge Functions）
-- =============================================================================

-- 开始处理一段录音 / 一条 WhatsApp：检查店、成员、路径、用量，都通过才记一行 voice_order_runs（running）。
-- 回传 {"result": "ok" | "not_found" | "not_member" | "invalid_path" | "quota", ...}
--   ok：run_id、shop_id、shop_name、locale、full_access；quota：window、retry_after_sec
-- 同一家店同时进来的会在店那一行排队（一个一个数用量）。p_run_id 空 → INVALID_RUN_ID，用过 → RUN_ID_USED
create or replace function public.reserve_voice_order_run(
  p_shop_id uuid,
  p_user_id uuid,
  p_run_id uuid,
  p_source public.draft_source,
  p_audio_path text default null,
  p_whatsapp_message_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_shop public.shops%rowtype;
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
  if exists (select 1 from public.voice_order_runs r where r.run_id = p_run_id) then
    raise exception 'RUN_ID_USED' using errcode = 'P0001';
  end if;
  if p_source is null or p_source = 'admin' then
    raise exception 'INVALID_SOURCE' using errcode = 'P0001';
  end if;

  select * into v_shop from public.shops s where s.id = p_shop_id for no key update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  if p_source = 'app_voice' then
    if p_user_id is null or not (
      exists (select 1 from public.shop_members m where m.shop_id = v_shop.id and m.user_id = p_user_id)
      or exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'admin')
    ) then
      return jsonb_build_object('result', 'not_member');
    end if;
    if not public._voice_path_ok(v_shop.id, p_audio_path) then
      return jsonb_build_object('result', 'invalid_path');
    end if;
  else
    if p_whatsapp_message_id is null or not exists (
      select 1 from public.whatsapp_messages m
      where m.id = p_whatsapp_message_id and m.shop_id = v_shop.id and m.direction = 'inbound'
    ) then
      return jsonb_build_object('result', 'not_found');
    end if;
    if p_audio_path is not null and not public._voice_path_ok(v_shop.id, p_audio_path) then
      return jsonb_build_object('result', 'invalid_path');
    end if;
  end if;

  for l in select * from public._voice_run_limits() loop
    select greatest(1, ceil(extract(epoch from (x.created_at + l.window_len - v_now)))::int) into v_wait
    from (
      select r.created_at, row_number() over (order by r.created_at desc, r.id desc) as k
      from public.voice_order_runs r
      where r.shop_id = v_shop.id and r.created_at > v_now - l.window_len
    ) x
    where x.k = l.max_runs;
    if v_wait is not null and (v_retry is null or v_wait > v_retry) then
      v_window := l.window_name;
      v_retry := v_wait;
    end if;
  end loop;
  if v_window is not null then
    return jsonb_build_object('result', 'quota', 'window', v_window, 'retry_after_sec', v_retry, 'locale', v_shop.locale);
  end if;

  insert into public.voice_order_runs (run_id, shop_id, user_id, source, audio_path, whatsapp_message_id, created_at)
  values (p_run_id, v_shop.id, p_user_id, p_source, p_audio_path, p_whatsapp_message_id, v_now);

  return jsonb_build_object(
    'result', 'ok',
    'run_id', p_run_id,
    'shop_id', v_shop.id,
    'shop_name', v_shop.name,
    'locale', v_shop.locale,
    'full_access', public.has_full_access(v_shop.id)
  );
end;
$$;

-- WhatsApp 进来的一条消息（record_whatsapp_message 记好之后）：要不要做成草稿。
-- 回传 result：
--   ok（已经占位，跟 reserve_voice_order_run 一样，加 message_type、body、media_id）
--   unknown_sender（不认识的号码；reply = 这 24 小时第一条才回「请先注册」，不会一直回）
--   wholesaler（批发商的号码：不是下单，不处理）、unsupported（照片、文件……：reply 同上）、
--   ignored（不是进来的消息）、not_found、quota
create or replace function public.reserve_whatsapp_order(p_message_id uuid, p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.whatsapp_messages%rowtype;
  v_first boolean;
  v_locale public.app_locale;
  v_res jsonb;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into m from public.whatsapp_messages x where x.id = p_message_id;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if m.direction <> 'inbound' then
    return jsonb_build_object('result', 'ignored');
  end if;

  -- 这个号码（或 BSUID）24 小时内的第一条
  v_first := not exists (
    select 1 from public.whatsapp_messages x
    where x.direction = 'inbound' and x.id <> m.id and x.created_at > now() - interval '24 hours'
      and x.created_at < m.created_at
      and (x.phone = m.phone or (m.phone is null and x.from_user_id = m.from_user_id))
  );

  if m.shop_id is null then
    if m.wholesaler_id is not null then
      return jsonb_build_object('result', 'wholesaler');
    end if;
    return jsonb_build_object('result', 'unknown_sender', 'reply', v_first);
  end if;
  select s.locale into v_locale from public.shops s where s.id = m.shop_id;
  if m.message_type not in ('text', 'audio') or (m.message_type = 'text' and nullif(trim(m.body), '') is null) then
    return jsonb_build_object('result', 'unsupported', 'reply', v_first, 'locale', v_locale, 'shop_id', m.shop_id);
  end if;

  v_res := public.reserve_voice_order_run(
    m.shop_id, null, p_run_id,
    case when m.message_type = 'audio' then 'whatsapp_voice' else 'whatsapp_text' end::public.draft_source,
    null, m.id);
  return v_res || jsonb_build_object(
    'message_type', m.message_type,
    'body', m.body,
    'media_id', case when jsonb_typeof(m.raw) = 'object' then m.raw ->> 'media_id' end,
    'locale', coalesce(v_res ->> 'locale', v_locale::text),
    'shop_id', m.shop_id
  );
end;
$$;

-- AI 要的资料：这家店可以下单的商品（最近买过的排前面）。最多 400 样
create or replace function public.get_voice_order_context(p_shop_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with bought as (
    select i.product_id, count(*)::int as times, (array_agg(i.qty order by o.created_at desc))[1] as last_qty,
           max(o.created_at) as last_at
    from public.orders o
    join public.order_items i on i.order_id = o.id
    where o.shop_id = p_shop_id and o.created_at > now() - interval '180 days' and o.status <> 'cancelled'
    group by i.product_id
  ),
  items as (
    select p.id, p.name, p.unit, p.pack_qty, p.min_order_qty, p.stock_status, w.id as wholesaler_id,
           w.name as wholesaler_name, ci.name as catalog_name, b.times, b.last_qty, b.last_at
    from public._orderable_products(p_shop_id) o
    join public.products p on p.id = o.product_id
    join public.wholesalers w on w.id = p.wholesaler_id
    left join public.catalog_items ci on ci.id = p.catalog_item_id
    left join bought b on b.product_id = p.id
    order by b.last_at desc nulls last, p.name, p.id
    limit 400
  )
  select jsonb_build_object(
    'shop_id', s.id,
    'shop_name', s.name,
    'locale', s.locale,
    'full_access', public.has_full_access(s.id),
    'products', coalesce((select jsonb_agg(jsonb_build_object(
      'product_id', i.id, 'name', i.name, 'unit', i.unit, 'pack_qty', i.pack_qty, 'min_order_qty', i.min_order_qty,
      'stock_status', i.stock_status, 'wholesaler_id', i.wholesaler_id, 'wholesaler_name', i.wholesaler_name,
      'catalog_name', i.catalog_name, 'times_bought', coalesce(i.times, 0), 'last_qty', i.last_qty)) from items i), '[]')
  )
  from public.shops s where s.id = p_shop_id;
$$;

-- AI 做好了：建草稿。p_lines = [{product_id, qty, said, confidence}]，不在这家店可以下单的商品
-- （或 id 不对）移到 unmatched（reason = not_orderable）；数量不对的当 1、confidence 最多 0.3。
-- p_unmatched = [{said, reason}]。WhatsApp 来的：老板自己发消息来下单，当成同意用 WhatsApp 收这张单的通知
-- （whatsapp_opt_in_at 还是空的才填）。回传 {result: created, draft_id, shop_id, locale, source, item_count, unmatched_count}
create or replace function public.create_order_draft(
  p_run_id uuid,
  p_transcript text,
  p_language text default null,
  p_lines jsonb default '[]',
  p_unmatched jsonb default '[]',
  p_ai_meta jsonb default null,
  p_audio_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.voice_order_runs%rowtype;
  v_draft uuid;
  v_unmatched jsonb := '[]';
  v_audio text;
  v_phone text;
  e jsonb;
  v_pid uuid;
  v_qty int;
  v_conf numeric;
  v_n int := 0;
  v_locale public.app_locale;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into r from public.voice_order_runs x where x.run_id = p_run_id for update;
  if not found or r.status <> 'running' then
    raise exception 'RUN_NOT_RUNNING' using errcode = 'P0001';
  end if;
  v_audio := coalesce(nullif(trim(p_audio_path), ''), r.audio_path);
  if v_audio is not null and not public._voice_path_ok(r.shop_id, v_audio) then
    raise exception 'INVALID_FILE_PATH' using errcode = 'P0001';
  end if;
  select m.phone into v_phone from public.whatsapp_messages m where m.id = r.whatsapp_message_id;

  insert into public.order_drafts (
    shop_id, source, whatsapp_message_id, sender_phone, audio_path, transcript, parsed_lines,
    language, ai_meta, created_by, run_id
  )
  values (
    r.shop_id, r.source, r.whatsapp_message_id, v_phone, v_audio, left(nullif(trim(p_transcript), ''), 4000),
    case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]' end,
    left(nullif(trim(p_language), ''), 20), p_ai_meta, r.user_id, r.run_id
  )
  returning id into v_draft;

  for e in select x from jsonb_array_elements(case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]' end) x
  loop
    exit when v_n >= 50;
    v_pid := case when e ->> 'product_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  then (e ->> 'product_id')::uuid end;
    if v_pid is null or not exists (select 1 from public._orderable_products(r.shop_id) o where o.product_id = v_pid) then
      v_unmatched := v_unmatched || jsonb_build_object('said', left(coalesce(e ->> 'said', ''), 200), 'reason', 'not_orderable');
      continue;
    end if;
    v_conf := case when jsonb_typeof(e -> 'confidence') = 'number'
                   then least(greatest((e ->> 'confidence')::numeric, 0), 1) end;
    v_qty := case when jsonb_typeof(e -> 'qty') = 'number' and (e ->> 'qty')::numeric between 1 and 100000
                  then floor((e ->> 'qty')::numeric)::int end;
    if v_qty is null then
      v_qty := 1;
      v_conf := least(coalesce(v_conf, 0.3), 0.3);
    end if;
    insert into public.order_draft_items (draft_id, product_id, qty, said, confidence, sort_order)
    values (v_draft, v_pid, v_qty, left(nullif(trim(e ->> 'said'), ''), 200), round(v_conf, 2), v_n);
    v_n := v_n + 1;
  end loop;

  for e in select x from jsonb_array_elements(case when jsonb_typeof(p_unmatched) = 'array' then p_unmatched else '[]' end) x
  loop
    exit when jsonb_array_length(v_unmatched) >= 30;
    if nullif(trim(e ->> 'said'), '') is not null then
      v_unmatched := v_unmatched || jsonb_build_object(
        'said', left(trim(e ->> 'said'), 200), 'reason', left(coalesce(e ->> 'reason', ''), 200));
    end if;
  end loop;
  update public.order_drafts set unmatched = v_unmatched where id = v_draft;

  if r.whatsapp_message_id is not null then
    update public.whatsapp_messages set media_path = coalesce(media_path, 'voice-orders/' || v_audio)
    where id = r.whatsapp_message_id and v_audio is not null;
    update public.shops set whatsapp_opt_in_at = now() where id = r.shop_id and whatsapp_opt_in_at is null;
  end if;

  update public.voice_order_runs set status = 'done', draft_id = v_draft, finished_at = now() where id = r.id;
  select s.locale into v_locale from public.shops s where s.id = r.shop_id;

  return jsonb_build_object(
    'result', 'created', 'draft_id', v_draft, 'shop_id', r.shop_id, 'locale', v_locale, 'source', r.source,
    'item_count', v_n, 'unmatched_count', jsonb_array_length(v_unmatched));
end;
$$;

-- 处理失败（语音转文字 / AI 出错）：记下原因。还在 running 才改，回传有没有改
create or replace function public.fail_voice_order_run(p_run_id uuid, p_error_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  update public.voice_order_runs
  set status = 'failed', error_code = left(coalesce(nullif(trim(p_error_code), ''), 'INTERNAL_ERROR'), 60),
      finished_at = now()
  where run_id = p_run_id and status = 'running';
  return found;
end;
$$;

-- =============================================================================
-- D. App（老板）和客服
-- =============================================================================

-- 拿草稿并检查权限。客服：全部；老板：自己店的（看不到别家的，当成没有这张）。
-- p_edit：要改 → 锁住；老板只能改自己的语音草稿（WhatsApp 的由客服处理）；要还在待确认
create or replace function public._draft_for(p_draft_id uuid, p_edit boolean)
returns public.order_drafts
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.order_drafts%rowtype;
  v_admin boolean := public.is_admin();
begin
  if p_edit then
    select * into d from public.order_drafts x where x.id = p_draft_id for update;
  else
    select * into d from public.order_drafts x where x.id = p_draft_id;
  end if;
  if not found or d.shop_id is null or not (v_admin or public.is_shop_member(d.shop_id)) then
    raise exception 'DRAFT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_edit then
    if not v_admin and d.source <> 'app_voice' then
      raise exception 'NOT_ALLOWED' using errcode = '42501';
    end if;
    if d.status <> 'pending_review' then
      raise exception 'DRAFT_NOT_PENDING' using errcode = 'P0001', detail = d.status::text;
    end if;
  end if;
  return d;
end;
$$;

create or replace function public._order_draft_json(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.order_drafts%rowtype;
  v_admin boolean := public.is_admin();
  v_window_phone text;
begin
  select * into d from public.order_drafts x where x.id = p_draft_id;
  if d.source in ('whatsapp_text', 'whatsapp_voice') then
    v_window_phone := public._whatsapp_window_phone(d.shop_id);
  end if;
  return jsonb_build_object(
    'id', d.id,
    'shop_id', d.shop_id,
    'shop_name', (select s.name from public.shops s where s.id = d.shop_id),
    'source', d.source,
    'status', d.status,
    'transcript', d.transcript,
    'language', d.language,
    'unmatched', d.unmatched,
    'created_at', d.created_at,
    'updated_at', d.updated_at,
    'reviewed_at', d.reviewed_at,
    'checkout_id', d.checkout_id,
    'reject_reason', d.reject_reason,
    'has_audio', d.audio_path is not null,
    'sender_phone', case when v_admin then d.sender_phone end,
    'whatsapp_window_open', case when v_admin and d.source in ('whatsapp_text', 'whatsapp_voice')
                                 then v_window_phone is not null end,
    'error_code', case when v_admin then d.ai_meta ->> 'error_code' end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id,
        'product_id', i.product_id,
        'qty', i.qty,
        'said', i.said,
        'confidence', i.confidence,
        'product_name', p.name,
        'unit', p.unit,
        'pack_qty', p.pack_qty,
        'min_order_qty', p.min_order_qty,
        'stock_status', p.stock_status,
        'wholesaler_id', w.id,
        'wholesaler_name', w.name,
        'unit_price_sen', case when public.can_see_prices(d.shop_id, w.id) then p.price_sen end,
        'orderable', exists (select 1 from public._orderable_products(d.shop_id) o where o.product_id = p.id)
      ) order by i.sort_order, i.created_at, i.id)
      from public.order_draft_items i
      join public.products p on p.id = i.product_id
      join public.wholesalers w on w.id = p.wholesaler_id
      where i.draft_id = d.id), '[]'),
    'quote', case when d.status = 'pending_review' then public._draft_quote(d.id, d.shop_id) end
  );
end;
$$;

-- 看一张草稿（买家：自己店的；客服：全部）。待确认的附上报价（跟「确认下单」页一样的格式）
create or replace function public.get_order_draft(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._draft_for(p_draft_id, false);
  return public._order_draft_json(p_draft_id);
end;
$$;

-- 这家店还没处理的语音草稿（首页提醒「你有一张草稿还没确认」）
create or replace function public.list_order_drafts(p_shop_id uuid, p_limit int default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x.j order by x.created_at desc)
    from (
      select d.created_at, jsonb_build_object(
        'id', d.id, 'source', d.source, 'status', d.status, 'created_at', d.created_at,
        'transcript', d.transcript,
        'item_count', (select count(*) from public.order_draft_items i where i.draft_id = d.id),
        'unmatched_count', jsonb_array_length(d.unmatched)) as j
      from public.order_drafts d
      where d.shop_id = p_shop_id and d.status = 'pending_review' and d.source = 'app_voice'
        and d.created_at > now() - interval '7 days'
      order by d.created_at desc
      limit greatest(least(coalesce(p_limit, 10), 50), 1)
    ) x), '[]');
end;
$$;

-- 改草稿：整份换掉。p_items = [{product_id, qty, said?, confidence?}]（最多 60 行）。
-- 商品一定要是这家店现在可以下单的（否则 INVALID_PRODUCT，detail = 那个 id）；数量 1–100000（否则 INVALID_QTY）。
-- p_unmatched 不是空的：换掉「没听懂」的列表（老板处理掉一句就拿掉一句）。回传 get_order_draft
create or replace function public.save_order_draft(p_draft_id uuid, p_items jsonb, p_unmatched jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.order_drafts%rowtype;
  e jsonb;
  v_pid uuid;
  v_qty numeric;
  v_n int := 0;
  v_before jsonb;
  v_unmatched jsonb := '[]';
begin
  d := public._draft_for(p_draft_id, true);
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 60 then
    raise exception 'INVALID_VALUE' using errcode = 'P0001';
  end if;
  select jsonb_agg(jsonb_build_object('product_id', i.product_id, 'qty', i.qty) order by i.sort_order)
  into v_before from public.order_draft_items i where i.draft_id = d.id;

  delete from public.order_draft_items where draft_id = d.id;
  for e in select x from jsonb_array_elements(p_items) x loop
    v_pid := case when e ->> 'product_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  then (e ->> 'product_id')::uuid end;
    if v_pid is null or not exists (select 1 from public._orderable_products(d.shop_id) o where o.product_id = v_pid) then
      raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = coalesce(e ->> 'product_id', '');
    end if;
    v_qty := case when jsonb_typeof(e -> 'qty') = 'number' then (e ->> 'qty')::numeric end;
    if v_qty is null or v_qty <> floor(v_qty) or v_qty < 1 or v_qty > 100000 then
      raise exception 'INVALID_QTY' using errcode = 'P0001', detail = coalesce(e ->> 'qty', '');
    end if;
    insert into public.order_draft_items (draft_id, product_id, qty, said, confidence, sort_order)
    values (
      d.id, v_pid, v_qty::int, left(nullif(trim(e ->> 'said'), ''), 200),
      case when jsonb_typeof(e -> 'confidence') = 'number'
           then round(least(greatest((e ->> 'confidence')::numeric, 0), 1), 2) end,
      v_n);
    v_n := v_n + 1;
  end loop;

  if p_unmatched is not null then
    if jsonb_typeof(p_unmatched) <> 'array' then
      raise exception 'INVALID_VALUE' using errcode = 'P0001';
    end if;
    for e in select x from jsonb_array_elements(p_unmatched) x loop
      exit when jsonb_array_length(v_unmatched) >= 30;
      if nullif(trim(e ->> 'said'), '') is not null then
        v_unmatched := v_unmatched || jsonb_build_object(
          'said', left(trim(e ->> 'said'), 200), 'reason', left(coalesce(e ->> 'reason', ''), 200));
      end if;
    end loop;
  end if;
  update public.order_drafts set unmatched = case when p_unmatched is null then unmatched else v_unmatched end,
    updated_at = now()
  where id = d.id;

  if public.is_admin() then
    perform public._admin_audit('admin_save_order_draft', 'order_drafts', d.id::text, d.shop_id, null,
      jsonb_build_object('items', coalesce(v_before, '[]')), jsonb_build_object('items', p_items));
  end if;
  return public._order_draft_json(d.id);
end;
$$;

-- 送出草稿：照现在的草稿下单。走 place_order（价钱、运费、起订量、付费规则只有一份），
-- 来源：App 语音 = voice、WhatsApp = whatsapp（只有客服能送）。p_expected_total_sen 是看到的总额（客服一定要给），
-- 对不上 → PRICE_CHANGED（detail = 新报价）。老板原来购物车里的东西照样留着。
-- 回传 {checkout_id, order_nos, total_sen, draft}
create or replace function public.submit_order_draft(
  p_draft_id uuid,
  p_expected_total_sen int default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.order_drafts%rowtype;
  v_admin boolean := public.is_admin();
  v_saved jsonb;
  v_checkout uuid;
  v_source public.order_source;
  v_orders text;
  v_total int;
  v_locale public.app_locale;
begin
  d := public._draft_for(p_draft_id, true);
  if not exists (select 1 from public.order_draft_items i where i.draft_id = d.id) then
    raise exception 'DRAFT_EMPTY' using errcode = 'P0001';
  end if;
  if v_admin and p_expected_total_sen is null then
    raise exception 'EXPECTED_TOTAL_REQUIRED' using errcode = 'P0001';
  end if;
  v_source := case when d.source in ('whatsapp_text', 'whatsapp_voice') then 'whatsapp'
                   when d.source = 'app_voice' then 'voice' else 'admin' end;

  -- 先存好原来的购物车，换成草稿的货下单，再放回去（出错的话整个退回，购物车也不会变）
  select jsonb_agg(to_jsonb(c)) into v_saved from public.cart_items c where c.shop_id = d.shop_id;
  perform 1 from public.cart_items c where c.shop_id = d.shop_id for update;
  perform public._load_draft_into_cart(d.id, d.shop_id);
  v_checkout := public.place_order(d.shop_id, p_expected_total_sen, p_note, v_source);
  insert into public.cart_items (shop_id, product_id, qty, added_by, updated_at)
  select x.shop_id, x.product_id, x.qty, x.added_by, x.updated_at
  from jsonb_populate_recordset(null::public.cart_items, coalesce(v_saved, '[]')) x;

  update public.order_drafts set
    status = 'confirmed', checkout_id = v_checkout, reviewed_by = auth.uid(), reviewed_at = now()
  where id = d.id;

  select string_agg(o.order_no, ', ' order by o.order_no), sum(o.total_sen)::int into v_orders, v_total
  from public.orders o where o.checkout_id = v_checkout;

  if v_source = 'whatsapp' then
    select s.locale into v_locale from public.shops s where s.id = d.shop_id;
    perform public._queue_whatsapp_reply(d.shop_id, public._draft_reply_text('placed', v_locale, jsonb_build_object(
      'orders', v_orders, 'total', 'RM' || to_char(v_total / 100.0, 'FM999999990.00'))), d.id);
  end if;
  if v_admin then
    perform public._admin_audit('admin_submit_order_draft', 'order_drafts', d.id::text, d.shop_id, null, null,
      jsonb_build_object('checkout_id', v_checkout, 'order_nos', v_orders, 'source', v_source));
  end if;

  return jsonb_build_object(
    'checkout_id', v_checkout, 'order_nos', v_orders, 'total_sen', v_total, 'draft', public._order_draft_json(d.id));
end;
$$;

-- 不要这张草稿。客服处理 WhatsApp 的：会用 WhatsApp 回老板原因（24 小时窗口内）。回传 get_order_draft
create or replace function public.reject_order_draft(p_draft_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.order_drafts%rowtype;
  v_reason text := left(nullif(trim(p_reason), ''), 300);
  v_locale public.app_locale;
begin
  d := public._draft_for(p_draft_id, true);
  update public.order_drafts set
    status = 'rejected', reject_reason = v_reason, reviewed_by = auth.uid(), reviewed_at = now()
  where id = d.id;

  if public.is_admin() then
    if d.source in ('whatsapp_text', 'whatsapp_voice') then
      select s.locale into v_locale from public.shops s where s.id = d.shop_id;
      perform public._queue_whatsapp_reply(d.shop_id, public._draft_reply_text('rejected', v_locale,
        jsonb_build_object('reason', coalesce(v_reason, case v_locale when 'en' then 'please call us'
          when 'ms' then 'sila hubungi kami' else '请打电话给我们' end))), d.id);
    end if;
    perform public._admin_audit('admin_reject_order_draft', 'order_drafts', d.id::text, d.shop_id, null, null,
      jsonb_build_object('reason', v_reason));
  end if;
  return public._order_draft_json(d.id);
end;
$$;

-- 客服后台：WhatsApp 订单（或 App 语音）草稿列表。p_channel：whatsapp / app / null（全部）
create or replace function public.admin_list_order_drafts(
  p_status public.draft_status default 'pending_review',
  p_channel text default 'whatsapp',
  p_limit int default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(x.j order by x.created_at)
    from (
      select d.created_at, jsonb_build_object(
        'id', d.id,
        'shop_id', d.shop_id,
        'shop_name', s.name,
        'shop_phone', coalesce(s.whatsapp_phone, s.phone),
        'source', d.source,
        'status', d.status,
        'created_at', d.created_at,
        'transcript', d.transcript,
        'sender_phone', d.sender_phone,
        'item_count', (select count(*) from public.order_draft_items i where i.draft_id = d.id),
        'unmatched_count', jsonb_array_length(d.unmatched),
        'error_code', d.ai_meta ->> 'error_code',
        'whatsapp_window_open', case when d.source in ('whatsapp_text', 'whatsapp_voice')
                                     then public._whatsapp_window_phone(d.shop_id) is not null end
      ) as j
      from public.order_drafts d
      join public.shops s on s.id = d.shop_id
      where (p_status is null or d.status = p_status)
        and (p_channel is null
             or (p_channel = 'whatsapp' and d.source in ('whatsapp_text', 'whatsapp_voice'))
             or (p_channel = 'app' and d.source = 'app_voice'))
      order by d.created_at
      limit greatest(least(coalesce(p_limit, 100), 500), 1)
    ) x), '[]');
end;
$$;

-- =============================================================================
-- E. 通知
-- =============================================================================

-- 选渠道（第四步的函数，加两条规则）：
--   1. whatsapp_reply（回 WhatsApp 下单的老板）：最近 24 小时这家店有发消息来 → 用 WhatsApp 回那个号码
--      （客服窗口内的普通文字；不看推送、不看 opt-in：是回他自己开始的对话）；窗口过了 → 没有渠道（skipped）
--   2. 买家（店）：有 App（推送）就一定用推送，notify_channel = whatsapp 也一样 —— WhatsApp 按条收费，
--      只给没装 App 的人。批发商照旧（客服可以替习惯看 WhatsApp 的批发商改成 whatsapp）
create or replace function public._notification_route(
  p_user_id uuid,
  p_shop_id uuid,
  p_wholesaler_id uuid,
  p_event_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pref public.notify_channel := 'push';
  v_locale public.app_locale := 'zh';
  v_phone text;
  v_opt_in timestamptz;
  v_targets jsonb;
  v_can_wa boolean;
  v_has_push boolean;
  v_channel text;
begin
  if p_event_type = 'whatsapp_reply' then
    v_phone := case when p_shop_id is not null then public._whatsapp_window_phone(p_shop_id) end;
    select s.locale into v_locale from public.shops s where s.id = p_shop_id;
    return jsonb_build_object(
      'channel', case when v_phone is not null then 'whatsapp' end,
      'push_targets', '[]'::jsonb,
      'whatsapp_phone', v_phone,
      'locale', coalesce(v_locale, 'zh'));
  end if;

  if p_user_id is not null then
    select p.locale into v_locale from public.profiles p where p.id = p_user_id;
    select jsonb_agg(jsonb_build_object('target', t.fcm_token, 'kind', t.kind) order by t.last_seen_at desc, t.fcm_token)
    into v_targets
    from public.device_tokens t
    where t.user_id = p_user_id and t.last_seen_at > now() - interval '60 days';
  elsif p_wholesaler_id is not null then
    select w.notify_channel, w.locale, coalesce(w.whatsapp_phone, w.phone), w.whatsapp_opt_in_at
    into v_pref, v_locale, v_phone, v_opt_in
    from public.wholesalers w where w.id = p_wholesaler_id;
    select jsonb_agg(jsonb_build_object('target', t.fcm_token, 'kind', t.kind) order by t.last_seen_at desc, t.fcm_token)
    into v_targets
    from public.wholesaler_members m
    join public.device_tokens t on t.user_id = m.user_id
    where m.wholesaler_id = p_wholesaler_id and t.last_seen_at > now() - interval '60 days';
  elsif p_shop_id is not null then
    select s.notify_channel, s.locale, coalesce(s.whatsapp_phone, s.phone), s.whatsapp_opt_in_at
    into v_pref, v_locale, v_phone, v_opt_in
    from public.shops s where s.id = p_shop_id;
    select jsonb_agg(jsonb_build_object('target', t.fcm_token, 'kind', t.kind) order by t.last_seen_at desc, t.fcm_token)
    into v_targets
    from public.shop_members m
    join public.device_tokens t on t.user_id = m.user_id
    where m.shop_id = p_shop_id and t.last_seen_at > now() - interval '60 days';
  end if;

  v_has_push := v_targets is not null;
  v_can_wa := p_user_id is null
    and v_phone is not null
    and v_opt_in is not null
    and coalesce(p_event_type, '') not in ('daily_summary', 'order_unconfirmed');

  v_channel := case
    when p_user_id is not null then case when v_has_push then 'push' end
    when p_shop_id is not null and v_has_push then 'push'
    when v_pref = 'whatsapp' then case when v_can_wa then 'whatsapp' end
    when v_pref = 'push' then case when v_has_push then 'push' end
    else case when v_has_push then 'push' when v_can_wa then 'whatsapp' end
  end;

  return jsonb_build_object(
    'channel', v_channel,
    'push_targets', case when v_channel = 'push' then v_targets else '[]'::jsonb end,
    'whatsapp_phone', case when v_channel = 'whatsapp' then v_phone end,
    'locale', coalesce(v_locale, 'zh')
  );
end;
$$;

-- 不通知自己做的事：老板自己按「收到了」/ 取消，不用再推送（或 WhatsApp）告诉他自己。
-- 批发商、客服、系统改的照样通知老板。
create or replace function public.notifications_skip_self()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.event_type = 'order_status_changed' and new.shop_id is not null
     and auth.uid() is not null and not public.is_admin() and public.is_shop_member(new.shop_id) then
    return null;
  end if;
  return new;
end;
$$;

create trigger notifications_skip_self before insert on public.notifications
  for each row execute function public.notifications_skip_self();

-- =============================================================================
-- F. Storage：voice-orders（私人，3 MB：60 秒 16 kHz 单声道 WAV 大约 1.9 MB）
-- 路径 <店的 id>/<uuid>.<副档名>；老板上传 / 读自己店的，客服全部；WhatsApp 的语音由服务器存
-- =============================================================================

create or replace function public._setup_voice_storage()
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null
     or to_regprocedure('storage.foldername(text)') is null then
    return false;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('voice-orders', 'voice-orders', false, 3145728, array[
    'audio/wav', 'audio/x-wav', 'audio/wave', 'audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac',
    'audio/ogg', 'audio/opus', 'audio/webm', 'audio/mpeg'])
  on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

  drop policy if exists "voice files: shop read" on storage.objects;
  drop policy if exists "voice files: shop upload" on storage.objects;
  drop policy if exists "voice files: admin full access" on storage.objects;

  create policy "voice files: shop read" on storage.objects for select to authenticated
    using (
      bucket_id = 'voice-orders'
      and (storage.foldername(name))[1] in (select t.id::text from public.my_shop_ids() as t(id))
    );
  create policy "voice files: shop upload" on storage.objects for insert to authenticated
    with check (
      bucket_id = 'voice-orders'
      and (storage.foldername(name))[1] in (select t.id::text from public.my_shop_ids() as t(id))
    );
  create policy "voice files: admin full access" on storage.objects for all to authenticated
    using (bucket_id = 'voice-orders' and (select public.is_admin()))
    with check (bucket_id = 'voice-orders' and (select public.is_admin()));
  return true;
end;
$$;

do $$
begin
  if not public._setup_voice_storage() then
    raise notice '没有 storage schema，跳过 voice-orders bucket 和规则';
  end if;
end;
$$;

-- =============================================================================
-- G. 函数权限：先全部收回，再只开放需要的
-- =============================================================================

revoke execute on function
  public._voice_path_ok(uuid, text),
  public._voice_run_limits(),
  public._orderable_products(uuid),
  public._load_draft_into_cart(uuid, uuid),
  public._draft_quote(uuid, uuid),
  public._whatsapp_window_phone(uuid),
  public._draft_reply_text(text, public.app_locale, jsonb),
  public._queue_whatsapp_reply(uuid, text, uuid),
  public.reserve_voice_order_run(uuid, uuid, uuid, public.draft_source, text, uuid),
  public.reserve_whatsapp_order(uuid, uuid),
  public.get_voice_order_context(uuid),
  public.create_order_draft(uuid, text, text, jsonb, jsonb, jsonb, text),
  public.fail_voice_order_run(uuid, text),
  public._draft_for(uuid, boolean),
  public._order_draft_json(uuid),
  public.get_order_draft(uuid),
  public.list_order_drafts(uuid, int),
  public.save_order_draft(uuid, jsonb, jsonb),
  public.submit_order_draft(uuid, int, text),
  public.reject_order_draft(uuid, text),
  public.admin_list_order_drafts(public.draft_status, text, int),
  public._notification_route(uuid, uuid, uuid, text),
  public.notifications_skip_self(),
  public._setup_voice_storage()
from public, anon, authenticated;

revoke execute on function public._setup_voice_storage() from service_role;

-- 表的检查（order_drafts.audio_path）要用
grant execute on function public._voice_path_ok(uuid, text) to authenticated, service_role;

-- App / 客服后台
grant execute on function
  public.get_order_draft(uuid),
  public.list_order_drafts(uuid, int),
  public.save_order_draft(uuid, jsonb, jsonb),
  public.submit_order_draft(uuid, int, text),
  public.reject_order_draft(uuid, text),
  public.admin_list_order_drafts(public.draft_status, text, int)
to authenticated;

-- 服务器
grant execute on function
  public.reserve_voice_order_run(uuid, uuid, uuid, public.draft_source, text, uuid),
  public.reserve_whatsapp_order(uuid, uuid),
  public.get_voice_order_context(uuid),
  public.create_order_draft(uuid, text, text, jsonb, jsonb, jsonb, text),
  public.fail_voice_order_run(uuid, text),
  public._notification_route(uuid, uuid, uuid, text)
to service_role;
