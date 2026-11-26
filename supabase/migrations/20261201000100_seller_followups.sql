-- 第四步补完：
--   A. get_order：批发商 / 客服看到店的 WhatsApp 号码（shop.whatsapp_phone；买家那边不回传）
--   B. claim_notifications：每条多回传收件的 wholesaler_id / shop_id（推送带 wholesaler_id，App 才知道换到哪一家）
--   C. list_seller_orders：游标分页（keyset：created_at, id），每一张多回传 cursor
--   D. 价目表导入：已上架的导入锁住（行、ai_raw 都不能改）；每一行「看过了」存在数据库（checked_at）

-- =============================================================================
-- A. get_order（照 20261126000100_buyer_app.sql 的最新定义，只改 shop 那一段）
-- =============================================================================
create or replace function public.get_order(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_is_admin boolean := public.is_admin();
begin
  select * into o from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;
  v_is_buyer := public.is_shop_member(o.shop_id);
  v_is_seller := public.is_wholesaler_member(o.wholesaler_id);
  if not (v_is_buyer or v_is_seller or v_is_admin) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'id', o.id,
    'order_no', o.order_no,
    'checkout_id', o.checkout_id,
    'status', o.status,
    'source', o.source,
    'goods_subtotal_sen', o.goods_subtotal_sen,
    'shipping_fee_sen', o.shipping_fee_sen,
    'total_sen', o.total_sen,
    'note', o.note,
    'expected_delivery_date', o.expected_delivery_date,
    'created_at', o.created_at,
    'confirmed_at', o.confirmed_at,
    'delivering_at', o.delivering_at,
    'delivered_at', o.delivered_at,
    'cancelled_at', o.cancelled_at,
    'cancel_reason', o.cancel_reason,
    'shop', (
      select jsonb_build_object('id', s.id, 'name', s.name, 'address', s.address, 'phone', s.phone,
                                'contact_name', s.contact_name, 'zone_name', z.name)
             -- WhatsApp 号码只给这家批发商和客服（联络买家用）；买家自己那边不需要
             || case when v_is_seller or v_is_admin
                     then jsonb_build_object('whatsapp_phone', s.whatsapp_phone)
                     else '{}'::jsonb end
      from public.shops s join public.delivery_zones z on z.id = s.zone_id where s.id = o.shop_id
    ),
    'wholesaler', (
      select jsonb_build_object('id', w.id, 'name', w.name, 'phone', w.phone, 'whatsapp_phone', w.whatsapp_phone,
                                'payment_terms', w.payment_terms)
      from public.wholesalers w where w.id = o.wholesaler_id
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'product_id', i.product_id, 'name', i.name_snapshot, 'unit', i.unit_snapshot,
        'pack_qty', i.pack_qty_snapshot, 'unit_price_sen', i.unit_price_sen, 'qty', i.qty,
        'line_total_sen', i.line_total_sen, 'is_out_of_stock', i.is_out_of_stock
      ) order by i.is_out_of_stock, i.name_snapshot)
      from public.order_items i where i.order_id = o.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'from_status', e.from_status, 'to_status', e.to_status, 'channel', e.channel,
        'note', e.note, 'created_at', e.created_at
      ) order by e.created_at, e.id)
      from public.order_status_events e where e.order_id = o.id
    ), '[]'::jsonb),
    'review', (
      select jsonb_build_object('rating', r.rating, 'tags', r.tags, 'comment', r.comment, 'created_at', r.created_at)
      from public.reviews r where r.order_id = o.id
    ),
    'actions', jsonb_build_object(
      'can_cancel', o.status in ('pending', 'confirmed') and (v_is_buyer or v_is_admin),
      'can_mark_received', o.status in ('confirmed', 'delivering') and (v_is_buyer or v_is_admin),
      'can_review', o.status = 'delivered' and v_is_buyer,
      'can_confirm', o.status = 'pending' and (v_is_seller or v_is_admin),
      'can_mark_delivering', o.status = 'confirmed' and (v_is_seller or v_is_admin),
      'can_mark_delivered', o.status in ('confirmed', 'delivering') and (v_is_seller or v_is_admin)
    )
  );
end;
$$;

revoke execute on function public.get_order(uuid) from public, anon, authenticated;
grant execute on function public.get_order(uuid) to authenticated;

-- =============================================================================
-- B. claim_notifications（照 20261127000200 的最新定义）：每条多回传 wholesaler_id、shop_id（收件人）。
--    dispatcher 把 wholesaler_id 放进推送的 data，一个人是两家批发商的成员时，按通知会打开对的那一家
-- =============================================================================
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
  return coalesce((
    select jsonb_agg(e || jsonb_build_object('wholesaler_id', n.wholesaler_id, 'shop_id', n.shop_id) order by t.ord)
    from jsonb_array_elements(v_out) with ordinality as t(e, ord)
    join public.notifications n on n.id = (t.e ->> 'id')::uuid
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.claim_notifications(int, uuid) from public, anon, authenticated;
grant execute on function public.claim_notifications(int, uuid) to service_role;

-- =============================================================================
-- C. list_seller_orders：游标分页
-- 排序跟原来一样：pending 在最前面（旧到新，先来先做），其他新到旧；同一个时间再按 id。
-- 每一张多回传 cursor（'p|时间|id' 或 'o|时间|id'，p = 在 pending 那一段）。下一页：p_after = 上一页最后一张的 cursor。
-- cursor 记的是读到的时候在哪一段：读第二页之前那张单改了状态也不会乱（最多那一张重复或少一张，App 按 id 去重）
-- =============================================================================
create or replace function public._seller_order_cursor(p_pending boolean, p_created_at timestamptz, p_id uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_pending then 'p' else 'o' end
         || '|' || pg_catalog.to_char(p_created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
         || '|' || p_id::text;
$$;

drop function public.list_seller_orders(uuid, public.order_status[], date, int);

create function public.list_seller_orders(
  p_wholesaler_id uuid,
  p_statuses public.order_status[] default null,
  p_delivery_date date default null,
  p_limit int default 50,
  p_after text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seg text;
  v_ts timestamptz;
  v_id uuid;
begin
  if not (public.is_wholesaler_member(p_wholesaler_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.wholesalers w where w.id = p_wholesaler_id) then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if nullif(p_after, '') is not null then
    if p_after !~ '^[po]\|\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      raise exception 'INVALID_CURSOR' using errcode = 'P0001';
    end if;
    v_seg := split_part(p_after, '|', 1);
    v_ts := split_part(p_after, '|', 2)::timestamptz;
    v_id := split_part(p_after, '|', 3)::uuid;
  end if;

  return coalesce((
    select jsonb_agg(x.j order by x.rn)
    from (
      select row_number() over (
               order by (o.status = 'pending') desc,
                        case when o.status = 'pending' then o.created_at end asc,
                        case when o.status = 'pending' then o.id end asc,
                        o.created_at desc,
                        o.id desc) as rn,
             jsonb_build_object(
               'id', o.id,
               'order_no', o.order_no,
               'status', o.status,
               'shop_name', s.name,
               'zone_name', z.name,
               'item_count', (select count(*) from public.order_items i where i.order_id = o.id),
               'out_of_stock_count', (select count(*) from public.order_items i where i.order_id = o.id and i.is_out_of_stock),
               'goods_subtotal_sen', o.goods_subtotal_sen,
               'shipping_fee_sen', o.shipping_fee_sen,
               'total_sen', o.total_sen,
               'note', o.note,
               'created_at', o.created_at,
               'expected_delivery_date', o.expected_delivery_date,
               'cursor', public._seller_order_cursor(o.status = 'pending', o.created_at, o.id)
             ) as j
      from public.orders o
      join public.shops s on s.id = o.shop_id
      join public.delivery_zones z on z.id = o.zone_id
      where o.wholesaler_id = p_wholesaler_id
        and (p_statuses is null or cardinality(p_statuses) = 0 or o.status = any (p_statuses))
        and (p_delivery_date is null or o.expected_delivery_date = p_delivery_date)
        and (v_seg is null
             -- 上一页停在 pending 那一段：pending 里比它晚的，再加上全部不是 pending 的
             or (v_seg = 'p' and (o.status <> 'pending' or (o.created_at, o.id) > (v_ts, v_id)))
             -- 停在其他那一段：不是 pending、而且比它早的
             or (v_seg = 'o' and o.status <> 'pending' and (o.created_at, o.id) < (v_ts, v_id)))
      order by rn
      limit greatest(least(coalesce(p_limit, 50), 200), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

create index if not exists orders_wholesaler_created_idx on public.orders (wholesaler_id, created_at desc, id desc);

revoke execute on function public._seller_order_cursor(boolean, timestamptz, uuid) from public, anon, authenticated;
revoke execute on function public.list_seller_orders(uuid, public.order_status[], date, int, text)
  from public, anon, authenticated;
grant execute on function public.list_seller_orders(uuid, public.order_status[], date, int, text) to authenticated;

-- =============================================================================
-- D. 价目表导入：上架后锁住；「看过了」存在数据库
-- =============================================================================

-- 老板看过、改过的行（AI 不太肯定的那几行就不再标黄色）。换手机、重开 App 也记得
alter table public.price_list_import_rows add column checked_at timestamptz;
comment on column public.price_list_import_rows.checked_at is
  '批发商看过 / 改过这一行的时间（App 改一行时 trigger 自动设；设成 null = 取消）。服务器写的行是 null';

-- 行的保护（每个人都检查，包括服务器和客服）：
--   导入已经上架（applied）→ 这一份的行不能新增、修改、删除 → IMPORT_ALREADY_APPLIED
--   （删掉整份导入时连带删掉的行可以：那时候导入已经不在了）
--   App（authenticated）改一行 = 看过了：checked_at 设成现在；特地改成 null 是取消
create or replace function public.price_list_import_rows_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    if exists (select 1 from public.price_list_imports i where i.id = old.import_id and i.status = 'applied') then
      raise exception 'IMPORT_ALREADY_APPLIED' using errcode = 'P0001', detail = old.row_no::text;
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  if exists (select 1 from public.price_list_imports i where i.id = new.import_id and i.status = 'applied') then
    raise exception 'IMPORT_ALREADY_APPLIED' using errcode = 'P0001', detail = new.row_no::text;
  end if;

  -- 跟 price_list_imports_guard 一样看 current_user：服务器、security definer 函数（suggest_import_matches）不算「看过」
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.checked_at := null;
    elsif not (new.checked_at is null and old.checked_at is not null) then
      new.checked_at := now();
    end if;
  end if;
  return new;
end;
$$;

create trigger price_list_import_rows_guard before insert or update or delete on public.price_list_import_rows
  for each row execute function public.price_list_import_rows_guard();

-- 导入本身：上架后 ai_raw、状态、上架时间都不能再改（每个人都检查）。
-- 名字排在 price_list_imports_guard 后面：App 自己改的话照样先看到 COLUMN_PROTECTED
create or replace function public.price_list_imports_lock_applied()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'applied' and (
       new.ai_raw is distinct from old.ai_raw
       or new.status is distinct from old.status
       or new.applied_at is distinct from old.applied_at) then
    raise exception 'IMPORT_ALREADY_APPLIED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger price_list_imports_lock_applied before update on public.price_list_imports
  for each row execute function public.price_list_imports_lock_applied();

revoke execute on function public.price_list_import_rows_guard() from public, anon, authenticated;
revoke execute on function public.price_list_imports_lock_applied() from public, anon, authenticated;
