-- 导出第七步（收费）的示范数据：packages/core/test/fixtures/{buyer_billing*,seller_billing,commission_invoice,payment_paid}.json
-- （手机 App）和 admin_payments.json（客服后台）。由 tool/export_billing_fixtures.sh 在「全部迁移 + seed.sql」的本机数据库上跑：
-- 用服务器身份照 Edge Function 的步骤开付款单（create_payment_intent → attach_payment_checkout → mark_payment_paid），
-- 再用老板 / 批发商 / 客服的身份读出来。网关是假的（单号 HP-DEMO-*）。
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
\set QUIET 1

-- ---------- 账号（用 seed 的电话登录会自动接上店 / 批发商） ----------
insert into auth.users (id, phone, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', '60120000001', '{"locale": "zh"}'),
  ('11111111-1111-4111-8111-111111111114', '60120000004', '{"locale": "ms"}'),
  ('11111111-1111-4111-8111-111111111112', '60120000002', '{"locale": "zh"}'),
  ('00000000-0000-4000-c000-000000000003', '60120000003', '{"locale": "zh"}');
update public.profiles set role = 'admin', full_name = '客服 Mei' where id = '00000000-0000-4000-c000-000000000003';

-- ---------- 批发商 A：阿明那张已送达的订单当作上个月的 → 月初自动发出账单 ----------
update public.commission_records set period_month = (date_trunc('month', public.today_myt()) - interval '1 month')::date;
select (public.run_billing_daily() ->> 'issued')::int >= 1;

-- ---------- 老板看（付款之前） ----------
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', false) is not null;
select set_config('role', 'authenticated', false) is not null;
\o :outdir/buyer_billing.json
select jsonb_pretty(public.get_buyer_billing('00000000-0000-4000-b000-000000000001'));
\o
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111114", "role": "authenticated"}', false) is not null;
\o :outdir/buyer_billing_lapsed.json
select jsonb_pretty(public.get_buyer_billing('00000000-0000-4000-b000-000000000002'));
\o

-- ---------- 服务器：阿明付 3 个月、批发商 A 付佣金账单（假的网关） ----------
select set_config('request.jwt.claims', '', false) is not null;
select set_config('role', 'none', false) is not null;
select public.create_payment_intent('11111111-1111-4111-8111-111111111111', 'subscription',
  '00000000-0000-4000-b000-000000000001', 3) ->> 'result' = 'ok';
select public.attach_payment_checkout(p.id, 'HP-DEMO-1', 'https://securecheckout.sandbox.hit-pay.com/demo-1')
from public.payments p where p.shop_id = '00000000-0000-4000-b000-000000000001' and p.status = 'pending';
select public.mark_payment_paid(p.id, 'hitpay', 'HP-DEMO-1', p.amount_sen, 'fpx', '{"id": "HP-DEMO-1"}') ->> 'result' = 'paid'
from public.payments p where p.gateway_ref = 'HP-DEMO-1';

select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', false) is not null;
select set_config('role', 'authenticated', false) is not null;
\o :outdir/payment_paid.json
select jsonb_pretty(public.get_payment(p.id)) from public.payments p where p.gateway_ref = 'HP-DEMO-1';
\o :outdir/buyer_billing_active.json
select jsonb_pretty(public.get_buyer_billing('00000000-0000-4000-b000-000000000001'));
\o

-- ---------- 批发商 A 看 ----------
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111112", "role": "authenticated"}', false) is not null;
\o :outdir/seller_billing.json
select jsonb_pretty(public.get_seller_billing('00000000-0000-4000-a000-00000000000a'));
\o :outdir/commission_invoice.json
select jsonb_pretty(public.get_commission_invoice(i.id)) from public.commission_invoices i
where i.wholesaler_id = '00000000-0000-4000-a000-00000000000a';
\o

-- ---------- 客服看 ----------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-c000-000000000003", "role": "authenticated"}', false) is not null;
\o :outdir/admin_payments.json
select jsonb_pretty(public.admin_list_payments());
\o
