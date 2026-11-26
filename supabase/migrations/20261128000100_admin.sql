-- =============================================================================
-- 第五步：客服后台（apps/admin_web）用的函数
--
--   A. 共用：_require_admin、_admin_audit（每个客服动作写一行 audit_logs）
--   B. 首页、店铺、批发商列表
--   C. 订单：全部订单（筛选）、超过 30 分钟没确认的跟进、代改状态
--   D. 代买家下单：购物车、下单
--   E. 代批发商管商品：列表、新增 / 修改（价钱、库存、上架 / 下架）
--   F. 批发商：审核 / 停权、佣金比例、创始会员、WhatsApp 同意
--   G. 订阅：列表、延长试用、手动标记已付、取消、创始价
--   H. 每月佣金报表和账单
--   I. 操作记录
--   J. 函数权限
--
-- 规则：
--   * 全部只给客服（is_admin()），否则 NOT_ALLOWED（42501）。
--   * 每个会改东西的函数都写一行 audit_logs（action = 函数名，acting_for = 代哪家店 / 批发商）。
--     表本身的 trigger（audit_admin_changes）照样会记每一行改了什么。
--   * 改订单状态、下单还是走原来的 set_order_status / confirm_order / place_order，规则只有一份。
-- =============================================================================

-- =============================================================================
-- A. 共用
-- =============================================================================

create or replace function public._require_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
end;
$$;

-- 写一行客服动作记录，回传 id
create or replace function public._admin_audit(
  p_action text,
  p_table text,
  p_record_id text,
  p_shop_id uuid default null,
  p_wholesaler_id uuid default null,
  p_before jsonb default null,
  p_after jsonb default null
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (
    actor_id, acting_for_shop_id, acting_for_wholesaler_id, action, table_name, record_id, before, after
  )
  values (auth.uid(), p_shop_id, p_wholesaler_id, p_action, p_table, p_record_id, p_before, p_after)
  returning id;
$$;

-- 订单太久没确认的门槛（分钟）
create or replace function public._alert_minutes()
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select a.order_confirm_alert_minutes from public.app_settings a), 30);
$$;

-- 订阅的样子（列表、改完回传都用这个）
create or replace function public._admin_subscription_json(p_subscription_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s.id,
    'shop_id', s.shop_id,
    'shop_name', sh.name,
    'shop_phone', coalesce(sh.whatsapp_phone, sh.phone),
    'status', s.status,
    'started_at', s.started_at,
    'trial_ends_at', s.trial_ends_at,
    'locked_price_sen', s.locked_price_sen,
    'is_founding_price', s.is_founding_price,
    'current_period_start', s.current_period_start,
    'current_period_end', s.current_period_end,
    'grace_until', s.grace_until,
    'lapsed_at', s.lapsed_at,
    'has_full_access', public.has_full_access(s.shop_id),
    'last_payment', (
      select jsonb_build_object('id', p.id, 'amount_sen', p.amount_sen, 'method', p.method,
                                'gateway', p.gateway, 'gateway_ref', p.gateway_ref, 'paid_at', p.paid_at)
      from public.payments p
      where p.purpose = 'subscription' and p.reference_id = s.id and p.status = 'paid'
      order by p.paid_at desc nulls last, p.created_at desc
      limit 1
    ),
    'created_at', s.created_at
  )
  from public.subscriptions s
  join public.shops sh on sh.id = s.shop_id
  where s.id = p_subscription_id;
$$;

-- 批发商的样子（列表、改完回传都用这个）
create or replace function public._admin_wholesaler_json(p_wholesaler_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', w.id,
    'name', w.name,
    'status', w.status,
    'is_founding', w.is_founding,
    'founding_no', w.founding_no,
    'contact_name', w.contact_name,
    'phone', w.phone,
    'whatsapp_phone', w.whatsapp_phone,
    'whatsapp_opt_in_at', w.whatsapp_opt_in_at,
    'notify_channel', w.notify_channel,
    'region_name', r.name,
    'industry_name', i.name,
    'commission_rate', cr.rate,
    'commission_rate_source', cr.rate_source,
    'commission_rate_override', wp.commission_rate_override,
    'industry_default_rate', i.default_commission_rate,
    'industry_founding_rate', i.founding_commission_rate,
    'active_product_count', (select count(*) from public.products p where p.wholesaler_id = w.id and p.status = 'active'),
    'pending_order_count', (select count(*) from public.orders o where o.wholesaler_id = w.id and o.status = 'pending'),
    'member_count', (select count(*) from public.wholesaler_members m where m.wholesaler_id = w.id),
    'rating_avg', w.rating_avg,
    'rating_count', w.rating_count,
    'approved_at', w.approved_at,
    'created_at', w.created_at
  )
  from public.wholesalers w
  join public.regions r on r.id = w.region_id
  join public.industries i on i.id = w.industry_id
  left join public.wholesaler_private wp on wp.wholesaler_id = w.id
  cross join lateral public.commission_rate_for(w.id) cr
  where w.id = p_wholesaler_id;
$$;

-- =============================================================================
-- B. 首页、店铺、批发商列表
-- =============================================================================

create or replace function public.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public.today_myt();
  v_month date := date_trunc('month', public.today_myt())::date;
  v_minutes int := public._alert_minutes();
begin
  perform public._require_admin();
  return jsonb_build_object(
    'today', v_today,
    'alert_minutes', v_minutes,
    'pending_wholesalers', (select count(*) from public.wholesalers w where w.status = 'pending'),
    'unconfirmed_orders', (
      select count(*) from public.orders o
      where o.status = 'pending' and o.created_at <= now() - make_interval(mins => v_minutes)),
    'pending_orders', (select count(*) from public.orders o where o.status = 'pending'),
    'today_order_count', (
      select count(*) from public.orders o where (o.created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'today_total_sen', (
      select coalesce(sum(o.total_sen), 0) from public.orders o
      where (o.created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today and o.status <> 'cancelled'),
    'subscriptions', (
      select jsonb_build_object(
        'trialing', count(*) filter (where l.status = 'trialing'),
        'active', count(*) filter (where l.status = 'active'),
        'past_due', count(*) filter (where l.status = 'past_due'),
        'lapsed', count(*) filter (where l.status = 'lapsed'),
        'founding_price', count(*) filter (where l.is_founding_price and l.status <> 'lapsed'))
      from (
        select distinct on (s.shop_id) s.status, s.is_founding_price
        from public.subscriptions s
        order by s.shop_id, s.created_at desc
      ) l
    ),
    'month', v_month,
    'month_gmv_sen', (
      select coalesce(sum(cr.base_amount_sen), 0) from public.commission_records cr where cr.period_month = v_month),
    'month_commission_sen', (
      select coalesce(sum(cr.commission_sen), 0) from public.commission_records cr where cr.period_month = v_month)
  );
end;
$$;

-- 把搜索文字变成 ilike 的样子（%、_ 当普通字）
create or replace function public._like_pattern(p_search text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when nullif(trim(p_search), '') is null then null
    else '%' || replace(replace(replace(trim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  end;
$$;

-- 搜索文字像电话号码（只有数字、空格、+、-、括号，至少 3 个数字）→ 比对电话的 like 样子。
-- 存的电话是 60 开头（60123456789），老板打的常常是 012-345 6789：去掉开头的 0 / 60 再比
create or replace function public._phone_pattern(p_search text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_search ~ '^[0-9+()\- ]+$' and length(regexp_replace(p_search, '\D', '', 'g')) >= 3
      then '%' || regexp_replace(regexp_replace(p_search, '\D', '', 'g'), '^(60|0)+', '') || '%'
  end;
$$;

create or replace function public.admin_list_shops(p_search text default null, p_limit int default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := public._like_pattern(p_search);
  v_digits text := public._phone_pattern(p_search);
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(x.j order by x.name, x.id)
    from (
      select s.name, s.id, jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'shop_type', s.shop_type,
        'zone_id', s.zone_id,
        'zone_name', z.name,
        'address', s.address,
        'contact_name', s.contact_name,
        'phone', s.phone,
        'whatsapp_phone', s.whatsapp_phone,
        'whatsapp_opt_in_at', s.whatsapp_opt_in_at,
        'is_active', s.is_active,
        'member_count', (select count(*) from public.shop_members m where m.shop_id = s.id),
        'cart_count', (select count(*) from public.cart_items c where c.shop_id = s.id),
        'has_full_access', public.has_full_access(s.id),
        'subscription_status', (
          select sub.status from public.subscriptions sub where sub.shop_id = s.id order by sub.created_at desc limit 1),
        'created_at', s.created_at
      ) as j
      from public.shops s
      join public.delivery_zones z on z.id = s.zone_id
      where v_like is null
         or s.name ilike v_like
         or s.contact_name ilike v_like
         or (v_digits is not null and (s.phone like v_digits or s.whatsapp_phone like v_digits))
      order by s.name, s.id
      limit greatest(least(coalesce(p_limit, 50), 200), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_wholesalers(
  p_status public.wholesaler_status default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := public._like_pattern(p_search);
  v_digits text := public._phone_pattern(p_search);
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(public._admin_wholesaler_json(w.id)
                     order by case w.status when 'pending' then 0 when 'active' then 1 else 2 end, w.name, w.id)
    from public.wholesalers w
    where (p_status is null or w.status = p_status)
      and (v_like is null
           or w.name ilike v_like
           or w.contact_name ilike v_like
           or (v_digits is not null and (w.phone like v_digits or w.whatsapp_phone like v_digits)))
  ), '[]'::jsonb);
end;
$$;

-- =============================================================================
-- C. 订单
-- =============================================================================

-- 全部订单。日期按马来西亚时间的下单日期（p_from、p_to 都包括）；
-- p_unconfirmed_only = 待确认超过 app_settings.order_confirm_alert_minutes 分钟的（跟进名单，旧的先）。
-- 回传 {total, orders: [...]}；total 是符合条件的总数（分页用）
create or replace function public.admin_list_orders(
  p_from date default null,
  p_to date default null,
  p_wholesaler_id uuid default null,
  p_shop_id uuid default null,
  p_statuses public.order_status[] default null,
  p_sources public.order_source[] default null,
  p_unconfirmed_only boolean default false,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_minutes int := public._alert_minutes();
  v_statuses public.order_status[] := case when cardinality(p_statuses) > 0 then p_statuses end;
  v_sources public.order_source[] := case when cardinality(p_sources) > 0 then p_sources end;
  v_unconfirmed boolean := coalesce(p_unconfirmed_only, false);
  v_limit int := greatest(least(coalesce(p_limit, 100), 500), 1);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_total int;
  v_rows jsonb;
begin
  perform public._require_admin();

  with hit as (
    select o.id, o.created_at, o.order_no
    from public.orders o
    where (p_from is null or (o.created_at at time zone 'Asia/Kuala_Lumpur')::date >= p_from)
      and (p_to is null or (o.created_at at time zone 'Asia/Kuala_Lumpur')::date <= p_to)
      and (p_wholesaler_id is null or o.wholesaler_id = p_wholesaler_id)
      and (p_shop_id is null or o.shop_id = p_shop_id)
      and (v_statuses is null or o.status = any (v_statuses))
      and (v_sources is null or o.source = any (v_sources))
      and (not v_unconfirmed
           or (o.status = 'pending' and o.created_at <= now() - make_interval(mins => v_minutes)))
  ),
  page as (
    select h.id,
           row_number() over (order by
             case when v_unconfirmed then h.created_at end asc,
             case when not v_unconfirmed then h.created_at end desc,
             h.order_no desc) as rn
    from hit h
    order by rn
    limit v_limit offset v_offset
  )
  select
    (select count(*) from hit),
    coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id,
      'order_no', o.order_no,
      'status', o.status,
      'source', o.source,
      'shop_id', o.shop_id,
      'shop_name', s.name,
      'shop_phone', coalesce(s.whatsapp_phone, s.phone),
      'wholesaler_id', o.wholesaler_id,
      'wholesaler_name', w.name,
      'wholesaler_phone', coalesce(w.whatsapp_phone, w.phone),
      'goods_subtotal_sen', o.goods_subtotal_sen,
      'shipping_fee_sen', o.shipping_fee_sen,
      'total_sen', o.total_sen,
      'item_count', (select count(*) from public.order_items i where i.order_id = o.id),
      'out_of_stock_count', (select count(*) from public.order_items i where i.order_id = o.id and i.is_out_of_stock),
      'created_at', o.created_at,
      'expected_delivery_date', o.expected_delivery_date,
      'pending_minutes', case when o.status = 'pending'
        then floor(extract(epoch from now() - o.created_at) / 60)::int end,
      'unconfirmed_alert_at', o.unconfirmed_alert_at,
      'last_followup', (
        select jsonb_build_object('at', a.created_at, 'note', a.after ->> 'note')
        from public.audit_logs a
        where a.action = 'admin_log_followup' and a.record_id = o.id::text
        order by a.created_at desc, a.id desc
        limit 1)
    ) order by pg.rn), '[]'::jsonb)
  into v_total, v_rows
  from page pg
  join public.orders o on o.id = pg.id
  join public.shops s on s.id = o.shop_id
  join public.wholesalers w on w.id = o.wholesaler_id;

  return jsonb_build_object('total', v_total, 'orders', v_rows);
end;
$$;

-- 跟进名单：客服打过电话了，记一句（例如「批发商说 3 点前确认」）
create or replace function public.admin_log_followup(p_order_id uuid, p_note text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
begin
  perform public._require_admin();
  select * into o from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if nullif(trim(p_note), '') is null or length(p_note) > 500 then
    raise exception 'INVALID_NOTE' using errcode = 'P0001';
  end if;
  return public._admin_audit('admin_log_followup', 'orders', o.id::text, o.shop_id, o.wholesaler_id,
    null, jsonb_build_object('note', trim(p_note), 'status', o.status));
end;
$$;

-- 代改订单状态（跟批发商 / 老板一样走 set_order_status，规则只有一份）
create or replace function public.admin_set_order_status(
  p_order_id uuid,
  p_status public.order_status,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
  v_after public.orders%rowtype;
begin
  perform public._require_admin();
  select * into o from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform public.set_order_status(p_order_id, p_status, p_note, 'admin');
  select * into v_after from public.orders where id = p_order_id;
  perform public._admin_audit('admin_set_order_status', 'orders', o.id::text, o.shop_id, o.wholesaler_id,
    jsonb_build_object('status', o.status),
    jsonb_build_object('status', v_after.status, 'note', nullif(trim(p_note), '')));
  return public.get_order(p_order_id);
end;
$$;

-- 代批发商确认（可以标几样缺货；全部缺货 → 缺货）
create or replace function public.admin_confirm_order(
  p_order_id uuid,
  p_out_of_stock_item_ids uuid[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
  v_status public.order_status;
begin
  perform public._require_admin();
  select * into o from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;
  v_status := public.confirm_order(p_order_id, coalesce(p_out_of_stock_item_ids, '{}'), 'admin');
  perform public._admin_audit('admin_confirm_order', 'orders', o.id::text, o.shop_id, o.wholesaler_id,
    jsonb_build_object('status', o.status, 'goods_subtotal_sen', o.goods_subtotal_sen),
    jsonb_build_object('status', v_status, 'out_of_stock_item_ids', to_jsonb(coalesce(p_out_of_stock_item_ids, '{}')),
                       'goods_subtotal_sen', (select x.goods_subtotal_sen from public.orders x where x.id = p_order_id)));
  return public.get_order(p_order_id);
end;
$$;

-- =============================================================================
-- D. 代买家下单
-- =============================================================================

-- 改这家店购物车里一样商品的数量（0 = 拿掉）。看报价用原来的 quote_cart(p_shop_id)
create or replace function public.admin_set_cart_item(p_shop_id uuid, p_product_id uuid, p_qty int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old int;
  v_wholesaler uuid;
begin
  perform public._require_admin();
  if not exists (select 1 from public.shops s where s.id = p_shop_id) then
    raise exception 'SHOP_NOT_FOUND' using errcode = 'P0001';
  end if;
  select p.wholesaler_id into v_wholesaler from public.products p where p.id = p_product_id;
  if v_wholesaler is null then
    raise exception 'PRODUCT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_qty is null or p_qty < 0 or p_qty > 100000 then
    raise exception 'INVALID_QTY' using errcode = 'P0001';
  end if;

  select c.qty into v_old from public.cart_items c where c.shop_id = p_shop_id and c.product_id = p_product_id;
  if p_qty = 0 then
    delete from public.cart_items c where c.shop_id = p_shop_id and c.product_id = p_product_id;
  else
    insert into public.cart_items (shop_id, product_id, qty, added_by)
    values (p_shop_id, p_product_id, p_qty, auth.uid())
    on conflict (shop_id, product_id) do update set qty = excluded.qty, added_by = excluded.added_by;
  end if;
  if v_old is distinct from nullif(p_qty, 0) then
    perform public._admin_audit('admin_set_cart_item', 'cart_items', p_product_id::text, p_shop_id, v_wholesaler,
      jsonb_build_object('qty', v_old), jsonb_build_object('qty', nullif(p_qty, 0)));
  end if;
  return public._quote_cart(p_shop_id);
end;
$$;

create or replace function public.admin_clear_cart(p_shop_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_items jsonb;
  v_count int;
begin
  perform public._require_admin();
  select coalesce(jsonb_agg(jsonb_build_object('product_id', c.product_id, 'qty', c.qty)), '[]'::jsonb)
  into v_items from public.cart_items c where c.shop_id = p_shop_id;
  delete from public.cart_items c where c.shop_id = p_shop_id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform public._admin_audit('admin_clear_cart', 'cart_items', p_shop_id::text, p_shop_id, null,
      jsonb_build_object('items', v_items), null);
  end if;
  return v_count;
end;
$$;

-- 代买家下单：订单来源是「客服」（admin），状态记录的 channel 是 admin。
-- p_expected_total_sen = 客服在画面上看到的总额，对不上 → PRICE_CHANGED（跟 App 一样）
create or replace function public.admin_place_order(
  p_shop_id uuid,
  p_expected_total_sen int,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checkout uuid;
  v_orders jsonb;
begin
  perform public._require_admin();
  if not exists (select 1 from public.shops s where s.id = p_shop_id) then
    raise exception 'SHOP_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_expected_total_sen is null then
    raise exception 'EXPECTED_TOTAL_REQUIRED' using errcode = 'P0001';
  end if;
  v_checkout := public.place_order(p_shop_id, p_expected_total_sen, p_note, 'admin');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id, 'order_no', o.order_no, 'wholesaler_id', o.wholesaler_id, 'wholesaler_name', w.name,
    'total_sen', o.total_sen) order by o.order_no), '[]'::jsonb)
  into v_orders
  from public.orders o join public.wholesalers w on w.id = o.wholesaler_id
  where o.checkout_id = v_checkout;

  perform public._admin_audit('admin_place_order', 'checkouts', v_checkout::text, p_shop_id, null, null,
    jsonb_build_object('checkout_id', v_checkout, 'total_sen', p_expected_total_sen,
                       'note', nullif(trim(p_note), ''), 'orders', v_orders));
  return jsonb_build_object('checkout_id', v_checkout, 'orders', v_orders);
end;
$$;

-- =============================================================================
-- E. 代批发商管商品
-- =============================================================================

-- 这家批发商的全部商品（包括草稿和下架的），栏位跟 products 表一样（App 的 SellerProduct）
create or replace function public.admin_list_products(p_wholesaler_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  if not exists (select 1 from public.wholesalers w where w.id = p_wholesaler_id) then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(p) - 'created_by'
                     order by case p.status when 'active' then 0 when 'draft' then 1 else 2 end, p.sort_order, p.name, p.id)
    from public.products p
    where p.wholesaler_id = p_wholesaler_id
  ), '[]'::jsonb);
end;
$$;

-- 新增（p_product_id 空）或修改一样商品。p_fields 只能有这些栏：
--   name, description, unit, pack_qty, price_sen, min_order_qty, stock_status, status,
--   catalog_item_id, category_id, lead_time_days_override, sort_order
-- 上架 = status active，下架 = archived。回传存好的那一行
create or replace function public.admin_save_product(
  p_wholesaler_id uuid,
  p_product_id uuid,
  p_fields jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allowed text[] := array['name', 'description', 'unit', 'pack_qty', 'price_sen', 'min_order_qty', 'stock_status',
                            'status', 'catalog_item_id', 'category_id', 'lead_time_days_override', 'sort_order'];
  v_bad text;
  v_old public.products%rowtype;
  v_new public.products%rowtype;
  v_fields jsonb := coalesce(p_fields, '{}'::jsonb);
begin
  perform public._require_admin();
  if jsonb_typeof(v_fields) <> 'object' then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001';
  end if;
  select k into v_bad from jsonb_object_keys(v_fields) as t(k) where not (k = any (v_allowed)) limit 1;
  if v_bad is not null then
    raise exception 'INVALID_FIELD' using errcode = 'P0001', detail = v_bad;
  end if;
  if not exists (select 1 from public.wholesalers w where w.id = p_wholesaler_id) then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;

  if p_product_id is not null then
    select * into v_old from public.products p where p.id = p_product_id and p.wholesaler_id = p_wholesaler_id for update;
    if not found then
      raise exception 'PRODUCT_NOT_FOUND' using errcode = 'P0001';
    end if;
  else
    v_old.id := gen_random_uuid();
    v_old.wholesaler_id := p_wholesaler_id;
    v_old.photo_paths := '{}';
    v_old.pack_qty := 1;
    v_old.min_order_qty := 1;
    v_old.stock_status := 'in_stock';
    v_old.status := 'active';
    v_old.sort_order := 0;
  end if;

  begin
    v_new := jsonb_populate_record(v_old, v_fields);
  exception when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = sqlerrm;
  end;

  if nullif(trim(v_new.name), '') is null then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'name';
  elsif v_new.unit is null then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'unit';
  elsif coalesce(v_new.pack_qty, 0) <= 0 then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'pack_qty';
  elsif coalesce(v_new.price_sen, 0) <= 0 then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'price_sen';
  elsif coalesce(v_new.min_order_qty, 0) <= 0 then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'min_order_qty';
  elsif v_new.lead_time_days_override is not null and v_new.lead_time_days_override not between 0 and 30 then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'lead_time_days_override';
  elsif v_new.stock_status is null or v_new.status is null then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'status';
  end if;
  if v_new.catalog_item_id is not null and not exists (select 1 from public.catalog_items c where c.id = v_new.catalog_item_id) then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'catalog_item_id';
  end if;
  if v_new.category_id is not null and not exists (select 1 from public.categories c where c.id = v_new.category_id) then
    raise exception 'INVALID_PRODUCT' using errcode = 'P0001', detail = 'category_id';
  end if;
  -- 跟 apply_price_list_import 一样：没给分类就跟着标准商品
  if v_new.category_id is null and v_new.catalog_item_id is not null then
    select c.category_id into v_new.category_id from public.catalog_items c where c.id = v_new.catalog_item_id;
  end if;

  if p_product_id is null then
    insert into public.products (
      id, wholesaler_id, catalog_item_id, category_id, name, description, photo_paths, unit, pack_qty, price_sen,
      min_order_qty, stock_status, lead_time_days_override, status, sort_order, created_by
    )
    values (
      v_new.id, p_wholesaler_id, v_new.catalog_item_id, v_new.category_id, trim(v_new.name), v_new.description,
      v_new.photo_paths, v_new.unit, v_new.pack_qty, v_new.price_sen, v_new.min_order_qty, v_new.stock_status,
      v_new.lead_time_days_override, v_new.status, v_new.sort_order, auth.uid()
    )
    returning * into v_new;
  else
    update public.products p set
      catalog_item_id = v_new.catalog_item_id,
      category_id = v_new.category_id,
      name = trim(v_new.name),
      description = v_new.description,
      unit = v_new.unit,
      pack_qty = v_new.pack_qty,
      price_sen = v_new.price_sen,
      min_order_qty = v_new.min_order_qty,
      stock_status = v_new.stock_status,
      lead_time_days_override = v_new.lead_time_days_override,
      status = v_new.status,
      sort_order = v_new.sort_order
    where p.id = p_product_id
    returning * into v_new;
  end if;

  perform public._admin_audit(
    case when p_product_id is null then 'admin_create_product' else 'admin_update_product' end,
    'products', v_new.id::text, null, p_wholesaler_id,
    case when p_product_id is null then null else to_jsonb(v_old) - 'created_by' - 'updated_at' end,
    to_jsonb(v_new) - 'created_by' - 'updated_at');
  return to_jsonb(v_new) - 'created_by';
end;
$$;

-- =============================================================================
-- F. 批发商：审核 / 停权、佣金比例、创始会员、WhatsApp 同意
-- =============================================================================

-- pending → active（审核通过，记下谁、什么时候）、pending → suspended（不通过）、
-- active → suspended（停权）、suspended → active（恢复）。不能改回 pending
create or replace function public.admin_set_wholesaler_status(
  p_wholesaler_id uuid,
  p_status public.wholesaler_status,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  w public.wholesalers%rowtype;
begin
  perform public._require_admin();
  select * into w from public.wholesalers where id = p_wholesaler_id for update;
  if not found then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if w.status = p_status then
    return public._admin_wholesaler_json(p_wholesaler_id);
  end if;
  if p_status is null or p_status = 'pending' then
    raise exception 'INVALID_TRANSITION' using errcode = 'P0001', detail = format('%s -> %s', w.status, p_status);
  end if;

  update public.wholesalers set
    status = p_status,
    approved_at = case when p_status = 'active' and approved_at is null then now() else approved_at end,
    approved_by = case when p_status = 'active' and approved_by is null then auth.uid() else approved_by end
  where id = p_wholesaler_id;

  perform public._admin_audit('admin_set_wholesaler_status', 'wholesalers', p_wholesaler_id::text, null, p_wholesaler_id,
    jsonb_build_object('status', w.status), jsonb_build_object('status', p_status, 'note', nullif(trim(p_note), '')));
  return public._admin_wholesaler_json(p_wholesaler_id);
end;
$$;

-- 单独调整佣金比例（0 到 0.2，例如 0.015 = 1.5%）；空 = 取消调整，回到创始 / 行业默认。
-- 只影响之后送达的订单（旧的佣金记录已经存了当时的比例）
create or replace function public.admin_set_commission_rate(p_wholesaler_id uuid, p_rate numeric)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old numeric;
begin
  perform public._require_admin();
  if not exists (select 1 from public.wholesalers w where w.id = p_wholesaler_id) then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_rate is not null and (p_rate < 0 or p_rate > 0.2 or p_rate <> round(p_rate, 4)) then
    raise exception 'INVALID_RATE' using errcode = 'P0001';
  end if;
  insert into public.wholesaler_private (wholesaler_id) values (p_wholesaler_id) on conflict do nothing;
  select wp.commission_rate_override into v_old from public.wholesaler_private wp where wp.wholesaler_id = p_wholesaler_id;
  update public.wholesaler_private set commission_rate_override = p_rate where wholesaler_id = p_wholesaler_id;
  perform public._admin_audit('admin_set_commission_rate', 'wholesaler_private', p_wholesaler_id::text, null, p_wholesaler_id,
    jsonb_build_object('commission_rate_override', v_old), jsonb_build_object('commission_rate_override', p_rate));
  return public._admin_wholesaler_json(p_wholesaler_id);
end;
$$;

-- 设为 / 取消创始会员（设的时候自动编号，名额满了 → FOUNDING_QUOTA_FULL）
create or replace function public.admin_set_wholesaler_founding(p_wholesaler_id uuid, p_is_founding boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  w public.wholesalers%rowtype;
begin
  perform public._require_admin();
  select * into w from public.wholesalers where id = p_wholesaler_id for update;
  if not found then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_is_founding is null then
    raise exception 'INVALID_VALUE' using errcode = 'P0001';
  end if;
  if w.is_founding = p_is_founding then
    return public._admin_wholesaler_json(p_wholesaler_id);
  end if;
  update public.wholesalers set
    is_founding = p_is_founding,
    founding_no = case when p_is_founding then founding_no end
  where id = p_wholesaler_id;
  perform public._admin_audit('admin_set_wholesaler_founding', 'wholesalers', p_wholesaler_id::text, null, p_wholesaler_id,
    jsonb_build_object('is_founding', w.is_founding, 'founding_no', w.founding_no),
    jsonb_build_object('is_founding', p_is_founding,
                       'founding_no', (select x.founding_no from public.wholesalers x where x.id = p_wholesaler_id)));
  return public._admin_wholesaler_json(p_wholesaler_id);
end;
$$;

-- 登记店铺 / 批发商同意用 WhatsApp 收消息（Meta 规定；没有就不发）。p_shop_id、p_wholesaler_id 给一个
create or replace function public.admin_set_whatsapp_opt_in(
  p_shop_id uuid default null,
  p_wholesaler_id uuid default null,
  p_opt_in boolean default true
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old timestamptz;
  v_new timestamptz;
begin
  perform public._require_admin();
  if num_nonnulls(p_shop_id, p_wholesaler_id) <> 1 or p_opt_in is null then
    raise exception 'INVALID_VALUE' using errcode = 'P0001';
  end if;
  if p_shop_id is not null then
    select s.whatsapp_opt_in_at into v_old from public.shops s where s.id = p_shop_id for update;
    if not found then
      raise exception 'SHOP_NOT_FOUND' using errcode = 'P0001';
    end if;
    update public.shops set whatsapp_opt_in_at = case when p_opt_in then coalesce(v_old, now()) end
    where id = p_shop_id returning whatsapp_opt_in_at into v_new;
  else
    select w.whatsapp_opt_in_at into v_old from public.wholesalers w where w.id = p_wholesaler_id for update;
    if not found then
      raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
    end if;
    update public.wholesalers set whatsapp_opt_in_at = case when p_opt_in then coalesce(v_old, now()) end
    where id = p_wholesaler_id returning whatsapp_opt_in_at into v_new;
  end if;
  if v_old is distinct from v_new then
    perform public._admin_audit('admin_set_whatsapp_opt_in', case when p_shop_id is null then 'wholesalers' else 'shops' end,
      coalesce(p_shop_id, p_wholesaler_id)::text, p_shop_id, p_wholesaler_id,
      jsonb_build_object('whatsapp_opt_in_at', v_old), jsonb_build_object('whatsapp_opt_in_at', v_new));
  end if;
  return v_new;
end;
$$;

-- =============================================================================
-- G. 订阅
-- =============================================================================

-- 每家店最新的一条订阅。p_founding_only = 只看创始价的
create or replace function public.admin_list_subscriptions(
  p_status public.subscription_status default null,
  p_founding_only boolean default false,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := public._like_pattern(p_search);
  v_digits text := public._phone_pattern(p_search);
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(public._admin_subscription_json(l.id) order by l.shop_name, l.id)
    from (
      select distinct on (s.shop_id) s.id, s.status, s.is_founding_price, sh.name as shop_name, sh.phone, sh.whatsapp_phone
      from public.subscriptions s
      join public.shops sh on sh.id = s.shop_id
      order by s.shop_id, s.created_at desc
    ) l
    where (p_status is null or l.status = p_status)
      and (not coalesce(p_founding_only, false) or l.is_founding_price)
      and (v_like is null or l.shop_name ilike v_like
           or (v_digits is not null and (l.phone like v_digits or l.whatsapp_phone like v_digits)))
  ), '[]'::jsonb);
end;
$$;

-- 延长试用 p_days 天（1–90）。试用中：从现在的结束日（还没到就从今天）往后加；
-- 试用刚过期（lapsed、从来没付过、这家店没有别的订阅）：重新打开试用
create or replace function public.admin_extend_trial(p_subscription_id uuid, p_days int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
begin
  perform public._require_admin();
  if p_days is null or p_days < 1 or p_days > 90 then
    raise exception 'INVALID_DAYS' using errcode = 'P0001';
  end if;
  select * into s from public.subscriptions where id = p_subscription_id for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;

  if s.status = 'trialing' then
    update public.subscriptions
    set trial_ends_at = greatest(coalesce(trial_ends_at, now()), now()) + make_interval(days => p_days)
    where id = s.id;
  elsif s.status = 'lapsed' and s.current_period_end is null and s.trial_ends_at is not null
        and not exists (select 1 from public.subscriptions x where x.shop_id = s.shop_id and x.created_at > s.created_at)
        and not exists (select 1 from public.subscriptions x where x.shop_id = s.shop_id and x.status <> 'lapsed') then
    update public.subscriptions
    set status = 'trialing', trial_ends_at = now() + make_interval(days => p_days), lapsed_at = null
    where id = s.id;
  else
    raise exception 'INVALID_SUBSCRIPTION_STATE' using errcode = 'P0001', detail = s.status::text;
  end if;

  perform public._admin_audit('admin_extend_trial', 'subscriptions', s.id::text, s.shop_id, null,
    jsonb_build_object('status', s.status, 'trial_ends_at', s.trial_ends_at),
    (select jsonb_build_object('status', x.status, 'trial_ends_at', x.trial_ends_at, 'days', p_days)
     from public.subscriptions x where x.id = s.id));
  return public._admin_subscription_json(s.id);
end;
$$;

-- 手动标记已付（老板转账 / 现金给客服）：记一笔付款（gateway = manual），订阅往后延 p_months 个月。
--   试用中 → active，从试用结束（或今天）开始算；
--   active / past_due → 从原来的结束日接着算，锁定的月费不变（宽限期内补付保留原价）；
--   lapsed（已停）→ 照规则新建一条订阅，按今天的价钱锁定（不能用回旧价钱）。
-- p_amount_sen 空 = 锁定的月费 x 月数。p_reference = 银行转账参考号（同一个不能记两次）
create or replace function public.admin_mark_subscription_paid(
  p_subscription_id uuid,
  p_months int default 1,
  p_amount_sen int default null,
  p_method public.payment_method default 'other',
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
  v_plan record;
  v_sub_id uuid;
  v_start timestamptz;
  v_price int;
  v_amount int;
  v_payment uuid;
  v_ref text := nullif(trim(p_reference), '');
begin
  perform public._require_admin();
  if p_months is null or p_months < 1 or p_months > 24 then
    raise exception 'INVALID_MONTHS' using errcode = 'P0001';
  end if;
  if p_amount_sen is not null and p_amount_sen <= 0 then
    raise exception 'INVALID_AMOUNT' using errcode = 'P0001';
  end if;
  select * into s from public.subscriptions where id = p_subscription_id for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;

  if s.status = 'lapsed' then
    if exists (select 1 from public.subscriptions x where x.shop_id = s.shop_id and x.status <> 'lapsed') then
      raise exception 'SUBSCRIPTION_ALREADY_OPEN' using errcode = 'P0001';
    end if;
    select * into v_plan from public.current_plan('buyer_monthly');
    if v_plan.plan_id is null then
      raise exception 'NO_PRICING_PLAN' using errcode = 'P0001';
    end if;
    v_price := v_plan.amount_sen;
    insert into public.subscriptions (
      shop_id, status, started_at, locked_price_sen, is_founding_price, current_period_start, current_period_end
    )
    values (s.shop_id, 'active', now(), v_price, v_plan.is_founding, now(), now() + make_interval(months => p_months))
    returning id into v_sub_id;
  else
    v_price := s.locked_price_sen;
    v_start := case
      when s.status = 'trialing' then greatest(now(), coalesce(s.trial_ends_at, now()))
      else coalesce(s.current_period_end, now())
    end;
    update public.subscriptions set
      status = 'active',
      current_period_start = v_start,
      current_period_end = v_start + make_interval(months => p_months),
      grace_until = null
    where id = s.id;
    v_sub_id := s.id;
  end if;

  v_amount := coalesce(p_amount_sen, v_price * p_months);
  begin
    insert into public.payments (
      payer_type, shop_id, purpose, reference_id, amount_sen, gateway, method, gateway_ref, status, paid_at, raw
    )
    values ('shop', s.shop_id, 'subscription', v_sub_id, v_amount, 'manual', coalesce(p_method, 'other'), v_ref,
            'paid', now(), jsonb_build_object('months', p_months, 'recorded_by', auth.uid()))
    returning id into v_payment;
  exception when unique_violation then
    raise exception 'DUPLICATE_PAYMENT_REFERENCE' using errcode = 'P0001', detail = v_ref;
  end;

  perform public._admin_audit('admin_mark_subscription_paid', 'subscriptions', v_sub_id::text, s.shop_id, null,
    jsonb_build_object('subscription_id', s.id, 'status', s.status, 'current_period_end', s.current_period_end,
                       'locked_price_sen', s.locked_price_sen),
    (select jsonb_build_object('subscription_id', x.id, 'status', x.status, 'current_period_end', x.current_period_end,
                               'locked_price_sen', x.locked_price_sen, 'payment_id', v_payment, 'amount_sen', v_amount,
                               'months', p_months, 'method', coalesce(p_method, 'other'), 'reference', v_ref)
     from public.subscriptions x where x.id = v_sub_id));
  return public._admin_subscription_json(v_sub_id) || jsonb_build_object('payment_id', v_payment);
end;
$$;

-- 取消订阅：马上停（lapsed）。之后回来要新建订阅，按当时的价钱锁定
create or replace function public.admin_cancel_subscription(p_subscription_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
begin
  perform public._require_admin();
  select * into s from public.subscriptions where id = p_subscription_id for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;
  if s.status = 'lapsed' then
    raise exception 'INVALID_SUBSCRIPTION_STATE' using errcode = 'P0001', detail = s.status::text;
  end if;
  update public.subscriptions set status = 'lapsed', lapsed_at = now(), grace_until = null where id = s.id;
  perform public._autofill_unlocked_wholesalers(s.shop_id);
  perform public._admin_audit('admin_cancel_subscription', 'subscriptions', s.id::text, s.shop_id, null,
    jsonb_build_object('status', s.status), jsonb_build_object('status', 'lapsed', 'reason', nullif(trim(p_reason), '')));
  return public._admin_subscription_json(s.id);
end;
$$;

-- 创始价：标记 / 取消，也可以顺便改锁定的月费（例如补回 RM50 的创始价）
create or replace function public.admin_set_subscription_founding(
  p_subscription_id uuid,
  p_is_founding boolean,
  p_locked_price_sen int default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
begin
  perform public._require_admin();
  if p_is_founding is null or (p_locked_price_sen is not null and p_locked_price_sen <= 0) then
    raise exception 'INVALID_VALUE' using errcode = 'P0001';
  end if;
  select * into s from public.subscriptions where id = p_subscription_id for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;
  update public.subscriptions set
    is_founding_price = p_is_founding,
    locked_price_sen = coalesce(p_locked_price_sen, locked_price_sen)
  where id = s.id;
  perform public._admin_audit('admin_set_subscription_founding', 'subscriptions', s.id::text, s.shop_id, null,
    jsonb_build_object('is_founding_price', s.is_founding_price, 'locked_price_sen', s.locked_price_sen),
    jsonb_build_object('is_founding_price', p_is_founding,
                       'locked_price_sen', coalesce(p_locked_price_sen, s.locked_price_sen)));
  return public._admin_subscription_json(s.id);
end;
$$;

-- =============================================================================
-- H. 每月佣金报表和账单
-- =============================================================================

-- 这个月（马来西亚时间，或 p_period_month 那个月）每家批发商：已送达订单的货价（不含运费）和应付佣金。
-- 按佣金记录的月份（送达的月份）算，比例是送达时存下来的。另外附上那个月的账单（有的话）和开账单用的资料
create or replace function public.admin_commission_report(p_period_month date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period date := coalesce(date_trunc('month', p_period_month)::date, date_trunc('month', public.today_myt())::date);
  v_rows jsonb;
begin
  perform public._require_admin();

  select coalesce(jsonb_agg(x.j order by x.name, x.id), '[]'::jsonb) into v_rows
  from (
    select w.name, w.id, jsonb_build_object(
      'wholesaler_id', w.id,
      'name', w.name,
      'status', w.status,
      'is_founding', w.is_founding,
      'phone', coalesce(w.whatsapp_phone, w.phone),
      'address', w.address,
      'billing', jsonb_build_object('name', coalesce(wp.billing_name, w.name), 'email', wp.billing_email,
                                    'address', coalesce(wp.billing_address, w.address), 'ssm_no', wp.ssm_no),
      'order_count', agg.cnt,
      'gmv_sen', agg.gmv,
      'commission_sen', agg.commission,
      'rates', agg.rates,
      'invoice', (
        select jsonb_build_object('id', i.id, 'invoice_no', i.invoice_no, 'status', i.status, 'order_count', i.order_count,
                                  'gmv_sen', i.gmv_sen, 'commission_sen', i.commission_sen, 'issued_at', i.issued_at,
                                  'due_date', i.due_date, 'paid_at', i.paid_at)
        from public.commission_invoices i where i.wholesaler_id = w.id and i.period_month = v_period),
      'orders', agg.orders
    ) as j
    from (
      select cr.wholesaler_id,
             count(*)::int as cnt,
             sum(cr.base_amount_sen)::bigint as gmv,
             sum(cr.commission_sen)::bigint as commission,
             (select jsonb_agg(distinct jsonb_build_object('rate', r.rate, 'rate_source', r.rate_source))
              from public.commission_records r
              where r.wholesaler_id = cr.wholesaler_id and r.period_month = v_period) as rates,
             jsonb_agg(jsonb_build_object(
               'order_id', o.id, 'order_no', o.order_no, 'shop_name', s.name, 'delivered_at', o.delivered_at,
               'base_amount_sen', cr.base_amount_sen, 'shipping_fee_sen', o.shipping_fee_sen,
               'rate', cr.rate, 'rate_source', cr.rate_source, 'commission_sen', cr.commission_sen
             ) order by o.delivered_at, o.order_no) as orders
      from public.commission_records cr
      join public.orders o on o.id = cr.order_id
      join public.shops s on s.id = o.shop_id
      where cr.period_month = v_period
      group by cr.wholesaler_id
    ) agg
    join public.wholesalers w on w.id = agg.wholesaler_id
    left join public.wholesaler_private wp on wp.wholesaler_id = w.id
  ) x;

  return jsonb_build_object(
    'period_month', v_period,
    'generated_at', now(),
    'invoice_due_days', (select a.commission_invoice_due_days from public.app_settings a),
    'order_count', (select count(*) from public.commission_records cr where cr.period_month = v_period),
    'gmv_sen', (select coalesce(sum(cr.base_amount_sen), 0) from public.commission_records cr where cr.period_month = v_period),
    'commission_sen', (select coalesce(sum(cr.commission_sen), 0) from public.commission_records cr where cr.period_month = v_period),
    'wholesalers', v_rows
  );
end;
$$;

-- 生成（或重算）草稿账单：原来的 generate_commission_invoices，加上操作记录
create or replace function public.admin_generate_invoices(p_period_month date default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  perform public._require_admin();
  v_count := public.generate_commission_invoices(p_period_month);
  perform public._admin_audit('admin_generate_invoices', 'commission_invoices', null, null, null, null,
    jsonb_build_object('period_month', p_period_month, 'invoices', v_count));
  return v_count;
end;
$$;

create or replace function public._admin_invoice_json(p_invoice_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(i) - 'pdf_path' || jsonb_build_object('wholesaler_name', w.name)
  from public.commission_invoices i join public.wholesalers w on w.id = i.wholesaler_id
  where i.id = p_invoice_id;
$$;

-- 发出账单：draft → issued，到期日 = 今天 + app_settings.commission_invoice_due_days
create or replace function public.admin_issue_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.commission_invoices%rowtype;
begin
  perform public._require_admin();
  select * into i from public.commission_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if i.status <> 'draft' then
    raise exception 'INVALID_INVOICE_STATE' using errcode = 'P0001', detail = i.status::text;
  end if;
  update public.commission_invoices set
    status = 'issued',
    issued_at = now(),
    due_date = public.today_myt() + (select a.commission_invoice_due_days from public.app_settings a)
  where id = i.id;
  perform public._admin_audit('admin_issue_invoice', 'commission_invoices', i.id::text, null, i.wholesaler_id,
    jsonb_build_object('status', i.status), jsonb_build_object('status', 'issued'));
  return public._admin_invoice_json(i.id);
end;
$$;

-- 批发商付了佣金（转账给客服）：issued / overdue → paid，记一笔付款
create or replace function public.admin_mark_invoice_paid(
  p_invoice_id uuid,
  p_method public.payment_method default 'other',
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.commission_invoices%rowtype;
  v_payment uuid;
  v_ref text := nullif(trim(p_reference), '');
begin
  perform public._require_admin();
  select * into i from public.commission_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if i.status not in ('issued', 'overdue') then
    raise exception 'INVALID_INVOICE_STATE' using errcode = 'P0001', detail = i.status::text;
  end if;
  if i.commission_sen > 0 then
    begin
      insert into public.payments (
        payer_type, wholesaler_id, purpose, reference_id, amount_sen, gateway, method, gateway_ref, status, paid_at, raw
      )
      values ('wholesaler', i.wholesaler_id, 'commission_invoice', i.id, i.commission_sen::int, 'manual',
              coalesce(p_method, 'other'), v_ref, 'paid', now(), jsonb_build_object('recorded_by', auth.uid()))
      returning id into v_payment;
    exception when unique_violation then
      raise exception 'DUPLICATE_PAYMENT_REFERENCE' using errcode = 'P0001', detail = v_ref;
    end;
  end if;
  update public.commission_invoices set status = 'paid', paid_at = now() where id = i.id;
  perform public._admin_audit('admin_mark_invoice_paid', 'commission_invoices', i.id::text, null, i.wholesaler_id,
    jsonb_build_object('status', i.status),
    jsonb_build_object('status', 'paid', 'payment_id', v_payment, 'method', coalesce(p_method, 'other'), 'reference', v_ref));
  return public._admin_invoice_json(i.id) || jsonb_build_object('payment_id', v_payment);
end;
$$;

-- =============================================================================
-- I. 操作记录
-- =============================================================================

-- 新到旧。p_admin_only = 只看客服函数写的（action 以 admin_ 开头），不看表的逐行记录。
-- 分页：p_before_id = 上一页最后一行的 id
create or replace function public.admin_list_audit_logs(
  p_action text default null,
  p_table text default null,
  p_shop_id uuid default null,
  p_wholesaler_id uuid default null,
  p_admin_only boolean default false,
  p_limit int default 100,
  p_before_id bigint default null
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
    select jsonb_agg(x.j order by x.id desc)
    from (
      select a.id, jsonb_build_object(
        'id', a.id,
        'created_at', a.created_at,
        'actor_id', a.actor_id,
        'actor_name', p.full_name,
        'actor_phone', p.phone,
        'action', a.action,
        'table_name', a.table_name,
        'record_id', a.record_id,
        'acting_for_shop_id', a.acting_for_shop_id,
        'acting_for_shop_name', s.name,
        'acting_for_wholesaler_id', a.acting_for_wholesaler_id,
        'acting_for_wholesaler_name', w.name,
        'before', a.before,
        'after', a.after
      ) as j
      from public.audit_logs a
      left join public.profiles p on p.id = a.actor_id
      left join public.shops s on s.id = a.acting_for_shop_id
      left join public.wholesalers w on w.id = a.acting_for_wholesaler_id
      where (p_action is null or a.action = p_action)
        and (p_table is null or a.table_name = p_table)
        and (p_shop_id is null or a.acting_for_shop_id = p_shop_id)
        and (p_wholesaler_id is null or a.acting_for_wholesaler_id = p_wholesaler_id)
        and (not coalesce(p_admin_only, false) or a.action like 'admin\_%')
        and (p_before_id is null or a.id < p_before_id)
      order by a.id desc
      limit greatest(least(coalesce(p_limit, 100), 500), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

-- =============================================================================
-- J. 函数权限：先全部收回，再只开放客服后台要用的（函数里面都会再检查 is_admin()）
-- =============================================================================

revoke execute on function
  public._require_admin(),
  public._admin_audit(text, text, text, uuid, uuid, jsonb, jsonb),
  public._alert_minutes(),
  public._admin_subscription_json(uuid),
  public._admin_wholesaler_json(uuid),
  public._like_pattern(text),
  public._phone_pattern(text),
  public._admin_invoice_json(uuid),
  public.admin_dashboard(),
  public.admin_list_shops(text, int),
  public.admin_list_wholesalers(public.wholesaler_status, text),
  public.admin_list_orders(date, date, uuid, uuid, public.order_status[], public.order_source[], boolean, int, int),
  public.admin_log_followup(uuid, text),
  public.admin_set_order_status(uuid, public.order_status, text),
  public.admin_confirm_order(uuid, uuid[]),
  public.admin_set_cart_item(uuid, uuid, int),
  public.admin_clear_cart(uuid),
  public.admin_place_order(uuid, int, text),
  public.admin_list_products(uuid),
  public.admin_save_product(uuid, uuid, jsonb),
  public.admin_set_wholesaler_status(uuid, public.wholesaler_status, text),
  public.admin_set_commission_rate(uuid, numeric),
  public.admin_set_wholesaler_founding(uuid, boolean),
  public.admin_set_whatsapp_opt_in(uuid, uuid, boolean),
  public.admin_list_subscriptions(public.subscription_status, boolean, text),
  public.admin_extend_trial(uuid, int),
  public.admin_mark_subscription_paid(uuid, int, int, public.payment_method, text),
  public.admin_cancel_subscription(uuid, text),
  public.admin_set_subscription_founding(uuid, boolean, int),
  public.admin_commission_report(date),
  public.admin_generate_invoices(date),
  public.admin_issue_invoice(uuid),
  public.admin_mark_invoice_paid(uuid, public.payment_method, text),
  public.admin_list_audit_logs(text, text, uuid, uuid, boolean, int, bigint)
from public, anon, authenticated;

-- 客服后台（登录的客服；不是客服 → NOT_ALLOWED）
grant execute on function
  public.admin_dashboard(),
  public.admin_list_shops(text, int),
  public.admin_list_wholesalers(public.wholesaler_status, text),
  public.admin_list_orders(date, date, uuid, uuid, public.order_status[], public.order_source[], boolean, int, int),
  public.admin_log_followup(uuid, text),
  public.admin_set_order_status(uuid, public.order_status, text),
  public.admin_confirm_order(uuid, uuid[]),
  public.admin_set_cart_item(uuid, uuid, int),
  public.admin_clear_cart(uuid),
  public.admin_place_order(uuid, int, text),
  public.admin_list_products(uuid),
  public.admin_save_product(uuid, uuid, jsonb),
  public.admin_set_wholesaler_status(uuid, public.wholesaler_status, text),
  public.admin_set_commission_rate(uuid, numeric),
  public.admin_set_wholesaler_founding(uuid, boolean),
  public.admin_set_whatsapp_opt_in(uuid, uuid, boolean),
  public.admin_list_subscriptions(public.subscription_status, boolean, text),
  public.admin_extend_trial(uuid, int),
  public.admin_mark_subscription_paid(uuid, int, int, public.payment_method, text),
  public.admin_cancel_subscription(uuid, text),
  public.admin_set_subscription_founding(uuid, boolean, int),
  public.admin_commission_report(date),
  public.admin_generate_invoices(date),
  public.admin_issue_invoice(uuid),
  public.admin_mark_invoice_paid(uuid, public.payment_method, text),
  public.admin_list_audit_logs(text, text, uuid, uuid, boolean, int, bigint)
to authenticated;
