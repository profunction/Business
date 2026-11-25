-- =============================================================================
-- 7/8 业务函数：注册、付费检查、看价钱、购物车报价、下单、改订单状态、评价、
--     佣金、订阅维护、操作记录
--
-- App 调用这些函数时，出错会返回英文代码（例如 'BELOW_MIN_ORDER'），
-- App 再按代码显示三语提示。
-- =============================================================================

-- =============================================================================
-- A. 注册
-- =============================================================================

-- 新账号：建 profiles；客服先建好的店铺 / 批发商，用同一个手机号登录就自动接上
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(new.phone);
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role public.user_role := 'buyer';
begin
  -- 注册时只能选买家或批发商，客服（admin）只能由客服设定
  if v_meta ->> 'role' = 'seller' then
    v_role := 'seller';
  end if;
  if v_phone is not null
     and exists (select 1 from public.wholesalers w where v_phone in (w.phone, w.whatsapp_phone)) then
    v_role := 'seller';
  end if;

  insert into public.profiles (id, role, phone, full_name, locale)
  values (
    new.id,
    v_role,
    v_phone,
    nullif(trim(v_meta ->> 'full_name'), ''),
    case when v_meta ->> 'locale' in ('zh', 'en', 'ms') then (v_meta ->> 'locale')::public.app_locale else 'zh' end
  );

  if v_phone is not null then
    insert into public.wholesaler_members (wholesaler_id, user_id, member_role)
    select w.id, new.id, 'owner'
    from public.wholesalers w
    where v_phone in (w.phone, w.whatsapp_phone)
      and not exists (select 1 from public.wholesaler_members m where m.wholesaler_id = w.id)
    on conflict do nothing;

    insert into public.shop_members (shop_id, user_id, member_role)
    select s.id, new.id, 'owner'
    from public.shops s
    where v_phone in (s.phone, s.whatsapp_phone)
      and not exists (select 1 from public.shop_members m where m.shop_id = s.id)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_user_phone_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set phone = public.normalize_phone(new.phone) where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_phone_changed
  after update of phone on auth.users
  for each row execute function public.handle_user_phone_change();

-- 批发商建立时自动建私密资料那一行
create or replace function public.wholesalers_create_private_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.wholesaler_private (wholesaler_id) values (new.id) on conflict do nothing;
  return null;
end;
$$;

create trigger wholesalers_after_insert
  after insert on public.wholesalers
  for each row execute function public.wholesalers_create_private_row();

-- 设为创始会员时自动编号（1、2、3……），超过名额就拒绝
create or replace function public.wholesalers_assign_founding_no()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quota int;
  v_count int;
begin
  if new.is_founding and new.founding_no is null then
    perform pg_advisory_xact_lock(hashtext('public.wholesalers.founding_no'));
    select founding_wholesaler_quota into v_quota from public.app_settings;
    select count(*) into v_count from public.wholesalers where is_founding and id <> new.id;
    if v_count >= v_quota then
      raise exception 'FOUNDING_QUOTA_FULL' using errcode = 'P0001', detail = v_quota::text;
    end if;
    select coalesce(max(founding_no), 0) + 1 into new.founding_no from public.wholesalers;
  end if;
  return new;
end;
$$;

create trigger wholesalers_founding_no
  before insert or update of is_founding on public.wholesalers
  for each row execute function public.wholesalers_assign_founding_no();

-- =============================================================================
-- B. 订阅和付费检查
-- =============================================================================

-- 现在的月费（当天有效、最新的那一行）
create or replace function public.current_plan(p_plan_code text default 'buyer_monthly')
returns table (plan_id uuid, amount_sen int, is_founding boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select pp.id, pp.amount_sen, pp.is_founding
  from public.pricing_plans pp
  where pp.plan_code = p_plan_code
    and pp.effective_from <= now()
    and (pp.effective_to is null or pp.effective_to > now())
  order by pp.effective_from desc
  limit 1;
$$;

-- 这家店能不能用全部功能（试用中、已付费、或还在宽限期内）
create or replace function public.has_full_access(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.subscriptions s
    cross join public.app_settings a
    where s.shop_id = p_shop_id
      and (
        (s.status = 'trialing' and s.trial_ends_at > now())
        or (s.status = 'active'
            and s.current_period_end + make_interval(days => a.subscription_grace_days) > now())
        or (s.status = 'past_due'
            and coalesce(s.grace_until, s.current_period_end + make_interval(days => a.subscription_grace_days)) > now())
      )
  );
$$;

-- 这家店看不看得到这家批发商的价钱
create or replace function public.can_see_prices(p_shop_id uuid, p_wholesaler_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_full_access(p_shop_id)
      or exists (
        select 1 from public.unlocked_wholesalers u
        where u.shop_id = p_shop_id and u.wholesaler_id = p_wholesaler_id
      );
$$;

-- 开始 14 天试用（一个手机号只能试用一次），月费按今天的价钱锁定
create or replace function public._start_trial(p_shop_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(p_phone);
  v_plan record;
  v_days int;
begin
  if v_phone is null then
    return false;
  end if;
  if exists (select 1 from public.subscriptions where shop_id = p_shop_id) then
    return false;
  end if;

  insert into public.trial_claims (phone, shop_id) values (v_phone, p_shop_id)
  on conflict (phone) do nothing;
  if not found then
    return false;                                  -- 这个手机号用过试用了
  end if;

  select * into v_plan from public.current_plan('buyer_monthly');
  if v_plan.plan_id is null then
    raise exception 'NO_PRICING_PLAN' using errcode = 'P0001';
  end if;
  select trial_days into v_days from public.app_settings;

  insert into public.subscriptions (shop_id, status, started_at, trial_ends_at, locked_price_sen, is_founding_price)
  values (p_shop_id, 'trialing', now(), now() + make_interval(days => v_days), v_plan.amount_sen, v_plan.is_founding);
  return true;
end;
$$;

-- 客服帮没装 App 的店开试用
create or replace function public.start_trial(p_shop_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (public.is_admin() or public.is_service_call()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  return public._start_trial(
    p_shop_id,
    (select coalesce(s.whatsapp_phone, s.phone) from public.shops s where s.id = p_shop_id)
  );
end;
$$;

-- App 用来显示「我的订阅」和「免费可看的批发商」
create or replace function public.get_subscription_status(p_shop_id uuid)
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
  return jsonb_build_object(
    'has_full_access', public.has_full_access(p_shop_id),
    'subscription', (
      select to_jsonb(x) from (
        select s.id, s.status, s.started_at, s.trial_ends_at, s.locked_price_sen, s.is_founding_price,
               s.current_period_end, s.grace_until, s.lapsed_at
        from public.subscriptions s
        where s.shop_id = p_shop_id
        order by s.created_at desc
        limit 1
      ) x
    ),
    'current_price_sen', (select cp.amount_sen from public.current_plan('buyer_monthly') cp),
    'free_unlocked_limit', (select a.free_unlocked_wholesalers from public.app_settings a),
    'unlocked_wholesaler_ids', coalesce(
      (select jsonb_agg(u.wholesaler_id order by u.unlocked_at) from public.unlocked_wholesalers u where u.shop_id = p_shop_id),
      '[]'::jsonb),
    'unlocks_change_allowed_at', (
      select s.unlocks_changed_at + make_interval(days => a.unlock_change_cooldown_days)
      from public.shops s cross join public.app_settings a
      where s.id = p_shop_id
    )
  );
end;
$$;

-- 未付费用户选「免费可看的批发商」（最多 3 家；换掉已经选的，每 30 天一次）
create or replace function public.set_unlocked_wholesalers(p_shop_id uuid, p_wholesaler_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct x from unnest(coalesce(p_wholesaler_ids, '{}'::uuid[])) as t(x));
  v_limit int;
  v_cooldown int;
  v_zone uuid;
  v_changed_at timestamptz;
  v_removed int;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  select a.free_unlocked_wholesalers, a.unlock_change_cooldown_days into v_limit, v_cooldown
  from public.app_settings a;
  if cardinality(v_ids) > v_limit then
    raise exception 'TOO_MANY_WHOLESALERS' using errcode = 'P0001', detail = v_limit::text;
  end if;

  select s.zone_id, s.unlocks_changed_at into v_zone, v_changed_at
  from public.shops s where s.id = p_shop_id for update;

  if exists (
    select 1 from unnest(v_ids) as t(wid)
    where not exists (
      select 1 from public.wholesalers w
      join public.wholesaler_delivery_zones dz
        on dz.wholesaler_id = w.id and dz.zone_id = v_zone and dz.is_active
      where w.id = t.wid and w.status = 'active'
    )
  ) then
    raise exception 'WHOLESALER_NOT_AVAILABLE' using errcode = 'P0001';
  end if;

  select count(*) into v_removed
  from public.unlocked_wholesalers u
  where u.shop_id = p_shop_id and not (u.wholesaler_id = any (v_ids));

  if v_removed > 0 and not public.is_admin() and v_changed_at is not null
     and v_changed_at + make_interval(days => v_cooldown) > now() then
    raise exception 'UNLOCK_COOLDOWN' using errcode = 'P0001',
      detail = (v_changed_at + make_interval(days => v_cooldown))::text;
  end if;

  delete from public.unlocked_wholesalers u
  where u.shop_id = p_shop_id and not (u.wholesaler_id = any (v_ids));
  insert into public.unlocked_wholesalers (shop_id, wholesaler_id)
  select p_shop_id, t.wid from unnest(v_ids) as t(wid)
  on conflict do nothing;

  if v_removed > 0 then
    update public.shops set unlocks_changed_at = now() where id = p_shop_id;
  end if;
end;
$$;

-- 试用或订阅停了之后，自动帮老板选最近买过的几家（他之后可以自己改）
create or replace function public._autofill_unlocked_wholesalers(p_shop_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.unlocked_wholesalers (shop_id, wholesaler_id)
  select p_shop_id, recent.wholesaler_id
  from (
    select o.wholesaler_id, max(o.created_at) as last_ordered_at
    from public.orders o
    join public.wholesalers w on w.id = o.wholesaler_id and w.status = 'active'
    where o.shop_id = p_shop_id and o.status <> 'cancelled'
    group by o.wholesaler_id
    order by last_ordered_at desc
    limit (select a.free_unlocked_wholesalers from public.app_settings a)
  ) recent
  where not exists (select 1 from public.unlocked_wholesalers u where u.shop_id = p_shop_id)
  on conflict do nothing;
$$;

-- =============================================================================
-- C. 注册店铺和批发商、推送 token
-- =============================================================================

create or replace function public.register_shop(
  p_name text,
  p_zone_id uuid,
  p_shop_type public.shop_type default 'other',
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
  v_shop_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  select * into v_profile from public.profiles where id = v_uid;
  if v_profile.role = 'seller' then
    raise exception 'ROLE_MISMATCH' using errcode = '42501';
  end if;
  if not exists (select 1 from public.delivery_zones z where z.id = p_zone_id and z.is_active) then
    raise exception 'INVALID_ZONE' using errcode = 'P0001';
  end if;

  insert into public.shops (name, shop_type, zone_id, address, contact_name, phone, whatsapp_phone, locale, created_by)
  values (
    trim(p_name), p_shop_type, p_zone_id, p_address,
    coalesce(p_contact_name, v_profile.full_name),
    v_profile.phone,
    coalesce(p_whatsapp_phone, v_profile.phone),
    v_profile.locale,
    v_uid
  )
  returning id into v_shop_id;

  insert into public.shop_members (shop_id, user_id, member_role) values (v_shop_id, v_uid, 'owner');
  perform public._start_trial(v_shop_id, v_profile.phone);
  return v_shop_id;
end;
$$;

-- 批发商自己注册：状态是「待审核」，客服审核通过后才出现在买家面前
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
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  select * into v_profile from public.profiles where id = v_uid;
  if v_profile.role = 'buyer' and exists (select 1 from public.shop_members m where m.user_id = v_uid) then
    raise exception 'ROLE_MISMATCH' using errcode = '42501';
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

-- 同一部手机换人登录时，token 转给新的人
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  insert into public.device_tokens (user_id, fcm_token, platform)
  values (auth.uid(), p_token, p_platform)
  on conflict (fcm_token) do update
    set user_id = excluded.user_id, platform = excluded.platform, last_seen_at = now();
end;
$$;

-- =============================================================================
-- D. 看商品和价钱（付费检查在这里做）
-- =============================================================================

-- 只列出送到这家店所在送货区的批发商。看不到价钱的，price_sen 是空的（App 画模糊方块）。
-- 排序：看得到价钱的在前，按「每个多少钱」由便宜到贵；看不到的按评分排（不泄露价钱高低）。
create or replace function public.get_offers(
  p_shop_id uuid,
  p_catalog_item_id uuid default null,
  p_wholesaler_id uuid default null,
  p_category_id uuid default null,
  p_search text default null,
  p_limit int default 200
)
returns table (
  product_id uuid,
  product_name text,
  description text,
  photo_paths text[],
  unit public.sell_unit,
  pack_qty int,
  min_order_qty int,
  stock_status public.stock_status,
  catalog_item_id uuid,
  category_id uuid,
  wholesaler_id uuid,
  wholesaler_name text,
  wholesaler_logo_path text,
  rating_avg numeric,
  rating_count int,
  is_founding boolean,
  price_visible boolean,
  price_sen int,
  price_per_base_unit_sen numeric,
  shipping_fee_sen int,
  free_shipping_min_sen int,
  min_order_sen int,
  lead_time_days int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_zone uuid;
  v_full boolean;
  v_search text;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  select s.zone_id into v_zone from public.shops s where s.id = p_shop_id;
  v_full := public.has_full_access(p_shop_id);
  v_search := case
    when nullif(trim(p_search), '') is null then null
    else '%' || replace(replace(replace(trim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  end;

  return query
  select
    p.id,
    p.name,
    p.description,
    p.photo_paths,
    p.unit,
    p.pack_qty,
    p.min_order_qty,
    p.stock_status,
    p.catalog_item_id,
    coalesce(p.category_id, ci.category_id),
    w.id,
    w.name,
    w.logo_path,
    w.rating_avg,
    w.rating_count,
    w.is_founding,
    v.visible,
    case when v.visible then p.price_sen end,
    case when v.visible then round(p.price_sen::numeric / p.pack_qty, 2) end,
    dz.shipping_fee_sen,
    dz.free_shipping_min_sen,
    dz.min_order_sen,
    coalesce(p.lead_time_days_override, dz.lead_time_days)::int
  from public.products p
  join public.wholesalers w on w.id = p.wholesaler_id and w.status = 'active'
  join public.wholesaler_delivery_zones dz
    on dz.wholesaler_id = w.id and dz.zone_id = v_zone and dz.is_active
  left join public.catalog_items ci on ci.id = p.catalog_item_id
  cross join lateral (
    select v_full or exists (
      select 1 from public.unlocked_wholesalers u
      where u.shop_id = p_shop_id and u.wholesaler_id = w.id
    ) as visible
  ) v
  where p.status = 'active'
    and (p_catalog_item_id is null or p.catalog_item_id = p_catalog_item_id)
    and (p_wholesaler_id is null or p.wholesaler_id = p_wholesaler_id)
    and (p_category_id is null or coalesce(p.category_id, ci.category_id) = p_category_id)
    and (v_search is null or p.name ilike v_search)
  order by
    v.visible desc,
    case when v.visible then p.price_sen::numeric / p.pack_qty end asc nulls last,
    w.rating_avg desc,
    p.name
  limit greatest(least(coalesce(p_limit, 200), 500), 1);
end;
$$;

-- =============================================================================
-- E. 购物车报价和下单
-- =============================================================================

-- 预计送货日期：今天 + 几天；过了截单时间再加一天；遇到不送货的日子往后推
create or replace function public.next_delivery_date(
  p_lead_days int,
  p_weekdays smallint[],
  p_cutoff time,
  p_at timestamptz default now()
)
returns date
language plpgsql
stable
set search_path = ''
as $$
declare
  v_local timestamp := p_at at time zone 'Asia/Kuala_Lumpur';
  v_date date := v_local::date + coalesce(p_lead_days, 1);
  i int := 0;
begin
  if p_cutoff is not null and v_local::time > p_cutoff then
    v_date := v_date + 1;
  end if;
  while p_weekdays is not null and cardinality(p_weekdays) > 0
        and not (extract(isodow from v_date)::smallint = any (p_weekdays)) and i < 7 loop
    v_date := v_date + 1;
    i := i + 1;
  end loop;
  return v_date;
end;
$$;

-- 购物车报价：按批发商分组，算货价、运费、最低消费，标出每一行的问题。
-- 看不到价钱的批发商，价钱返回空值。
create or replace function public._quote_cart(p_shop_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with shop as (
    select s.id, s.zone_id, public.has_full_access(s.id) as full_access
    from public.shops s
    where s.id = p_shop_id
  ),
  lines as (
    select
      c.product_id,
      p.wholesaler_id,
      w.name as wholesaler_name,
      w.order_cutoff_time,
      p.name as product_name,
      p.unit,
      p.pack_qty,
      c.qty,
      p.min_order_qty,
      p.price_sen,
      p.price_sen * c.qty as line_total_sen,
      coalesce(p.lead_time_days_override, dz.lead_time_days) as lead_time_days,
      case
        when p.status <> 'active' or w.status <> 'active' then 'PRODUCT_UNAVAILABLE'
        when dz.wholesaler_id is null then 'NOT_DELIVERING'
        when not (shop.full_access or exists (
          select 1 from public.unlocked_wholesalers u
          where u.shop_id = shop.id and u.wholesaler_id = p.wholesaler_id
        )) then 'WHOLESALER_LOCKED'
        when p.stock_status = 'out_of_stock' then 'OUT_OF_STOCK'
        when c.qty < p.min_order_qty then 'BELOW_MIN_QTY'
      end as problem
    from public.cart_items c
    cross join shop
    join public.products p on p.id = c.product_id
    join public.wholesalers w on w.id = p.wholesaler_id
    left join public.wholesaler_delivery_zones dz
      on dz.wholesaler_id = p.wholesaler_id and dz.zone_id = shop.zone_id and dz.is_active
    where c.shop_id = shop.id
  ),
  groups as (
    select
      l.wholesaler_id,
      min(l.wholesaler_name) as wholesaler_name,
      min(l.order_cutoff_time) as order_cutoff_time,
      coalesce(sum(l.line_total_sen) filter (where l.problem is null), 0)::int as goods_subtotal_sen,
      bool_or(l.problem is not null) as has_line_problem,
      max(l.lead_time_days) as lead_time_days,
      jsonb_agg(jsonb_build_object(
        'product_id', l.product_id,
        'product_name', l.product_name,
        'unit', l.unit,
        'pack_qty', l.pack_qty,
        'qty', l.qty,
        'min_order_qty', l.min_order_qty,
        'unit_price_sen', case when l.problem = 'WHOLESALER_LOCKED' then null else l.price_sen end,
        'line_total_sen', case when l.problem = 'WHOLESALER_LOCKED' then null else l.line_total_sen end,
        'problem', l.problem
      ) order by l.product_name) as lines
    from lines l
    group by l.wholesaler_id
  ),
  priced as (
    select
      g.*,
      dz.free_shipping_min_sen,
      dz.min_order_sen,
      case
        when dz.wholesaler_id is null then null
        when dz.free_shipping_min_sen is not null and g.goods_subtotal_sen >= dz.free_shipping_min_sen then 0
        else dz.shipping_fee_sen
      end as shipping_fee_sen,
      greatest(coalesce(dz.min_order_sen, 0) - g.goods_subtotal_sen, 0) as short_by_sen,
      case when dz.wholesaler_id is not null
        then public.next_delivery_date(g.lead_time_days, dz.delivery_weekdays, g.order_cutoff_time)
      end as expected_delivery_date
    from groups g
    cross join shop
    left join public.wholesaler_delivery_zones dz
      on dz.wholesaler_id = g.wholesaler_id and dz.zone_id = shop.zone_id and dz.is_active
  )
  select jsonb_build_object(
    'shop_id', p_shop_id,
    'can_place', coalesce(bool_and(
      not p.has_line_problem and p.short_by_sen = 0 and p.shipping_fee_sen is not null
    ), false),
    'goods_total_sen', coalesce(sum(p.goods_subtotal_sen), 0),
    'shipping_total_sen', coalesce(sum(p.shipping_fee_sen), 0),
    'total_sen', coalesce(sum(p.goods_subtotal_sen + coalesce(p.shipping_fee_sen, 0)), 0),
    'groups', coalesce(jsonb_agg(jsonb_build_object(
      'wholesaler_id', p.wholesaler_id,
      'wholesaler_name', p.wholesaler_name,
      'goods_subtotal_sen', p.goods_subtotal_sen,
      'shipping_fee_sen', p.shipping_fee_sen,
      'free_shipping_min_sen', p.free_shipping_min_sen,
      'min_order_sen', p.min_order_sen,
      'short_by_sen', p.short_by_sen,
      'expected_delivery_date', p.expected_delivery_date,
      'problem', case
        when p.shipping_fee_sen is null then 'NOT_DELIVERING'
        when p.short_by_sen > 0 then 'BELOW_MIN_ORDER'
      end,
      'lines', p.lines
    ) order by p.wholesaler_name), '[]'::jsonb)
  )
  from priced p;
$$;

-- App 在「确认下单」页面调用：显示货价 + 运费 = 总额
create or replace function public.quote_cart(p_shop_id uuid)
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
  return public._quote_cart(p_shop_id);
end;
$$;

create or replace function public._next_order_no(p_region_code text)
returns text
language sql
volatile
set search_path = ''
as $$
  select coalesce(p_region_code, 'XX')
      || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYMMDD')
      || '-'
      || lpad(nextval('public.order_no_seq')::text, 5, '0');
$$;

-- 下单：把购物车按批发商拆成几张订单。
-- p_expected_total_sen = 老板在确认页看到的总额；跟服务器算的不一样（例如刚好改价）就拒绝，
-- 让 App 重新报价，不会多收老板的钱。
create or replace function public.place_order(
  p_shop_id uuid,
  p_expected_total_sen int default null,
  p_note text default null,
  p_source public.order_source default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  v_is_service boolean := public.is_service_call();
  v_source public.order_source;
  v_channel public.event_channel;
  v_quote jsonb;
  v_zone uuid;
  v_region_code text;
  v_checkout_id uuid;
  v_order_id uuid;
  g jsonb;
begin
  if not (public.is_shop_member(p_shop_id) or v_is_admin or v_is_service) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  if v_is_admin or v_is_service then
    v_source := coalesce(p_source, 'admin');
    v_channel := case when v_is_admin then 'admin' else 'system' end;
  else
    v_source := coalesce(p_source, 'app');
    v_channel := 'app';
    if v_source not in ('app', 'voice', 'reorder') then
      raise exception 'INVALID_SOURCE' using errcode = 'P0001';
    end if;
  end if;

  -- 锁住购物车和商品，避免算钱的时候刚好有人改价
  perform 1 from public.cart_items c where c.shop_id = p_shop_id for update;
  perform 1 from public.products p
  where p.id in (select c.product_id from public.cart_items c where c.shop_id = p_shop_id)
  for share;

  v_quote := public._quote_cart(p_shop_id);
  if jsonb_array_length(v_quote -> 'groups') = 0 then
    raise exception 'CART_EMPTY' using errcode = 'P0001';
  end if;
  if not (v_quote ->> 'can_place')::boolean then
    raise exception 'CART_HAS_PROBLEMS' using errcode = 'P0001', detail = v_quote::text;
  end if;
  if p_expected_total_sen is not null and p_expected_total_sen <> (v_quote ->> 'total_sen')::int then
    raise exception 'PRICE_CHANGED' using errcode = 'P0001', detail = v_quote::text;
  end if;

  select s.zone_id, r.code into v_zone, v_region_code
  from public.shops s
  join public.delivery_zones z on z.id = s.zone_id
  join public.regions r on r.id = z.region_id
  where s.id = p_shop_id;

  insert into public.checkouts (shop_id, source, goods_total_sen, shipping_total_sen, created_by)
  values (p_shop_id, v_source, (v_quote ->> 'goods_total_sen')::int, (v_quote ->> 'shipping_total_sen')::int, v_uid)
  returning id into v_checkout_id;

  for g in select * from jsonb_array_elements(v_quote -> 'groups') loop
    insert into public.orders (
      order_no, checkout_id, shop_id, wholesaler_id, zone_id,
      goods_subtotal_sen, shipping_fee_sen, expected_delivery_date, note, source, created_by
    )
    values (
      public._next_order_no(v_region_code), v_checkout_id, p_shop_id, (g ->> 'wholesaler_id')::uuid, v_zone,
      (g ->> 'goods_subtotal_sen')::int, (g ->> 'shipping_fee_sen')::int,
      (g ->> 'expected_delivery_date')::date, nullif(trim(p_note), ''), v_source, v_uid
    )
    returning id into v_order_id;

    insert into public.order_items (
      order_id, product_id, catalog_item_id, name_snapshot, unit_snapshot, pack_qty_snapshot, unit_price_sen, qty
    )
    select v_order_id, p.id, p.catalog_item_id, p.name, p.unit, p.pack_qty, p.price_sen, c.qty
    from public.cart_items c
    join public.products p on p.id = c.product_id
    where c.shop_id = p_shop_id and p.wholesaler_id = (g ->> 'wholesaler_id')::uuid;

    insert into public.order_status_events (order_id, from_status, to_status, actor_id, channel)
    values (v_order_id, null, 'pending', v_uid, v_channel);
  end loop;

  delete from public.cart_items c where c.shop_id = p_shop_id;
  return v_checkout_id;
end;
$$;

-- 「跟上次一样」：把上一次结账的货放回购物车，返回最新报价、改了价的商品、买不到的商品。
-- App 显示给老板看一眼，按确认后再调用 place_order(p_source => 'reorder')。
create or replace function public.reorder_last(p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checkout uuid;
  v_skipped jsonb;
  v_changes jsonb;
  v_added int;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  select c.id into v_checkout
  from public.checkouts c
  where c.shop_id = p_shop_id
  order by c.created_at desc
  limit 1;
  if v_checkout is null then
    raise exception 'NO_PREVIOUS_ORDER' using errcode = 'P0001';
  end if;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'product_name', li.name_snapshot,
      'reason', case when p.id is null then 'PRODUCT_REMOVED' else 'PRODUCT_UNAVAILABLE' end
    )) filter (where p.id is null or p.status <> 'active'), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'product_id', p.id,
      'product_name', p.name,
      'old_price_sen', li.unit_price_sen,
      'new_price_sen', p.price_sen
    )) filter (where p.status = 'active' and p.price_sen <> li.unit_price_sen
                 and public.can_see_prices(p_shop_id, p.wholesaler_id)), '[]'::jsonb)
  into v_skipped, v_changes
  from public.order_items li
  join public.orders o on o.id = li.order_id
  left join public.products p on p.id = li.product_id
  where o.checkout_id = v_checkout;

  delete from public.cart_items c where c.shop_id = p_shop_id;
  insert into public.cart_items (shop_id, product_id, qty, added_by)
  select p_shop_id, li.product_id, li.qty, auth.uid()
  from public.order_items li
  join public.orders o on o.id = li.order_id
  join public.products p on p.id = li.product_id
  where o.checkout_id = v_checkout and p.status = 'active'
  on conflict (shop_id, product_id) do update set qty = excluded.qty;
  get diagnostics v_added = row_count;

  return jsonb_build_object(
    'source_checkout_id', v_checkout,
    'added_count', v_added,
    'skipped', v_skipped,
    'price_changes', v_changes,
    'quote', public._quote_cart(p_shop_id)
  );
end;
$$;

-- =============================================================================
-- F. 订单状态
-- =============================================================================
--   待确认 --确认--> 已确认 --> 送货中 --> 已送达
--     |                 \______________/^
--     |--缺货--> 缺货
--     \--取消--> 已取消（待确认或已确认时，老板或客服可以取消）
-- 谁可以改：
--   确认 / 缺货 / 送货中：批发商、客服、服务器（WhatsApp 按钮）
--   已送达：批发商、老板（「收到了」）、客服、服务器
--   取消：老板、客服
create or replace function public.set_order_status(
  p_order_id uuid,
  p_status public.order_status,
  p_note text default null,
  p_channel public.event_channel default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  v_is_service boolean := public.is_service_call();
  v_is_seller boolean;
  v_is_buyer boolean;
  v_allowed boolean;
  v_channel public.event_channel;
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;

  v_is_seller := public.is_wholesaler_member(o.wholesaler_id);
  v_is_buyer := public.is_shop_member(o.shop_id);
  if not (v_is_admin or v_is_service or v_is_seller or v_is_buyer) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  -- 同一个按钮按两次（WhatsApp 常见）：不报错，什么都不做
  if o.status = p_status then
    return;
  end if;

  v_allowed := case
    when o.status = 'pending' and p_status in ('confirmed', 'out_of_stock')
      then v_is_seller or v_is_admin or v_is_service
    when o.status in ('pending', 'confirmed') and p_status = 'cancelled'
      then v_is_buyer or v_is_admin
    when o.status = 'confirmed' and p_status = 'delivering'
      then v_is_seller or v_is_admin or v_is_service
    when o.status in ('confirmed', 'delivering') and p_status = 'delivered'
      then v_is_seller or v_is_buyer or v_is_admin or v_is_service
    else false
  end;
  if not v_allowed then
    raise exception 'INVALID_TRANSITION' using errcode = 'P0001', detail = format('%s -> %s', o.status, p_status);
  end if;

  v_channel := case
    when v_is_service then coalesce(p_channel, 'system')
    when v_is_admin then 'admin'
    else 'app'
  end;

  if p_status = 'out_of_stock' then
    update public.order_items set is_out_of_stock = true where order_id = p_order_id;
  end if;

  update public.orders set
    status = p_status,
    confirmed_at = case when p_status = 'confirmed' then now() else confirmed_at end,
    delivering_at = case when p_status = 'delivering' then now() else delivering_at end,
    delivered_at = case when p_status = 'delivered' then now() else delivered_at end,
    cancelled_at = case when p_status = 'cancelled' then now() else cancelled_at end,
    cancel_reason = case when p_status = 'cancelled' then nullif(trim(p_note), '') else cancel_reason end
  where id = p_order_id;

  insert into public.order_status_events (order_id, from_status, to_status, actor_id, channel, note)
  values (p_order_id, o.status, p_status, v_uid, v_channel, nullif(trim(p_note), ''));
end;
$$;

-- 批发商一键「确认」：可以顺便标出哪几样缺货（那几样不算钱，运费照下单时的）。
-- 全部都缺货就变成「缺货」。
create or replace function public.confirm_order(
  p_order_id uuid,
  p_out_of_stock_item_ids uuid[] default '{}',
  p_channel public.event_channel default null
)
returns public.order_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
  v_ids uuid[] := coalesce(p_out_of_stock_item_ids, '{}'::uuid[]);
  v_remaining int;
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not (public.is_wholesaler_member(o.wholesaler_id) or public.is_admin() or public.is_service_call()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if o.status <> 'pending' then
    raise exception 'INVALID_TRANSITION' using errcode = 'P0001', detail = format('%s -> confirmed', o.status);
  end if;
  if exists (
    select 1 from unnest(v_ids) as t(item_id)
    where not exists (select 1 from public.order_items i where i.id = t.item_id and i.order_id = p_order_id)
  ) then
    raise exception 'ITEM_NOT_IN_ORDER' using errcode = 'P0001';
  end if;

  update public.order_items set is_out_of_stock = (id = any (v_ids)) where order_id = p_order_id;
  select count(*) into v_remaining
  from public.order_items where order_id = p_order_id and not is_out_of_stock;

  if v_remaining = 0 then
    perform public.set_order_status(p_order_id, 'out_of_stock', null, p_channel);
    return 'out_of_stock';
  end if;

  update public.orders set goods_subtotal_sen = (
    select coalesce(sum(i.line_total_sen), 0) from public.order_items i
    where i.order_id = p_order_id and not i.is_out_of_stock
  )
  where id = p_order_id;
  perform public.set_order_status(p_order_id, 'confirmed', null, p_channel);
  return 'confirmed';
end;
$$;

-- 佣金比例：批发商单独调整的 > 创始会员比例 > 行业默认比例
create or replace function public.commission_rate_for(p_wholesaler_id uuid)
returns table (rate numeric, rate_source public.commission_rate_source)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case
      when wp.commission_rate_override is not null then wp.commission_rate_override
      when w.is_founding then i.founding_commission_rate
      else i.default_commission_rate
    end,
    case
      when wp.commission_rate_override is not null then 'override'::public.commission_rate_source
      when w.is_founding then 'founding'::public.commission_rate_source
      else 'industry'::public.commission_rate_source
    end
  from public.wholesalers w
  join public.industries i on i.id = w.industry_id
  left join public.wholesaler_private wp on wp.wholesaler_id = w.id
  where w.id = p_wholesaler_id;
$$;

-- 订单建立 / 状态改变：发通知；送达时生成佣金记录
create or replace function public.orders_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_name text;
  v_wholesaler_name text;
  v_oos int;
begin
  select s.name into v_shop_name from public.shops s where s.id = new.shop_id;
  select w.name into v_wholesaler_name from public.wholesalers w where w.id = new.wholesaler_id;

  if tg_op = 'INSERT' then
    insert into public.notifications (wholesaler_id, event_type, payload)
    values (new.wholesaler_id, 'order_new', jsonb_build_object(
      'order_id', new.id, 'order_no', new.order_no, 'shop_name', v_shop_name,
      'total_sen', new.total_sen, 'expected_delivery_date', new.expected_delivery_date));
    return null;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'cancelled' then
      insert into public.notifications (wholesaler_id, event_type, payload)
      values (new.wholesaler_id, 'order_cancelled', jsonb_build_object(
        'order_id', new.id, 'order_no', new.order_no, 'shop_name', v_shop_name,
        'reason', new.cancel_reason));
    else
      select count(*) into v_oos from public.order_items i where i.order_id = new.id and i.is_out_of_stock;
      insert into public.notifications (shop_id, event_type, payload)
      values (new.shop_id, 'order_status_changed', jsonb_build_object(
        'order_id', new.id, 'order_no', new.order_no, 'status', new.status,
        'wholesaler_name', v_wholesaler_name, 'total_sen', new.total_sen,
        'out_of_stock_count', v_oos));
    end if;

    if new.status = 'delivered' then
      insert into public.commission_records (
        order_id, wholesaler_id, period_month, base_amount_sen, rate, rate_source, commission_sen
      )
      select
        new.id,
        new.wholesaler_id,
        date_trunc('month', coalesce(new.delivered_at, now()) at time zone 'Asia/Kuala_Lumpur')::date,
        new.goods_subtotal_sen,
        r.rate,
        r.rate_source,
        round(new.goods_subtotal_sen * r.rate)::int
      from public.commission_rate_for(new.wholesaler_id) r
      on conflict (order_id) do nothing;
    end if;
  end if;
  return null;
end;
$$;

create trigger orders_after_insert
  after insert on public.orders
  for each row execute function public.orders_after_change();
create trigger orders_after_status_change
  after update of status on public.orders
  for each row execute function public.orders_after_change();

-- =============================================================================
-- G. 评价
-- =============================================================================

create or replace function public.submit_review(
  p_order_id uuid,
  p_rating int,
  p_tags text[] default '{}',
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders%rowtype;
  v_id uuid;
begin
  select * into o from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not public.is_shop_member(o.shop_id) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if o.status <> 'delivered' then
    raise exception 'ORDER_NOT_DELIVERED' using errcode = 'P0001';
  end if;

  insert into public.reviews (order_id, shop_id, wholesaler_id, rating, tags, comment, created_by)
  values (o.id, o.shop_id, o.wholesaler_id, p_rating, coalesce(p_tags, '{}'), nullif(trim(p_comment), ''), auth.uid())
  on conflict (order_id) do update
    set rating = excluded.rating, tags = excluded.tags, comment = excluded.comment
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.reviews_refresh_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wholesaler uuid;
begin
  v_wholesaler := case when tg_op = 'DELETE' then old.wholesaler_id else new.wholesaler_id end;
  update public.wholesalers w
  set rating_avg = coalesce(r.avg_rating, 0), rating_count = r.cnt
  from (
    select round(avg(rv.rating)::numeric, 2) as avg_rating, count(*)::int as cnt
    from public.reviews rv where rv.wholesaler_id = v_wholesaler
  ) r
  where w.id = v_wholesaler;
  return null;
end;
$$;

create trigger reviews_after_change
  after insert or update of rating or delete on public.reviews
  for each row execute function public.reviews_refresh_rating();

-- =============================================================================
-- H. 每月佣金账单、每天订阅维护（定时任务调用，客服也可以手动跑）
-- =============================================================================

-- 把还没开账单的佣金记录汇总成每家批发商一张草稿账单（客服在后台确认后发出）。
-- 默认处理上个月（马来西亚时间）。可以重复跑：草稿会重新计算，已发出的不会动。
create or replace function public.generate_commission_invoices(p_period_month date default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period date;
  v_count int := 0;
  w record;
  v_invoice public.commission_invoices%rowtype;
begin
  if not (public.is_admin() or public.is_service_call()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  v_period := coalesce(
    date_trunc('month', p_period_month)::date,
    (date_trunc('month', public.today_myt()) - interval '1 month')::date
  );

  for w in
    select distinct cr.wholesaler_id
    from public.commission_records cr
    where cr.invoice_id is null and cr.period_month <= v_period
  loop
    insert into public.commission_invoices (invoice_no, wholesaler_id, period_month)
    values (
      'INV' || to_char(v_period, 'YYMM') || '-' || lpad(nextval('public.invoice_no_seq')::text, 4, '0'),
      w.wholesaler_id,
      v_period
    )
    on conflict (wholesaler_id, period_month) do nothing;

    select * into v_invoice from public.commission_invoices i
    where i.wholesaler_id = w.wholesaler_id and i.period_month = v_period;
    if v_invoice.status <> 'draft' then
      continue;                                    -- 已发出的账单不改，剩下的留到下个月
    end if;

    update public.commission_records cr set invoice_id = v_invoice.id
    where cr.wholesaler_id = w.wholesaler_id and cr.invoice_id is null and cr.period_month <= v_period;

    update public.commission_invoices i set
      order_count = t.cnt,
      gmv_sen = t.gmv,
      commission_sen = t.commission
    from (
      select count(*)::int as cnt,
             coalesce(sum(cr.base_amount_sen), 0) as gmv,
             coalesce(sum(cr.commission_sen), 0) as commission
      from public.commission_records cr where cr.invoice_id = v_invoice.id
    ) t
    where i.id = v_invoice.id;

    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- 试用结束没付费 -> 已停；到期没付 -> 逾期（宽限期内补付保留原价）；过了宽限期 -> 已停。
-- 停了的店自动帮他选最近买过的几家批发商作为「免费可看」。
create or replace function public.run_subscription_maintenance()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grace int;
  v_trial_lapsed int := 0;
  v_past_due int := 0;
  v_lapsed int := 0;
  r record;
begin
  if not (public.is_admin() or public.is_service_call()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select a.subscription_grace_days into v_grace from public.app_settings a;

  for r in
    update public.subscriptions s set status = 'lapsed', lapsed_at = now()
    where s.status = 'trialing' and s.trial_ends_at <= now()
    returning s.shop_id
  loop
    perform public._autofill_unlocked_wholesalers(r.shop_id);
    v_trial_lapsed := v_trial_lapsed + 1;
  end loop;

  update public.subscriptions s
  set status = 'past_due', grace_until = s.current_period_end + make_interval(days => v_grace)
  where s.status = 'active' and s.current_period_end <= now();
  get diagnostics v_past_due = row_count;

  for r in
    update public.subscriptions s set status = 'lapsed', lapsed_at = now()
    where s.status = 'past_due' and s.grace_until <= now()
    returning s.shop_id
  loop
    perform public._autofill_unlocked_wholesalers(r.shop_id);
    v_lapsed := v_lapsed + 1;
  end loop;

  return jsonb_build_object('trial_lapsed', v_trial_lapsed, 'past_due', v_past_due, 'lapsed', v_lapsed);
end;
$$;

-- =============================================================================
-- I. 操作记录：客服（admin）改了什么都记下来
-- =============================================================================

create or replace function public.audit_admin_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new jsonb;
  v_old jsonb;
  v_row jsonb;
begin
  if not public.is_admin() then
    return null;
  end if;
  v_new := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_old := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_row := coalesce(v_new, v_old);

  insert into public.audit_logs (
    actor_id, acting_for_shop_id, acting_for_wholesaler_id, action, table_name, record_id, before, after
  )
  values (
    auth.uid(),
    case when tg_table_name = 'shops' then (v_row ->> 'id')::uuid else (v_row ->> 'shop_id')::uuid end,
    case when tg_table_name = 'wholesalers' then (v_row ->> 'id')::uuid else (v_row ->> 'wholesaler_id')::uuid end,
    lower(tg_op),
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'order_id', v_row ->> 'product_id', v_row ->> 'wholesaler_id', v_row ->> 'shop_id'),
    v_old,
    v_new
  );
  return null;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'shops', 'shop_members', 'wholesalers', 'wholesaler_private', 'wholesaler_members',
    'wholesaler_delivery_zones', 'products', 'cart_items', 'orders', 'order_items', 'subscriptions',
    'unlocked_wholesalers', 'payments', 'commission_invoices', 'pricing_plans', 'industries', 'app_settings'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.audit_admin_changes()', t || '_audit', t);
  end loop;
end;
$$;

-- =============================================================================
-- J. 函数权限：默认谁都不能调用，只开放 App 要用的
-- （Supabase 默认会把新函数开放给 anon 和 authenticated，所以这里要先全部收回）
-- 以后新增函数的迁移也要照这样做。
-- =============================================================================

revoke execute on all functions in schema public from public, anon, authenticated;

-- RLS 规则和受保护字段要用到的辅助函数
grant execute on function
  public.is_service_call(),
  public.is_admin(),
  public.my_shop_ids(),
  public.my_wholesaler_ids(),
  public.is_shop_member(uuid),
  public.is_shop_owner(uuid),
  public.is_wholesaler_member(uuid),
  public.is_wholesaler_owner(uuid),
  public.can_access_order(uuid),
  public.is_my_customer(uuid),
  public.normalize_phone(text),
  public.is_i18n_name(jsonb),
  public.today_myt()
to authenticated;

-- App 调用的函数（每个函数里面都会再检查是谁在调用）
grant execute on function
  public.register_shop(text, uuid, public.shop_type, text, text, text),
  public.register_wholesaler(text, uuid, uuid, text, text, text),
  public.register_device_token(text, text),
  public.get_subscription_status(uuid),
  public.set_unlocked_wholesalers(uuid, uuid[]),
  public.get_offers(uuid, uuid, uuid, uuid, text, int),
  public.quote_cart(uuid),
  public.place_order(uuid, int, text, public.order_source),
  public.reorder_last(uuid),
  public.set_order_status(uuid, public.order_status, text, public.event_channel),
  public.confirm_order(uuid, uuid[], public.event_channel),
  public.submit_review(uuid, int, text[], text),
  public.start_trial(uuid),
  public.generate_commission_invoices(date),
  public.run_subscription_maintenance()
to authenticated;

grant execute on all functions in schema public to service_role;
