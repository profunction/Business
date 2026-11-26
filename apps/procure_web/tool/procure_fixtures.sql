-- 导出公司采购网页（procure_web）和客服后台「公司」的示范数据（packages/core/test/fixtures/procure_*.json、admin_compan*.json）。
-- 由 tool/export_fixtures.sh 在「全部迁移 + seed.sql」的本机数据库上跑：用公司 admin 的身份注册公司、加分店、邀请成员、
-- 选方案；跑一次每天的公司收费工作（试用快结束 → 开第一期账单、通知）；再用 admin / requester / 客服的身份读出来。
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
\set QUIET 1

-- ---------- 账号 ----------
insert into auth.users (id, phone, raw_user_meta_data) values
  ('22222222-2222-4222-8222-222222222201', '60120000005', '{"locale": "zh", "full_name": "林美玲"}'),
  ('22222222-2222-4222-8222-222222222202', '60120000006', '{"locale": "en", "full_name": "Rajesh Kumar"}'),
  ('22222222-2222-4222-8222-222222222203', '60120000007', '{"locale": "ms", "full_name": "Aisyah"}'),
  ('00000000-0000-4000-c000-000000000003', '60120000003', '{"locale": "zh"}');
update public.profiles set role = 'admin', full_name = '客服 Mei' where id = '00000000-0000-4000-c000-000000000003';

-- ---------- 公司 admin：注册公司、分店、成员、方案 ----------
select set_config('request.jwt.claims', '{"sub": "22222222-2222-4222-8222-222222222201", "role": "authenticated"}', false) is not null;
select set_config('role', 'authenticated', false) is not null;
select public.register_company('Grand Hotel Johor Bahru', 'hotel', (select id from public.regions where code = 'JHB'),
  '202301012345 (1234567-X)', 'ap@grandhotel.example',
  jsonb_build_object('name', 'Grand Hotel 中央厨房', 'zone_id', (select id from public.delivery_zones where code = 'tebrau'),
    'address', 'Jalan Molek 1, Taman Molek', 'contact_name', 'Chef Lim', 'phone', '0123334001', 'site_code', 'CK',
    'cost_center', 'CC-100')) is not null;
select public.add_company_site(c.id, 'Grand Hotel 宴会厅', (select id from public.delivery_zones where code = 'skudai'),
  'Jalan Skudai 8', 'Ms Tan', '0123334002', 'BQ', 'CC-200') is not null
from public.companies c;
select public.update_company(c.id, '{"legal_name": "Grand Hotel JB Sdn Bhd", "tin": "C2581234560", "billing_address": "Jalan Molek 1, 81100 Johor Bahru"}') is not null
from public.companies c;
select public.invite_company_member(c.id, '0120000006', '{finance}', true, null) is not null from public.companies c;
select public.invite_company_member(c.id, '0120000007', '{requester}', false,
  array[(select s.id from public.shops s where s.site_code = 'BQ')]) is not null from public.companies c;
select public.invite_company_member(c.id, '012-333 4444', '{approver}', true, null) is not null from public.companies c;
select public.change_company_plan(c.id, 'co_pro', 'monthly') is not null from public.companies c;

-- ---------- 试用还剩 5 天：每天的工作开第一期账单、通知 admin / finance ----------
select set_config('role', 'none', false) is not null;
select set_config('request.jwt.claims', '', false) is not null;
update public.company_subscriptions set trial_ends_at = now() + interval '5 days';
select (public.run_company_billing_daily() ->> 'issued')::int = 1;
update public.notifications set read_at = now()
where event_type = 'company_trial_ending' and user_id = '22222222-2222-4222-8222-222222222201';

-- ---------- 导出：公司 admin ----------
select set_config('request.jwt.claims', '{"sub": "22222222-2222-4222-8222-222222222201", "role": "authenticated"}', false) is not null;
select set_config('role', 'authenticated', false) is not null;
\o :outdir/procure_my_context.json
select jsonb_pretty(public.get_my_context());
\o :outdir/procure_context.json
select jsonb_pretty(public.get_company_context(c.id)) from public.companies c;
\o :outdir/procure_members.json
select jsonb_pretty(public.list_company_members(c.id)) from public.companies c;
\o :outdir/procure_billing.json
select jsonb_pretty(public.get_company_billing(c.id)) from public.companies c;
\o :outdir/procure_inbox.json
select jsonb_pretty(public.list_my_inbox());
\o :outdir/procure_offers.json
select jsonb_pretty(jsonb_agg(to_jsonb(t))) from public.get_offers((select s.id from public.shops s where s.site_code = 'CK')) t;
\o :outdir/procure_zones.json
select jsonb_pretty(jsonb_agg(jsonb_build_object('id', z.id, 'code', z.code, 'name', z.name) order by z.sort_order))
from public.delivery_zones z where z.is_active;
\o :outdir/procure_regions.json
select jsonb_pretty(jsonb_agg(jsonb_build_object('id', r.id, 'code', r.code, 'name', r.name) order by r.code)) from public.regions r;
\o

-- ---------- 导出：requester（只能管宴会厅） ----------
select set_config('request.jwt.claims', '{"sub": "22222222-2222-4222-8222-222222222203", "role": "authenticated"}', false) is not null;
\o :outdir/procure_context_requester.json
select jsonb_pretty(public.get_company_context(c.id)) from public.companies c;
\o

-- ---------- 导出：客服 ----------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-c000-000000000003", "role": "authenticated"}', false) is not null;
\o :outdir/admin_companies.json
select jsonb_pretty(public.admin_list_companies());
\o :outdir/admin_company_detail.json
select jsonb_pretty(public.admin_get_company(c.id)) from public.companies c;
\o
