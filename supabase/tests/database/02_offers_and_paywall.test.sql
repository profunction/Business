-- 比价和付费检查：试用中看得到全部价钱；未付费只看得到自己选的 3 家
begin;
\ir _helpers.psql
select plan(19);
select tests.setup_world();

-- ---------- 试用中（S1）----------
select tests.login_as(tests.uid('buyer1'));

select is(
  (select count(*)::int from public.get_offers(tests.uid('S1'), p_catalog_item_id => 'bbbbbbbb-0000-4000-8000-000000000041')),
  3, '同一样杯子有 3 家可以比（W4 还没审核、W1 的草稿都不算）'
);
select is(
  (select array_agg(wholesaler_name order by rn) from (
    select wholesaler_name, row_number() over () as rn
    from public.get_offers(tests.uid('S1'), p_catalog_item_id => 'bbbbbbbb-0000-4000-8000-000000000041')
  ) x),
  array['W3 特别比例', 'W1 创始批发商', 'W2 普通批发商'],
  '按「每个多少钱」排：W3 8.2 仙 < W1 8.5 仙 < W2 9.6 仙（只比箱价会排错）'
);
select is(
  (select price_per_base_unit_sen from public.get_offers(tests.uid('S1'), p_wholesaler_id => tests.uid('W2'))),
  9.60, '50 个一包 RM4.80 = 每个 9.6 仙'
);
select ok(
  (select bool_and(price_visible and price_sen is not null) from public.get_offers(tests.uid('S1'))),
  '试用中全部价钱都看得到'
);
select is(
  (select shipping_fee_sen || '/' || free_shipping_min_sen || '/' || min_order_sen || '/' || lead_time_days
   from public.get_offers(tests.uid('S1'), p_wholesaler_id => tests.uid('W1')) limit 1),
  '800/15000/5000/1', '同时显示运费、免运费门槛、最低消费、几天送到'
);
select is(
  (select count(*)::int from public.get_offers(tests.uid('S1'), p_search => '平盖')),
  2, '可以用名字搜索'
);
select throws_ok(
  $$select * from public.get_offers('dddddddd-0000-4000-8000-000000000002')$$,
  '42501', 'NOT_ALLOWED', '不能用别家店的身份看价钱'
);
select is(
  (select (s ->> 'has_full_access') || '/' || (s -> 'subscription' ->> 'status') || '/' || (s -> 'subscription' ->> 'locked_price_sen')
   from public.get_subscription_status(tests.uid('S1')) s),
  'true/trialing/5000', '试用中，月费锁定 RM50'
);

-- ---------- 未付费（S3）----------
select tests.login_as(tests.uid('buyer3'));

select ok(
  (select bool_and(not price_visible and price_sen is null and price_per_base_unit_sen is null)
   from public.get_offers(tests.uid('S3'))),
  '未付费又没选批发商：价钱全部是空的（服务器根本不发出去）'
);
select lives_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000003', array['cccccccc-0000-4000-8000-000000000001']::uuid[])$$,
  '未付费用户选 W1 作为免费可看'
);
select is(
  (select array_agg(wholesaler_name || ':' || coalesce(price_sen::text, '-') order by wholesaler_name)
   from public.get_offers(tests.uid('S3'), p_catalog_item_id => 'bbbbbbbb-0000-4000-8000-000000000041')),
  array['W1 创始批发商:8500', 'W2 普通批发商:-', 'W3 特别比例:-'],
  '只有选了的 W1 看得到价钱'
);
select is(
  (select wholesaler_name from public.get_offers(tests.uid('S3'), p_catalog_item_id => 'bbbbbbbb-0000-4000-8000-000000000041') limit 1),
  'W1 创始批发商', '看得到价钱的排在前面'
);
select lives_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000003',
      array['cccccccc-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000003']::uuid[])$$,
  '第一次换（拿掉 W1、加 W2 和 W3）可以'
);
select throws_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000003',
      array['cccccccc-0000-4000-8000-000000000001']::uuid[])$$,
  'P0001', 'UNLOCK_COOLDOWN', '30 天内不能再换'
);
select lives_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000003',
      array['cccccccc-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000001']::uuid[])$$,
  '只是补满空位（不拿掉已选的）随时可以'
);
select throws_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000003',
      array['cccccccc-0000-4000-8000-000000000004']::uuid[])$$,
  'P0001', 'WHOLESALER_NOT_AVAILABLE', '不能选还没审核的批发商'
);

select tests.logout();
update public.app_settings set free_unlocked_wholesalers = 1;
select tests.login_as(tests.uid('buyer3'));
select throws_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000002',
      array['cccccccc-0000-4000-8000-000000000001']::uuid[])$$,
  '42501', 'NOT_ALLOWED', '不能帮别家店选'
);
select throws_ok(
  $$select public.set_unlocked_wholesalers('dddddddd-0000-4000-8000-000000000003',
      array['cccccccc-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000002']::uuid[])$$,
  'P0001', 'TOO_MANY_WHOLESALERS', '超过免费家数会被拒绝'
);

-- ---------- 一个手机号只能试用一次 ----------
select tests.login_as(tests.uid('buyer1'));
select public.register_shop('S1 的第二间分店', tests.uid('Z1')) as second_shop \gset
select is(
  public.get_subscription_status(:'second_shop') ->> 'has_full_access',
  'false', '同一个手机号开第二间店，不会再送试用'
);

select tests.logout();
select * from finish();
rollback;
