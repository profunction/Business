-- 买家 App 的读取函数：登录资料、首页、分类、商品列表、批发商列表、订单列表和详情
begin;
\ir _helpers.psql
select plan(26);
select tests.setup_world();

-- S1 下一张单：W1（P1 x1）、W2（P3 x5）
select tests.add_to_cart('S1', 'P1', 1);
select tests.add_to_cart('S1', 'P3', 5);
select public.place_order(tests.uid('S1'));
select tests.add_to_cart('S1', 'P2', 1);    -- 购物车里留一样

-- ---------- 登录后的资料 ----------
select tests.login_as(tests.uid('buyer1'));
select is(
  (select (c -> 'profile' ->> 'role') || '/' || jsonb_array_length(c -> 'shops') || '/' || jsonb_array_length(c -> 'wholesalers')
   from public.get_my_context() c),
  'buyer/1/0', '买家：1 间店，没有批发商'
);
select tests.login_as(tests.uid('seller1'));
select is(
  (select (c -> 'profile' ->> 'role') || '/' || jsonb_array_length(c -> 'shops') || '/' || (c -> 'wholesalers' -> 0 ->> 'name')
   from public.get_my_context() c),
  'seller/0/W1 创始批发商', '批发商：看到自己的批发商'
);

-- ---------- 首页 ----------
select tests.login_as(tests.uid('buyer1'));
select public.get_buyer_home(tests.uid('S1')) as home \gset
select is((:'home'::jsonb -> 'shop' ->> 'name'), 'S1 店', '首页：店名');
select is((:'home'::jsonb ->> 'cart_count')::int, 1, '首页：购物车有 1 样');
select is((:'home'::jsonb ->> 'active_order_count')::int, 2, '首页：2 张进行中的订单');
select is((:'home'::jsonb -> 'last_checkout' ->> 'total_sen')::int, 8500 + 800 + 2400 + 1000, '首页：上一次结账的总额（给「跟上次一样」用）');
select is((:'home'::jsonb -> 'last_checkout' ->> 'item_count')::int, 2, '上一次结账有 2 样货');
select is((:'home'::jsonb -> 'subscription' ->> 'has_full_access'), 'true', '首页：试用中');
select throws_ok(format('select public.get_buyer_home(%L)', tests.uid('S2')), '42501', 'NOT_ALLOWED', '不能看别家店的首页');

-- ---------- 分类和商品列表 ----------
select is(
  (select item_count from public.get_categories(tests.uid('S1')) where code = 'test_cups'),
  2, '分类里有 2 样标准商品（杯、盖）'
);
select is(
  (select offer_count || '/' || visible_offer_count || '/' || min_price_per_base_unit_sen
   from public.get_catalog_overview(tests.uid('S1')) where catalog_item_id = 'bbbbbbbb-0000-4000-8000-000000000041'),
  '3/3/8.20', '16oz 杯：3 家有卖，最便宜每个 8.2 仙'
);
select is(
  (select count(*)::int from public.get_catalog_overview(tests.uid('S1'), p_search => 'cup')),
  1, '可以用英文名搜索'
);
select is(
  (select count(*)::int from public.get_catalog_overview(tests.uid('S1'), p_search => '平盖')),
  1, '也可以用批发商自己写的商品名搜索'
);

select tests.login_as(tests.uid('buyer3'));
select is(
  (select offer_count || '/' || visible_offer_count || '/' || coalesce(min_price_per_base_unit_sen::text, 'null')
   from public.get_catalog_overview(tests.uid('S3')) where catalog_item_id = 'bbbbbbbb-0000-4000-8000-000000000041'),
  '3/0/null', '未付费：知道有 3 家卖，但最便宜的价钱不显示'
);
select tests.logout();
insert into public.unlocked_wholesalers (shop_id, wholesaler_id) values (tests.uid('S3'), tests.uid('W2'));
select tests.login_as(tests.uid('buyer3'));
select is(
  (select visible_offer_count || '/' || min_price_per_base_unit_sen
   from public.get_catalog_overview(tests.uid('S3')) where catalog_item_id = 'bbbbbbbb-0000-4000-8000-000000000041'),
  '1/9.60', '最便宜只从看得到的批发商算（W2 每个 9.6 仙，不会泄露 W3 的 8.2 仙）'
);

-- ---------- 批发商列表 ----------
select is(
  (select array_agg(name || ':' || price_visible || ':' || product_count order by name) from public.list_wholesalers(tests.uid('S3'))),
  array['W1 创始批发商:false:2', 'W2 普通批发商:true:1', 'W3 特别比例:false:2'],
  '批发商列表：不包括待审核的 W4；标出哪家看得到价钱'
);
select is(
  (select shipping_fee_sen || '/' || min_order_sen || '/' || lead_time_days from public.list_wholesalers(tests.uid('S3')) where wholesaler_id = tests.uid('W3')),
  '500/3000/2', '批发商列表显示运费、最低消费、几天送到'
);

-- ---------- 订单列表和详情 ----------
select tests.login_as(tests.uid('buyer1'));
select is(jsonb_array_length(public.list_orders(tests.uid('S1'))), 2, '我的订单：2 张');
select is(
  (select o ->> 'status' || '/' || (o ->> 'total_sen') from jsonb_array_elements(public.list_orders(tests.uid('S1'))) o
   where o ->> 'wholesaler_id' = tests.uid('W1')::text),
  'pending/9300', 'W1 那张：待确认，RM93'
);

select public.get_order(tests.order_of('S1', 'W1')) as d1 \gset
select is(jsonb_array_length(:'d1'::jsonb -> 'items'), 1, '订单详情有明细');
select is(
  (select string_agg(k, ',' order by k) from jsonb_each_text(:'d1'::jsonb -> 'actions') as t(k, v) where v = 'true'),
  'can_cancel', '买家在「待确认」时只能取消'
);

select tests.login_as(tests.uid('seller1'));
select is(
  (select string_agg(k, ',' order by k) from jsonb_each_text(public.get_order(tests.order_of('S1', 'W1')) -> 'actions') as t(k, v) where v = 'true'),
  'can_confirm', '批发商在「待确认」时可以确认'
);
select public.confirm_order(tests.order_of('S1', 'W1'));
select tests.login_as(tests.uid('buyer1'));
select is(
  (select string_agg(k, ',' order by k) from jsonb_each_text(public.get_order(tests.order_of('S1', 'W1')) -> 'actions') as t(k, v) where v = 'true'),
  'can_cancel,can_mark_received', '确认后买家可以取消或按「收到了」'
);
select public.set_order_status(tests.order_of('S1', 'W1'), 'delivered');
select is(
  (select string_agg(k, ',' order by k) from jsonb_each_text(public.get_order(tests.order_of('S1', 'W1')) -> 'actions') as t(k, v) where v = 'true'),
  'can_review', '送到后可以评价'
);
select is(jsonb_array_length(public.get_order(tests.order_of('S1', 'W1')) -> 'events'), 3, '订单详情有状态记录（进度条用）');

select tests.login_as(tests.uid('buyer2'));
select throws_ok(format('select public.get_order(%L)', :'d1'::jsonb ->> 'id'), '42501', 'NOT_ALLOWED',
  '不能看别家店的订单详情');

select tests.logout();
select * from finish();
rollback;
