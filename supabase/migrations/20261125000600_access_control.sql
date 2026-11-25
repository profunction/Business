-- =============================================================================
-- 6/8 权限：辅助函数、受保护字段、行级安全规则（RLS）
--
-- 原则：
--   * 每张表都开 RLS，没写规则的就是谁都看不到（服务器端的 service_role 除外）。
--   * 买家只看到自己店的订单，批发商只看到发给自己的订单，客服（admin）看到全部。
--   * 商品价钱不开放给买家直接查，要经过 get_offers() 等函数做付费检查。
--   * 下单、改订单状态、评价等重要动作不开放直接写表，只能调用第 7 个迁移里的函数。
-- =============================================================================

-- ---------- 辅助函数 ----------

-- 是不是服务器在调用（Edge Function 用 service_role、定时任务、迁移）
create or replace function public.is_service_call()
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when nullif(current_setting('request.jwt.claims', true), '') is not null
      then (current_setting('request.jwt.claims', true)::jsonb ->> 'role') = 'service_role'
    else coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon')
  end;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.my_shop_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select shop_id from public.shop_members where user_id = auth.uid();
$$;

create or replace function public.my_wholesaler_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select wholesaler_id from public.wholesaler_members where user_id = auth.uid();
$$;

create or replace function public.is_shop_member(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.shop_members where shop_id = p_shop_id and user_id = auth.uid());
$$;

create or replace function public.is_shop_owner(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.shop_members
    where shop_id = p_shop_id and user_id = auth.uid() and member_role = 'owner'
  );
$$;

create or replace function public.is_wholesaler_member(p_wholesaler_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.wholesaler_members where wholesaler_id = p_wholesaler_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_wholesaler_owner(p_wholesaler_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.wholesaler_members
    where wholesaler_id = p_wholesaler_id and user_id = auth.uid() and member_role = 'owner'
  );
$$;

-- 这张订单我能不能看（买家、批发商、客服）
create or replace function public.can_access_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and (
        o.shop_id in (select shop_id from public.shop_members where user_id = auth.uid())
        or o.wholesaler_id in (select wholesaler_id from public.wholesaler_members where user_id = auth.uid())
        or public.is_admin()
      )
  );
$$;

-- 这家店有没有向我的批发商下过单（批发商要看店名、地址、电话去送货）
create or replace function public.is_my_customer(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    join public.wholesaler_members m on m.wholesaler_id = o.wholesaler_id
    where o.shop_id = p_shop_id and m.user_id = auth.uid()
  );
$$;

-- ---------- 受保护字段 ----------
-- 用户可以改自己的资料，但有些字段只有客服或服务器能改（例如角色、批发商审核状态）。
-- 在 security definer 函数里（current_user 是函数主人）或服务器调用时不检查。
create or replace function public.protect_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  col text;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  foreach col in array tg_argv loop
    if (to_jsonb(new) -> col) is distinct from (to_jsonb(old) -> col) then
      raise exception 'COLUMN_PROTECTED' using errcode = '42501', detail = col;
    end if;
  end loop;
  return new;
end;
$$;

create trigger profiles_protect before update on public.profiles
  for each row execute function public.protect_columns('id', 'role', 'phone');
create trigger shops_protect before update on public.shops
  for each row execute function public.protect_columns('id', 'is_active', 'unlocks_changed_at', 'created_by');
create trigger wholesalers_protect before update on public.wholesalers
  for each row execute function public.protect_columns(
    'id', 'industry_id', 'region_id', 'status', 'is_founding', 'founding_no', 'founding_fee_paid_at',
    'rating_avg', 'rating_count', 'approved_at', 'approved_by', 'created_by');
create trigger wholesaler_private_protect before update on public.wholesaler_private
  for each row execute function public.protect_columns('wholesaler_id', 'commission_rate_override');
create trigger products_protect before update on public.products
  for each row execute function public.protect_columns('id', 'wholesaler_id', 'created_by');

-- ---------- 开启 RLS ----------

alter table public.regions enable row level security;
alter table public.delivery_zones enable row level security;
alter table public.industries enable row level security;
alter table public.categories enable row level security;
alter table public.app_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_members enable row level security;
alter table public.wholesalers enable row level security;
alter table public.wholesaler_private enable row level security;
alter table public.wholesaler_members enable row level security;
alter table public.wholesaler_delivery_zones enable row level security;
alter table public.device_tokens enable row level security;
alter table public.catalog_items enable row level security;
alter table public.products enable row level security;
alter table public.product_price_history enable row level security;
alter table public.price_list_imports enable row level security;
alter table public.price_list_import_rows enable row level security;
alter table public.cart_items enable row level security;
alter table public.checkouts enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_events enable row level security;
alter table public.reviews enable row level security;
alter table public.pricing_plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.trial_claims enable row level security;
alter table public.unlocked_wholesalers enable row level security;
alter table public.payments enable row level security;
alter table public.commission_invoices enable row level security;
alter table public.commission_records enable row level security;
alter table public.whatsapp_messages enable row level security;
alter table public.order_drafts enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

-- ---------- 客服（admin） ----------
-- 一般的表：能看能改
do $$
declare
  t text;
begin
  foreach t in array array[
    'regions', 'delivery_zones', 'industries', 'categories', 'app_settings', 'profiles',
    'shops', 'shop_members', 'wholesalers', 'wholesaler_private', 'wholesaler_members',
    'wholesaler_delivery_zones', 'device_tokens', 'catalog_items', 'products',
    'price_list_imports', 'price_list_import_rows', 'cart_items', 'reviews', 'pricing_plans',
    'subscriptions', 'trial_claims', 'unlocked_wholesalers', 'payments', 'commission_invoices',
    'whatsapp_messages', 'order_drafts', 'notifications'
  ] loop
    execute format(
      'create policy "admin: full access" on public.%I for all to authenticated '
      'using ((select public.is_admin())) with check ((select public.is_admin()))', t);
  end loop;
end;
$$;

-- 订单、佣金和记录类的表：客服也只能看。要改订单就调用函数（place_order、set_order_status……），
-- 金额、状态和佣金才会一致，函数也会记下是客服代操作。
do $$
declare
  t text;
begin
  foreach t in array array[
    'checkouts', 'orders', 'order_items', 'order_status_events', 'commission_records',
    'product_price_history', 'audit_logs'
  ] loop
    execute format(
      'create policy "admin: read" on public.%I for select to authenticated '
      'using ((select public.is_admin()))', t);
  end loop;
end;
$$;

-- ---------- 设定类：登录的人都能看 ----------
create policy "everyone: read regions" on public.regions for select to authenticated using (true);
create policy "everyone: read delivery zones" on public.delivery_zones for select to authenticated using (true);
create policy "everyone: read industries" on public.industries for select to authenticated using (true);
create policy "everyone: read categories" on public.categories for select to authenticated using (true);
create policy "everyone: read app settings" on public.app_settings for select to authenticated using (true);
create policy "everyone: read catalog items" on public.catalog_items for select to authenticated using (true);
create policy "everyone: read pricing plans" on public.pricing_plans for select to authenticated using (true);

-- ---------- 用户资料 ----------
create policy "self: read own profile" on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy "self: update own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------- 店铺 ----------
create policy "buyer: read own shops" on public.shops for select to authenticated
  using (id in (select public.my_shop_ids()));
create policy "seller: read customer shops" on public.shops for select to authenticated
  using (public.is_my_customer(id));
create policy "buyer owner: update own shop" on public.shops for update to authenticated
  using (public.is_shop_owner(id)) with check (public.is_shop_owner(id));

create policy "member: read own shop memberships" on public.shop_members for select to authenticated
  using (user_id = (select auth.uid()) or shop_id in (select public.my_shop_ids()));

-- ---------- 批发商 ----------
create policy "everyone: read active wholesalers" on public.wholesalers for select to authenticated
  using (status = 'active');
create policy "seller: read own wholesalers" on public.wholesalers for select to authenticated
  using (id in (select public.my_wholesaler_ids()));
create policy "seller owner: update own wholesaler" on public.wholesalers for update to authenticated
  using (public.is_wholesaler_owner(id)) with check (public.is_wholesaler_owner(id));

create policy "seller: read own private info" on public.wholesaler_private for select to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()));
create policy "seller owner: update own private info" on public.wholesaler_private for update to authenticated
  using (public.is_wholesaler_owner(wholesaler_id)) with check (public.is_wholesaler_owner(wholesaler_id));

create policy "member: read own wholesaler memberships" on public.wholesaler_members for select to authenticated
  using (user_id = (select auth.uid()) or wholesaler_id in (select public.my_wholesaler_ids()));

-- 运费和送货区：公开（下单前就要显示）
create policy "everyone: read delivery zones of wholesalers" on public.wholesaler_delivery_zones
  for select to authenticated using (true);
create policy "seller: manage own delivery zones" on public.wholesaler_delivery_zones
  for all to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()))
  with check (wholesaler_id in (select public.my_wholesaler_ids()));

-- ---------- 推送 token ----------
create policy "self: manage own device tokens" on public.device_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------- 商品（买家通过函数读，这里只开放给批发商自己） ----------
create policy "seller: manage own products" on public.products for all to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()))
  with check (wholesaler_id in (select public.my_wholesaler_ids()));

create policy "seller: read own price history" on public.product_price_history for select to authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_id and p.wholesaler_id in (select public.my_wholesaler_ids())
  ));

create policy "seller: manage own price list imports" on public.price_list_imports for all to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()))
  with check (wholesaler_id in (select public.my_wholesaler_ids()));

create policy "seller: manage own price list rows" on public.price_list_import_rows for all to authenticated
  using (exists (
    select 1 from public.price_list_imports i
    where i.id = import_id and i.wholesaler_id in (select public.my_wholesaler_ids())
  ))
  with check (exists (
    select 1 from public.price_list_imports i
    where i.id = import_id and i.wholesaler_id in (select public.my_wholesaler_ids())
  ));

-- ---------- 购物车 ----------
create policy "buyer: manage own cart" on public.cart_items for all to authenticated
  using (shop_id in (select public.my_shop_ids()))
  with check (shop_id in (select public.my_shop_ids()));

-- ---------- 订单（只能看，写入走函数） ----------
create policy "buyer: read own checkouts" on public.checkouts for select to authenticated
  using (shop_id in (select public.my_shop_ids()));

create policy "buyer: read own orders" on public.orders for select to authenticated
  using (shop_id in (select public.my_shop_ids()));
create policy "seller: read orders sent to them" on public.orders for select to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()));

create policy "parties: read order items" on public.order_items for select to authenticated
  using (public.can_access_order(order_id));
create policy "parties: read order status events" on public.order_status_events for select to authenticated
  using (public.can_access_order(order_id));

-- 评价公开给所有登录的人看；写入走 submit_review()
create policy "everyone: read reviews" on public.reviews for select to authenticated using (true);

-- ---------- 订阅、付款、佣金 ----------
create policy "buyer: read own subscriptions" on public.subscriptions for select to authenticated
  using (shop_id in (select public.my_shop_ids()));
create policy "buyer: read own unlocked wholesalers" on public.unlocked_wholesalers for select to authenticated
  using (shop_id in (select public.my_shop_ids()));
create policy "payer: read own payments" on public.payments for select to authenticated
  using (
    shop_id in (select public.my_shop_ids())
    or wholesaler_id in (select public.my_wholesaler_ids())
  );
create policy "seller: read own commission invoices" on public.commission_invoices for select to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()));
create policy "seller: read own commission records" on public.commission_records for select to authenticated
  using (wholesaler_id in (select public.my_wholesaler_ids()));

-- ---------- 草稿和通知 ----------
create policy "buyer: read own order drafts" on public.order_drafts for select to authenticated
  using (shop_id in (select public.my_shop_ids()));

create policy "recipient: read own notifications" on public.notifications for select to authenticated
  using (
    user_id = (select auth.uid())
    or shop_id in (select public.my_shop_ids())
    or wholesaler_id in (select public.my_wholesaler_ids())
  );
