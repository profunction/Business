-- 第五步：客服后台函数（admin_*）：权限、代下单、代管商品、订单筛选和跟进、代改状态、
-- 批发商审核 / 佣金比例 / 创始会员、订阅（延长试用、手动付款、取消、创始价）、佣金报表和账单、操作记录
begin;
\ir _helpers.psql
select plan(164);
select tests.setup_world();

-- 这个文件用的：最新一行客服动作记录
create function tests.last_audit(p_action text) returns public.audit_logs language sql as $$
  select * from public.audit_logs where action = p_action order by id desc limit 1;
$$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- =============================================================================
-- 权限：不是客服都不能叫
-- =============================================================================
select tests.login_as(tests.uid('buyer1'));
select is(tests.error_of('select public.admin_dashboard()'), 'NOT_ALLOWED', '买家不能看客服首页');
select is(tests.error_of(format('select public.admin_place_order(%L, 100)', tests.uid('S1'))), 'NOT_ALLOWED',
  '买家不能用客服下单（连自己的店也不行）');
select is(tests.error_of(format('select public.admin_list_orders()')), 'NOT_ALLOWED', '买家不能看全部订单');
select tests.login_as(tests.uid('seller1'));
select is(tests.error_of(format('select public.admin_save_product(%L, %L, %L)', tests.uid('W1'), tests.uid('P1'), '{"price_sen": 1}')),
  'NOT_ALLOWED', '批发商不能用客服函数改商品（连自己的也不行）');
select is(tests.error_of(format('select public.admin_set_wholesaler_status(%L, %L)', tests.uid('W1'), 'active')),
  'NOT_ALLOWED', '批发商不能审核自己');
select is(tests.error_of(format('select public.admin_set_commission_rate(%L, 0)', tests.uid('W1'))),
  'NOT_ALLOWED', '批发商不能改自己的佣金比例');
select is(tests.error_of('select public.admin_commission_report()'), 'NOT_ALLOWED', '批发商不能看佣金报表');
select is(tests.error_of('select public.admin_list_audit_logs()'), 'NOT_ALLOWED', '批发商不能看操作记录');
select tests.login_as_anon();
select throws_ok('select public.admin_dashboard()', '42501', null, '没登录：没有权限叫');
select tests.logout();
select is(tests.error_of('select public.admin_dashboard()'), 'NOT_ALLOWED', '服务器身份也不行（只给客服）');
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'admin\_%'
      and (has_function_privilege('anon', p.oid, 'execute') or not p.prosecdef
           or not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false))
  ),
  '全部 admin_ 函数：security definer、固定 search_path、anon 不能叫'
);
select ok(
  not has_function_privilege('authenticated', 'public._admin_audit(text, text, text, uuid, uuid, jsonb, jsonb)', 'execute'),
  '写操作记录的小工具 App 叫不到'
);

-- =============================================================================
-- 代买家下单
-- =============================================================================
select tests.login_as(tests.uid('admin'));

select ok(jsonb_array_length(public.admin_list_shops()) >= 3, '店铺列表');
select is((select jsonb_agg(e ->> 'name') from jsonb_array_elements(public.admin_list_shops('S2')) e), '["S2 店"]'::jsonb,
  '按店名搜索');
select is((select jsonb_agg(e ->> 'name') from jsonb_array_elements(public.admin_list_shops('011-100 0003')) e), '["S3 店"]'::jsonb,
  '按电话搜索（不管格式）');

select is(((public.admin_set_cart_item(tests.uid('S1'), tests.uid('P1'), 2)) ->> 'total_sen')::int, 17000,
  '加进购物车后回传报价（2 箱 RM85，满 RM150 免运费）');
select is((select qty from public.cart_items where shop_id = tests.uid('S1') and product_id = tests.uid('P1')), 2, '购物车有了');
select is((select added_by from public.cart_items where shop_id = tests.uid('S1') and product_id = tests.uid('P1')),
  tests.uid('admin'), '记下是客服加的');
select is((tests.last_audit('admin_set_cart_item')).acting_for_shop_id, tests.uid('S1'), '操作记录：代 S1');
select is(tests.error_of(format('select public.admin_set_cart_item(%L, %L, -1)', tests.uid('S1'), tests.uid('P1'))),
  'INVALID_QTY', '数量不能是负的');
select is(tests.error_of(format('select public.admin_set_cart_item(%L, %L, 1)', tests.uid('S1'), gen_random_uuid())),
  'PRODUCT_NOT_FOUND', '没有这样商品');
select is(tests.error_of(format('select public.admin_set_cart_item(%L, %L, 1)', gen_random_uuid(), tests.uid('P1'))),
  'SHOP_NOT_FOUND', '没有这家店');
select ok(tests.error_of(format('select public.admin_place_order(%L, 99)', tests.uid('S1'))) like 'PRICE_CHANGED:%',
  '总额对不上 → PRICE_CHANGED（不会多收钱）');
select is(tests.error_of(format('select public.admin_place_order(%L, null)', tests.uid('S1'))), 'EXPECTED_TOTAL_REQUIRED',
  '一定要给看到的总额');

select public.admin_place_order(tests.uid('S1'), 17000, '客服电话下单') as placed \gset
select tests.order_of('S1', 'W1') as o1 \gset
select is((select source::text from public.orders where id = :'o1'), 'admin', '订单来源是客服');
select is((select created_by from public.orders where id = :'o1'), tests.uid('admin'), '下单的人是客服');
select is((select channel::text from public.order_status_events where order_id = :'o1' and to_status = 'pending'), 'admin',
  '状态记录的渠道是客服');
select is((select note from public.orders where id = :'o1'), '客服电话下单', '备注');
select is((:'placed'::jsonb -> 'orders' -> 0 ->> 'id')::uuid, :'o1'::uuid, '回传订单');
select is((select count(*)::int from public.cart_items where shop_id = tests.uid('S1')), 0, '购物车清空');
select is((tests.last_audit('admin_place_order')).acting_for_shop_id, tests.uid('S1'), '操作记录：代 S1 下单');
select is(((tests.last_audit('admin_place_order')).after ->> 'total_sen')::int, 17000, '操作记录有总额');
select is((select count(*)::int from public.notifications where wholesaler_id = tests.uid('W1') and event_type = 'order_new'
           and payload ->> 'order_id' = :'o1'), 1, '批发商照样收到新订单通知');

-- 未付费的店：客服代下单也一样只能向免费开放的批发商下单
\o /dev/null
select public.admin_set_cart_item(tests.uid('S3'), tests.uid('P4'), 1);
\o
select ok(tests.error_of(format('select public.admin_place_order(%L, 8700)', tests.uid('S3'))) like 'CART_HAS_PROBLEMS:%WHOLESALER_LOCKED%',
  '未付费的店：代下单也要照规则（WHOLESALER_LOCKED）');
select is(public.admin_clear_cart(tests.uid('S3')), 1, '清空购物车');
select is(((tests.last_audit('admin_clear_cart')).before -> 'items' -> 0 ->> 'qty')::int, 1, '操作记录：清掉了什么');

-- =============================================================================
-- 代批发商管商品
-- =============================================================================
select is(jsonb_array_length(public.admin_list_products(tests.uid('W1'))), 3, 'W1 全部商品（包括草稿）');
select is(public.admin_list_products(tests.uid('W1')) -> 0 ->> 'status', 'active', '上架的排前面');
select ok(not (public.admin_list_products(tests.uid('W1')) -> 0 ? 'created_by'), '不回传 created_by');
select is(tests.error_of(format('select public.admin_list_products(%L)', gen_random_uuid())), 'WHOLESALER_NOT_FOUND', '没有这家批发商');

select public.admin_save_product(tests.uid('W1'), tests.uid('P1'), '{"price_sen": 8800}') as saved \gset
select is((:'saved'::jsonb ->> 'price_sen')::int, 8800, '代批发商改价钱');
select is((select new_price_sen from public.product_price_history where product_id = tests.uid('P1') order by id desc limit 1), 8800,
  '改价记录');
select is((select changed_by from public.product_price_history where product_id = tests.uid('P1') order by id desc limit 1),
  tests.uid('admin'), '改价记录：客服改的');
select is((tests.last_audit('admin_update_product')).acting_for_wholesaler_id, tests.uid('W1'), '操作记录：代 W1');
select is(((tests.last_audit('admin_update_product')).before ->> 'price_sen')::int, 8500, '操作记录：改之前的价钱');
select is(((tests.last_audit('admin_update_product')).after ->> 'price_sen')::int, 8800, '操作记录：改之后的价钱');
select is((public.admin_save_product(tests.uid('W1'), tests.uid('P1'), '{"stock_status": "low_stock"}') ->> 'stock_status'), 'low_stock',
  '代改库存');
select is((public.admin_save_product(tests.uid('W1'), tests.uid('P1'), '{"status": "archived"}') ->> 'status'), 'archived', '代下架');
select is((public.admin_save_product(tests.uid('W1'), tests.uid('P1'), '{"status": "active"}') ->> 'status'), 'active', '代上架');
select is((select price_sen from public.products where id = tests.uid('P1')), 8800, '只改给的栏，其他不动');

select public.admin_save_product(tests.uid('W2'), null,
  '{"name": " 22oz 杯 ", "unit": "carton", "pack_qty": 500, "price_sen": 6000, "catalog_item_id": "bbbbbbbb-0000-4000-8000-000000000041"}') as created \gset
select is(:'created'::jsonb ->> 'name', '22oz 杯', '代批发商新增商品（名字去掉空白）');
select is((select wholesaler_id from public.products where id = (:'created'::jsonb ->> 'id')::uuid), tests.uid('W2'), '是 W2 的');
select is((select status::text from public.products where id = (:'created'::jsonb ->> 'id')::uuid), 'active', '新增默认上架');
select is((select category_id from public.products where id = (:'created'::jsonb ->> 'id')::uuid),
  'bbbbbbbb-0000-4000-8000-000000000031'::uuid, '分类跟着标准商品');
select is((tests.last_audit('admin_create_product')).acting_for_wholesaler_id, tests.uid('W2'), '操作记录：代 W2 新增');

select is(tests.error_of(format('select public.admin_save_product(%L, %L, %L)', tests.uid('W2'), tests.uid('P1'), '{"price_sen": 1}')),
  'PRODUCT_NOT_FOUND', '别家批发商的商品不能改');
select is(tests.error_of(format('select public.admin_save_product(%L, %L, %L)', tests.uid('W1'), tests.uid('P1'), '{"wholesaler_id": "x"}')),
  'INVALID_FIELD:wholesaler_id', '不能改商品是哪家的');
select is(tests.error_of(format('select public.admin_save_product(%L, %L, %L)', tests.uid('W1'), tests.uid('P1'), '{"price_sen": 0}')),
  'INVALID_PRODUCT:price_sen', '价钱要大于 0');
select ok(tests.error_of(format('select public.admin_save_product(%L, %L, %L)', tests.uid('W1'), tests.uid('P1'), '{"unit": "truck"}')) like 'INVALID_PRODUCT:%',
  '单位不对');
select is(tests.error_of(format('select public.admin_save_product(%L, null, %L)', tests.uid('W1'), '{"unit": "carton", "price_sen": 100}')),
  'INVALID_PRODUCT:name', '新增一定要有名字');
select is(tests.error_of(format('select public.admin_save_product(%L, null, %L)', tests.uid('W1'), '{"name": "x", "price_sen": 100}')),
  'INVALID_PRODUCT:unit', '新增一定要有单位');

-- =============================================================================
-- 订单：筛选、跟进名单、代改状态
-- =============================================================================
-- 再下两张：S2 向 W1（app）、S1 向 W3（app）。o_old 下单 2 小时还没确认
select tests.logout();
select tests.add_to_cart('S2', 'P2', 2);
\o /dev/null
select public.place_order(tests.uid('S2'));
\o
select tests.order_of('S2', 'W1') as o2 \gset
select tests.add_to_cart('S1', 'P4', 1);
\o /dev/null
select public.place_order(tests.uid('S1'));
\o
select tests.order_of('S1', 'W3') as o3 \gset
update public.orders set created_at = now() - interval '2 hours' where id = :'o2';
update public.orders set created_at = now() - interval '3 days' where id = :'o3';
select tests.login_as(tests.uid('admin'));

select is((public.admin_list_orders() ->> 'total')::int, (select count(*)::int from public.orders), '全部订单（包括种子数据的）');
select is((select array_agg(e ->> 'order_no' order by ord) from jsonb_array_elements(public.admin_list_orders() -> 'orders') with ordinality t(e, ord)),
  (select array_agg(order_no order by created_at desc) from public.orders), '新到旧');
select is((public.admin_list_orders(p_wholesaler_id => tests.uid('W1')) ->> 'total')::int, 2, '按批发商');
select is((public.admin_list_orders(p_shop_id => tests.uid('S1')) ->> 'total')::int, 2, '按店');
select is((public.admin_list_orders(p_sources => array['admin']::public.order_source[]) -> 'orders' -> 0 ->> 'id')::uuid,
  :'o1'::uuid, '按来源（客服下的单）');
select is((public.admin_list_orders(p_sources => '{}') ->> 'total')::int, (select count(*)::int from public.orders), '空的来源 = 不筛选');
select is((public.admin_list_orders(p_shop_id => tests.uid('S1'), p_from => public.today_myt() - 1) -> 'orders' -> 0 ->> 'id')::uuid, :'o1'::uuid, '按日期（从）');
select is((public.admin_list_orders(p_shop_id => tests.uid('S1'), p_to => public.today_myt() - 2) -> 'orders' -> 0 ->> 'id')::uuid, :'o3'::uuid, '按日期（到）');
select is((public.admin_list_orders(p_wholesaler_id => tests.uid('W1'), p_statuses => array['confirmed']::public.order_status[]) ->> 'total')::int, 0, '按状态');
select is((public.admin_list_orders(p_limit => 1, p_offset => 1) ->> 'total')::int, (select count(*)::int from public.orders), '分页时 total 还是全部');
select is(jsonb_array_length(public.admin_list_orders(p_limit => 1, p_offset => 1) -> 'orders'), 1, '分页');

select is((select array_agg((e ->> 'id')::uuid order by ord) from jsonb_array_elements(public.admin_list_orders(p_unconfirmed_only => true) -> 'orders') with ordinality t(e, ord)),
  array[:'o3', :'o2']::uuid[], '跟进名单：超过 30 分钟没确认，旧的先');
select ok((public.admin_list_orders(p_unconfirmed_only => true) -> 'orders' -> 1 ->> 'pending_minutes')::int between 119 and 121,
  '等了几分钟');
select is((public.admin_dashboard() ->> 'unconfirmed_orders')::int, (public.admin_list_orders(p_unconfirmed_only => true) ->> 'total')::int, '首页：要跟进的单');
select is((public.admin_dashboard() ->> 'pending_wholesalers')::int, (select count(*)::int from public.wholesalers where status = 'pending'), '首页：待审核的批发商');
select is((public.admin_dashboard() ->> 'today_order_count')::int, (select count(*)::int from public.orders where (created_at at time zone 'Asia/Kuala_Lumpur')::date = public.today_myt()), '首页：今天的单');

select ok(public.admin_log_followup(:'o2', '打了电话，批发商说下午确认') > 0, '记下跟进');
select is(public.admin_list_orders(p_unconfirmed_only => true) -> 'orders' -> 1 -> 'last_followup' ->> 'note',
  '打了电话，批发商说下午确认', '跟进名单看到最后一次跟进');
select is((tests.last_audit('admin_log_followup')).acting_for_wholesaler_id, tests.uid('W1'), '跟进记录：哪家批发商');
select is(tests.error_of(format('select public.admin_log_followup(%L, %L)', :'o2', '  ')), 'INVALID_NOTE', '跟进要写东西');

-- 代批发商确认（P2 缺货）
select public.admin_confirm_order(:'o1', array[]::uuid[]) as conf1 \gset
select is(:'conf1'::jsonb ->> 'status', 'confirmed', '代确认');
select is((select channel::text from public.order_status_events where order_id = :'o1' and to_status = 'confirmed'), 'admin',
  '状态记录的渠道是客服');
select public.admin_confirm_order(:'o2', array[(select id from public.order_items where order_id = :'o2')]) as conf2 \gset
select is(:'conf2'::jsonb ->> 'status', 'out_of_stock', '全部缺货 → 缺货');
select is(tests.error_of(format('select public.admin_confirm_order(%L)', :'o1')), 'INVALID_TRANSITION:confirmed -> confirmed',
  '已经确认的不能再确认');
select is((tests.last_audit('admin_confirm_order')).after ->> 'status', 'out_of_stock', '操作记录：确认的结果');

select is(public.admin_set_order_status(:'o1', 'delivering') ->> 'status', 'delivering', '代改：送货中');
select is(public.admin_set_order_status(:'o1', 'delivered') ->> 'status', 'delivered', '代改：已送达');
select is((select base_amount_sen from public.commission_records where order_id = :'o1'), 17000, '送达后有佣金记录（不含运费；下单时的价钱）');
select is((tests.last_audit('admin_set_order_status')).before ->> 'status', 'delivering', '操作记录：改之前');
select is((tests.last_audit('admin_set_order_status')).after ->> 'status', 'delivered', '操作记录：改之后');
select is(tests.error_of(format('select public.admin_set_order_status(%L, %L)', :'o1', 'pending')),
  'INVALID_TRANSITION:delivered -> pending', '照原来的规则：送达了不能改回去');
select is(public.admin_set_order_status(:'o3', 'cancelled', '老板打电话取消') ->> 'cancel_reason', '老板打电话取消', '代取消');
select is(tests.error_of(format('select public.admin_set_order_status(%L, %L)', gen_random_uuid(), 'confirmed')),
  'ORDER_NOT_FOUND', '没有这张单');

-- =============================================================================
-- 批发商：审核 / 停权、佣金比例、创始会员、WhatsApp 同意
-- =============================================================================
select ok(public.admin_list_wholesalers('pending') @> '[{"name": "W4 待审核"}]'::jsonb
  and not public.admin_list_wholesalers('pending') @> '[{"status": "active"}]'::jsonb, '待审核名单');
select is(public.admin_list_wholesalers() -> 0 ->> 'status', 'pending', '待审核的排最前面');
select is(public.admin_set_wholesaler_status(tests.uid('W4'), 'active') ->> 'status', 'active', '审核通过');
select is((select approved_by from public.wholesalers where id = tests.uid('W4')), tests.uid('admin'), '记下谁审核的');
select ok((select approved_at is not null from public.wholesalers where id = tests.uid('W4')), '记下审核时间');
select is((tests.last_audit('admin_set_wholesaler_status')).acting_for_wholesaler_id, tests.uid('W4'), '操作记录：审核哪家');
select is(tests.error_of(format('select public.admin_set_wholesaler_status(%L, %L)', tests.uid('W4'), 'pending')),
  'INVALID_TRANSITION:active -> pending', '不能改回待审核');
select is(public.admin_set_wholesaler_status(tests.uid('W4'), 'suspended', '投诉太多') ->> 'status', 'suspended', '停权');
select is((tests.last_audit('admin_set_wholesaler_status')).after ->> 'note', '投诉太多', '停权原因');

select is(public.admin_list_wholesalers(p_search => 'W2') -> 0 ->> 'commission_rate_source', 'industry', 'W2 用行业默认比例');
select is((public.admin_set_commission_rate(tests.uid('W2'), 0.0125) ->> 'commission_rate')::numeric, 0.0125, '单独调整佣金比例');
select is(public.admin_list_wholesalers(p_search => 'W2') -> 0 ->> 'commission_rate_source', 'override', '变成单独调整');
select is(((tests.last_audit('admin_set_commission_rate')).after ->> 'commission_rate_override')::numeric, 0.0125, '操作记录：新比例');
select is(tests.error_of(format('select public.admin_set_commission_rate(%L, 0.3)', tests.uid('W2'))), 'INVALID_RATE', '最多 20%');
select is(tests.error_of(format('select public.admin_set_commission_rate(%L, 0.00001)', tests.uid('W2'))), 'INVALID_RATE', '最多 4 位小数');
select is(public.admin_set_commission_rate(tests.uid('W2'), null) ->> 'commission_rate_source', 'industry', '取消调整');

select (select max(founding_no) + 1 from public.wholesalers) as next_no \gset
select is((public.admin_set_wholesaler_founding(tests.uid('W2'), true) ->> 'founding_no')::int, :next_no, '设为创始会员，自动编号');
select is(public.admin_list_wholesalers(p_search => 'W2') -> 0 ->> 'commission_rate_source', 'founding', '用创始比例');
select is(public.admin_set_wholesaler_founding(tests.uid('W2'), false) ->> 'founding_no', null, '取消创始会员');

select ok(public.admin_set_whatsapp_opt_in(p_wholesaler_id => tests.uid('W2')) is not null, '登记批发商同意 WhatsApp');
select is(public.admin_set_whatsapp_opt_in(p_shop_id => tests.uid('S2'), p_opt_in => false), null, '取消店铺的同意');
select is(tests.error_of(format('select public.admin_set_whatsapp_opt_in(%L, %L)', tests.uid('S2'), tests.uid('W2'))), 'INVALID_VALUE',
  '店铺和批发商只能给一个');

-- =============================================================================
-- 订阅
-- =============================================================================
select (select id from public.subscriptions where shop_id = tests.uid('S1')) as sub1 \gset
select (select id from public.subscriptions where shop_id = tests.uid('S2')) as sub2 \gset

select is(jsonb_array_length(public.admin_list_subscriptions()), (select count(distinct shop_id)::int from public.subscriptions), '订阅列表（每家店最新一条）');
select is(public.admin_list_subscriptions(p_search => 'S1 店') -> 0 ->> 'locked_price_sen', '5000', '锁定的月费');
select ok(public.admin_list_subscriptions(p_founding_only => true) @> '[{"shop_name": "S1 店"}]'::jsonb
  and not public.admin_list_subscriptions(p_founding_only => true) @> '[{"is_founding_price": false}]'::jsonb, '创始价的');

select (select trial_ends_at from public.subscriptions where id = :'sub1') as trial1 \gset
select is((public.admin_extend_trial(:'sub1', 7) ->> 'trial_ends_at')::timestamptz, :'trial1'::timestamptz + interval '7 days',
  '延长试用 7 天');
select is(tests.error_of(format('select public.admin_extend_trial(%L, 0)', :'sub1')), 'INVALID_DAYS', '天数 1–90');

-- 付款：试用中 → active，从试用结束开始算一个月
select public.admin_mark_subscription_paid(:'sub1', 1, null, 'duitnow', 'DN-001') as paid1 \gset
select is(:'paid1'::jsonb ->> 'status', 'active', '手动标记已付 → 有效');
select is((:'paid1'::jsonb ->> 'current_period_end')::timestamptz, :'trial1'::timestamptz + interval '7 days' + interval '1 month',
  '从试用结束开始算');
select is((select amount_sen from public.payments where id = (:'paid1'::jsonb ->> 'payment_id')::uuid), 5000, '付款金额 = 锁定的月费');
select is((select gateway || '/' || method || '/' || gateway_ref from public.payments where id = (:'paid1'::jsonb ->> 'payment_id')::uuid),
  'manual/duitnow/DN-001', '付款记录');
select is(tests.error_of(format('select public.admin_mark_subscription_paid(%L, 1, null, %L, %L)', :'sub1', 'duitnow', 'DN-001')),
  'DUPLICATE_PAYMENT_REFERENCE:DN-001', '同一个参考号不能记两次');
select is(tests.error_of(format('select public.admin_extend_trial(%L, 5)', :'sub1')), 'INVALID_SUBSCRIPTION_STATE:active',
  '已经付费的不能延长试用');

-- 创始价
select is(public.admin_set_subscription_founding(:'sub1', false) ->> 'is_founding_price', 'false', '取消创始价标记');
select is(public.admin_set_subscription_founding(:'sub1', true, 4500) ->> 'locked_price_sen', '4500', '标记创始价并改锁定月费');

-- 取消 → 已停；再付款 → 新的订阅，按今天的价钱锁定（不能用回旧价钱）
select is(public.admin_cancel_subscription(:'sub2', '老板说不用了') ->> 'status', 'lapsed', '取消订阅');
select is(tests.error_of(format('select public.admin_cancel_subscription(%L)', :'sub2')), 'INVALID_SUBSCRIPTION_STATE:lapsed', '已经停了');
insert into public.pricing_plans (plan_code, amount_sen, is_founding, effective_from)
values ('buyer_monthly', 6900, false, now() - interval '1 minute');
select public.admin_mark_subscription_paid(:'sub2', 2) as paid2 \gset
select isnt((:'paid2'::jsonb ->> 'id')::uuid, :'sub2'::uuid, '停了之后付款：新建一条订阅');
select is((:'paid2'::jsonb ->> 'locked_price_sen')::int, 6900, '按今天的价钱锁定');
select is((select amount_sen from public.payments where id = (:'paid2'::jsonb ->> 'payment_id')::uuid), 13800, '两个月');
select is(tests.error_of(format('select public.admin_mark_subscription_paid(%L)', :'sub2')), 'SUBSCRIPTION_ALREADY_OPEN',
  '旧的那条不能再付（已经有新的）');
select is(tests.error_of(format('select public.admin_extend_trial(%L, 3)', :'sub2')), 'INVALID_SUBSCRIPTION_STATE:lapsed',
  '付过费又停了的不能重新试用');

-- 试用过期的店：可以重新打开试用
select tests.logout();
\o /dev/null
select public._start_trial(tests.uid('S3'), '60111000003');
\o
update public.subscriptions set status = 'lapsed', lapsed_at = now(), trial_ends_at = now() - interval '1 day'
where shop_id = tests.uid('S3');
select tests.login_as(tests.uid('admin'));
select (select id from public.subscriptions where shop_id = tests.uid('S3')) as sub3 \gset
select is(public.admin_extend_trial(:'sub3', 5) ->> 'status', 'trialing', '试用过期：重新打开试用');
select is(public.admin_list_subscriptions(p_search => 'S3 店') -> 0 ->> 'has_full_access', 'true', '又看得到全部价钱');
select is((tests.last_audit('admin_extend_trial')).acting_for_shop_id, tests.uid('S3'), '操作记录：代哪家店');

-- =============================================================================
-- 佣金报表和账单
-- =============================================================================
-- 再送达一张 W3 的（W3 单独调整 2.5%）
select tests.logout();
select tests.add_to_cart('S2', 'P4', 2);
\o /dev/null
select public.place_order(tests.uid('S2'));
\o
select tests.order_of('S2', 'W3') as o4 \gset
select tests.login_as(tests.uid('admin'));
\o /dev/null
select public.admin_confirm_order(:'o4');
\o
\o /dev/null
select public.admin_set_order_status(:'o4', 'delivered');
\o

select public.admin_commission_report() as rep \gset
select is((:'rep'::jsonb ->> 'period_month')::date, date_trunc('month', public.today_myt())::date, '默认这个月');
select is((select (e ->> 'gmv_sen')::int from jsonb_array_elements(:'rep'::jsonb -> 'wholesalers') e where e ->> 'name' = 'W3 特别比例'), 16400, 'W3 货价（不含运费）');
select is((select (e ->> 'commission_sen')::int from jsonb_array_elements(:'rep'::jsonb -> 'wholesalers') e where e ->> 'name' = 'W3 特别比例'), 410, 'W3 佣金 2.5%');
select is((:'rep'::jsonb ->> 'commission_sen')::int, (select sum((e ->> 'commission_sen')::int)::int from jsonb_array_elements(:'rep'::jsonb -> 'wholesalers') e), '合计 = 每家加起来');
select ok(:'rep'::jsonb -> 'wholesalers' @> '[{"name": "W1 创始批发商", "gmv_sen": 17000, "commission_sen": 255, "order_count": 1}]'::jsonb, 'W1：货价 RM170、佣金 1.5%');
select ok(not (:'rep'::jsonb -> 'wholesalers' @> '[{"name": "W2 普通批发商"}]'::jsonb), '没有送达订单的批发商不列');
select is((select e from jsonb_array_elements(:'rep'::jsonb -> 'wholesalers') e where e ->> 'name' = 'W1 创始批发商') -> 'orders' -> 0 ->> 'order_no',
  (select order_no from public.orders where id = :'o1'), '每张单的明细');
select is((select e from jsonb_array_elements(:'rep'::jsonb -> 'wholesalers') e where e ->> 'name' = 'W1 创始批发商') -> 'rates', '[{"rate": 0.0150, "rate_source": "founding"}]'::jsonb, '用了哪个比例');
select is((select e from jsonb_array_elements(:'rep'::jsonb -> 'wholesalers') e where e ->> 'name' = 'W1 创始批发商') -> 'invoice', 'null'::jsonb, '还没有账单');
select is(jsonb_array_length(public.admin_commission_report('2020-01-15') -> 'wholesalers'), 0, '别的月份');

select ok(public.admin_generate_invoices(date_trunc('month', public.today_myt())::date) >= 2, '生成这个月的草稿账单');
select ((select e from jsonb_array_elements(public.admin_commission_report() -> 'wholesalers') e where e ->> 'name' = 'W1 创始批发商') -> 'invoice' ->> 'id') as inv1 \gset
select is((select e from jsonb_array_elements(public.admin_commission_report() -> 'wholesalers') e where e ->> 'name' = 'W1 创始批发商') -> 'invoice' ->> 'status', 'draft', '报表看到账单');
select is(tests.error_of(format('select public.admin_mark_invoice_paid(%L)', :'inv1')), 'INVALID_INVOICE_STATE:draft', '草稿不能标已付');
select is(public.admin_issue_invoice(:'inv1') ->> 'status', 'issued', '发出账单');
select is((select due_date from public.commission_invoices where id = :'inv1'), public.today_myt() + 14, '到期日');
select public.admin_mark_invoice_paid(:'inv1', 'fpx', 'FPX-9') as invpaid \gset
select is(:'invpaid'::jsonb ->> 'status', 'paid', '标记已付');
select is((select amount_sen || '/' || purpose from public.payments where id = (:'invpaid'::jsonb ->> 'payment_id')::uuid),
  '255/commission_invoice', '记一笔佣金付款');
select is((tests.last_audit('admin_mark_invoice_paid')).acting_for_wholesaler_id, tests.uid('W1'), '操作记录：哪家批发商付的');

-- =============================================================================
-- 操作记录
-- =============================================================================
select ok((select bool_and(e ->> 'action' like 'admin\_%') from jsonb_array_elements(public.admin_list_audit_logs(p_admin_only => true)) e),
  '只看客服动作');
select ok(jsonb_array_length(public.admin_list_audit_logs()) > jsonb_array_length(public.admin_list_audit_logs(p_admin_only => true)),
  '全部记录还包括表的逐行记录');
select is(public.admin_list_audit_logs(p_action => 'admin_place_order') -> 0 ->> 'acting_for_shop_name', 'S1 店', '代哪家店（名字）');
select is(public.admin_list_audit_logs(p_action => 'admin_place_order') -> 0 ->> 'actor_phone', '60111000099', '谁做的');
select ok((select bool_and((e ->> 'acting_for_wholesaler_id')::uuid = tests.uid('W4'))
           from jsonb_array_elements(public.admin_list_audit_logs(p_wholesaler_id => tests.uid('W4'))) e), '按批发商');
select is(jsonb_array_length(public.admin_list_audit_logs(p_limit => 2)), 2, '每页几行');
select ok((public.admin_list_audit_logs(p_limit => 1, p_before_id => (public.admin_list_audit_logs(p_limit => 1) -> 0 ->> 'id')::bigint) -> 0 ->> 'id')::bigint
          < (public.admin_list_audit_logs(p_limit => 1) -> 0 ->> 'id')::bigint, '下一页');

select * from finish();
rollback;
