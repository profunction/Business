-- 第四步：批发商首页、订单列表、送货总结、价目表导入、通知发送（选渠道、重试）、
-- WhatsApp 按钮 / 消息 / 状态、客服提醒、每日总结、dispatcher（pg_net + Vault）、Storage、定时任务、权限
begin;
\ir _helpers.psql
select plan(256);
select tests.setup_world();

-- ---------- 准备订单 ----------
-- 送货区：Z2 排在 Z1 前面；S3 搬到 Z2，并且免费开放 W1 给 S3（S3 没有试用）
update public.delivery_zones set sort_order = 20 where id = tests.uid('Z1');
update public.delivery_zones set sort_order = 10 where id = tests.uid('Z2');
update public.shops set zone_id = tests.uid('Z2') where id = tests.uid('S3');
insert into public.unlocked_wholesalers (shop_id, wholesaler_id) values (tests.uid('S3'), tests.uid('W1'));

-- S1：W1 P1 x2 + P2 x1（RM215，满 RM150 免运费）；W2 P3 x5
select tests.add_to_cart('S1', 'P1', 2);
select tests.add_to_cart('S1', 'P2', 1);
select tests.add_to_cart('S1', 'P3', 5);
select public.place_order(tests.uid('S1')) as checkout_s1 \gset
-- S2：W1 P1 x1（RM85 + 运费 RM8）
select tests.add_to_cart('S2', 'P1', 1);
select public.place_order(tests.uid('S2')) as checkout_s2 \gset
-- S3：W1 P2 x2（RM90 + 运费 RM8）
select tests.add_to_cart('S3', 'P2', 2);
select public.place_order(tests.uid('S3')) as checkout_s3 \gset

select tests.order_of('S1', 'W1') as o1 \gset
select tests.order_of('S2', 'W1') as o2 \gset
select tests.order_of('S3', 'W1') as o3 \gset
select tests.order_of('S1', 'W2') as o_w2 \gset

-- 都是今天送；下单时间：o2 最早，o1 其次，o3 最晚
update public.orders set expected_delivery_date = public.today_myt() where wholesaler_id = tests.uid('W1');
update public.orders set created_at = now() - interval '3 hours' where id = :'o2';
update public.orders set created_at = now() - interval '2 hours' where id = :'o1';
update public.orders set created_at = now() - interval '1 hour' where id = :'o3';
update public.products set stock_status = 'low_stock' where id = tests.uid('P2');

-- ---------- 订单列表 ----------
select tests.login_as(tests.uid('seller1'));
select is(
  (select array_agg((e ->> 'id')::uuid order by ord) from jsonb_array_elements(public.list_seller_orders(tests.uid('W1'))) with ordinality as t(e, ord)),
  array[:'o2', :'o1', :'o3']::uuid[],
  '全部待确认时：先来先做（下单时间旧到新）'
);

select public.confirm_order(:'o1', array[(select id from public.order_items where order_id = :'o1' and product_id = tests.uid('P2'))]);
select public.confirm_order(:'o3');

select public.list_seller_orders(tests.uid('W1')) as list1 \gset
select is(
  (select array_agg((e ->> 'id')::uuid order by ord) from jsonb_array_elements(:'list1'::jsonb) with ordinality as t(e, ord)),
  array[:'o2', :'o3', :'o1']::uuid[],
  '待确认排最前面；其他的按下单时间新到旧'
);
select is(
  (select e ->> 'status' || '/' || (e ->> 'shop_name') || '/' || (e -> 'zone_name' ->> 'zh') || '/' || (e ->> 'item_count')
          || '/' || (e ->> 'out_of_stock_count') || '/' || (e ->> 'goods_subtotal_sen') || '/' || (e ->> 'shipping_fee_sen')
          || '/' || (e ->> 'total_sen')
   from jsonb_array_elements(:'list1'::jsonb) e where (e ->> 'id')::uuid = :'o1'),
  'confirmed/S1 店/一区/2/1/17000/0/17000',
  '每张单：状态、店名、送货区（三语）、几样、几样缺货、金额'
);
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys(:'list1'::jsonb -> 0) as t(k)),
  'created_at,expected_delivery_date,goods_subtotal_sen,id,item_count,note,order_no,out_of_stock_count,shipping_fee_sen,shop_name,status,total_sen,zone_name',
  '列表每一行的字段'
);
select is(jsonb_array_length(public.list_seller_orders(tests.uid('W1'), array['pending']::public.order_status[])), 1, '只看待确认');
select is(
  jsonb_array_length(public.list_seller_orders(tests.uid('W1'), array['confirmed', 'delivering']::public.order_status[], public.today_myt())),
  2, '今天要送：已确认 / 送货中、今天送'
);
select is(
  jsonb_array_length(public.list_seller_orders(tests.uid('W1'), null, public.today_myt() + 1)), 0, '按送货日期筛选'
);
select is(
  (public.list_seller_orders(tests.uid('W1'), p_limit => 1) -> 0 ->> 'id')::uuid, :'o2'::uuid, 'p_limit 限制张数'
);
select is(
  (select array_agg((e ->> 'id')::uuid order by ord)
   from jsonb_array_elements(public.list_seller_orders(tests.uid('W1'), '{}'::public.order_status[])) with ordinality as t(e, ord)),
  array[:'o2', :'o3', :'o1']::uuid[], 'p_statuses 是空数组：等于不筛选（App 的「全部」）'
);
select is(
  jsonb_array_length(public.list_seller_orders(tests.uid('W1'), p_limit => 0))
    || '/' || jsonb_array_length(public.list_seller_orders(tests.uid('W1'), p_limit => -5)),
  '1/1', 'p_limit 最少 1'
);
-- p_limit 最多 200：子交易里多放 198 张已送达的单（一共 201 张），看完退回
savepoint many_orders;
select tests.logout();
insert into public.orders (order_no, checkout_id, shop_id, wholesaler_id, zone_id, status, goods_subtotal_sen, shipping_fee_sen,
                           expected_delivery_date, source)
select o.order_no || '-' || g, o.checkout_id, o.shop_id, o.wholesaler_id, o.zone_id, 'delivered', o.goods_subtotal_sen,
       o.shipping_fee_sen, o.expected_delivery_date, o.source
from public.orders o cross join generate_series(1, 198) g
where o.id = :'o1';
select tests.login_as(tests.uid('seller1'));
select jsonb_array_length(public.list_seller_orders(tests.uid('W1'), p_limit => 500)) as many_500,
       jsonb_array_length(public.list_seller_orders(tests.uid('W1'), p_limit => null)) as many_null,
       (select count(*) from public.orders where wholesaler_id = tests.uid('W1')) as many_total \gset
rollback to savepoint many_orders;
select is(:many_total || '/' || :many_500 || '/' || :many_null, '201/200/50', 'p_limit 最多 200；不给（null）就是 50');
select throws_ok(format('select public.list_seller_orders(%L)', tests.uid('W2')), '42501', 'NOT_ALLOWED', '不能看别家批发商的订单');

select tests.login_as(tests.uid('seller2'));
select is(
  (select array_agg((e ->> 'id')::uuid) from jsonb_array_elements(public.list_seller_orders(tests.uid('W2'))) e),
  array[:'o_w2']::uuid[], 'W2 只看到发给自己的那张'
);

-- ---------- 首页 ----------
-- 缺货 / 快卖完只算上架中的商品：草稿 P6 也缺货，但不算
select tests.logout();
update public.products set stock_status = 'out_of_stock' where id = tests.uid('P6');
select tests.login_as(tests.uid('seller1'));
select public.get_seller_home(tests.uid('W1')) as home \gset
select is(
  (:'home'::jsonb -> 'wholesaler' ->> 'name') || '/' || (:'home'::jsonb -> 'wholesaler' ->> 'status') || '/'
    || (:'home'::jsonb -> 'wholesaler' ->> 'is_founding') || '/' || (:'home'::jsonb -> 'wholesaler' ->> 'notify_channel'),
  'W1 创始批发商/active/true/auto', '首页：批发商资料'
);
select is((:'home'::jsonb ->> 'pending_count')::int, 1, '首页：1 张待确认');
select is(
  (:'home'::jsonb ->> 'oldest_pending_at')::timestamptz, (select created_at from public.orders where id = :'o2'),
  '首页：最旧那张待确认的下单时间'
);
select is((:'home'::jsonb ->> 'today')::date, public.today_myt(), '首页：今天的日期（马来西亚时间）');
select is((:'home'::jsonb ->> 'today_order_count')::int, 2, '首页：今天要送 2 张');
select is((:'home'::jsonb ->> 'today_total_sen')::int, 17000 + 9800, '首页：今天要送的总额（缺货的不算）');
select is(
  :'home'::jsonb -> 'product_counts', '{"active": 2, "draft": 1, "out_of_stock": 0, "low_stock": 1}'::jsonb,
  '首页：商品数量（上架、草稿、缺货、快卖完）；草稿缺货不算缺货'
);
-- 下架（archived）的快卖完也不算
select tests.logout();
update public.products set status = 'archived', stock_status = 'low_stock' where id = tests.uid('P6');
select tests.login_as(tests.uid('seller1'));
select is(
  public.get_seller_home(tests.uid('W1')) -> 'product_counts', '{"active": 2, "draft": 0, "out_of_stock": 0, "low_stock": 1}'::jsonb,
  '首页：下架的商品快卖完不算快卖完'
);
select tests.logout();
update public.products set status = 'draft', stock_status = 'in_stock' where id = tests.uid('P6');
select tests.login_as(tests.uid('seller1'));
select is(:'home'::jsonb -> 'latest_import', 'null'::jsonb, '还没上传过价目表');
select throws_ok(format('select public.get_seller_home(%L)', tests.uid('W2')), '42501', 'NOT_ALLOWED', '不能看别家批发商的首页');
select tests.login_as(tests.uid('buyer1'));
select throws_ok(format('select public.get_seller_home(%L)', tests.uid('W1')), '42501', 'NOT_ALLOWED', '买家不能看批发商首页');
select tests.login_as(tests.uid('admin'));
select is((public.get_seller_home(tests.uid('W1')) ->> 'pending_count')::int, 1, '客服可以看任何一家批发商的首页');
select is(jsonb_array_length(public.list_seller_orders(tests.uid('W1'))), 3, '客服可以看任何一家批发商的订单');
-- 客服打错 / 已删掉的批发商：三个都报 WHOLESALER_NOT_FOUND（订单列表不是回空的，像是「没有订单」）
select throws_ok(format('select public.get_seller_home(%L)', '00000000-0000-4000-8000-000000000999'),
  'P0001', 'WHOLESALER_NOT_FOUND', '首页：批发商不存在');
select throws_ok(format('select public.list_seller_orders(%L)', '00000000-0000-4000-8000-000000000999'),
  'P0001', 'WHOLESALER_NOT_FOUND', '订单列表：批发商不存在');
select throws_ok(format('select public.get_delivery_summary(%L)', '00000000-0000-4000-8000-000000000999'),
  'P0001', 'WHOLESALER_NOT_FOUND', '送货总结：批发商不存在');

-- ---------- 订单详情（第三步的 get_order，批发商也用）----------
select tests.login_as(tests.uid('seller1'));
select is(
  (select string_agg(k, ',' order by k) from jsonb_each_text(public.get_order(:'o2') -> 'actions') as t(k, v) where v = 'true'),
  'can_confirm', '待确认的单：批发商可以确认'
);
select is(
  (select d -> 'shop' ->> 'name' || '/' || (d -> 'shop' ->> 'phone') || '/' || (d -> 'shop' -> 'zone_name' ->> 'en')
   from public.get_order(:'o2') d),
  'S2 店/60111000002/Zone 1', '订单详情有店名、电话、送货区'
);
select is(
  (select string_agg(k, ',' order by k) from jsonb_each_text(public.get_order(:'o1') -> 'actions') as t(k, v) where v = 'true'),
  'can_mark_delivered,can_mark_delivering', '已确认的单：可以出发送货或已送达'
);

-- ---------- 送货总结 ----------
select public.get_delivery_summary(tests.uid('W1')) as sum1 \gset
select is((:'sum1'::jsonb ->> 'date')::date, public.today_myt(), '不给日期就是今天');
select is(
  (:'sum1'::jsonb ->> 'order_count') || '/' || (:'sum1'::jsonb ->> 'pending_count') || '/' || (:'sum1'::jsonb ->> 'goods_total_sen')
    || '/' || (:'sum1'::jsonb ->> 'shipping_total_sen') || '/' || (:'sum1'::jsonb ->> 'total_sen'),
  '2/1/26000/800/26800', '2 张要送、还有 1 张没确认、货价 + 运费 = 总额'
);
select is(
  :'sum1'::jsonb -> 'picking',
  '[{"name": "W1 16oz 杯", "unit": "carton", "pack_qty": 1000, "qty": 2},
    {"name": "W1 平盖", "unit": "carton", "pack_qty": 1000, "qty": 2}]'::jsonb,
  '拣货单：同一样货加总，缺货的那样（S1 的平盖）不算'
);
select is(
  (select array_agg(e -> 'shop' ->> 'name' order by ord) from jsonb_array_elements(:'sum1'::jsonb -> 'orders') with ordinality as t(e, ord)),
  array['S3 店', 'S1 店'], '每张单按送货区（Z2 排前面）再按店名排'
);
select is(
  (select e -> 'shop' ->> 'phone' || '/' || (e -> 'shop' -> 'zone_name' ->> 'zh') || '/' || (e -> 'payment_terms')::text
   from jsonb_array_elements(:'sum1'::jsonb -> 'orders') e where (e ->> 'id')::uuid = :'o3'),
  '60111000003/二区/["cod"]', '送货单上有店的电话、送货区、付款方式'
);
select is(
  (select string_agg((i ->> 'name') || ':' || (i ->> 'is_out_of_stock'), ',' order by io)
   from jsonb_array_elements(:'sum1'::jsonb -> 'orders') with ordinality as t(e, eo),
        jsonb_array_elements(e -> 'items') with ordinality as u(i, io)
   where (e ->> 'id')::uuid = :'o1'),
  'W1 16oz 杯:false,W1 平盖:true', '每张单的明细：缺货的也列出来（标明缺货），排在后面'
);
select is(
  (public.get_delivery_summary(tests.uid('W1'), public.today_myt() + 1) ->> 'order_count')::int, 0, '别的日期没有单'
);

-- 加总和店名排序再看清楚（在子交易里做，看完退回）：o2 也确认，S1 再下一张 o4（P1 x1）。
-- 这样 P1 在三张单里都有；一区有三张单：S1 店 o1、S1 店 o4、S2 店 o2
-- （店名顺序跟订单号、下单时间的顺序都不一样）
savepoint more_orders;
select tests.logout();
select tests.add_to_cart('S1', 'P1', 1);
select public.place_order(tests.uid('S1'));
select tests.order_of('S1', 'W1') as o4 \gset
update public.orders set expected_delivery_date = public.today_myt() where id = :'o4';
select public.confirm_order(:'o2');
select public.confirm_order(:'o4');
select tests.login_as(tests.uid('seller1'));
select public.get_delivery_summary(tests.uid('W1')) as sum2 \gset
rollback to savepoint more_orders;
select is(
  :'sum2'::jsonb -> 'picking',
  '[{"name": "W1 16oz 杯", "unit": "carton", "pack_qty": 1000, "qty": 4},
    {"name": "W1 平盖", "unit": "carton", "pack_qty": 1000, "qty": 2}]'::jsonb,
  '拣货单：同一样货几张单加起来（2 + 1 + 1 = 4），缺货的不算'
);
select is(
  (select array_agg((e ->> 'id')::uuid order by ord) from jsonb_array_elements(:'sum2'::jsonb -> 'orders') with ordinality as t(e, ord)),
  array[:'o3', :'o1', :'o4', :'o2']::uuid[],
  '同一个送货区里按店名排（同一家店再按订单号），不是按订单号或下单时间'
);

select tests.login_as(tests.uid('seller2'));
select throws_ok(format('select public.get_delivery_summary(%L)', tests.uid('W1')), '42501', 'NOT_ALLOWED', '不能看别家的送货总结');

-- ---------- 每天早上的总结通知 ----------
select tests.logout();
-- 只发给 active 的批发商：W2 今天也有单，但先停用
update public.wholesalers set status = 'suspended' where id = tests.uid('W2');
select is(public.enqueue_daily_summaries(), 1, '停用（suspended）的批发商不发：只有 W1（今天有单要送）');
select is(
  (select count(*)::int from public.notifications where wholesaler_id = tests.uid('W2') and event_type = 'daily_summary'),
  0, 'W2 没有总结'
);
update public.wholesalers set status = 'active' where id = tests.uid('W2');
select is(public.enqueue_daily_summaries(), 1, 'W2 恢复后再跑：W2（今天有单还没确认）也有一条，W1 不会重复');
select is(
  (select payload from public.notifications where wholesaler_id = tests.uid('W1') and event_type = 'daily_summary'),
  jsonb_build_object('date', public.today_myt(), 'order_count', 2, 'pending_count', 1, 'total_sen', 26800),
  '总结内容：日期、几张要送、几张没确认、总额'
);
select is(public.enqueue_daily_summaries(), 0, '同一天再跑不会重复发');

-- =============================================================================
-- 价目表导入
-- =============================================================================
\set imp '99999999-0000-4000-8000-000000000001'
-- 只用测试的标准商品比对（种子数据的标准商品先停用，结果才固定）
update public.catalog_items set is_active = false where code not like 'test\_%';
insert into public.price_list_imports (id, wholesaler_id, file_path, file_type, created_by)
values (:'imp', tests.uid('W1'), 'cccccccc-0000-4000-8000-000000000001/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a11.jpg', 'image', tests.uid('seller1'));
insert into public.price_list_import_rows (import_id, row_no, raw_text, name, unit, pack_qty, price_sen, min_order_qty) values
  (:'imp', 1, 'W1 16oz 杯 1000个 RM88', 'W1 16oz 杯', 'carton', 1000, 8800, null),     -- 对到 P1
  (:'imp', 2, 'W1 平盖 新款 RM42 起订2', 'W1 平盖 新款', 'carton', 1000, 4200, 2),        -- 对到 P2
  (:'imp', 3, '95 lid flat 100pcs RM6.50', '95 lid flat', 'pack', 100, 650, null),     -- 新商品，像标准商品「95 lid」
  (:'imp', 4, 'Mystery item ???', 'Mystery item', null, null, null, null),            -- 没价钱
  (:'imp', 5, '??? RM10', null, 'carton', 1, 1000, null),                               -- 没名字
  (:'imp', 6, 'Plastic spoon white 100pcs RM5', 'Plastic spoon white', 'pack', 100, 500, null),
  (:'imp', 7, 'W1 16oz 杯 (旧) 500个 RM45', 'W1 16oz 杯 (旧)', 'carton', 500, 4500, null); -- 也像 P1，但 P1 已经对给第 1 行

select tests.login_as(tests.uid('seller1'));
-- 档案路径：服务器会用自己的身份下载（不受 Storage 规则限制），所以只能是自己文件夹里的 <uuid>.<副档名>
select throws_ok(
  format('insert into public.price_list_imports (wholesaler_id, file_path, file_type) values (%L, %L, %L)',
         tests.uid('W1'), tests.uid('W2') || '/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a11.jpg', 'image'),
  '23514', null, '档案路径指到别家批发商的文件夹：不行'
);
select throws_ok(
  format('insert into public.price_list_imports (wholesaler_id, file_path, file_type) values (%L, %L, %L)',
         tests.uid('W1'), tests.uid('W1') || '/%2e%2e/' || tests.uid('W2') || '/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a11.jpg', 'image'),
  '23514', null, '路径里有编码过的 ..（%2e%2e）：不行'
);
select throws_ok(
  format('update public.price_list_imports set file_path = %L where id = %L',
         tests.uid('W1') || '/..\' || tests.uid('W2') || '/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a11.jpg', :'imp'),
  '23514', null, '改成有 .. 和反斜线的路径也不行'
);
select throws_ok(format('select public.apply_price_list_import(%L)', :'imp'), 'P0001', 'IMPORT_NOT_IN_REVIEW',
  'AI 还没处理完（processing）不能上架');

select tests.logout();
select is(
  public.suggest_import_matches(:'imp'), '{"rows": 7, "matched": 2, "suggested": 3}'::jsonb,
  '比对结果：7 行、2 行对到自己的商品、3 行有建议的标准商品'
);
select is(
  (select array_agg(r.action::text || ':' || coalesce(p.name, '-') || ':' || coalesce(ci.code, '-') order by r.row_no)
   from public.price_list_import_rows r
   left join public.products p on p.id = r.matched_product_id
   left join public.catalog_items ci on ci.id = r.suggested_catalog_item_id
   where r.import_id = :'imp'),
  array[
    'update:W1 16oz 杯:test_cup_16oz',
    'update:W1 平盖:-',
    'create:-:test_lid_95',
    'skip:-:-',
    'skip:-:-',
    'create:-:-',
    'create:-:test_cup_16oz'
  ],
  '每一行：对到哪样商品、建议哪样标准商品、要做什么（一样商品只对给最像的一行）'
);
update public.price_list_imports set status = 'review' where id = :'imp';   -- Edge Function 处理完

select tests.login_as(tests.uid('seller1'));
select is(
  (select count(*)::int from public.price_list_import_rows where import_id = :'imp'), 7, '批发商看得到自己的导入行'
);
select is(
  (public.get_seller_home(tests.uid('W1')) -> 'latest_import' ->> 'status'), 'review', '首页显示最新一次导入的状态'
);

select tests.login_as(tests.uid('seller2'));
select is((select count(*)::int from public.price_list_import_rows where import_id = :'imp'), 0, '别家批发商看不到这些行');
select throws_ok(format('select public.apply_price_list_import(%L)', :'imp'), '42501', 'NOT_ALLOWED', '别家批发商不能上架');
select tests.login_as(tests.uid('buyer1'));
select throws_ok(format('select public.apply_price_list_import(%L)', :'imp'), '42501', 'NOT_ALLOWED', '买家不能上架');

select tests.login_as(tests.uid('seller1'));
update public.price_list_import_rows set action = 'create' where import_id = :'imp' and row_no = 4;
select is(
  tests.error_of(format('select public.apply_price_list_import(%L)', :'imp')),
  'IMPORT_ROW_INCOMPLETE:4', '要新增但资料不完整（没单位、包装、价钱）：报错并指出第几行'
);
update public.price_list_import_rows set action = 'update', matched_product_id = tests.uid('P6') where import_id = :'imp' and row_no = 4;
select is(
  tests.error_of(format('select public.apply_price_list_import(%L)', :'imp')),
  'IMPORT_ROW_INCOMPLETE:4', '要更新但没价钱：报错并指出第几行'
);
update public.price_list_import_rows set matched_product_id = null, price_sen = 990 where import_id = :'imp' and row_no = 4;
select is(
  tests.error_of(format('select public.apply_price_list_import(%L)', :'imp')),
  'IMPORT_ROW_INCOMPLETE:4', '要更新但没对到商品：报错并指出第几行'
);
update public.price_list_import_rows set action = 'skip', price_sen = null where import_id = :'imp' and row_no = 4;

update public.price_list_import_rows set matched_product_id = tests.uid('P3') where import_id = :'imp' and row_no = 2;
select is(
  tests.error_of(format('select public.apply_price_list_import(%L)', :'imp')),
  'IMPORT_ROW_INVALID_PRODUCT:2', '把行改成对到别家批发商的商品：不能上架'
);
select is((select price_sen from public.products where id = tests.uid('P3')), null::int, '（批发商看不到别家的商品）');
select tests.logout();
select is((select price_sen from public.products where id = tests.uid('P3')), 480, '别家的商品价钱没被改');
select tests.login_as(tests.uid('seller1'));
update public.price_list_import_rows set matched_product_id = tests.uid('P2') where import_id = :'imp' and row_no = 2;

update public.price_list_import_rows set action = 'update', matched_product_id = tests.uid('P1') where import_id = :'imp' and row_no = 7;
select is(
  tests.error_of(format('select public.apply_price_list_import(%L)', :'imp')),
  'IMPORT_DUPLICATE_PRODUCT:1', '两行改同一样商品：要先改好'
);
update public.price_list_import_rows set action = 'create', matched_product_id = null where import_id = :'imp' and row_no = 7;

select is(
  public.apply_price_list_import(:'imp'), '{"created": 3, "updated": 2, "skipped": 2}'::jsonb,
  '确认上架：新增 3 样、改了 2 样、跳过 2 行'
);
select is(
  (select price_sen || '/' || status || '/' || min_order_qty from public.products where id = tests.uid('P1')),
  '8800/active/1', 'P1 改了价钱，起订量没填就不改'
);
select is(
  (select price_sen || '/' || min_order_qty || '/' || stock_status from public.products where id = tests.uid('P2')),
  '4200/2/low_stock', 'P2 改了价钱和起订量，库存状态不动'
);
select is(
  (select p.status || '/' || p.unit || '/' || p.pack_qty || '/' || p.price_sen || '/' || p.min_order_qty || '/' || ci.code
          || '/' || (p.category_id = ci.category_id)
   from public.products p join public.catalog_items ci on ci.id = p.catalog_item_id
   where p.wholesaler_id = tests.uid('W1') and p.name = '95 lid flat'),
  'active/pack/100/650/1/test_lid_95/true', '新商品直接上架，对到标准商品和它的分类，起订量默认 1'
);
select is(
  (select count(*)::int from public.products where wholesaler_id = tests.uid('W1') and name in ('Plastic spoon white', 'W1 16oz 杯 (旧)') and status = 'active'),
  2, '其他新商品也上架了'
);
select is(
  (select changed_by from public.product_price_history where product_id = tests.uid('P1') order by id desc limit 1),
  tests.uid('seller1'), '改价记录记下是谁改的'
);
select is(
  (select status || '/' || (applied_at is not null) from public.price_list_imports where id = :'imp'),
  'applied/true', '导入标为已上架'
);
select throws_ok(format('select public.apply_price_list_import(%L)', :'imp'), 'P0001', 'IMPORT_NOT_IN_REVIEW', '不能上架两次');
select tests.logout();
select throws_ok(format('select public.suggest_import_matches(%L)', :'imp'), 'P0001', 'IMPORT_ALREADY_APPLIED', '已上架的导入不能再比对');
select throws_ok(format('select public.suggest_import_matches(%L)', '99999999-0000-4000-8000-000000000999'),
  'P0001', 'IMPORT_NOT_FOUND', '比对：没有这次导入');
select tests.login_as(tests.uid('seller1'));
select throws_ok(format('select public.apply_price_list_import(%L)', '99999999-0000-4000-8000-000000000999'),
  'P0001', 'IMPORT_NOT_FOUND', '上架：没有这次导入');
select tests.logout();

-- 商品名相似度：英文跟 pg_trgm 一样；中文字也算字（不会因为数字一样就当成同一样东西）
select is(public._name_similarity('16oz PP Cup', '16oz cup'), extensions.similarity('16oz pp cup', '16oz cup'), '英文名字直接用 pg_trgm');
select is(
  public._trgm_sim(public._name_trgms('16oz PP Cup 95mm'), public._name_trgms('16OZ cup')),
  extensions.similarity('16oz pp cup 95mm', '16oz cup'), '自己切的三字组跟 pg_trgm 结果一样'
);
select ok(public._name_similarity('95 平盖', '95 平盖 1000个') > 0.45, '中文：同一样东西多写了包装 → 算同一样');
select ok(public._name_similarity('95 平盖', '95 拱形盖') <= 0.45, '中文：数字一样但东西不一样 → 不算同一样');
select is(
  (select n.nspname::text from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm'),
  'extensions', 'pg_trgm 装在 extensions schema'
);

-- 不同尺寸：名字只差一个数字，三字组相似度很高（12oz / 16oz 杯 0.54，90 / 95 盖 0.71），
-- 但不是同一样东西，不能把新尺寸的价钱写到旧尺寸上。两边的数字要一边包含另一边才算同一样
select is(public._name_numbers('１６oz PP杯 95mm 1000个'), array['1000', '16', '95'], '名字里的数字（全形当半形）');
select is(public._name_numbers('RM6.50 x 016 / 1.0'), array['1', '16', '6.5'], '数字统一写法（016 = 16，6.50 = 6.5）');
\set imp2 '99999999-0000-4000-8000-000000000002'
insert into public.price_list_imports (id, wholesaler_id, file_path, file_type, status)
values (:'imp2', tests.uid('W1'), tests.uid('W1') || '/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a12.jpg', 'image', 'processing');
insert into public.price_list_import_rows (import_id, row_no, name, unit, pack_qty, price_sen) values
  (:'imp2', 1, 'W1 12oz 杯', 'carton', 1000, 7200),    -- 新尺寸：不是 P1「W1 16oz 杯」
  (:'imp2', 2, '90 lid flat', 'pack', 100, 600),       -- 新尺寸：不是「95 lid flat」
  (:'imp2', 3, 'W1 平盖 95mm', 'carton', 1000, 4300);  -- 多写了尺寸：还是 P2「W1 平盖」
select is(
  public.suggest_import_matches(:'imp2'), '{"rows": 3, "matched": 1, "suggested": 1}'::jsonb,
  '只有数字对得上的才对到商品、标准商品'
);
select is(
  (select array_agg(r.action::text || ':' || coalesce(p.name, '-') || ':' || coalesce(ci.code, '-') order by r.row_no)
   from public.price_list_import_rows r
   left join public.products p on p.id = r.matched_product_id
   left join public.catalog_items ci on ci.id = r.suggested_catalog_item_id
   where r.import_id = :'imp2'),
  array['create:-:-', 'create:-:-', 'update:W1 平盖:test_lid_95'],
  '12oz 不对到 16oz、90 不对到 95（新增，不改旧尺寸的价钱，也不建议别的尺寸的标准商品）；数字多写了的照样对到'
);

-- 速度：每一对都重新切三字组的话，几百行 × 几百样商品要十几秒以上（Edge Function 会超时）。
-- 子交易里做 200 行 × 400 样商品，看完退回；名字都很像（最坏的情况）
\set imp_perf '99999999-0000-4000-8000-0000000000ff'
savepoint perf;
insert into public.products (wholesaler_id, name, unit, pack_qty, price_sen, status)
select tests.uid('W3'),
       'PP杯 ' || (array['8', '12', '16', '22', '24'])[1 + g % 5] || '安士 ' || (array['90', '95', '98'])[1 + g % 3] || '口径 款' || g,
       'carton', 1000, 1000 + g, 'active'
from generate_series(1, 400) g;
insert into public.price_list_imports (id, wholesaler_id, file_path, file_type)
values (:'imp_perf', tests.uid('W3'), tests.uid('W3') || '/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9aff.jpg', 'image');
insert into public.price_list_import_rows (import_id, row_no, name, unit, pack_qty, price_sen)
select :'imp_perf', g,
       'PP杯 ' || (array['8', '12', '16', '22', '24'])[1 + h % 5] || '安士 ' || (array['90', '95', '98'])[1 + h % 3] || '口径 款' || h,
       'carton', 1000, 2000 + g
from generate_series(1, 200) g cross join lateral (select g * 2 as h) x;
select clock_timestamp() as perf_t0 \gset
select public.suggest_import_matches(:'imp_perf') as perf_result \gset
select round(extract(epoch from clock_timestamp() - :'perf_t0'::timestamptz), 2) as perf_secs \gset
select count(*) filter (where p.name ~ ('款' || (r.row_no * 2) || '$'))::int as perf_right
from public.price_list_import_rows r join public.products p on p.id = r.matched_product_id
where r.import_id = :'imp_perf' \gset
rollback to savepoint perf;
select ok(:perf_secs < 5, '200 行 × 400 样很像的商品：几秒内比对完（这次 ' || :perf_secs || ' 秒）');
select is(
  (:'perf_result'::jsonb ->> 'matched') || '/' || :perf_right, '200/200', '每一行都对到同一款（数字都一样的那一样）'
);

-- 一对一、同样像、下架的商品（W3，全英文名字）
--   * 新款「16oz Clear Thick」最像的是「16oz Clear」，但已经对给第 1 行 → create；
--     不能退而求其次对到「16oz Clear Printed」（确认上架时会把新款的价钱写到 Printed 上，新款也没建）
--   * 同名两样（上架、下架）一样像：上架的优先（下架那样的 id 故意排在前面）
--   * 只有下架的那样对得上：也对到，上架时重新上架
--   * 同名、不同单位的两样，两行都没写单位：一样像，两行各对一样（不会有一行变 create）
\set imp3 '99999999-0000-4000-8000-000000000003'
\set pc_clear   'eeeeeeee-0000-4000-8000-000000000001'
\set pc_printed 'eeeeeeee-0000-4000-8000-000000000002'
\set bowl_arch  'eeeeeeee-0000-4000-8000-000000000003'
\set bowl_act   'eeeeeeee-0000-4000-8000-000000000004'
\set bag_arch   'eeeeeeee-0000-4000-8000-000000000005'
\set straw_pack 'eeeeeeee-0000-4000-8000-000000000006'
\set straw_ctn  'eeeeeeee-0000-4000-8000-000000000007'
insert into public.products (id, wholesaler_id, name, unit, pack_qty, price_sen, status) values
  (:'pc_clear',   tests.uid('W3'), 'PP Cup 16oz Clear',         'carton', 1000, 9000,  'active'),
  (:'pc_printed', tests.uid('W3'), 'PP Cup 16oz Clear Printed', 'carton', 1000, 9900,  'active'),
  (:'bowl_arch',  tests.uid('W3'), 'Kraft Bowl 750ml',          'carton', 300,  11000, 'archived'),
  (:'bowl_act',   tests.uid('W3'), 'Kraft Bowl 750ml',          'carton', 300,  11500, 'active'),
  (:'bag_arch',   tests.uid('W3'), 'Paper Bag Medium',          'pack',   50,   1200,  'archived'),
  (:'straw_pack', tests.uid('W3'), 'Straw 6mm Black',           'pack',   100,  500,   'active'),
  (:'straw_ctn',  tests.uid('W3'), 'Straw 6mm Black',           'carton', 5000, 20000, 'active');
insert into public.price_list_imports (id, wholesaler_id, file_path, file_type)
values (:'imp3', tests.uid('W3'), tests.uid('W3') || '/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a13.jpg', 'image');
insert into public.price_list_import_rows (id, import_id, row_no, name, unit, pack_qty, price_sen) values
  ('99999999-0000-4000-8000-000000000301', :'imp3', 1, 'PP Cup 16oz Clear',       'carton', 1000, 9100),
  ('99999999-0000-4000-8000-000000000302', :'imp3', 2, 'PP Cup 16oz Clear Thick', 'carton', 1000, 9500),
  ('99999999-0000-4000-8000-000000000303', :'imp3', 3, 'Kraft Bowl 750ml',        'carton', 300,  11800),
  ('99999999-0000-4000-8000-000000000304', :'imp3', 4, 'Paper Bag Medium',        'pack',   50,   1300),
  ('99999999-0000-4000-8000-000000000305', :'imp3', 5, 'Straw 6mm Black',         null,     null, 550),
  ('99999999-0000-4000-8000-000000000306', :'imp3', 6, 'Straw 6mm Black',         null,     null, 21000);
select ok(
  public._name_similarity('PP Cup 16oz Clear Thick', 'PP Cup 16oz Clear Printed') > 0.45
    and public._name_similarity('PP Cup 16oz Clear Thick', 'PP Cup 16oz Clear')
        > public._name_similarity('PP Cup 16oz Clear Thick', 'PP Cup 16oz Clear Printed'),
  '（新款跟 Printed 也超过 0.45，但跟 Clear 更像）'
);
select is(
  public.suggest_import_matches(:'imp3') ->> 'matched', '5', '6 行里 5 行对到自己的商品'
);
select is(
  (select array_agg(r.action::text || ':' || coalesce(p.name || '/' || p.status || '/' || p.unit, '-') order by r.row_no)
   from public.price_list_import_rows r
   left join public.products p on p.id = r.matched_product_id
   where r.import_id = :'imp3'),
  array[
    'update:PP Cup 16oz Clear/active/carton',
    'create:-',
    'update:Kraft Bowl 750ml/active/carton',
    'update:Paper Bag Medium/archived/pack',
    'update:Straw 6mm Black/active/pack',
    'update:Straw 6mm Black/active/carton'
  ],
  '最像的已经给了别行 → create（不对到第二像的）；同样像时上架的优先；下架的也对得到；同样像的两样两行各一样'
);
update public.price_list_imports set status = 'review' where id = :'imp3';
select tests.login_as(tests.uid('seller3'));
select is(
  public.apply_price_list_import(:'imp3'), '{"created": 1, "updated": 5, "skipped": 0}'::jsonb, 'W3 确认上架：新增 1 样、改了 5 样'
);
select tests.logout();
select is(
  (select string_agg(p.name || ':' || p.unit || ':' || p.price_sen || ':' || p.status, ', '
                     order by p.name collate "C", p.unit, p.price_sen)
   from public.products p where p.wholesaler_id = tests.uid('W3') and p.name ~ '^(PP Cup|Kraft|Paper|Straw)'),
  'Kraft Bowl 750ml:carton:11000:archived, Kraft Bowl 750ml:carton:11800:active, '
  || 'PP Cup 16oz Clear:carton:9100:active, PP Cup 16oz Clear Printed:carton:9900:active, PP Cup 16oz Clear Thick:carton:9500:active, '
  || 'Paper Bag Medium:pack:1300:active, Straw 6mm Black:carton:21000:active, Straw 6mm Black:pack:550:active',
  '上架后：Printed 的价钱没被改、新款 Thick 新增了；下架的那样碗不动；对到的下架纸袋重新上架'
);

-- =============================================================================
-- 通知发送：选渠道、领取、完成、重试
-- =============================================================================
select tests.logout();
delete from public.notifications;
-- W1：auto，seller1 有装 App（W1 还没同意 WhatsApp；有 App 又同意 WhatsApp 的情况在后面用 W3 测）
insert into public.device_tokens (user_id, fcm_token, platform, kind) values (tests.uid('seller1'), 'tok-seller1', 'android', 'token');
-- W2：auto，没装 App，有 WhatsApp 而且同意了，语言英文
update public.wholesalers set whatsapp_phone = '012-200 0002', whatsapp_opt_in_at = now(), locale = 'en' where id = tests.uid('W2');
-- W3：有 WhatsApp 号码但没同意；seller3 的 token 超过 60 天没用
update public.wholesalers set whatsapp_phone = '60122000003' where id = tests.uid('W3');
insert into public.device_tokens (user_id, fcm_token, platform, last_seen_at) values (tests.uid('seller3'), 'tok-old', 'android', now() - interval '61 days');
-- 客服有装 App（新的 FID）
insert into public.device_tokens (user_id, fcm_token, platform, kind) values (tests.uid('admin'), 'fid-admin', 'ios', 'fid');

\set n1 '11111111-0000-4000-8000-000000000001'
\set n2 '11111111-0000-4000-8000-000000000002'
\set n3 '11111111-0000-4000-8000-000000000003'
\set n4 '11111111-0000-4000-8000-000000000004'
\set n5 '11111111-0000-4000-8000-000000000005'
\set n6 '11111111-0000-4000-8000-000000000006'
\set n7 '11111111-0000-4000-8000-000000000007'
insert into public.notifications (id, wholesaler_id, shop_id, user_id, event_type, payload, created_at) values
  (:'n1', tests.uid('W1'), null, null, 'order_new', jsonb_build_object('order_id', :'o2'), now() - interval '6 minutes'),
  (:'n2', tests.uid('W2'), null, null, 'order_new', jsonb_build_object('order_id', :'o_w2'), now() - interval '5 minutes'),
  (:'n3', tests.uid('W2'), null, null, 'order_new', jsonb_build_object('order_id', :'o_w2'), now() - interval '4 minutes'),
  (:'n4', tests.uid('W2'), null, null, 'daily_summary', '{"order_count": 1}', now() - interval '3 minutes'),
  (:'n5', tests.uid('W3'), null, null, 'order_new', '{}', now() - interval '2 minutes'),
  (:'n6', null, null, tests.uid('admin'), 'order_unconfirmed', jsonb_build_object('order_id', :'o2'), now() - interval '1 minute'),
  (:'n7', null, tests.uid('S1'), null, 'order_status_changed', jsonb_build_object('order_id', :'o1'), now());

select public.claim_notifications() as c1 \gset
select is(
  (select array_agg((e ->> 'id')::uuid order by ord) from jsonb_array_elements(:'c1'::jsonb) with ordinality as t(e, ord)),
  array[:'n1', :'n2', :'n4', :'n5', :'n6', :'n7']::uuid[],
  '领走排队中的通知（旧到新）；同一个 WhatsApp 号码这一轮只领一条（n3 留着）'
);
select is(
  (select string_agg(coalesce(e ->> 'channel', 'null'), ',' order by ord) from jsonb_array_elements(:'c1'::jsonb) with ordinality as t(e, ord)),
  'push,whatsapp,null,null,push,null',
  '选渠道：有 token → 推送；没 token 但同意 WhatsApp → WhatsApp；daily_summary 不走 WhatsApp；没同意 → 没渠道；客服 → 推送'
);
select is(
  (select e -> 'push_targets' from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n1'),
  '[{"target": "tok-seller1", "kind": "token"}]'::jsonb, '推送对象：批发商成员的 token'
);
select is(
  (select e -> 'push_targets' from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n6'),
  '[{"target": "fid-admin", "kind": "fid"}]'::jsonb, '推送对象也可以是 FID'
);
select is(
  (select (e ->> 'whatsapp_phone') || '/' || (e ->> 'locale') || '/' || (e -> 'push_targets')::text
   from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n2'),
  '60122000002/en/[]', 'WhatsApp：号码统一格式，语言跟批发商'
);
select is(
  (select e -> 'details' ->> 'order_no' || '/' || (e -> 'details' ->> 'shop_name') || '/' || (e -> 'details' ->> 'shop_phone')
          || '/' || (e -> 'details' ->> 'items_text') || '/' || (e -> 'details' ->> 'item_count') || '/' || (e -> 'details' ->> 'total_sen')
   from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n1'),
  (select order_no from public.orders where id = :'o2') || '/S2 店/60111000002/W1 16oz 杯 x1 箱/1/9300',
  '订单类通知附上订单资料（中文单位）'
);
select is(
  (select e -> 'details' ->> 'items_text' from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n2'),
  'W2 16oz 杯 小包 x5 pack', '单位按收件人的语言（英文）'
);
select is(
  (select e -> 'details' ->> 'items_text' || '/' || (e -> 'details' ->> 'out_of_stock_count')
   from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n7'),
  'W1 16oz 杯 x2 箱; W1 平盖 x1 箱（缺货）/1', '多样货用「; 」分开，缺货的标出来'
);
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys(:'c1'::jsonb -> 0) as t(k)),
  'attempts,channel,details,event_type,id,locale,payload,push_targets,whatsapp_phone',
  '每条领到的通知的字段'
);
select is(
  (select e -> 'details' from jsonb_array_elements(:'c1'::jsonb) e where (e ->> 'id')::uuid = :'n4'),
  'null'::jsonb, '不是订单类的通知没有 details'
);
select is(
  (select string_agg(id::text || ':' || status, ',' order by id) from public.notifications where claimed_at = now()),
  :'n1' || ':sending,' || :'n2' || ':sending,' || :'n4' || ':sending,' || :'n5' || ':sending,' || :'n6' || ':sending,' || :'n7' || ':sending',
  '领走的设为「发送中」，记下领取时间'
);
select is(public.claim_notifications(), '[]'::jsonb, '马上再领：领不到同一条，同号码的 n3 也还不能领（n2 还在发）');

select ok(public.complete_notification(:'n2', 'sent', 'whatsapp', null, 'wamid.N2'), 'n2 WhatsApp 发出去了');
select is(
  (select status || '/' || attempts || '/' || channel || '/' || wa_message_id || '/' || (sent_at = now()) from public.notifications where id = :'n2'),
  'sent/1/whatsapp/wamid.N2/true', '发出去：记下时间和 WhatsApp 消息 id'
);
select is(
  (select direction || '/' || message_type || '/' || phone || '/' || wholesaler_id || '/' || order_id
   from public.whatsapp_messages where wa_message_id = 'wamid.N2'),
  'outbound/template/60122000002/' || tests.uid('W2') || '/' || :'o_w2',
  '发出去的 WhatsApp 记一行（关联批发商和订单）'
);
select is(
  (select array_agg((e ->> 'id')::uuid) from jsonb_array_elements(public.claim_notifications()) e),
  array[:'n3']::uuid[], 'n2 发完了，同号码的 n3 现在可以领'
);

-- 失败重试
select ok(public.complete_notification(:'n1', 'failed', 'push', 'FCM 503'), 'n1 推送失败');
select is(
  (select status || '/' || attempts || '/' || (next_attempt_at = now() + interval '2 minutes') || '/' || last_error from public.notifications where id = :'n1'),
  'failed/1/true/FCM 503', '第 1 次失败：2 分钟后重试'
);
select is(public.claim_notifications(), '[]'::jsonb, '还没到重试时间，领不到');
update public.notifications set next_attempt_at = now() - interval '1 second' where id = :'n1';
select is(
  (select array_agg((e ->> 'id')::uuid || ':' || (e ->> 'attempts')) from jsonb_array_elements(public.claim_notifications()) e),
  array[:'n1' || ':1'], '到时间了，失败的可以再领'
);
select ok(public.complete_notification(:'n1', 'failed', 'push', 'FCM 503'), '又失败');
select is(
  (select attempts || '/' || (next_attempt_at = now() + interval '4 minutes') from public.notifications where id = :'n1'),
  '2/true', '第 2 次失败：4 分钟后重试（2 的次方）'
);
select is(public.complete_notification(:'n1', 'sent', 'push'), false, '不是「发送中」的不能再完成一次');
select is((select status || '/' || attempts from public.notifications where id = :'n1'), 'failed/2', '没有被改');
-- 卡住被重新领、另一个 dispatcher 已经完成了（sent），原来那个 dispatcher 的 WhatsApp 后来才报告发出去：
-- 通知不改，但那条 WhatsApp 照样记下（按钮 context 要对得到这张订单和批发商，只有 BSUID 的批发商按按钮才认得）
\set n15 '11111111-0000-4000-8000-000000000015'
insert into public.notifications (id, wholesaler_id, event_type, payload, status, attempts, channel, sent_at, wa_message_id)
values (:'n15', tests.uid('W2'), 'order_new', jsonb_build_object('order_id', :'o_w2'), 'sent', 1, 'whatsapp',
        now() - interval '1 minute', 'wamid.FIRST');
select is(public.complete_notification(:'n15', 'sent', 'whatsapp', null, 'wamid.LATE'), false, '已经完成的通知：回 false');
select is(
  (select status || '/' || attempts || '/' || wa_message_id || '/' || (sent_at = now() - interval '1 minute') from public.notifications where id = :'n15'),
  'sent/1/wamid.FIRST/true', '通知没有被改'
);
select is(
  (select direction || '/' || message_type || '/' || phone || '/' || wholesaler_id || '/' || order_id
   from public.whatsapp_messages where wa_message_id = 'wamid.LATE'),
  'outbound/template/60122000002/' || tests.uid('W2') || '/' || :'o_w2',
  '晚到的那条 WhatsApp 也记一行（关联批发商和订单）'
);
update public.notifications set next_attempt_at = now() - interval '1 second' where id = :'n1';
select is(jsonb_array_length(public.claim_notifications()), 1, '再领一次');
select ok(public.complete_notification(:'n1', 'failed', 'whatsapp', 'WA 131026 not on WhatsApp', p_retry => false), '永久失败');
select is(
  (select status || '/' || attempts || '/' || coalesce(next_attempt_at::text, 'null') from public.notifications where id = :'n1'),
  'failed/5/null', '永久失败：attempts 设为 5，不再重试'
);
update public.notifications set next_attempt_at = now() - interval '1 hour' where id = :'n1';
select is(public.claim_notifications(), '[]'::jsonb, '永久失败的永远领不到');

-- 卡住的「发送中」
update public.notifications set claimed_at = now() - interval '11 minutes' where id = :'n5';
update public.notifications set claimed_at = now() - interval '5 minutes' where id = :'n7';
select is(
  (select array_agg((e ->> 'id')::uuid || ':' || (e ->> 'attempts')) from jsonb_array_elements(public.claim_notifications()) e),
  array[:'n5' || ':1'], '「发送中」超过 10 分钟当成卡住，重新领（算失败一次）；5 分钟的还不算'
);
-- 之前某一次失败留下的错误（FCM 503）不是这次放弃的原因
update public.notifications set claimed_at = now() - interval '20 minutes', attempts = 4, last_error = 'FCM 503' where id = :'n7';
select is(public.claim_notifications(), '[]'::jsonb, '卡住太多次的不再领');
select is(
  (select status || '/' || attempts || '/' || last_error from public.notifications where id = :'n7'), 'failed/5/STUCK_IN_SENDING',
  '直接标为失败，错误写 STUCK_IN_SENDING（盖掉之前的 FCM 503）'
);

-- 第 3、4 次失败：8、16 分钟后重试；第 5 次失败（就算是可以重试的错误）就不再试
\set n8 '11111111-0000-4000-8000-000000000008'
insert into public.notifications (id, wholesaler_id, event_type, payload, status, attempts)
values (:'n8', tests.uid('W1'), 'test', '{}', 'sending', 2);
select public.complete_notification(:'n8', 'failed', 'push', 'FCM 503');
select is(
  (select attempts || '/' || (next_attempt_at = now() + interval '8 minutes') from public.notifications where id = :'n8'),
  '3/true', '第 3 次失败：8 分钟后重试'
);
update public.notifications set status = 'sending' where id = :'n8';
select public.complete_notification(:'n8', 'failed', 'push', 'FCM 503');
select is(
  (select attempts || '/' || (next_attempt_at = now() + interval '16 minutes') from public.notifications where id = :'n8'),
  '4/true', '第 4 次失败：16 分钟后重试'
);
update public.notifications set status = 'sending' where id = :'n8';
select public.complete_notification(:'n8', 'failed', 'push', 'FCM 503');
select is(
  (select status || '/' || attempts || '/' || coalesce(next_attempt_at::text, 'null') from public.notifications where id = :'n8'),
  'failed/5/null', '第 5 次失败：不再重试'
);

select ok(public.complete_notification(:'n4', 'skipped', null, 'NO_CHANNEL'), '没渠道的标为跳过');
select is((select status || '/' || attempts || '/' || last_error from public.notifications where id = :'n4'), 'skipped/1/NO_CHANNEL', '跳过：记下原因');
select throws_ok(format('select public.complete_notification(%L, %L, %L)', :'n6', 'queued', 'push'), 'P0001', 'INVALID_STATUS', '只能完成为 sent / failed / skipped');
select throws_ok(format('select public.complete_notification(%L, %L, %L)', '11111111-0000-4000-8000-000000000999', 'sent', 'push'),
  'P0001', 'NOTIFICATION_NOT_FOUND', '没有这条通知');

-- notify_channel 强制
update public.wholesalers set notify_channel = 'whatsapp', whatsapp_phone = '60122000001', whatsapp_opt_in_at = now() where id = tests.uid('W1');
update public.wholesalers set notify_channel = 'push' where id = tests.uid('W2');
insert into public.notifications (wholesaler_id, event_type, payload, created_at) values
  (tests.uid('W1'), 'order_new', jsonb_build_object('order_id', :'o2'), now() + interval '1 second'),
  (tests.uid('W1'), 'daily_summary', '{}', now() + interval '2 seconds'),
  (tests.uid('W2'), 'order_new', jsonb_build_object('order_id', :'o_w2'), now() + interval '3 seconds');
select public.claim_notifications() as c2 \gset
select is(
  (select string_agg((e ->> 'event_type') || ':' || coalesce(e ->> 'channel', 'null') || ':' || coalesce(e ->> 'whatsapp_phone', '-'), ',' order by ord)
   from jsonb_array_elements(:'c2'::jsonb) with ordinality as t(e, ord)),
  'order_new:whatsapp:60122000001,daily_summary:null:-,order_new:null:-',
  'notify_channel = whatsapp：有 App 也发 WhatsApp（但每日总结不发 WhatsApp）；= push：没 token 就不发'
);
update public.wholesalers set whatsapp_opt_in_at = null where id = tests.uid('W1');
insert into public.notifications (wholesaler_id, event_type, payload) values (tests.uid('W1'), 'order_new', '{}');
select is(
  (select e ->> 'channel' from jsonb_array_elements(public.claim_notifications()) e), null,
  'notify_channel = whatsapp 但没同意：不发'
);

-- auto：有 App 又同意 WhatsApp → 先用推送（WhatsApp 按条收费）；店铺（买家）也一样选渠道
update public.wholesalers set whatsapp_opt_in_at = now() where id = tests.uid('W3');   -- W3 有 WhatsApp 号码
insert into public.device_tokens (user_id, fcm_token, platform) values
  (tests.uid('seller3'), 'tok-seller3', 'android'),
  (tests.uid('buyer2'), 'tok-buyer2', 'ios');
update public.shops set whatsapp_opt_in_at = now(), locale = 'ms' where id = tests.uid('S3');   -- buyer3 没装 App
insert into public.notifications (wholesaler_id, shop_id, event_type, payload, created_at) values
  (tests.uid('W3'), null, 'order_new', '{}', now() + interval '4 seconds'),
  (null, tests.uid('S2'), 'order_status_changed', jsonb_build_object('order_id', :'o2'), now() + interval '5 seconds'),
  (null, tests.uid('S3'), 'order_status_changed', jsonb_build_object('order_id', :'o3'), now() + interval '6 seconds');
select public.claim_notifications() as c3 \gset
select is(
  (select string_agg(coalesce(e ->> 'channel', 'null'), ',' order by ord) from jsonb_array_elements(:'c3'::jsonb) with ordinality as t(e, ord)),
  'push,push,whatsapp',
  'auto：批发商有 App 又同意 WhatsApp → 推送；店铺成员有 App → 推送；店铺同意 WhatsApp、没 App → WhatsApp'
);
select is(
  (select jsonb_agg(e -> 'push_targets' order by ord) from jsonb_array_elements(:'c3'::jsonb) with ordinality as t(e, ord) where ord <= 2),
  '[[{"target": "tok-seller3", "kind": "token"}], [{"target": "tok-buyer2", "kind": "token"}]]'::jsonb,
  '推送对象：批发商成员（60 天内的）、店铺成员的 token'
);
select is(
  (select (e ->> 'whatsapp_phone') || '/' || (e ->> 'locale') || '/' || (e -> 'push_targets')::text || '/' || (e -> 'details' ->> 'items_text')
   from jsonb_array_elements(:'c3'::jsonb) with ordinality as t(e, ord) where ord = 3),
  '60111000003/ms/[]/W1 平盖 x2 karton', '店铺的 WhatsApp：店的号码、店的语言'
);

select is(public.remove_device_tokens(array['tok-seller1', 'not-a-token']), 1, '删掉 FCM 说失效的 token');
select is((select count(*)::int from public.device_tokens where fcm_token = 'tok-seller1'), 0, 'token 删掉了');

-- ---------- 推送 token 登记 ----------
select tests.login_as(tests.uid('buyer1'));
select lives_ok($$select public.register_device_token('fid-buyer1', 'android', 'fid')$$, '登记 FID');
select lives_ok($$select public.register_device_token('tok-buyer1', 'ios')$$, '登记旧的 token（kind 默认 token）');
select is(
  (select string_agg(fcm_token || ':' || kind || ':' || platform, ',' order by fcm_token) from public.device_tokens),
  'fid-buyer1:fid:android,tok-buyer1:token:ios', '自己的 token 和种类'
);
select throws_ok($$select public.register_device_token('x', 'android', 'apns')$$, 'P0001', 'INVALID_TOKEN_KIND', '种类只能是 token / fid');
select throws_ok($$select public.register_device_token('   ', 'android')$$, 'P0001', 'INVALID_TOKEN', 'token 不能是空的');
select throws_ok($$select public.register_device_token(null, 'android')$$, 'P0001', 'INVALID_TOKEN', 'token 不能是 null');
select throws_ok($$select public.register_device_token('x', 'symbian')$$, 'P0001', 'INVALID_PLATFORM', '平台只能是 ios / android / web');
select throws_ok($$select public.register_device_token('x', null)$$, 'P0001', 'INVALID_PLATFORM', '平台不能是 null');
select tests.login_as(tests.uid('buyer2'));
select lives_ok($$select public.register_device_token('fid-buyer1', 'android', 'fid')$$, '同一部手机换人登录');
select tests.logout();
select is((select user_id from public.device_tokens where fcm_token = 'fid-buyer1'), tests.uid('buyer2'), 'token 转给新的人');
select is(to_regprocedure('public.register_device_token(text,text)'), null, '旧的两个参数版本已经删掉');
select tests.login_as_anon();
select throws_ok($$select public.register_device_token('x', 'android')$$, '42501', null, '没登录不能登记');

-- =============================================================================
-- WhatsApp 按钮
-- =============================================================================
select tests.logout();
select tests.add_to_cart('S2', 'P3', 5);
select public.place_order(tests.uid('S2'));
select tests.order_of('S2', 'W2') as ow_b \gset
select tests.add_to_cart('S2', 'P3', 6);
select public.place_order(tests.uid('S2'));
select tests.order_of('S2', 'W2') as ow_c \gset
select tests.add_to_cart('S1', 'P3', 7);
select public.place_order(tests.uid('S1'));
select tests.order_of('S1', 'W2') as ow_d \gset

select is(
  public.handle_whatsapp_button('+60 12-200 0002', 'MY.W2', 'wamid.N2', 'CONFIRM:' || :'o_w2', 'wamid.B1', '{"type": "button"}'),
  jsonb_build_object('result', 'confirmed', 'order_no', (select order_no from public.orders where id = :'o_w2'), 'status', 'confirmed', 'locale', 'en'),
  '批发商按「确认」：订单确认，回传订单号和语言'
);
select is(
  (select status::text || '/' || (select channel::text from public.order_status_events e where e.order_id = o.id order by e.id desc limit 1)
   from public.orders o where o.id = :'o_w2'),
  'confirmed/whatsapp', '状态记录写明是从 WhatsApp 确认的'
);
select is(
  public.handle_whatsapp_button('60122000002', 'MY.W2', 'wamid.N2', 'CONFIRM:' || :'o_w2', 'wamid.B1'),
  '{"result": "duplicate"}'::jsonb, 'Meta 重送同一个 webhook：回 duplicate'
);
select is(
  public.handle_whatsapp_button('60199999999', null, null, 'OOS:' || :'ow_b', 'wamid.B2') ->> 'result',
  'not_authorized', '号码不是这家批发商的：不授权'
);
select is((select status::text from public.orders where id = :'ow_b'), 'pending', '订单没被改');
select is(
  public.handle_whatsapp_button('+60 11-1000 012', null, null, 'OOS:' || :'ow_b', 'wamid.B3') ->> 'result',
  'out_of_stock', '批发商成员的电话按「缺货」也可以'
);
select is(
  (select o.status::text || '/' || bool_and(i.is_out_of_stock) from public.orders o join public.order_items i on i.order_id = o.id
   where o.id = :'ow_b' group by o.status),
  'out_of_stock/true', '整张单缺货'
);
select is(
  public.handle_whatsapp_button('60122000002', null, null, 'CONFIRM:' || :'ow_b', 'wamid.B4') ->> 'result',
  'already_out_of_stock', '已经处理过的单：回 already_<状态>，不再改'
);
select is(
  public.handle_whatsapp_button('60122000002', null, null, 'HELLO', 'wamid.B5') ->> 'result',
  'invalid_payload', '看不懂的按钮'
);
select is(
  public.handle_whatsapp_button('60122000002', null, null, 'CONFIRM:00000000-0000-4000-8000-000000000999', 'wamid.B6') ->> 'result',
  'order_not_found', '找不到订单'
);

-- 只有 BSUID（没有号码）：要按在我们发给这家批发商、这张订单的那条消息上
\set n11 '11111111-0000-4000-8000-000000000011'
insert into public.notifications (id, wholesaler_id, event_type, payload, status)
values (:'n11', tests.uid('W2'), 'order_new', jsonb_build_object('order_id', :'ow_c'), 'sending');
select public.complete_notification(:'n11', 'sent', 'whatsapp', null, 'wamid.OUT.C');
select is(
  public.handle_whatsapp_button('60199999999', 'MY.OTHER', 'wamid.OUT.C', 'CONFIRM:' || :'ow_c', 'wamid.B10'),
  '{"result": "not_authorized", "locale": null}'::jsonb,
  '号码有给但对不上：就算按在发给这家批发商这张单的消息上也不授权（不看 context），也不透露订单资料'
);
select is((select status::text from public.orders where id = :'ow_c'), 'pending', 'ow_c 没被改');
select is(
  public.handle_whatsapp_button(null, 'MY.ONLY_BSUID', 'wamid.OUT.C', 'CONFIRM:' || :'ow_c', 'wamid.B7') ->> 'result',
  'confirmed', '只有 BSUID：按钮按在发给这家批发商这张单的消息上 → 可以确认'
);
select is(
  public.handle_whatsapp_button(null, 'MY.ONLY_BSUID', 'wamid.OUT.C', 'CONFIRM:' || :'ow_d', 'wamid.B8') ->> 'result',
  'not_authorized', '只有 BSUID，但那条消息是别张单的：不授权'
);
select is(
  public.handle_whatsapp_button(null, 'MY.ONLY_BSUID', null, 'CONFIRM:' || :'ow_d', 'wamid.B9') ->> 'result',
  'not_authorized', '没有号码也没有 context：不授权'
);
-- 别家批发商（W1）自己的号码、W1 成员的电话，按 W2 的订单
select is(
  public.handle_whatsapp_button('60122000001', null, null, 'CONFIRM:' || :'ow_d', 'wamid.B11'),
  '{"result": "not_authorized", "locale": "zh"}'::jsonb,
  '别家批发商的号码按这张单：不授权（只回发信人的语言）'
);
select is(
  public.handle_whatsapp_button('+60 11-1000 011', null, null, 'OOS:' || :'ow_d', 'wamid.B12') ->> 'result',
  'not_authorized', '别家批发商成员的电话按这张单：不授权'
);
-- 只有 BSUID：按在发给「店铺」的同一张单的消息上（不是发给批发商的）
\set n13 '11111111-0000-4000-8000-000000000013'
insert into public.notifications (id, shop_id, event_type, payload, status)
values (:'n13', tests.uid('S1'), 'order_status_changed', jsonb_build_object('order_id', :'ow_d'), 'sending');
select public.complete_notification(:'n13', 'sent', 'whatsapp', null, 'wamid.OUT.SHOP');
select is(
  public.handle_whatsapp_button(null, 'MY.ONLY_BSUID', 'wamid.OUT.SHOP', 'CONFIRM:' || :'ow_d', 'wamid.B13') ->> 'result',
  'not_authorized', '只有 BSUID，按在发给店铺的这张单的消息上：不授权（要是发给这家批发商的）'
);
-- 只有送达状态建出来的那一行（还不知道是发给谁、哪张单）
select public.update_whatsapp_status('wamid.ONLY.STATUS', 'delivered');
select is(
  public.handle_whatsapp_button(null, 'MY.ONLY_BSUID', 'wamid.ONLY.STATUS', 'CONFIRM:' || :'ow_d', 'wamid.B14') ->> 'result',
  'not_authorized', '只有 BSUID，按在只有送达状态的那一行上：不授权'
);
select is((select status::text from public.orders where id = :'ow_d'), 'pending', 'ow_d 没被改');
select is(
  (select coalesce(phone, 'null') || '/' || from_user_id || '/' || context_wa_message_id || '/' || order_id || '/' || body
   from public.whatsapp_messages where wa_message_id = 'wamid.B7'),
  'null/MY.ONLY_BSUID/wamid.OUT.C/' || :'ow_c' || '/CONFIRM:' || :'ow_c', '按钮消息记下 BSUID、按在哪条消息上、对到的订单（没有号码也能存）'
);
select is(
  (select count(*)::int from public.whatsapp_messages where direction = 'inbound' and message_type = 'button'),
  14, '每个按钮（重复的除外）都记了一行'
);

-- ---------- 其他进来的消息 ----------
select is(
  (select r ->> 'result' || '/' || (r ->> 'shop_id') from public.record_whatsapp_message(
     '60111000001', 'text', 'nak 2 kotak cawan', null, 'wamid.T1', '{"from_user_id": "MY.S1", "type": "text"}') r),
  'recorded/' || tests.uid('S1'), '文字消息：记录，按号码对上店'
);
select is(
  public.record_whatsapp_message('60111000001', 'text', 'nak 2 kotak cawan', null, 'wamid.T1', '{}'),
  '{"result": "duplicate"}'::jsonb, '重复的 id 忽略'
);
select public.record_whatsapp_message('60122000002', 'audio', null, 'MEDIA123', 'wamid.T2', '{"type": "audio"}');
select is(
  (select message_type || '/' || wholesaler_id || '/' || (raw ->> 'media_id') || '/' || coalesce(from_user_id, 'null')
   from public.whatsapp_messages where wa_message_id = 'wamid.T2'),
  'audio/' || tests.uid('W2') || '/MEDIA123/null', '语音：对上批发商，记下媒体 id'
);
select is(
  (select from_user_id from public.whatsapp_messages where wa_message_id = 'wamid.T1'), 'MY.S1', '记下 BSUID'
);

-- ---------- 送达状态 ----------
select is(public.update_whatsapp_status('wamid.N2', 'delivered') ->> 'result', 'updated', 'delivered');
select is(public.update_whatsapp_status('wamid.N2', 'read') ->> 'result', 'updated', 'read');
select is(public.update_whatsapp_status('wamid.N2', 'delivered') ->> 'result', 'stale', '晚到的 delivered 不会把 read 改回去');
select is((select delivery_status from public.whatsapp_messages where wa_message_id = 'wamid.N2'), 'read', '还是 read');
select is(public.update_whatsapp_status('wamid.N2', 'failed', 131026, 'Message undeliverable') ->> 'result', 'updated', 'failed 永远覆盖');
select is(public.update_whatsapp_status('wamid.N2', 'read') ->> 'result', 'stale', 'failed 之后不会再变');
select is(
  (select delivery_status || '/' || error_code || '/' || (raw ->> 'status_error') from public.whatsapp_messages where wa_message_id = 'wamid.N2'),
  'failed/131026/Message undeliverable', '记下错误代码'
);
select is(
  (select last_error from public.notifications where id = :'n2'), 'Message undeliverable (131026)', '通知也记下 WhatsApp 发送失败的原因'
);
select is(public.update_whatsapp_status('wamid.N2', 'deleted') ->> 'result', 'ignored', '不认识的状态忽略');
-- 语音消息「played」排在「read」后面：晚到的 read 不会把 played 改回去
select is(public.update_whatsapp_status('wamid.OUT.C', 'read') ->> 'result', 'updated', 'read');
select is(public.update_whatsapp_status('wamid.OUT.C', 'played') ->> 'result', 'updated', 'played 比 read 后面');
select is(public.update_whatsapp_status('wamid.OUT.C', 'read') ->> 'result', 'stale', '晚到的 read 不会把 played 改回去');
select is((select delivery_status from public.whatsapp_messages where wa_message_id = 'wamid.OUT.C'), 'played', '还是 played');
select is(public.update_whatsapp_status('wamid.EARLY', 'sent') ->> 'result', 'updated', '状态比完成记录先到：先建一行');
\set n12 '11111111-0000-4000-8000-000000000012'
insert into public.notifications (id, wholesaler_id, event_type, payload, status)
values (:'n12', tests.uid('W2'), 'order_new', jsonb_build_object('order_id', :'ow_d'), 'sending');
select public.complete_notification(:'n12', 'sent', 'whatsapp', null, 'wamid.EARLY');
select is(
  (select message_type || '/' || delivery_status || '/' || order_id || '/' || wholesaler_id from public.whatsapp_messages where wa_message_id = 'wamid.EARLY'),
  'template/sent/' || :'ow_d' || '/' || tests.uid('W2'), '之后完成时补上订单和批发商，状态不变'
);
-- 「failed」比完成记录先到（例如号码不在 WhatsApp）：错误也要记进通知，跟后到的一样
select is(
  public.update_whatsapp_status('wamid.EARLY.FAIL', 'failed', 131026, 'Message undeliverable') ->> 'result', 'updated',
  'failed 比完成记录先到：先建一行'
);
\set n14 '11111111-0000-4000-8000-000000000014'
insert into public.notifications (id, wholesaler_id, event_type, payload, status)
values (:'n14', tests.uid('W2'), 'order_new', jsonb_build_object('order_id', :'ow_d'), 'sending');
select public.complete_notification(:'n14', 'sent', 'whatsapp', null, 'wamid.EARLY.FAIL');
select is(
  (select n.status || '/' || n.last_error || '/' || m.delivery_status || '/' || m.order_id || '/' || m.wholesaler_id
   from public.notifications n join public.whatsapp_messages m on m.wa_message_id = n.wa_message_id where n.id = :'n14'),
  'sent/Message undeliverable (131026)/failed/' || :'ow_d' || '/' || tests.uid('W2'),
  '之后完成：通知的 last_error 记下先到的 WhatsApp 失败原因，那一行照样补上订单和批发商'
);

-- =============================================================================
-- 客服提醒：太久没确认的单
-- =============================================================================
-- 现在待确认的：o2（W1，3 小时前）、ow_d（W2，刚下）
-- 还没有客服账号：不提醒，订单也先不标记（等有客服再提醒）
select array_agg(id)::text as admins from public.profiles where role = 'admin' \gset
update public.profiles set role = 'buyer' where id = any (:'admins'::uuid[]);
select is(public.enqueue_unconfirmed_alerts(), 0, '还没有客服：不提醒');
select is(
  (select count(*)::int from public.orders where unconfirmed_alert_at is not null)
    + (select count(*)::int from public.notifications where event_type = 'order_unconfirmed' and status = 'queued'),
  0, '订单也先不标记（有客服之后还会提醒）'
);
update public.profiles set role = 'admin' where id = any (:'admins'::uuid[]);
select is(public.enqueue_unconfirmed_alerts(), 1, '只有 o2 超过 30 分钟没确认');
select is(
  (select user_id || '/' || (payload ->> 'order_id') || '/' || (payload ->> 'wholesaler_name') || '/' || (payload ->> 'pending_minutes')
   from public.notifications where event_type = 'order_unconfirmed' and payload ->> 'order_id' = :'o2' and status = 'queued'),
  tests.uid('admin') || '/' || :'o2' || '/W1 创始批发商/180', '通知每个客服：哪张单、哪家批发商、等了几分钟'
);
select ok((select unconfirmed_alert_at = now() from public.orders where id = :'o2'), '订单记下提醒过了');
select is(public.enqueue_unconfirmed_alerts(), 0, '同一张单只提醒一次');
update public.orders set created_at = now() - interval '29 minutes' where id = :'ow_d';
select is(public.enqueue_unconfirmed_alerts(), 0, '29 分钟还不提醒');
update public.orders set created_at = now() - interval '31 minutes' where id = :'ow_d';
select is(public.enqueue_unconfirmed_alerts(), 1, '31 分钟就提醒');

-- items_text 太长：截到某一样为止，最多 900 字
insert into public.order_items (order_id, product_id, name_snapshot, unit_snapshot, pack_qty_snapshot, unit_price_sen, qty)
select :'o3', null, 'Long product name for testing number ' || lpad(g::text, 3, '0'), 'box', 10, 100, 1
from generate_series(1, 40) g;
select ok(
  (select length(d ->> 'items_text') <= 900 and (d ->> 'items_text') like '%box; …' and (d ->> 'item_count')::int = 41
   from public._notification_order_details(:'o3', 'en') d),
  'items_text 最多 900 字，超过就截到某一样为止，后面加「; …」'
);
-- 名字里的换行、一串空白变成一个空格（WhatsApp 模板参数不能有）；缺货标记按收件人的语言
insert into public.order_items (order_id, product_id, name_snapshot, unit_snapshot, pack_qty_snapshot, unit_price_sen, qty)
values (:'ow_b', null, E'  Cawan\n16oz   PP\t kertas ', 'box', 10, 100, 2);
select is(
  (select d ->> 'items_text' from public._notification_order_details(:'ow_b', 'ms') d),
  'Cawan 16oz PP kertas x2 kotak; W2 16oz 杯 小包 x5 paket (habis stok)',
  'items_text：换行、一串空白变成一个空格；马来文的单位和缺货标记'
);
select is(
  (select d ->> 'items_text' from public._notification_order_details(:'ow_b', 'en') d),
  'Cawan 16oz PP kertas x2 box; W2 16oz 杯 小包 x5 pack (out of stock)',
  '英文的单位和缺货标记'
);
select is(public._unit_label('piece', 'ms') || ',' || public._unit_label('bundle', 'zh') || ',' || public._unit_label('kg', 'en'), 'biji,扎,kg', '单位三语');

-- =============================================================================
-- 权限
-- =============================================================================
select is(
  (select coalesce(string_agg(c.relname, ', '), '')
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  '', 'public 里每张表都还开着 RLS'
);

-- 第四步的函数：登录用户只能直接调用 App 用的这几个（其他的是服务器用的，或者是内部的小函数）
\set seller_fns '''_name_trgms'', ''_trgm_sim'', ''_name_similarity'', ''_name_numbers'', ''_unit_label'', ''get_seller_home'', ''list_seller_orders'', ''get_delivery_summary'', ''suggest_import_matches'', ''apply_price_list_import'', ''_notification_route'', ''_notification_order_details'', ''claim_notifications'', ''complete_notification'', ''remove_device_tokens'', ''register_device_token'', ''handle_whatsapp_button'', ''record_whatsapp_message'', ''update_whatsapp_status'', ''enqueue_daily_summaries'', ''enqueue_unconfirmed_alerts'', ''_request_notification_dispatch'', ''notifications_after_insert'', ''_schedule_seller_jobs'', ''_setup_seller_storage'''
select is(
  (select string_agg(p.proname, ',' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (:seller_fns) and has_function_privilege('authenticated', p.oid, 'execute')),
  'apply_price_list_import,get_delivery_summary,get_seller_home,list_seller_orders,register_device_token',
  '登录用户（authenticated）只能调用 App 用的五个函数'
);
select is(
  (select count(*)::int
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (:seller_fns)
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))),
  0, '没登录（anon）、public 一个都不能调用'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (:seller_fns)),
  25, '（上面检查的函数都存在）'
);

select tests.login_as(tests.uid('seller1'));
select throws_ok(format('select public._notification_order_details(%L, %L)', :'ow_d', 'zh'), '42501', null,
  '普通用户不能读通知用的订单资料（有店的电话、地址）');
select throws_ok(format('select public._notification_route(null, null, %L, %L)', tests.uid('W1'), 'order_new'), '42501', null,
  '普通用户不能查通知渠道（有电话、推送 token）');
select throws_ok(format('select public.suggest_import_matches(%L)', :'imp'), '42501', null, '普通用户不能调用 suggest_import_matches');
select throws_ok('select public.claim_notifications()', '42501', null, '普通用户不能领通知');
select throws_ok(format('select public.complete_notification(%L, %L, %L)', :'n6', 'sent', 'push'), '42501', null, '普通用户不能完成通知');
select throws_ok($$select public.remove_device_tokens(array['x'])$$, '42501', null, '普通用户不能删 token');
select throws_ok(format('select public.handle_whatsapp_button(%L, null, null, %L, %L)', '60122000002', 'CONFIRM:' || :'ow_d', 'wamid.X1'),
  '42501', null, '普通用户不能假装是 WhatsApp 按钮');
select throws_ok($$select public.record_whatsapp_message('6012', 'text', 'x', null, 'wamid.X2', '{}')$$, '42501', null, '普通用户不能写 WhatsApp 消息');
select throws_ok($$select public.update_whatsapp_status('wamid.N2', 'read')$$, '42501', null, '普通用户不能改送达状态');
select throws_ok('select public.enqueue_daily_summaries()', '42501', null, '普通用户不能排每日总结');
select throws_ok('select public.enqueue_unconfirmed_alerts()', '42501', null, '普通用户不能排客服提醒');
select throws_ok('select public._request_notification_dispatch()', '42501', null, '普通用户不能叫 dispatcher');
select tests.login_as(tests.uid('admin'));
select throws_ok('select public.claim_notifications()', '42501', null, '客服也不能领通知（只给服务器）');
-- 就算有 service_role 的权限，身份是普通用户也不行（函数第一行检查）
select set_config('request.jwt.claims', json_build_object('sub', tests.uid('seller1'), 'role', 'authenticated')::text, true);
select set_config('role', 'service_role', true);
select throws_ok('select public.claim_notifications()', '42501', 'NOT_ALLOWED', '函数自己检查是不是服务器在调用');
select tests.logout();

select tests.login_as(tests.uid('buyer1'));
select is((select count(*)::int from public.whatsapp_messages), 0, '买家看不到 WhatsApp 消息');
select is(
  (select count(*)::int from public.notifications where shop_id = tests.uid('S1')) > 0, true, '买家看得到自己店的通知'
);
select tests.login_as(tests.uid('seller1'));
select lives_ok(
  format('update public.wholesalers set whatsapp_opt_in_at = now(), notify_channel = %L where id = %L', 'whatsapp', tests.uid('W1')),
  '批发商自己可以打开「用 WhatsApp 收订单」'
);
select tests.logout();
select ok((select whatsapp_opt_in_at is not null from public.wholesalers where id = tests.uid('W1')), '同意时间记下来了');

-- =============================================================================
-- dispatcher：新增通知时用 pg_net 叫 Edge Function（这里用假的 net / vault 测）
-- （下面故意弄坏 pg_net、重复建 Storage 规则，会有预期中的 WARNING / NOTICE，不显示）
--
-- 本机（scripts/test-db.sh）没有 net / vault / storage / cron，就自己建假的来测。
-- 在真的 Supabase（supabase test db）上这些 schema 已经有了：不能再建、也不能把真的换掉，
-- 改成检查迁移建好的东西，测不了的用 skip（测试数目两边一样）。
-- =============================================================================
set local client_min_messages = error;
select to_regnamespace('net') is null and to_regnamespace('vault') is null as fake_dispatch,
       to_regnamespace('storage') is null as fake_storage,
       to_regnamespace('cron') is null as fake_cron \gset

\if :fake_dispatch
select is(public._request_notification_dispatch(), null::bigint, '没有 pg_net / Vault：跳过，不报错');
create schema net;
create table net.calls (id bigserial primary key, url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds int);
create function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds int default 2000
) returns bigint language sql as $$
  insert into net.calls (url, body, params, headers, timeout_milliseconds)
  values (http_post.url, http_post.body, http_post.params, http_post.headers, http_post.timeout_milliseconds)
  returning id;
$$;
create schema vault;
create table vault.decrypted_secrets (name text primary key, decrypted_secret text);

insert into public.notifications (wholesaler_id, event_type) values (tests.uid('W1'), 'test');
select is((select count(*)::int from net.calls), 0, 'Vault 里还没有秘密：跳过');
insert into vault.decrypted_secrets values ('project_url', 'https://abc.supabase.co/'), ('secret_key', 'sb_secret_test');
insert into public.notifications (wholesaler_id, event_type) values (tests.uid('W1'), 'test');
select is(
  (select url || ' ' || (headers ->> 'apikey') || ' ' || (headers ->> 'Content-Type') || ' ' || body::text || ' ' || timeout_milliseconds
   from net.calls order by id desc limit 1),
  'https://abc.supabase.co/functions/v1/dispatch-notifications sb_secret_test application/json {} 10000',
  '新增通知：马上叫 dispatcher（secret key 放 apikey 头，等 10 秒）'
);
insert into public.notifications (wholesaler_id, event_type) values (tests.uid('W1'), 'a'), (tests.uid('W1'), 'b');
select is((select count(*)::int from net.calls), 2, '一次新增几条只叫一次');

select tests.login_as(tests.uid('buyer1'));
select tests.add_to_cart('S1', 'P3', 5);
select lives_ok(format('select public.place_order(%L)', tests.uid('S1')), '买家下单');
select tests.logout();
select is((select count(*)::int from net.calls), 3, '买家下单产生的通知也会叫 dispatcher');

update public.notifications set status = 'sent';
select is(public._request_notification_dispatch(true), null::bigint, '定时任务：没有要发的就不叫');
update public.notifications set status = 'queued' where id = :'n6';
select isnt(public._request_notification_dispatch(true), null::bigint, '定时任务：有要发的才叫');

create or replace function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds int default 2000
) returns bigint language plpgsql as $$ begin raise exception 'pg_net is broken'; end; $$;
select lives_ok(
  format('insert into public.notifications (wholesaler_id, event_type) values (%L, %L)', tests.uid('W1'), 'test'),
  'pg_net 出错也不会挡住新增通知（下单）'
);
\else
select skip('Supabase 平台已经有 pg_net / Vault：不换成假的，dispatcher 在这里不测', 9);
\endif

-- =============================================================================
-- Storage（这里用假的 storage schema 测 bucket 和规则）
-- =============================================================================
\if :fake_storage
select is(public._setup_seller_storage(), false, '没有 storage schema：跳过');
create schema storage;
create table storage.buckets (
  id text primary key, name text not null, public boolean not null default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id),
  name text not null, owner uuid default auth.uid()
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language plpgsql as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end;
$$;
grant usage on schema storage to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;

select ok(public._setup_seller_storage(), '有 storage：建 bucket 和规则');
select ok(public._setup_seller_storage(), '可以重复跑');
select is(
  (select string_agg(id || ':' || public || ':' || file_size_limit || ':' || cardinality(allowed_mime_types), ',' order by id)
   from storage.buckets where id in ('price-lists', 'product-photos')),
  'price-lists:false:10485760:7,product-photos:true:5242880:3', '价目表私人 10 MB；商品照片公开 5 MB'
);

select tests.login_as(tests.uid('seller1'));
select lives_ok(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'price-lists', tests.uid('W1') || '/a.jpg'),
  '批发商上传价目表到自己的文件夹'
);
select lives_ok(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'product-photos', tests.uid('W1') || '/p.jpg'),
  '批发商上传商品照片到自己的文件夹'
);
select throws_ok(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'price-lists', tests.uid('W2') || '/a.jpg'),
  '42501', null, '不能上传到别家批发商的文件夹'
);
select throws_ok(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'price-lists', 'not-a-uuid/a.jpg'),
  '42501', null, '文件夹不是批发商 id 也不行（不会因为不是 uuid 报别的错）'
);
select is((select count(*)::int from storage.objects), 2, '批发商看得到自己的文件');
select tests.login_as(tests.uid('seller2'));
select is((select count(*)::int from storage.objects), 0, '别家批发商看不到');
select is(
  (select count(*)::int from (
     select 1 from storage.objects where bucket_id = 'price-lists'
   ) x), 0, '别家批发商也读不到价目表');
update storage.objects set name = tests.uid('W2') || '/stolen.jpg';
delete from storage.objects;
select tests.login_as(tests.uid('buyer1'));
select throws_ok(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'product-photos', tests.uid('W1') || '/x.jpg'),
  '42501', null, '买家不能上传'
);
select tests.login_as(tests.uid('admin'));
select is((select count(*)::int from storage.objects), 2, '客服看得到全部（别家改不到、删不到）');
select tests.login_as(tests.uid('seller1'));
select lives_ok(format('delete from storage.objects where name = %L', tests.uid('W1') || '/a.jpg'), '批发商删自己的文件');
select is((select count(*)::int from storage.objects), 1, '删掉了');
\else
-- 真的 Supabase：迁移已经建好 bucket 和规则
select ok(public._setup_seller_storage(), '有 storage：建 bucket 和规则（可以重复跑）');
select is(
  (select string_agg(id || ':' || public || ':' || file_size_limit || ':' || cardinality(allowed_mime_types), ',' order by id)
   from storage.buckets where id in ('price-lists', 'product-photos')),
  'price-lists:false:10485760:7,product-photos:true:5242880:3', '价目表私人 10 MB；商品照片公开 5 MB'
);
select is(
  (select string_agg(policyname, ',' order by policyname) from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and policyname like 'seller files:%'),
  'seller files: admin full access,seller files: member delete,seller files: member read,seller files: member update,seller files: member upload',
  'storage.objects 上的五条规则都建好了'
);
select skip('真的 Storage：上传 / 读取的规则要经过 Storage API，在这里不测', 12);
\endif

-- =============================================================================
-- 定时任务（这里用假的 cron.schedule 测）
-- =============================================================================
select tests.logout();
\if :fake_cron
select is(public._schedule_seller_jobs(), false, '没有 pg_cron：跳过');
create schema cron;
create table cron.test_jobs (jobname text primary key, schedule text, command text);
create function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $$
  insert into cron.test_jobs values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command;
  select 1::bigint;
$$;
select ok(public._schedule_seller_jobs(), '有 pg_cron：建定时任务');
select is(
  (select string_agg(jobname || ' | ' || schedule || ' | ' || command, E'\n' order by jobname) from cron.test_jobs),
  'daily-delivery-summary | 30 21 * * * | select public.enqueue_daily_summaries()' || E'\n'
  || 'dispatch-notifications | * * * * * | select public._request_notification_dispatch(true)' || E'\n'
  || 'unconfirmed-order-alerts | */5 * * * * | select public.enqueue_unconfirmed_alerts()',
  '三个定时任务：每天 05:30（马来西亚）总结、每 5 分钟客服提醒、每分钟补发通知'
);
\else
-- 真的 pg_cron（Supabase）：迁移已经建好；再跑一次是更新同名的
select ok(public._schedule_seller_jobs(), '有 pg_cron：建定时任务（同名的会更新）');
select is(
  (select string_agg(jobname || ' | ' || schedule || ' | ' || command, E'\n' order by jobname) from cron.job
   where jobname in ('daily-delivery-summary', 'dispatch-notifications', 'unconfirmed-order-alerts')),
  'daily-delivery-summary | 30 21 * * * | select public.enqueue_daily_summaries()' || E'\n'
  || 'dispatch-notifications | * * * * * | select public._request_notification_dispatch(true)' || E'\n'
  || 'unconfirmed-order-alerts | */5 * * * * | select public.enqueue_unconfirmed_alerts()',
  '三个定时任务：每天 05:30（马来西亚）总结、每 5 分钟客服提醒、每分钟补发通知'
);
select skip('真的 pg_cron：「没有 pg_cron 就跳过」在这里不测', 1);
\endif

select * from finish();
rollback;
