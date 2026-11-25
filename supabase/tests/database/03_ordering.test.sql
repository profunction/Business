-- 下单流程：报价、拆单、运费、起订量、缺货、改状态、佣金、评价、重复下单、客服代下单
begin;
\ir _helpers.psql
select plan(53);
select tests.setup_world();

-- S1 的购物车：
--   W1：P1 杯 1 箱 RM85 + P2 盖 1 箱 RM45 = RM130（未满 RM150，运费 RM8）
--   W2：P3 小包杯 5 包 x RM4.80 = RM24（运费 RM10）
--   W3：P4 杯 1 箱 RM82（运费 RM5）
--   货价 RM236 + 运费 RM23 = RM259
select tests.add_to_cart('S1', 'P1', 1);
select tests.add_to_cart('S1', 'P2', 1);
select tests.add_to_cart('S1', 'P3', 5);
select tests.add_to_cart('S1', 'P4', 1);

select tests.login_as(tests.uid('buyer1'));

-- ---------- 报价 ----------
select public.quote_cart(tests.uid('S1')) as q1 \gset
select is((:'q1'::jsonb ->> 'can_place')::boolean, true, '购物车没有问题，可以下单');
select is((:'q1'::jsonb ->> 'goods_total_sen')::int, 23600, '货价 RM236');
select is((:'q1'::jsonb ->> 'shipping_total_sen')::int, 2300, '运费 RM8 + RM10 + RM5 = RM23');
select is((:'q1'::jsonb ->> 'total_sen')::int, 25900, '总额 RM259');
select is(jsonb_array_length(:'q1'::jsonb -> 'groups'), 3, '按批发商分成 3 组');

-- ---------- 下单 ----------
select throws_ok(
  format('select public.place_order(%L, 25000)', tests.uid('S1')),
  'P0001', 'PRICE_CHANGED', '老板看到的总额跟服务器算的不一样，就不下单'
);
select public.place_order(tests.uid('S1'), 25900) as checkout1 \gset
select is((select count(*)::int from public.orders where checkout_id = :'checkout1'), 3, '一次结账拆成 3 张订单');
select is((select count(*)::int from public.cart_items), 0, '下单后购物车清空');

select tests.order_of('S1', 'W1') as o_w1 \gset
select tests.order_of('S1', 'W2') as o_w2 \gset
select tests.order_of('S1', 'W3') as o_w3 \gset

select is(
  (select status::text || '/' || goods_subtotal_sen || '/' || shipping_fee_sen || '/' || total_sen from public.orders where id = :'o_w1'),
  'pending/13000/800/13800', 'W1 的订单：待确认，货价 RM130 + 运费 RM8'
);
select matches((select order_no from public.orders where id = :'o_w1'), '^TST\d{6}-\d{5}$', '订单号：地区 + 日期 + 流水号');
select is(
  (select array_agg(name_snapshot || ' x' || qty || ' @' || unit_price_sen order by name_snapshot) from public.order_items where order_id = :'o_w1'),
  array['W1 16oz 杯 x1 @8500', 'W1 平盖 x1 @4500'], '订单明细保存了下单时的名称和价钱'
);
select is((select expected_delivery_date from public.orders where id = :'o_w2'), public.today_myt(), 'W2 当天送（lead time 0 天）');
select is((select count(*)::int from public.order_status_events where order_id = :'o_w1'), 1, '记下了「待确认」');

-- ---------- 谁看得到这些订单 ----------
select tests.login_as(tests.uid('buyer2'));
select is((select count(*)::int from public.orders), 0, '别家店看不到这些订单');
select is((select count(*)::int from public.order_items), 0, '别家店也看不到订单明细');

select tests.login_as(tests.uid('seller1'));
select is((select count(*)::int from public.orders), 1, 'W1 只看到发给自己的那 1 张');
select is((select count(*)::int from public.order_items), 2, 'W1 看到自己那张的 2 行明细');
select is((select name from public.shops), 'S1 店', 'W1 现在看得到下单的店（要送货）');

select tests.login_as(tests.uid('admin'));
select is((select count(*)::int from public.orders where shop_id = tests.uid('S1')), 3, '客服看到全部');

-- ---------- 有问题的购物车 ----------
select tests.logout();
select tests.add_to_cart('S2', 'P2', 1);   -- W1 只有 RM45，未到最低消费 RM50
select tests.add_to_cart('S2', 'P3', 2);   -- W2 起订 5 包
select tests.add_to_cart('S2', 'P5', 1);   -- W3 缺货
select tests.add_to_cart('S3', 'P3', 5);   -- S3 未付费，W2 不在免费名单
select tests.login_as(tests.uid('buyer2'));
select public.quote_cart(tests.uid('S2')) as q2 \gset
select is(
  (select g ->> 'problem' || '/' || (g ->> 'short_by_sen') from jsonb_array_elements(:'q2'::jsonb -> 'groups') g
   where g ->> 'wholesaler_id' = tests.uid('W1')::text),
  'BELOW_MIN_ORDER/500', '未到最低消费，显示还差 RM5'
);
select is(
  (select l ->> 'problem' from jsonb_array_elements(:'q2'::jsonb -> 'groups') g, jsonb_array_elements(g -> 'lines') l
   where l ->> 'product_id' = tests.uid('P3')::text),
  'BELOW_MIN_QTY', '未到起订量'
);
select is(
  (select l ->> 'problem' from jsonb_array_elements(:'q2'::jsonb -> 'groups') g, jsonb_array_elements(g -> 'lines') l
   where l ->> 'product_id' = tests.uid('P5')::text),
  'OUT_OF_STOCK', '缺货的不能下单'
);
select throws_ok(format('select public.place_order(%L)', tests.uid('S2')), 'P0001', 'CART_HAS_PROBLEMS', '有问题就不能下单');

select tests.login_as(tests.uid('buyer3'));
select is(
  (select (l ->> 'problem') || '/' || coalesce(l ->> 'unit_price_sen', 'null')
   from jsonb_array_elements(public.quote_cart(tests.uid('S3')) -> 'groups') g, jsonb_array_elements(g -> 'lines') l),
  'WHOLESALER_LOCKED/null', '未付费用户放进购物车的锁定批发商：不能下单，价钱也不显示'
);

-- ---------- 改订单状态 ----------
select tests.login_as(tests.uid('buyer1'));
select throws_ok(format('select public.set_order_status(%L, %L)', :'o_w1', 'confirmed'),
  'P0001', 'INVALID_TRANSITION', '老板不能自己确认订单');
select throws_ok(format('select public.place_order(%L, p_source => %L)', tests.uid('S1'), 'admin'),
  'P0001', 'INVALID_SOURCE', '老板不能假装是客服下单');

select tests.login_as(tests.uid('seller2'));
select throws_ok(format('select public.confirm_order(%L)', :'o_w1'), '42501', 'NOT_ALLOWED', '别家批发商不能确认这张单');

select tests.login_as(tests.uid('seller1'));
select is(
  public.confirm_order(:'o_w1', array[(select id from public.order_items where order_id = :'o_w1' and product_id = tests.uid('P2'))]),
  'confirmed'::public.order_status, 'W1 确认，同时标出平盖缺货'
);
select is(
  (select goods_subtotal_sen || '/' || shipping_fee_sen from public.orders where id = :'o_w1'),
  '8500/800', '缺货的平盖不算钱，运费照下单时的'
);
select throws_ok(format('select public.set_order_status(%L, %L)', :'o_w1', 'cancelled'),
  'P0001', 'INVALID_TRANSITION', '批发商不能取消订单（要找客服）');
select lives_ok(format('select public.set_order_status(%L, %L)', :'o_w1', 'delivered'), 'W1 标为已送达');
select lives_ok(format('select public.set_order_status(%L, %L)', :'o_w1', 'delivered'), '同一个按钮按两次不会出错');

select tests.login_as(tests.uid('seller2'));
select is(public.confirm_order(:'o_w2'), 'confirmed'::public.order_status, 'W2 确认');
select lives_ok(format('select public.set_order_status(%L, %L)', :'o_w2', 'delivered'), 'W2 送达');

select tests.login_as(tests.uid('seller3'));
select is(public.confirm_order(:'o_w3'), 'confirmed'::public.order_status, 'W3 确认');
select tests.login_as(tests.uid('buyer1'));
select lives_ok(format('select public.set_order_status(%L, %L)', :'o_w3', 'delivered'), '老板也可以按「收到了」');

select is((select count(*)::int from public.order_status_events where order_id = :'o_w1'), 3, 'W1 的记录：待确认 → 已确认 → 已送达');
select is((select count(*)::int from public.notifications where shop_id = tests.uid('S1')), 6, '老板收到 6 个状态通知');

-- ---------- 佣金（送达时自动生成，比例当时就存下来）----------
select tests.logout();
select is(
  (select array_agg(w.name || ':' || cr.rate_source || ':' || cr.rate || ':' || cr.commission_sen order by w.name)
   from public.commission_records cr join public.wholesalers w on w.id = cr.wholesaler_id
   where cr.order_id in (:'o_w1', :'o_w2', :'o_w3')),
  array[
    'W1 创始批发商:founding:0.0150:128',   -- RM85 x 1.5% = RM1.275 → 128 仙
    'W2 普通批发商:industry:0.0300:72',    -- RM24 x 3%
    'W3 特别比例:override:0.0250:205'      -- RM82 x 2.5%
  ],
  '佣金比例：创始会员 / 行业默认 / 单独调整，都只算货价不算运费'
);

-- ---------- 评价 ----------
select tests.login_as(tests.uid('buyer1'));
select lives_ok(format('select public.submit_review(%L, 4, array[%L])', :'o_w1', 'on_time'), '老板给 W1 打 4 星');
select is((select rating_avg || '/' || rating_count from public.wholesalers where id = tests.uid('W1')), '4.00/1', 'W1 评分自动更新');
select lives_ok(format('select public.submit_review(%L, 2)', :'o_w1'), '可以改评价');
select is((select rating_avg::text from public.wholesalers where id = tests.uid('W1')), '2.00', '改评价后评分跟着改，不会重复算');

select tests.login_as(tests.uid('buyer2'));
select throws_ok(format('select public.submit_review(%L, 1)', :'o_w1'), '42501', 'NOT_ALLOWED', '不能评别家店的订单');

-- ---------- 跟上次一样 ----------
select tests.logout();
update public.products set price_sen = 8000 where id = tests.uid('P4');   -- W3 降价 RM2
select tests.login_as(tests.uid('buyer1'));
select public.reorder_last(tests.uid('S1')) as r1 \gset
select is((:'r1'::jsonb ->> 'added_count')::int, 4, '上次的 4 样货放回购物车');
select is(
  (select (c ->> 'old_price_sen') || '→' || (c ->> 'new_price_sen') from jsonb_array_elements(:'r1'::jsonb -> 'price_changes') c),
  '8200→8000', '告诉老板哪样改了价'
);
select is((:'r1'::jsonb -> 'quote' ->> 'total_sen')::int, 25700, '新的总额 RM257');
select lives_ok(format('select public.place_order(%L, 25700, p_source => %L)', tests.uid('S1'), 'reorder'), '一键重复下单');

select tests.order_of('S1', 'W2') as o_w2_new \gset
select lives_ok(format('select public.set_order_status(%L, %L, %L)', :'o_w2_new', 'cancelled', '下错了'), '老板取消还没确认的订单');
select throws_ok(format('select public.submit_review(%L, 5)', tests.order_of('S1', 'W1')),
  'P0001', 'ORDER_NOT_DELIVERED', '还没送到不能评价');

-- ---------- 客服代下单 ----------
select tests.login_as(tests.uid('admin'));
insert into public.cart_items (shop_id, product_id, qty) values (tests.uid('S2'), tests.uid('P1'), 1)
  on conflict (shop_id, product_id) do update set qty = excluded.qty;
delete from public.cart_items where shop_id = tests.uid('S2') and product_id <> tests.uid('P1');
select lives_ok(format('select public.place_order(%L)', tests.uid('S2')), '客服帮 S2 下单');
select is(
  (select source::text from public.orders where shop_id = tests.uid('S2')),
  'admin', '订单记下是客服下的'
);
select ok(
  exists (select 1 from public.audit_logs
          where table_name = 'orders' and action = 'insert'
            and actor_id = tests.uid('admin') and acting_for_shop_id = tests.uid('S2')),
  '操作记录里查得到客服代 S2 下单'
);

select tests.logout();
select * from finish();
rollback;
