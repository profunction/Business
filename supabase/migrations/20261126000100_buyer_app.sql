-- =============================================================================
-- 第三步：买家 App 要用的读取函数
--   get_my_context      登录后：我是谁、我有哪些店 / 批发商
--   get_buyer_home      首页：订阅、购物车数量、进行中的订单、上一次结账
--   get_categories      分类（只列有货送到这家店的）
--   get_catalog_overview 标准商品列表：几家有卖、最便宜每个多少钱
--   list_wholesalers    送到这家店的批发商
--   list_orders         我的订单
--   get_order           订单详情，连同「现在可以按哪些按钮」（规则跟 set_order_status 一致）
-- =============================================================================

create or replace function public.get_my_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'profile', (
      select jsonb_build_object('id', p.id, 'role', p.role, 'full_name', p.full_name, 'phone', p.phone, 'locale', p.locale)
      from public.profiles p where p.id = v_uid
    ),
    'shops', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'member_role', m.member_role, 'zone_id', s.zone_id
      ) order by s.created_at)
      from public.shop_members m join public.shops s on s.id = m.shop_id
      where m.user_id = v_uid and s.is_active
    ), '[]'::jsonb),
    'wholesalers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id, 'name', w.name, 'member_role', m.member_role, 'status', w.status
      ) order by w.created_at)
      from public.wholesaler_members m join public.wholesalers w on w.id = m.wholesaler_id
      where m.user_id = v_uid
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_buyer_home(p_shop_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_last uuid;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  select c.id into v_last
  from public.checkouts c
  where c.shop_id = p_shop_id
  order by c.created_at desc
  limit 1;

  return jsonb_build_object(
    'shop', (
      select jsonb_build_object('id', s.id, 'name', s.name, 'shop_type', s.shop_type, 'zone_id', s.zone_id, 'zone_name', z.name)
      from public.shops s join public.delivery_zones z on z.id = s.zone_id
      where s.id = p_shop_id
    ),
    'subscription', public.get_subscription_status(p_shop_id),
    'cart_count', (select count(*) from public.cart_items c where c.shop_id = p_shop_id),
    'active_order_count', (
      select count(*) from public.orders o
      where o.shop_id = p_shop_id and o.status in ('pending', 'confirmed', 'delivering')
    ),
    'last_checkout', case when v_last is null then null else (
      select jsonb_build_object(
        'id', c.id,
        'created_at', c.created_at,
        'total_sen', c.goods_total_sen + c.shipping_total_sen,
        'item_count', (select count(*) from public.order_items i join public.orders o on o.id = i.order_id where o.checkout_id = c.id),
        'wholesaler_names', (
          select jsonb_agg(w.name order by w.name)
          from public.orders o join public.wholesalers w on w.id = o.wholesaler_id
          where o.checkout_id = c.id
        )
      )
      from public.checkouts c where c.id = v_last
    ) end
  );
end;
$$;

-- 只算「有已上架的货、批发商送到这家店那区」的标准商品
create or replace function public._available_catalog_items(p_shop_id uuid)
returns table (catalog_item_id uuid, product_id uuid, wholesaler_id uuid, price_sen int, pack_qty int, lead_time_days int, product_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.catalog_item_id, p.id, p.wholesaler_id, p.price_sen, p.pack_qty,
         coalesce(p.lead_time_days_override, dz.lead_time_days)::int, p.name
  from public.shops s
  join public.wholesaler_delivery_zones dz on dz.zone_id = s.zone_id and dz.is_active
  join public.wholesalers w on w.id = dz.wholesaler_id and w.status = 'active'
  join public.products p on p.wholesaler_id = w.id and p.status = 'active' and p.catalog_item_id is not null
  where s.id = p_shop_id;
$$;

create or replace function public.get_categories(p_shop_id uuid)
returns table (category_id uuid, code text, name jsonb, sort_order int, item_count int)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  return query
  select c.id, c.code, c.name, c.sort_order, count(distinct ci.id)::int
  from public.categories c
  join public.catalog_items ci on ci.category_id = c.id and ci.is_active
  join public._available_catalog_items(p_shop_id) a on a.catalog_item_id = ci.id
  where c.is_active
  group by c.id
  order by c.sort_order, c.code;
end;
$$;

-- 标准商品列表。最便宜的价钱只从看得到价钱的批发商里算（不泄露锁住的价钱）
create or replace function public.get_catalog_overview(
  p_shop_id uuid,
  p_category_id uuid default null,
  p_search text default null
)
returns table (
  catalog_item_id uuid,
  category_id uuid,
  name jsonb,
  spec jsonb,
  base_unit text,
  image_path text,
  offer_count int,
  visible_offer_count int,
  min_price_per_base_unit_sen numeric,
  fastest_lead_time_days int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_full boolean;
  v_search text;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  v_full := public.has_full_access(p_shop_id);
  v_search := case
    when nullif(trim(p_search), '') is null then null
    else '%' || replace(replace(replace(trim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  end;

  return query
  select
    ci.id,
    ci.category_id,
    ci.name,
    ci.spec,
    ci.base_unit,
    ci.image_path,
    count(*)::int,
    count(*) filter (where v.visible)::int,
    min(round(a.price_sen::numeric / a.pack_qty, 2)) filter (where v.visible),
    min(a.lead_time_days)::int
  from public._available_catalog_items(p_shop_id) a
  join public.catalog_items ci on ci.id = a.catalog_item_id and ci.is_active
  cross join lateral (
    select v_full or exists (
      select 1 from public.unlocked_wholesalers u where u.shop_id = p_shop_id and u.wholesaler_id = a.wholesaler_id
    ) as visible
  ) v
  where (p_category_id is null or ci.category_id = p_category_id)
    and (
      v_search is null
      or ci.name ->> 'zh' ilike v_search or ci.name ->> 'en' ilike v_search or ci.name ->> 'ms' ilike v_search
      or a.product_name ilike v_search
    )
  group by ci.id
  order by (select c.sort_order from public.categories c where c.id = ci.category_id), ci.sort_order, ci.name ->> 'en';
end;
$$;

create or replace function public.list_wholesalers(p_shop_id uuid)
returns table (
  wholesaler_id uuid,
  name text,
  description text,
  logo_path text,
  rating_avg numeric,
  rating_count int,
  is_founding boolean,
  payment_terms text[],
  shipping_fee_sen int,
  free_shipping_min_sen int,
  min_order_sen int,
  lead_time_days int,
  delivery_weekdays smallint[],
  product_count int,
  price_visible boolean,
  is_unlocked boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_full boolean;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  v_full := public.has_full_access(p_shop_id);

  return query
  select
    w.id, w.name, w.description, w.logo_path, w.rating_avg, w.rating_count, w.is_founding, w.payment_terms,
    dz.shipping_fee_sen, dz.free_shipping_min_sen, dz.min_order_sen, dz.lead_time_days::int, dz.delivery_weekdays,
    (select count(*)::int from public.products p where p.wholesaler_id = w.id and p.status = 'active'),
    v_full or u.wholesaler_id is not null,
    u.wholesaler_id is not null
  from public.shops s
  join public.wholesaler_delivery_zones dz on dz.zone_id = s.zone_id and dz.is_active
  join public.wholesalers w on w.id = dz.wholesaler_id and w.status = 'active'
  left join public.unlocked_wholesalers u on u.shop_id = s.id and u.wholesaler_id = w.id
  where s.id = p_shop_id
  order by w.rating_avg desc, w.rating_count desc, w.name;
end;
$$;

create or replace function public.list_orders(
  p_shop_id uuid,
  p_limit int default 30,
  p_before timestamptz default null
)
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
    select jsonb_agg(x.j order by x.created_at desc, x.order_no desc)
    from (
      select o.created_at, o.order_no, jsonb_build_object(
        'id', o.id,
        'order_no', o.order_no,
        'status', o.status,
        'wholesaler_id', o.wholesaler_id,
        'wholesaler_name', w.name,
        'goods_subtotal_sen', o.goods_subtotal_sen,
        'shipping_fee_sen', o.shipping_fee_sen,
        'total_sen', o.total_sen,
        'item_count', (select count(*) from public.order_items i where i.order_id = o.id),
        'out_of_stock_count', (select count(*) from public.order_items i where i.order_id = o.id and i.is_out_of_stock),
        'created_at', o.created_at,
        'expected_delivery_date', o.expected_delivery_date,
        'delivered_at', o.delivered_at,
        'has_review', exists (select 1 from public.reviews r where r.order_id = o.id)
      ) as j
      from public.orders o
      join public.wholesalers w on w.id = o.wholesaler_id
      where o.shop_id = p_shop_id
        and (p_before is null or o.created_at < p_before)
      order by o.created_at desc, o.order_no desc
      limit greatest(least(coalesce(p_limit, 30), 100), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

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

-- ---------- 权限 ----------
revoke execute on function
  public.get_my_context(),
  public.get_buyer_home(uuid),
  public._available_catalog_items(uuid),
  public.get_categories(uuid),
  public.get_catalog_overview(uuid, uuid, text),
  public.list_wholesalers(uuid),
  public.list_orders(uuid, int, timestamptz),
  public.get_order(uuid)
from public, anon, authenticated;

grant execute on function
  public.get_my_context(),
  public.get_buyer_home(uuid),
  public.get_categories(uuid),
  public.get_catalog_overview(uuid, uuid, text),
  public.list_wholesalers(uuid),
  public.list_orders(uuid, int, timestamptz),
  public.get_order(uuid)
to authenticated;

grant execute on function public._available_catalog_items(uuid) to service_role;
