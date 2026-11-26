-- 导出客服后台的示范数据（packages/core/test/fixtures/admin_*.json）。由 tool/export_fixtures.sh 在
-- 「全部迁移 + seed.sql」的本机数据库上跑：先准备几张订单，再用客服身份叫 admin_* 函数，把回传原样存下来。
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
\set QUIET 1

-- ---------- 准备（服务器身份） ----------
insert into auth.users (id, phone, raw_user_meta_data)
values ('00000000-0000-4000-c000-000000000003', '60120000003', '{"locale": "zh"}');
update public.profiles set role = 'admin', full_name = '客服 Mei' where id = '00000000-0000-4000-c000-000000000003';

-- Siti（未付费，免费开放 A）：向 A 下单，45 分钟还没确认 → 跟进名单
insert into public.cart_items (shop_id, product_id, qty)
select '00000000-0000-4000-b000-000000000002', p.id, v.qty
from (values ('650ml 长方饭盒连盖', 1)) as v(name, qty)
join public.products p on p.name = v.name;
select public.place_order('00000000-0000-4000-b000-000000000002', p_source => 'app') is not null;
update public.orders set created_at = now() - interval '45 minutes'
where shop_id = '00000000-0000-4000-b000-000000000002';

-- 阿明：向 B、C 下单（App），B 10 分钟前，C 已确认
insert into public.cart_items (shop_id, product_id, qty)
select '00000000-0000-4000-b000-000000000001', p.id, v.qty
from (values ('16oz PP Cup 95mm (1000pcs)', 2), ('Dome Lid 95mm (1000pcs)', 2), ('Cawan PP 16oz 95mm', 3)) as v(name, qty)
join public.products p on p.name = v.name;
select public.place_order('00000000-0000-4000-b000-000000000001', p_source => 'app') is not null;
update public.orders o set created_at = now() - interval '10 minutes'
from public.wholesalers w where w.id = o.wholesaler_id and o.status = 'pending' and o.source = 'app'
  and o.shop_id = '00000000-0000-4000-b000-000000000001';
select public.confirm_order(o.id) is not null from public.orders o
where o.wholesaler_id = '00000000-0000-4000-a000-00000000000c' and o.status = 'pending';

-- ---------- 客服登录 ----------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-c000-000000000003", "role": "authenticated"}', false) is not null;
select set_config('role', 'authenticated', false) is not null;

-- 客服代阿明下单（打电话来）：A 的 22 安士杯 2 箱
select public.admin_set_cart_item('00000000-0000-4000-b000-000000000001', p.id, 2) is not null
from public.products p where p.name = '22安士 PP杯 95口径';
select public.admin_place_order('00000000-0000-4000-b000-000000000001',
  (public.quote_cart('00000000-0000-4000-b000-000000000001') ->> 'total_sen')::int, '老板打电话来订') is not null;
-- B 的那张代改：确认后送达（这个月多一家有佣金）
select public.admin_confirm_order(o.id) is not null from public.orders o
where o.wholesaler_id = '00000000-0000-4000-a000-00000000000b' and o.status = 'pending';
select public.admin_set_order_status(o.id, 'delivered') is not null from public.orders o
where o.wholesaler_id = '00000000-0000-4000-a000-00000000000b' and o.status = 'confirmed';
-- 跟进、改价、佣金比例
select public.admin_log_followup(o.id, '打了电话，陈老板说 3 点前确认') is not null from public.orders o
where o.shop_id = '00000000-0000-4000-b000-000000000002' and o.status = 'pending';
select public.admin_save_product('00000000-0000-4000-a000-00000000000a', p.id, '{"price_sen": 8300}') is not null
from public.products p where p.name = '16安士 PP杯 95口径';
select public.admin_set_commission_rate('00000000-0000-4000-a000-00000000000c', 0.025) is not null;
-- 购物车里先放一样（示范代下单的报价）
select public.admin_set_cart_item('00000000-0000-4000-b000-000000000001', p.id, 3) is not null
from public.products p where p.name = '95 平盖';

-- ---------- 导出 ----------
\o :outdir/admin_my_context.json
select jsonb_pretty(public.get_my_context());
\o :outdir/admin_dashboard.json
select jsonb_pretty(public.admin_dashboard());
\o :outdir/admin_shops.json
select jsonb_pretty(public.admin_list_shops());
\o :outdir/admin_wholesalers.json
select jsonb_pretty(public.admin_list_wholesalers());
\o :outdir/admin_orders.json
select jsonb_pretty(public.admin_list_orders());
\o :outdir/admin_order_detail.json
select jsonb_pretty(public.get_order(o.id)) from public.orders o
where o.shop_id = '00000000-0000-4000-b000-000000000002' and o.status = 'pending';
\o :outdir/admin_offers.json
select jsonb_pretty(jsonb_agg(to_jsonb(t))) from public.get_offers('00000000-0000-4000-b000-000000000001') t;
\o :outdir/admin_quote.json
select jsonb_pretty(public.quote_cart('00000000-0000-4000-b000-000000000001'));
\o :outdir/admin_products.json
select jsonb_pretty(public.admin_list_products('00000000-0000-4000-a000-00000000000a'));
\o :outdir/admin_subscriptions.json
select jsonb_pretty(public.admin_list_subscriptions());
\o :outdir/admin_commission_report.json
select jsonb_pretty(public.admin_commission_report());
\o :outdir/admin_audit_logs.json
select jsonb_pretty(public.admin_list_audit_logs(p_limit => 60));
\o
