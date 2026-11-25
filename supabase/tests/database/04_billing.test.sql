-- 收费：佣金账单、试用 / 订阅到期、价钱跟着账号锁定、创始会员名额
begin;
\ir _helpers.psql
select plan(23);
select tests.setup_world();

-- 先做几张已送达的订单（用服务器身份：等于客服代下单、WhatsApp 按确认）
--   S1 -> W1：P1 1 箱 RM85（佣金 1.5% = 128 仙）
--   S1 -> W2：P3 5 包 RM24（佣金 3% = 72 仙）
--   S2 -> W1：P1 2 箱 RM170（佣金 1.5% = 255 仙）
select tests.add_to_cart('S1', 'P1', 1);
select tests.add_to_cart('S1', 'P3', 5);
select public.place_order(tests.uid('S1'));
select tests.add_to_cart('S2', 'P1', 2);
select public.place_order(tests.uid('S2'));
select public.confirm_order(o.id) from public.orders o where o.shop_id in (tests.uid('S1'), tests.uid('S2'));
select public.set_order_status(o.id, 'delivered') from public.orders o where o.shop_id in (tests.uid('S1'), tests.uid('S2'));

-- ---------- 月底佣金账单 ----------
select tests.login_as(tests.uid('seller1'));
select throws_ok('select public.generate_commission_invoices()', '42501', 'NOT_ALLOWED', '批发商不能自己开账单');

select tests.login_as(tests.uid('admin'));
select ok(public.generate_commission_invoices(date_trunc('month', public.today_myt())::date) >= 2, '客服生成这个月的账单');
select is(
  (select status || '/' || order_count || '/' || gmv_sen || '/' || commission_sen
   from public.commission_invoices where wholesaler_id = tests.uid('W1')),
  'draft/2/25500/383', 'W1 的账单：2 张单，货价 RM255，佣金 RM3.83（草稿，等客服发出）'
);
select matches((select invoice_no from public.commission_invoices where wholesaler_id = tests.uid('W1')), '^INV\d{4}-\d{4}$', '账单号');
select lives_ok(format('select public.generate_commission_invoices(%L)', date_trunc('month', public.today_myt())::date), '重复跑没问题');
select is((select commission_sen from public.commission_invoices where wholesaler_id = tests.uid('W1')), 383::bigint, '重复跑不会重复算');

select tests.login_as(tests.uid('seller1'));
select is((select count(*)::int from public.commission_invoices), 1, 'W1 只看到自己的账单');
select is((select count(*)::int from public.commission_records), 2, 'W1 看得到自己每一张单的佣金');
select tests.login_as(tests.uid('buyer1'));
select is((select count(*)::int from public.commission_invoices) + (select count(*)::int from public.commission_records), 0,
  '买家看不到佣金');

-- 账单发出之后才送达的订单：不改已发出的账单，留到下一张
select tests.login_as(tests.uid('admin'));
update public.commission_invoices set status = 'issued', issued_at = now() where wholesaler_id = tests.uid('W1');
select tests.logout();
select tests.add_to_cart('S1', 'P1', 1);
select public.place_order(tests.uid('S1'));
select public.confirm_order(tests.order_of('S1', 'W1'));
select public.set_order_status(tests.order_of('S1', 'W1'), 'delivered');
select public.generate_commission_invoices(date_trunc('month', public.today_myt())::date);
select is((select commission_sen from public.commission_invoices where wholesaler_id = tests.uid('W1')), 383::bigint,
  '已发出的账单不会被改');
select public.generate_commission_invoices((date_trunc('month', public.today_myt()) + interval '1 month')::date);
select is(
  (select order_count || '/' || commission_sen from public.commission_invoices
   where wholesaler_id = tests.uid('W1') and period_month = (date_trunc('month', public.today_myt()) + interval '1 month')::date),
  '1/128', '晚到的那张单算进下一张账单'
);

-- ---------- 试用到期 ----------
update public.subscriptions set trial_ends_at = now() - interval '1 minute' where shop_id = tests.uid('S1');
select is((public.run_subscription_maintenance() ->> 'trial_lapsed')::int >= 1, true, '每天的维护把到期的试用停掉');
select is((select status::text from public.subscriptions where shop_id = tests.uid('S1')), 'lapsed', 'S1 试用结束没付费 -> 已停');
select is(
  (select array_agg(w.name order by w.name) from public.unlocked_wholesalers u join public.wholesalers w on w.id = u.wholesaler_id
   where u.shop_id = tests.uid('S1')),
  array['W1 创始批发商', 'W2 普通批发商'], '自动帮他选最近买过的批发商作为免费可看'
);
select tests.login_as(tests.uid('buyer1'));
select is(public.get_subscription_status(tests.uid('S1')) ->> 'has_full_access', 'false', '试用结束后不能看全部价钱');
select is(
  (select count(*)::int from public.get_offers(tests.uid('S1')) where price_visible),
  3, '只看得到自动选的 W1、W2 的商品价钱'
);

-- ---------- 付费订阅到期：宽限期内照样能用 ----------
select tests.logout();
update public.subscriptions
set status = 'active', current_period_start = now() - interval '31 days', current_period_end = now() - interval '1 day'
where shop_id = tests.uid('S2');
select public.run_subscription_maintenance();
select is(
  (select status::text || '/' || (grace_until = current_period_end + interval '7 days') from public.subscriptions where shop_id = tests.uid('S2')),
  'past_due/true', '到期没付 -> 逾期，宽限 7 天'
);
select is(public.has_full_access(tests.uid('S2')), true, '宽限期内还能用全部功能（补付就保留原价）');
update public.subscriptions set grace_until = now() - interval '1 minute' where shop_id = tests.uid('S2');
select public.run_subscription_maintenance();
select is(
  (select status::text || '/' || public.has_full_access(tests.uid('S2'))::text from public.subscriptions where shop_id = tests.uid('S2')),
  'lapsed/false', '过了宽限期 -> 已停'
);

-- ---------- 价钱跟着账号锁定 ----------
insert into public.pricing_plans (plan_code, amount_sen, is_founding, effective_from)
values ('buyer_monthly', 6000, false, now() - interval '1 minute');
insert into auth.users (id, phone) values ('aaaaaaaa-0000-4000-8000-000000000301', '60111000301');
select tests.login_as('aaaaaaaa-0000-4000-8000-000000000301');
select public.register_shop('新开的店', tests.uid('Z1')) as new_shop \gset
select is(
  (select (s -> 'subscription' ->> 'locked_price_sen') || '/' || (s -> 'subscription' ->> 'is_founding_price')
   from public.get_subscription_status(:'new_shop') s),
  '6000/false', '涨价后才注册的店：按新价钱 RM60 锁定，不是创始价'
);
select tests.logout();
select is((select locked_price_sen from public.subscriptions where shop_id = tests.uid('S1')), 5000,
  '早期的店还是锁定 RM50');
select throws_ok(
  format($$insert into public.subscriptions (shop_id, status, locked_price_sen) values (%L, 'active', 5000)$$, :'new_shop'),
  '23505', null, '一家店同时只能有一条还没停的订阅'
);

-- ---------- 创始会员名额 ----------
update public.app_settings set founding_wholesaler_quota = (select count(*) from public.wholesalers where is_founding);
select throws_ok(
  format($$update public.wholesalers set is_founding = true where id = %L$$, tests.uid('W2')),
  'P0001', 'FOUNDING_QUOTA_FULL', '创始会员名额满了就不能再加'
);

select * from finish();
rollback;
