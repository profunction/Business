-- 权限测试：RLS、受保护字段、注册时的角色、自动接上客服建好的批发商
begin;
\ir _helpers.psql
select plan(27);
select tests.setup_world();

-- ---------- 每张表都开了 RLS ----------
select is(
  (select coalesce(string_agg(c.relname, ', '), '')
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  '',
  'public 里每张表都开了 RLS'
);

-- ---------- 注册时的角色 ----------
insert into auth.users (id, phone, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000201', '0121110201', '{"role": "admin"}'),
  ('aaaaaaaa-0000-4000-8000-000000000202', '+60 12-111 0202', '{"role": "seller", "locale": "ms"}');

select is((select role::text from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000201'), 'buyer',
  '注册时自己填 admin 没用，还是买家');
select is((select phone from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000201'), '60121110201',
  '手机号统一成 60 开头');
select is((select role::text || '/' || locale::text from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000202'),
  'seller/ms', '注册时可以选批发商和语言');

-- 客服先建好批发商（没装 App），老板之后用同一个号码登录就自动接上
insert into public.wholesalers (id, name, industry_id, region_id, phone, status)
values ('cccccccc-0000-4000-8000-000000000201', '客服建的批发商', 'bbbbbbbb-0000-4000-8000-000000000021',
        'bbbbbbbb-0000-4000-8000-000000000001', '012-111 0203', 'active');
insert into auth.users (id, phone) values ('aaaaaaaa-0000-4000-8000-000000000203', '60121110203');
select ok(
  exists (select 1 from public.wholesaler_members
          where wholesaler_id = 'cccccccc-0000-4000-8000-000000000201'
            and user_id = 'aaaaaaaa-0000-4000-8000-000000000203' and member_role = 'owner'),
  '同一个手机号登录，自动成为客服建好的批发商的老板'
);
select is((select role::text from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000203'), 'seller',
  '接上批发商的账号自动变成卖家');

-- ---------- 受保护字段 ----------
select tests.login_as(tests.uid('buyer1'));
select throws_ok(
  $$update public.profiles set role = 'admin' where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '42501', 'COLUMN_PROTECTED', '买家不能把自己改成客服'
);
select lives_ok(
  $$update public.profiles set full_name = '阿明', locale = 'en' where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '买家可以改自己的名字和语言'
);
select is((select count(*)::int from public.profiles), 1, '买家只看到自己的资料');

select tests.login_as(tests.uid('seller2'));
select throws_ok(
  $$update public.wholesalers set status = 'suspended' where id = 'cccccccc-0000-4000-8000-000000000002'$$,
  '42501', 'COLUMN_PROTECTED', '批发商不能改自己的审核状态'
);
select throws_ok(
  $$update public.wholesaler_private set commission_rate_override = 0 where wholesaler_id = 'cccccccc-0000-4000-8000-000000000002'$$,
  '42501', 'COLUMN_PROTECTED', '批发商不能改自己的佣金比例'
);
select lives_ok(
  $$update public.wholesalers set description = '新介绍', order_cutoff_time = '16:00' where id = 'cccccccc-0000-4000-8000-000000000002'$$,
  '批发商可以改自己的介绍和截单时间'
);
select is(
  (select count(*)::int from public.wholesalers where id = 'cccccccc-0000-4000-8000-000000000001' and description = '新介绍'),
  0, '批发商改不到别家的资料'
);
select lives_ok(
  $$update public.wholesalers set description = '偷改' where id = 'cccccccc-0000-4000-8000-000000000001'$$,
  '改别家资料不会报错，但一行都改不到'
);
select tests.logout();
select isnt((select description from public.wholesalers where id = tests.uid('W1')), '偷改', '别家的资料确实没被改');

-- ---------- 看得到什么 ----------
select tests.login_as(tests.uid('buyer1'));
select is((select count(*)::int from public.products), 0, '买家不能直接查商品表（价钱要走 get_offers）');
select is(
  (select count(*)::int from public.wholesalers where region_id = 'bbbbbbbb-0000-4000-8000-000000000001'),
  4, '买家看得到已上架的批发商（W1-W3 和客服建的那家），看不到待审核的 W4'
);
select is((select count(*)::int from public.wholesaler_private), 0, '买家看不到批发商的佣金比例和账单资料');
select is((select count(*)::int from public.shops), 1, '买家只看到自己的店');
select throws_ok(
  $$insert into public.orders (order_no, checkout_id, shop_id, wholesaler_id, zone_id, goods_subtotal_sen, shipping_fee_sen, source)
    values ('X', gen_random_uuid(), 'dddddddd-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001',
            'bbbbbbbb-0000-4000-8000-000000000011', 1, 0, 'app')$$,
  '42501', null, '买家不能直接写订单表（要用 place_order）'
);
select throws_ok(
  $$select public._quote_cart('dddddddd-0000-4000-8000-000000000001')$$,
  '42501', null, '买家不能调用内部函数'
);

select tests.login_as(tests.uid('seller1'));
select is((select count(*)::int from public.products), 3, '批发商看得到自己全部的商品（包括草稿）');
select is((select count(*)::int from public.products where wholesaler_id <> tests.uid('W1')), 0, '批发商看不到别家的商品');
select is((select count(*)::int from public.shops), 0, '还没人下单时，批发商看不到任何店');

select tests.login_as(tests.uid('admin'));
select is((select count(*)::int from public.products where wholesaler_id in (tests.uid('W1'), tests.uid('W2'))), 4,
  '客服看得到全部商品');

select tests.login_as_anon();
select is((select count(*)::int from public.wholesalers), 0, '没登录什么都看不到');
select throws_ok(
  $$select public.get_offers('dddddddd-0000-4000-8000-000000000001')$$,
  '42501', null, '没登录不能调用 App 的函数'
);

select tests.logout();
select * from finish();
rollback;
