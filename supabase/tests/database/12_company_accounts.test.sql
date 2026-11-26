-- 第八步第 1 期：公司账号、分店、角色、公司方案。
-- 公司员工只看得到自己公司 / 自己分店；分店价钱跟公司订阅走；分店电话登录不会变成分店成员；邀请自动接上；
-- 方案上限；最后一个 admin；续费锁定价 / 宽限 / 停了按新价；公司分店不能走小店的下单路；收件箱；客服；权限
begin;
\ir _helpers.psql
select plan(175);
select tests.setup_world();

-- 公司的人
insert into auth.users (id, phone) values
  ('aaaaaaaa-0000-4000-8000-000000000101', '60122000101'),   -- co_admin：注册公司 C1
  ('aaaaaaaa-0000-4000-8000-000000000102', '60122000102'),   -- co_finance（之后邀请，已经有账号）
  ('aaaaaaaa-0000-4000-8000-000000000104', '60122000104'),   -- other_admin：注册公司 C2
  ('aaaaaaaa-0000-4000-8000-000000000105', '60122000105');   -- 没公司的人
create function tests.cu(p text) returns uuid language sql immutable as $$
  select (case p
    when 'co_admin' then 'aaaaaaaa-0000-4000-8000-000000000101'
    when 'co_finance' then 'aaaaaaaa-0000-4000-8000-000000000102'
    when 'co_req' then 'aaaaaaaa-0000-4000-8000-000000000103'
    when 'other_admin' then 'aaaaaaaa-0000-4000-8000-000000000104'
    when 'nobody' then 'aaaaaaaa-0000-4000-8000-000000000105'
  end)::uuid;
$$;
create function tests.csub(p_company uuid) returns public.company_subscriptions language sql stable security definer as $$
  select * from public._company_current_sub(p_company);
$$;
-- 内部函数 App 叫不到：测试用 postgres 身份看
create function tests.full_access(p uuid) returns boolean language sql stable security definer as $$ select public.has_full_access(p) $$;
create function tests.limits(p uuid, out max_sites int, out max_users int) language sql stable security definer as $$
  select * from public._company_limits(p) $$;
create function tests.user_count(p uuid) returns int language sql stable security definer as $$ select public._company_user_count(p) $$;
create function tests.req_feature(p uuid, f text) returns void language sql stable security definer as $$
  select public._require_company_feature(p, f) $$;
-- 开单 + 网关单号（服务器身份，跟 create-payment 一样）。回传付款单 id
create function tests.co_intent(p_user uuid, p_invoice uuid) returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  v := public.create_payment_intent(p_user, 'company_plan', p_invoice);
  if v ->> 'result' <> 'ok' then
    raise exception 'intent failed: %', v;
  end if;
  perform public.attach_payment_checkout((v -> 'payment' ->> 'id')::uuid, 'HP-' || (v -> 'payment' ->> 'id'),
    'https://pay.test/' || (v -> 'payment' ->> 'id'));
  return (v -> 'payment' ->> 'id')::uuid;
end;
$$;
create function tests.paid(p_payment uuid) returns jsonb language sql as $$
  select public.mark_payment_paid(p.id, 'hitpay', p.gateway_ref, p.amount_sen, 'fpx', '{"test": true}')
  from public.payments p where p.id = p_payment;
$$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- =============================================================================
-- 权限、表、编号
-- =============================================================================
select ok(
  not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'compan%' and not c.relrowsecurity),
  '新表都开了 RLS');
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('register_company', 'update_company', 'add_company_site', 'update_company_site',
        'archive_company_site', 'invite_company_member', 'set_company_member', 'remove_company_member',
        'cancel_company_invite', 'get_company_context', 'list_company_members', 'get_company_billing',
        'change_company_plan', 'list_my_inbox', 'mark_inbox_read', 'run_company_billing_daily',
        '_extend_company_subscription', '_issue_company_invoice', 'company_has_feature', 'admin_list_companies',
        'admin_get_company', 'admin_set_company_status', 'admin_set_company_plan', 'admin_extend_company_trial',
        'admin_issue_company_invoice', 'admin_mark_company_invoice_paid', 'my_company_ids', 'can_access_site')
      and (has_function_privilege('anon', p.oid, 'execute') or not p.prosecdef
           or not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false))),
  '新函数：security definer、固定 search_path、anon 不能叫');
select ok(not has_function_privilege('authenticated', 'public._extend_company_subscription(uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._issue_company_invoice(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._notify_company(uuid, public.company_role[], text, jsonb)', 'execute'),
  '内部小工具 App 叫不到');
select is((select string_agg(code, ',' order by sort_order) from public.company_plans where is_public), 'co_starter,co_pro,co_enterprise',
  '公开的方案：Starter、Pro、Enterprise（试用不公开）');
select ok(public._next_doc_no('PO') ~ '^PO[0-9]{4}-[0-9]{5}$' and public._next_doc_no('RFQ') ~ '^RFQ[0-9]{4}-[0-9]{4}$',
  '编号：种类 + YYMM + 流水号');
select is(tests.error_of($$select public._next_doc_no('XX')$$), 'INVALID_VALUE:XX', '不认识的编号种类');

-- =============================================================================
-- 注册公司
-- =============================================================================
select tests.login_as(tests.uid('seller1'));
select is(tests.error_of(format($$select public.register_company('Hotel X', 'hotel', %L)$$, 'bbbbbbbb-0000-4000-8000-000000000001')),
  'ROLE_MISMATCH', '批发商不能注册公司');
select tests.login_as(tests.cu('co_admin'));
select is(tests.error_of($$select public.register_company('Hotel X', 'hotel', gen_random_uuid())$$), 'INVALID_VALUE:region_id',
  '地区不对');
select is(tests.error_of($$select public.register_company('  ', 'hotel', 'bbbbbbbb-0000-4000-8000-000000000001')$$),
  'INVALID_VALUE:name', '名字不能空');
select public.register_company('Grand Hotel JB', 'hotel', 'bbbbbbbb-0000-4000-8000-000000000001', '2023-0101 2345 (1234567-x)',
  'ap@grand.test', jsonb_build_object('name', 'Grand Hotel 厨房', 'zone_id', tests.uid('Z1'), 'address', 'Jalan 1',
  'contact_name', 'Chef Lim', 'phone', '60122000999')) as c1 \gset
select is((select ssm_no from public.companies where id = :'c1'), '2023010123451234567X', 'SSM 正规化：大写、只留字母数字');
select is((select roles::text || '/' || all_sites from public.company_members where company_id = :'c1' and user_id = tests.cu('co_admin')),
  '{admin,approver,finance,requester}/true', '注册的人当 admin（全部角色、全部分店）');
select is((tests.csub(:'c1')).status::text || '/' || (tests.csub(:'c1')).plan_code, 'trialing/co_trial', '开试用');
select ok((tests.csub(:'c1')).trial_ends_at between now() + interval '29 days 23 hours' and now() + interval '30 days 1 hour',
  '试用 30 天（app_settings.company_trial_days）');
select (select id from public.shops where company_id = :'c1') as site1 \gset
select is((select name || '/' || shop_type || '/' || coalesce(phone, '') from public.shops where id = :'site1'),
  'Grand Hotel 厨房/other/60122000999', '顺便建第一个分店（shops.company_id）');
select is((select count(*)::int from public.shop_members where shop_id = :'site1'), 0, '分店没有 shop_members');
select is((select count(*)::int from public.subscriptions where shop_id = :'site1'), 0, '分店没有自己的小店订阅');
select is(tests.error_of($$select public.register_company('Copycat', 'hotel', 'bbbbbbbb-0000-4000-8000-000000000001', '2023010123451234567x')$$),
  'SSM_ALREADY_REGISTERED', '同一个 SSM 不能注册两家');

-- 同一个号码第二家：不送试用（lapsed，马上有一张 Starter 账单要付）
select public.register_company('Second Co', 'factory', 'bbbbbbbb-0000-4000-8000-000000000001') as c9 \gset
select is((tests.csub(:'c9')).status::text || '/' || (tests.csub(:'c9')).plan_code, 'lapsed/co_starter', '号码拿过试用：不送');
select is((select amount_sen || '/' || status || '/' || (due_date = public.today_myt()) from public.company_invoices where company_id = :'c9'),
  '29000/issued/true', '要先付第一期 Starter（RM290，今天到期）');
select is(tests.full_access(public.add_company_site(:'c9', 'S9 site', tests.uid('Z1'), null, null, null)), false,
  '没付的公司：分店看不到价钱');

select tests.login_as(tests.cu('other_admin'));
select is(tests.error_of($$select public.register_company('Other Co', 'factory', 'bbbbbbbb-0000-4000-8000-000000000001', '2023010123451234567X')$$),
  'SSM_ALREADY_REGISTERED', 'SSM 拿过了');
select public.register_company('Other Co', 'factory', 'bbbbbbbb-0000-4000-8000-000000000001', '999999-K') as c2 \gset
select is((tests.csub(:'c2')).status::text, 'trialing', '另一个号码、另一个 SSM：有试用');
select public.add_company_site(:'c2', 'Other 厂', tests.uid('Z1'), null, null, null) as site_other \gset

-- =============================================================================
-- 分店价钱跟公司订阅走；公司分店不能走小店的下单路
-- =============================================================================
select tests.login_as(tests.cu('co_admin'));
select ok(public.is_shop_member(:'site1') and public.is_shop_owner(:'site1'), 'admin 等于分店的成员和老板');
select ok(not public.is_shop_member(:'site_other'), '别家公司的分店不是我的');
select ok(tests.full_access(:'site1'), '公司试用中：分店看得到全部价钱');
select ok((select bool_and(o.price_visible) and count(*) >= 5 from public.get_offers(:'site1') o),
  '分店用 get_offers 比价（全部看得到价钱）');
select is(tests.error_of(format('select public.get_offers(%L)', :'site_other')), 'NOT_ALLOWED', '别家公司的分店不能看');
select is(tests.error_of(format('select public.place_order(%L)', :'site1')), 'USE_REQUISITION', '公司分店不能 place_order');
select is(tests.error_of(format('select public.reorder_last(%L)', :'site1')), 'USE_REQUISITION', '不能「跟上次一样」');
select is(tests.error_of(format($$insert into public.cart_items (shop_id, product_id, qty) values (%L, %L, 1)$$, :'site1', tests.uid('P1'))),
  'USE_REQUISITION', '购物车不能加（RLS 让我进来，trigger 挡住）');
select tests.login_as(tests.uid('admin'));
select is(tests.error_of(format('select public.admin_set_cart_item(%L, %L, 1)', :'site1', tests.uid('P1'))), 'USE_REQUISITION',
  '客服也不能代分店用购物车');
select is(tests.error_of(format('select public.admin_place_order(%L, 100)', :'site1')), 'USE_REQUISITION', '客服也不能代下单');
select tests.logout();
select is(tests.error_of(format('select public.reserve_voice_order_run(%L, %L, gen_random_uuid(), %L, %L)',
  :'site1', tests.cu('co_admin'), 'app_voice', 'x.wav')), 'USE_REQUISITION', '服务器也不能（语音下单）');
select is(tests.error_of(format($$insert into public.checkouts (shop_id, source) values (%L, 'app')$$, :'site1')), 'USE_REQUISITION',
  '直接写结账也挡住');
select lives_ok(format($$insert into public.checkouts (shop_id, source) values (%L, 'procurement')$$, :'site1'),
  '采购单（第 2 期）的结账可以');
select ok(not public.start_trial(:'site1') and not exists (select 1 from public.subscriptions where shop_id = :'site1'),
  '公司分店不拿小店的试用');
select is(public.create_payment_intent(tests.uid('admin'), 'subscription', :'site1') ->> 'result', 'not_allowed',
  '公司分店没有小店月费可以付');
-- 小店照旧
select tests.add_to_cart('S1', 'P1', 1);
select tests.login_as(tests.uid('buyer1'));
select isnt(public.place_order(tests.uid('S1')), null, '小店照旧可以下单');
select ok(not public.is_shop_member(:'site1'), '小店老板不是公司分店的成员');
select tests.logout();

-- =============================================================================
-- 分店电话登录不会变成分店成员；邀请自动接上
-- =============================================================================
insert into auth.users (id, phone) values ('aaaaaaaa-0000-4000-8000-000000000199', '60122000999');
select is((select count(*)::int from public.shop_members where user_id = 'aaaaaaaa-0000-4000-8000-000000000199'), 0,
  '分店电话（Chef Lim）登录：不会变成分店的老板');

select tests.login_as(tests.cu('co_admin'));
select public.add_company_site(:'c1', 'Grand Hotel 宴会厅', tests.uid('Z2'), 'Jalan 2', 'Ms Tan', null, 'BQ', 'CC-200') as site2 \gset
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, true, null)', :'c1', '123', '{requester}')),
  'INVALID_PHONE', '号码不对');
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, true, null)', :'c1', '0122000103', '{}')),
  'INVALID_VALUE:roles', '一定要有角色');
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, false, %L)', :'c1', '0122000103', '{requester}',
  array[:'site_other']::uuid[])), 'INVALID_VALUE:shop_ids', '只能选自己公司的分店');
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, true, null)', :'c1', '0111000011', '{requester}')),
  'ROLE_MISMATCH', '批发商的号码不能当公司成员');
-- 号码还没有账号：留邀请，只能管宴会厅
select public.invite_company_member(:'c1', '012-200 0103', '{requester}', false, array[:'site2']::uuid[]) as inv_req \gset
select is((select phone || '/' || (accepted_at is null) from public.company_invites where id = :'inv_req'), '60122000103/true',
  '还没有账号：留邀请（号码正规化）');
-- 号码已经有账号：直接加
select public.invite_company_member(:'c1', '0122000102', '{finance}', true, null) as inv_fin \gset
select is((select roles::text from public.company_members where company_id = :'c1' and user_id = tests.cu('co_finance')), '{finance}',
  '已经有账号：直接加成员');
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, true, null)', :'c1', '0122000102', '{finance}')),
  'ALREADY_MEMBER', '已经是成员');
select public.invite_company_member(:'c1', '012-200 0103', '{requester}', false, array[:'site2']::uuid[]) as inv_req \gset
select is((select count(*)::int from public.company_invites where company_id = :'c1' and phone = '60122000103' and accepted_at is null), 1,
  '再邀请一次：换掉旧的（只有一条没接受的）');
select tests.logout();
insert into auth.users (id, phone) values (tests.cu('co_req'), '+60 12-200 0103');
select is((select roles::text || '/' || all_sites from public.company_members where company_id = :'c1' and user_id = tests.cu('co_req')),
  '{requester}/false', '登录后自动接上邀请');
select is((select array_agg(shop_id)::text from public.company_member_sites where user_id = tests.cu('co_req')), '{' || :'site2' || '}',
  '只能管宴会厅');
select is((select profiles.role::text from public.profiles where id = tests.cu('co_req')), 'buyer', '公司员工的角色照旧是 buyer');

-- =============================================================================
-- 公司员工只看得到自己公司 / 自己分店
-- =============================================================================
select tests.login_as(tests.cu('co_req'));
select ok(public.is_shop_member(:'site2') and not public.is_shop_member(:'site1'), 'requester 只能管自己的分店');
select ok(not public.is_shop_owner(:'site2'), 'requester 不是分店的老板');
select is((select count(*)::int from public.shops where company_id = :'c1'), 1, 'RLS：只看得到自己的分店');
select is((select count(*)::int from public.companies), 1, 'RLS：只看得到自己的公司');
select is((select count(*)::int from public.company_subscriptions), 0, 'RLS：requester 看不到订阅');
select is(tests.error_of(format('select public.get_company_billing(%L)', :'c1')), 'NOT_ALLOWED', 'requester 不能看账单');
select is(tests.error_of(format('select public.list_company_members(%L)', :'c1')), 'NOT_ALLOWED', 'requester 不能看成员');
select is(tests.error_of(format('select public.add_company_site(%L, %L, %L, null, null, null)', :'c1', 'x', tests.uid('Z1'))),
  'NOT_ALLOWED', 'requester 不能加分店');
select is(public.get_company_context(:'c1') -> 'my_roles', '["requester"]'::jsonb, '我的角色');
select is(jsonb_array_length(public.get_company_context(:'c1') -> 'sites'), 1, '我能管的分店（一个）');
select is((select jsonb_array_length(c -> 'sites') || '/' || (c ->> 'name')
           from jsonb_array_elements(public.get_my_context() -> 'companies') c), '1/Grand Hotel JB', 'get_my_context 多回传公司');
select is(jsonb_array_length(public.get_my_context() -> 'shops'), 0, '公司分店不放进 shops（App 的小店界面不变）');
select is(tests.error_of(format('select public.get_company_context(%L)', :'c2')), 'NOT_ALLOWED', '别家公司看不到');
select is(tests.error_of(format('select public.get_company_context(%L)', gen_random_uuid())), 'COMPANY_NOT_FOUND', '没有这家公司');
select is(tests.error_of(format($$select public.register_wholesaler('X', %L, %L)$$, 'bbbbbbbb-0000-4000-8000-000000000001',
  'bbbbbbbb-0000-4000-8000-000000000021')), 'ROLE_MISMATCH', '公司成员不能注册批发商');
select tests.login_as(tests.cu('co_finance'));
select ok(public.is_shop_member(:'site1') and public.is_shop_member(:'site2'), 'finance 永远全部分店');
select is((select count(*)::int from public.company_subscriptions), 1, 'RLS：finance 看得到订阅');
select is(jsonb_array_length(public.list_company_members(:'c1') -> 'members'), 3, 'finance 看得到成员');
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, true, null)', :'c1', '0122000188', '{requester}')),
  'NOT_ALLOWED', 'finance 不能邀请');
select tests.login_as(tests.cu('nobody'));
select is((select count(*)::int from public.companies) + (select count(*)::int from public.company_members)
          + (select count(*)::int from public.company_invites), 0, '没公司的人什么都看不到');
select is(jsonb_array_length(public.get_my_context() -> 'companies'), 0, '没有公司');
select tests.login_as_anon();
select is((select count(*)::int from public.company_plans), 3, '没登录也看得到公开的方案（网站用）');
select tests.logout();

-- =============================================================================
-- 改资料、分店
-- =============================================================================
select tests.login_as(tests.cu('co_admin'));
select is(tests.error_of(format($$select public.update_company(%L, '{"status": "active"}')$$, :'c1')), 'INVALID_FIELD:status',
  '只能改资料和设定栏位');
select is(tests.error_of(format($$select public.update_company(%L, '{"reissue_tolerance_bp": -5}')$$, :'c1')) like 'INVALID_VALUE%', true,
  '值不对');
select is(public.update_company(:'c1', '{"legal_name": "Grand Hotel JB Sdn Bhd", "auto_receive_days": null, "benchmark_tolerance_bp": 1500}')
  ->> 'legal_name', 'Grand Hotel JB Sdn Bhd', '改公司全名');
select is((select coalesce(auto_receive_days::text, 'null') || '/' || benchmark_tolerance_bp from public.companies where id = :'c1'),
  'null/1500', '设定：不自动收货、比价容差 15%');
select is(public.update_company_site(:'site2', '{"cost_center": "CC-201"}') ->> 'cost_center', 'CC-201', '改分店的成本中心');
select is(tests.error_of(format($$select public.update_company_site(%L, '{"company_id": null}')$$, :'site2')), 'INVALID_FIELD:company_id',
  '分店不能换公司');
select is(tests.error_of(format($$update public.shops set company_id = null where id = %L$$, :'site2')), 'COLUMN_PROTECTED:company_id',
  '直接改表也不行');
select is(tests.error_of(format('select public.update_company_site(%L, %L)', tests.uid('S1'), '{"name": "x"}')), 'SHOP_NOT_FOUND',
  '小店不是公司分店');

-- 方案上限：试用 3 个分店
select public.add_company_site(:'c1', 'Grand Hotel 酒吧', tests.uid('Z1'), null, null, null) as site3 \gset
select is(tests.error_of(format('select public.add_company_site(%L, %L, %L, null, null, null)', :'c1', '第四个', tests.uid('Z1'))),
  'PLAN_LIMIT_SITES:3', '超过方案的分店数');
select is((public.archive_company_site(:'site3')) ->> 'is_active', 'false', '封存一个分店');
select isnt(public.add_company_site(:'c1', '第四个', tests.uid('Z1'), null, null, null), null, '封存的不算：可以再加');

-- 最后一个 admin
select is(tests.error_of(format('select public.remove_company_member(%L, %L)', :'c1', tests.cu('co_admin'))), 'LAST_COMPANY_ADMIN',
  '不能拿掉最后一个 admin');
select is(tests.error_of(format('select public.set_company_member(%L, %L, %L, true, null, true)', :'c1', tests.cu('co_admin'), '{finance}')),
  'LAST_COMPANY_ADMIN', '不能把最后一个 admin 改成别的');
select is(public.set_company_member(:'c1', tests.cu('co_finance'), '{admin,finance}', true, null, true) -> 'members' -> 0 ->> 'is_active',
  'true', '多一个 admin');
select lives_ok(format('select public.set_company_member(%L, %L, %L, true, null, true)', :'c1', tests.cu('co_admin'), '{approver}'),
  '有另一个 admin 就可以改');
select tests.login_as(tests.cu('co_finance'));
select lives_ok(format('select public.set_company_member(%L, %L, %L, true, null, true)', :'c1', tests.cu('co_admin'),
  '{admin,approver,finance,requester}'), '改回来');

-- 用户上限：试用 10 个（成员 + 没过期的邀请）
select tests.login_as(tests.cu('co_admin'));
select public.invite_company_member(:'c1', '01220002' || lpad(n::text, 2, '0'), '{requester}', true, null) is not null
from generate_series(1, 7) n;
select is(tests.user_count(:'c1'), 10, '3 个成员 + 7 个邀请 = 10');
select is(tests.error_of(format('select public.invite_company_member(%L, %L, %L, true, null)', :'c1', '0122000299', '{requester}')),
  'PLAN_LIMIT_USERS:10', '超过方案的用户数');
select tests.logout();
update public.company_invites set expires_at = now() - interval '1 minute' where phone = '60122000201';
select tests.login_as(tests.cu('co_admin'));
select isnt(public.invite_company_member(:'c1', '0122000299', '{requester}', true, null), null, '过期的邀请不算');
select (select id from public.company_invites where phone = '60122000299') as inv_cancel \gset
select is(jsonb_array_length(public.cancel_company_invite(:'inv_cancel') -> 'invites'), 7, '取消邀请');
select is(tests.error_of(format('select public.cancel_company_invite(%L)', :'inv_cancel')), 'INVITE_NOT_FOUND', '取消过的找不到');
select tests.logout();
update public.company_invites set expires_at = now() - interval '1 minute' where company_id = :'c1' and accepted_at is null;
select tests.login_as(tests.cu('co_admin'));

-- =============================================================================
-- 功能、换方案、账单、付款、续费
-- =============================================================================
select ok(public.company_has_feature(:'c1', 'reverse_auction') and public.company_has_feature(:'c1', 'ai_insights'),
  '试用 = Pro 的全部功能');
select is(tests.error_of(format('select tests.req_feature(%L, %L)', :'c9', 'rfq')), 'COMPANY_PLAN_INACTIVE',
  '订阅停了：COMPANY_PLAN_INACTIVE');
select is(tests.error_of(format('select public.change_company_plan(%L, %L, %L)', :'c1', 'co_enterprise', 'monthly')), 'NOT_ALLOWED',
  '企业方案只能客服设');
select is(tests.error_of(format('select public.change_company_plan(%L, %L, %L)', :'c1', 'co_trial', 'monthly')), 'INVALID_VALUE:co_trial',
  '试用不能选');
select is(public.change_company_plan(:'c1', 'co_starter', 'monthly') -> 'subscription' ->> 'pending_plan_code', 'co_starter',
  '试用中选 Starter：下一期生效');
select is((select count(*)::int from public.company_invoices where company_id = :'c1'), 0, '离试用结束还远：还没开账单');
-- 价钱涨了：已经选的照选的那天锁定
select tests.logout();
insert into public.company_plans (code, name, monthly_price_sen, annual_price_sen, max_sites, max_users, features, sort_order, effective_from)
values ('co_starter', '{"zh": "入门版", "en": "Starter", "ms": "Permulaan"}', 35000, 350000, 3, 15, '{requisitions,rfq,statements}', 1,
        now() - interval '1 second');
select tests.logout();
update public.company_subscriptions set trial_ends_at = now() + interval '3 days' where company_id = :'c1';
select is(public.run_company_billing_daily() ->> 'issued', '1', '试用结束前 7 天内：开第一期账单');
select (select id from public.company_invoices where company_id = :'c1' and status = 'issued') as ci1 \gset
select is((select plan_code || '/' || amount_sen || '/' || (period_start = (tests.csub(:'c1')).trial_ends_at)
           || '/' || (due_date = ((tests.csub(:'c1')).trial_ends_at at time zone 'Asia/Kuala_Lumpur')::date)
           from public.company_invoices where id = :'ci1'),
  'co_starter/29000/true/true', '账单：选的那天锁定 RM290（不是涨了的 RM350），从试用结束开始，到期 = 期末');
select is((select count(*)::int from public.notifications where event_type = 'company_invoice_issued'
           and payload ->> 'company_id' = :'c1'), 2, '通知 admin、finance（每个人一条）');
select is((select count(*)::int from public.notifications where event_type = 'company_trial_ending'
           and payload ->> 'company_id' = :'c1' and payload ->> 'days' = '7'), 2, '试用快结束（7 天）通知');
select is(public.run_company_billing_daily() ->> 'issued', '0', '再跑一次：不会再开、不会再通知');
select is((select count(*)::int from public.notifications where event_type = 'company_trial_ending' and payload ->> 'company_id' = :'c1'), 2,
  '提醒只发一次');

-- 付款：只有 admin / finance
select is(public.create_payment_intent(tests.cu('co_req'), 'company_plan', :'ci1') ->> 'result', 'not_allowed', 'requester 不能付公司方案');
select is(public.create_payment_intent(tests.cu('other_admin'), 'company_plan', :'ci1') ->> 'result', 'not_allowed', '别家公司不能付');
select is(public.create_payment_intent(tests.cu('co_finance'), 'company_plan', gen_random_uuid()) ->> 'result', 'not_found',
  '没有这张账单');
select tests.co_intent(tests.cu('co_finance'), :'ci1') as pay1 \gset
select is((select payer_type || '/' || purpose || '/' || amount_sen || '/' || (company_id = :'c1') from public.payments where id = :'pay1'),
  'company/company_plan/29000/true', '付款单：公司付公司方案');
select tests.login_as(tests.cu('co_finance'));
select is(public.get_payment(:'pay1') ->> 'company_id', :'c1', 'finance 看得到付款单');
select tests.login_as(tests.cu('co_req'));
select is(tests.error_of(format('select public.get_payment(%L)', :'pay1')), 'NOT_ALLOWED', 'requester 看不到');
select is((select count(*)::int from public.payments), 0, 'RLS：requester 看不到公司的付款');
select tests.logout();
select (tests.csub(:'c1')).trial_ends_at as trial_end1 \gset
select is(tests.paid(:'pay1') ->> 'result', 'paid', '网关说已付');
select is((tests.csub(:'c1')).status::text || '/' || (tests.csub(:'c1')).plan_code || '/' || (tests.csub(:'c1')).locked_price_sen,
  'active/co_starter/29000', '试用 → active Starter，锁定 RM290');
select is((tests.csub(:'c1')).current_period_end, :'trial_end1'::timestamptz + interval '1 month', '从试用结束开始算一个月（试用不会少）');
select is((select status::text from public.company_invoices where id = :'ci1'), 'paid', '账单已付');
select is(tests.paid(:'pay1') ->> 'result', 'already_paid', '网关重复通知：只算一次');
select is((tests.csub(:'c1')).current_period_end, :'trial_end1'::timestamptz + interval '1 month', '不会再加');
select is((select count(*)::int from public.notifications where event_type = 'payment_received' and payload ->> 'company_id' = :'c1'), 2,
  '收到付款：通知 admin、finance');
select ok(not public.company_has_feature(:'c1', 'reverse_auction') and public.company_has_feature(:'c1', 'rfq'),
  'Starter：没有反向竞价，有询价');
select is((tests.limits(:'c1')).max_users, 15, 'Starter 上限 15 个用户');

-- 一直续费：锁定价不变（就算现在的价钱涨了）
update public.company_subscriptions set current_period_end = now() + interval '2 days' where company_id = :'c1' and status = 'active';
select is(public.run_company_billing_daily() ->> 'issued', '1', '期末前开下一期');
select (select id from public.company_invoices where company_id = :'c1' and status = 'issued') as ci2 \gset
select is((select amount_sen from public.company_invoices where id = :'ci2'), 29000, '续费还是 RM290（现在 RM350）');

-- 过期没付 → past_due（宽限期内照样能用）→ 补付原价
update public.company_subscriptions set current_period_end = now() - interval '1 hour' where company_id = :'c1' and status = 'active';
select is(public.run_company_billing_daily() ->> 'past_due', '1', '过了期末没付 → past_due');
select is((tests.csub(:'c1')).grace_until, (tests.csub(:'c1')).current_period_end + interval '14 days', '宽限 14 天');
select is((select status::text from public.company_invoices where id = :'ci2'), 'overdue', '账单逾期');
select is((select count(*)::int from public.notifications where event_type = 'company_invoice_overdue' and payload ->> 'company_id' = :'c1'), 2,
  '逾期通知 admin、finance');
select ok(tests.full_access(:'site1'), '宽限期内：分店照样看得到价钱');
select (tests.csub(:'c1')).current_period_end as end2 \gset
select tests.paid(tests.co_intent(tests.cu('co_admin'), :'ci2')) ->> 'result' as _ \gset
select is((tests.csub(:'c1')).status::text || '/' || (tests.csub(:'c1')).locked_price_sen || '/'
          || ((tests.csub(:'c1')).current_period_end = :'end2'::timestamptz + interval '1 month'),
  'active/29000/true', '宽限期内补付：原价，从原来的期末接着算');

-- 换方案：下一期生效
select tests.login_as(tests.cu('co_admin'));
select is(public.change_company_plan(:'c1', 'co_pro', 'annual') -> 'subscription' ->> 'pending_price_sen', '790000',
  '换 Pro 年付：价钱照今天锁定');
select is((tests.csub(:'c1')).plan_code, 'co_starter', '这一期还是 Starter');
select is(public.change_company_plan(:'c1', 'co_starter', 'monthly') -> 'subscription' ->> 'pending_plan_code', null,
  '选回现在的方案 = 不换了');
select tests.logout();

-- 停了：过了宽限期 → lapsed（没付的账单作废）→ 回来按当时的价钱
update public.company_subscriptions set current_period_end = now() + interval '1 day' where company_id = :'c1' and status = 'active';
select public.run_company_billing_daily() is not null as _ \gset
select (select id from public.company_invoices where company_id = :'c1' and status = 'issued') as ci3 \gset
update public.company_subscriptions set current_period_end = now() - interval '20 days', status = 'past_due',
  grace_until = now() - interval '6 days' where company_id = :'c1' and status = 'active';
select is(public.run_company_billing_daily() ->> 'lapsed', '1', '过了宽限期 → lapsed');
select is((select status::text || '/' || void_reason from public.company_invoices where id = :'ci3'), 'void/LAPSED', '没付的账单作废');
select ok(not tests.full_access(:'site1'), '停了：分店看不到价钱');
select tests.login_as(tests.cu('co_admin'));
select is((select count(*)::int from public.get_offers(:'site1') o where o.price_visible), 0, '价钱是空的（模糊）');
select is(public.change_company_plan(:'c1', 'co_starter', 'monthly') -> 'invoices' -> 0 ->> 'amount_sen', '35000',
  '停了再回来：马上开账单，按现在的价钱 RM350');
select tests.logout();
select (select id from public.company_invoices where company_id = :'c1' and status = 'issued') as ci4 \gset
select is(tests.paid(tests.co_intent(tests.cu('co_admin'), :'ci4')) ->> 'result', 'paid', '付了');
select is((select count(*)::int from public.company_subscriptions where company_id = :'c1'), 2, '新建一条订阅（旧的留着）');
select is((tests.csub(:'c1')).status::text || '/' || (tests.csub(:'c1')).locked_price_sen, 'active/35000', '按新价 RM350 锁定');
select ok((tests.csub(:'c1')).current_period_start > now() - interval '1 minute', '从付款那天开始');
select ok(tests.full_access(:'site1'), '付了：分店又看得到价钱');
select is(public.create_payment_intent(tests.cu('co_admin'), 'company_plan', :'ci4') ->> 'result', 'nothing_due', '付过的账单不能再付');

-- 试用结束还没选方案 → lapsed
update public.company_subscriptions set trial_ends_at = now() - interval '1 minute' where company_id = :'c2';
select public.run_company_billing_daily() is not null as _ \gset
select is((tests.csub(:'c2')).status::text, 'lapsed', '试用结束没选方案：停了');

-- =============================================================================
-- 收件箱
-- =============================================================================
select tests.login_as(tests.cu('co_finance'));
select ok((public.list_my_inbox() ->> 'unread_count')::int >= 4, '收件箱：我的通知');
select is((select count(*)::int from jsonb_array_elements(public.list_my_inbox(2) -> 'items')), 2, '一页几条');
select (public.list_my_inbox(1) -> 'items' -> 0 ->> 'id') as n1 \gset
select is(public.mark_inbox_read(array[:'n1']::uuid[]), 1, '标一条已读');
select is(public.mark_inbox_read(array[:'n1']::uuid[]), 0, '已读的不会再改');
select ok(public.mark_inbox_read() > 0, '全部标已读');
select is((public.list_my_inbox() ->> 'unread_count')::int, 0, '没有未读的');
select tests.login_as(tests.cu('co_req'));
select is(public.mark_inbox_read(array[:'n1']::uuid[]), 0, '别人的通知改不到');

-- =============================================================================
-- 客服
-- =============================================================================
select tests.login_as(tests.cu('co_admin'));
select is(tests.error_of('select public.admin_list_companies()'), 'NOT_ALLOWED', '公司 admin 不是客服');
select tests.login_as(tests.uid('admin'));
select is((select count(*)::int from jsonb_array_elements(public.admin_list_companies('grand'))), 1, '客服搜公司名字');
select is(public.admin_list_companies('1234567X') -> 0 ->> 'name', 'Grand Hotel JB', '客服搜 SSM');
select is(jsonb_array_length(public.admin_get_company(:'c1') -> 'sites'), 4, '公司详情：全部分店（包括封存的）');
select is(public.get_company_context(:'c1') ->> 'acting_as_admin', 'true', '客服可以看任何公司');
select is(tests.error_of(format('select public.admin_set_company_status(%L, %L)', :'c1', 'suspended')), 'INVALID_NOTE', '停权要写原因');
select is(public.admin_set_company_status(:'c1', 'suspended', '没付钱的争议') ->> 'status', 'suspended', '停权');
select ok((select count(*) > 0 from public.audit_logs where action = 'admin_set_company_status' and acting_for_company_id = :'c1'),
  '客服动作写 audit_logs（acting_for_company_id）');
select tests.login_as(tests.cu('co_admin'));
select ok(not tests.full_access(:'site1'), '停权：分店看不到价钱');
select is(tests.error_of(format($$select public.update_company(%L, '{"tin": "C123"}')$$, :'c1')), 'COMPANY_SUSPENDED', '停权：不能改东西');
select is(tests.error_of(format('select public.change_company_plan(%L, %L, %L)', :'c1', 'co_pro', 'monthly')), 'COMPANY_SUSPENDED',
  '停权：不能换方案');
select tests.login_as(tests.uid('admin'));
select is(public.admin_set_company_status(:'c1', 'active') ->> 'status', 'active', '恢复');
select is(tests.error_of(format('select public.admin_set_company_plan(%L, %L, %L)', :'c2', 'co_enterprise', 'monthly')), 'INVALID_AMOUNT',
  '企业方案一定要给价钱');
select is(public.admin_extend_company_trial(:'c2', 14) -> 'subscription' ->> 'status', 'trialing', '试用过期、没付过：客服重开试用');
select is(tests.error_of(format('select public.admin_extend_company_trial(%L, 14)', :'c1')), 'INVALID_SUBSCRIPTION_STATE:active',
  '付过钱的不能重开试用');
select is(public.admin_set_company_plan(:'c2', 'co_enterprise', 'monthly', 250000) -> 'subscription' ->> 'custom_price', 'true',
  '企业方案自订价 RM2,500');
select is(public.admin_issue_company_invoice(:'c2') ->> 'amount_sen', '250000', '马上开账单（自订价）');
select (select id from public.company_invoices where company_id = :'c2' and status = 'issued') as ci_c2 \gset
select is(public.admin_mark_company_invoice_paid(:'ci_c2', 'other', 'BANK-001') ->> 'status', 'paid', '银行转账：客服标已付');
select is((tests.csub(:'c2')).status::text || '/' || (tests.csub(:'c2')).plan_code || '/' || (tests.csub(:'c2')).custom_price,
  'active/co_enterprise/true', '企业方案生效，自订价留着');
select is((select gateway || '/' || amount_sen from public.payments where company_id = :'c2'), 'manual/250000', '记一笔手动付款');
select is(tests.error_of(format('select public.admin_mark_company_invoice_paid(%L)', :'ci_c2')), 'INVALID_INVOICE_STATE:paid', '不能标两次');
select ok(exists (select 1 from jsonb_array_elements(public.admin_list_payments(p_purpose => 'company_plan')) x
  where x ->> 'payer_name' = 'Other Co' and x ->> 'invoice_no' like 'CI%'), '付款记录有公司名字和账单号码');
select ok(public.company_has_feature(:'c2', 'ai_spend') and (tests.limits(:'c2')).max_sites is null, '企业方案：全部功能、不限分店');

select * from finish();
rollback;
