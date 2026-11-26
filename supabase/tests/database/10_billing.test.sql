-- 第七步：收费。付款单（开单 / 网关单号 / 已付，重复通知只算一次）、月费续费从哪天算、价钱锁定、
-- 宽限期、停了再回来按新价、创始上架费、每月佣金账单自动发出 / 逾期 / 提醒、买家快到期提醒、只用推送、权限
begin;
\ir _helpers.psql
select plan(107);
select tests.setup_world();

-- 开单 + 网关单号 + 付款页（服务器身份，跟 create-payment 一样）。回传付款单 id
create function tests.intent(p_user text, p_purpose public.payment_purpose, p_target uuid, p_months int default 1)
returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  v := public.create_payment_intent(tests.uid(p_user), p_purpose, p_target, p_months);
  if v ->> 'result' <> 'ok' then
    raise exception 'intent failed: %', v;
  end if;
  if not (v -> 'reuse')::boolean then
    perform public.attach_payment_checkout((v -> 'payment' ->> 'id')::uuid, 'HP-' || (v -> 'payment' ->> 'id'),
      'https://pay.test/' || (v -> 'payment' ->> 'id'));
  end if;
  return (v -> 'payment' ->> 'id')::uuid;
end;
$$;
-- 网关说「已付」（金额照付款单）
create function tests.paid(p_payment uuid, p_amount int default null) returns jsonb language sql as $$
  select public.mark_payment_paid(p.id, 'hitpay', p.gateway_ref, coalesce(p_amount, p.amount_sen), 'fpx', '{"test": true}')
  from public.payments p where p.id = p_payment;
$$;
create function tests.sub(p_shop text) returns public.subscriptions language sql stable as $$
  select * from public.subscriptions where shop_id = tests.uid(p_shop) order by created_at desc, (status <> 'lapsed') desc limit 1;
$$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- =============================================================================
-- 权限
-- =============================================================================
select tests.login_as(tests.uid('buyer1'));
select throws_ok(format('select public.create_payment_intent(%L, %L, %L)', tests.uid('buyer1'), 'subscription', tests.uid('S1')),
  '42501', null, '买家不能自己开付款单（要经过 create-payment）');
select throws_ok(format('select public.mark_payment_paid(%L, %L, %L, 5000)', gen_random_uuid(), 'hitpay', 'x'),
  '42501', null, '买家不能自己标已付');
select throws_ok(format('select public.attach_payment_checkout(%L, %L, %L)', gen_random_uuid(), 'x', 'https://x'),
  '42501', null, '买家不能改付款页');
select is(tests.error_of('select public.admin_list_payments()'), 'NOT_ALLOWED', '买家不能看全部付款');
select is(tests.error_of(format('select public.get_seller_billing(%L)', tests.uid('W1'))), 'NOT_ALLOWED', '买家不能看批发商的收费');
select is(tests.error_of('select public.run_billing_daily()'), 'NOT_ALLOWED', '买家不能跑收费工作');
select tests.login_as(tests.uid('buyer2'));
select is(tests.error_of(format('select public.get_buyer_billing(%L)', tests.uid('S1'))), 'NOT_ALLOWED', '别家店看不到我的订阅');
select tests.logout();
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('_extend_subscription', '_payment_json', 'create_payment_intent', 'attach_payment_checkout',
        'fail_payment', 'mark_payment_paid', 'get_payment', 'get_buyer_billing', 'get_seller_billing',
        'get_commission_invoice', 'admin_list_payments', 'admin_mark_listing_fee_paid', '_issue_invoice', 'run_billing_daily')
      and (has_function_privilege('anon', p.oid, 'execute') or not p.prosecdef
           or not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false))
  ),
  '新函数：security definer、固定 search_path、anon 不能叫'
);
select ok(not has_function_privilege('authenticated', 'public._extend_subscription(uuid, int, int, boolean, uuid, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public._issue_invoice(uuid)', 'execute'), '内部小工具 App 叫不到');
select ok(has_function_privilege('service_role', 'public.mark_payment_paid(uuid, text, text, int, public.payment_method, jsonb)', 'execute'),
  '服务器可以标已付');

-- =============================================================================
-- 开付款单：月费
-- =============================================================================
select is(public.create_payment_intent(tests.uid('buyer2'), 'subscription', tests.uid('S1')) ->> 'result', 'not_allowed',
  '别家店的老板不能替我开');
select is(public.create_payment_intent(tests.uid('buyer1'), 'subscription', tests.uid('S1'), 13) ->> 'result', 'invalid',
  '最多 12 个月');
select is(public.create_payment_intent(tests.uid('buyer1'), 'subscription', gen_random_uuid()) ->> 'result', 'not_found',
  '没有这家店');
select is(public.create_payment_intent(tests.uid('buyer1'), 'subscription', tests.uid('S1'), 1, 'bad gateway!') ->> 'result',
  'invalid', '网关名字不对');

select public.create_payment_intent(tests.uid('buyer1'), 'subscription', tests.uid('S1'), 3) as i1 \gset
select is(:'i1'::jsonb -> 'payment' ->> 'amount_sen', '15000', '试用中（锁定 RM50）付 3 个月 = RM150');
select is(:'i1'::jsonb -> 'payment' ->> 'reference_id', (tests.sub('S1')).id::text, '对到现在这条订阅');
select is(:'i1'::jsonb -> 'payment' ->> 'checkout_url', null, '还没去网关：没有付款页');
select isnt(public.create_payment_intent(tests.uid('buyer1'), 'subscription', tests.uid('S1'), 3) -> 'payment' ->> 'id',
  :'i1'::jsonb -> 'payment' ->> 'id', '还没有付款页的不拿出来重用（重新开一张，免得拿到网关开失败的）');
select ok(public.attach_payment_checkout((:'i1'::jsonb -> 'payment' ->> 'id')::uuid, 'HP-1', 'https://pay.test/1'), '记下网关单号');
select ok(not public.attach_payment_checkout((:'i1'::jsonb -> 'payment' ->> 'id')::uuid, 'HP-2', 'https://pay.test/2'),
  '网关单号只能记一次');
select is(tests.error_of(format('select public.attach_payment_checkout(%L, %L, %L)', :'i1'::jsonb -> 'payment' ->> 'id', 'HP-3',
  'http://insecure')), 'INVALID_CHECKOUT', '付款页一定要 https');
select public.create_payment_intent(tests.uid('buyer1'), 'subscription', tests.uid('S1'), 3) as i1b \gset
select is(:'i1b'::jsonb ->> 'reuse', 'true', '同样的东西再按一次：拿回同一张');
select is(:'i1b'::jsonb -> 'payment' ->> 'checkout_url', 'https://pay.test/1', '同一个付款页');
select isnt(public.create_payment_intent(tests.uid('buyer1'), 'subscription', tests.uid('S1'), 1) -> 'payment' ->> 'id',
  :'i1'::jsonb -> 'payment' ->> 'id', '月数不同 → 另一张');

-- =============================================================================
-- 网关说已付
-- =============================================================================
select (:'i1'::jsonb -> 'payment' ->> 'id') as p1 \gset
select is(public.mark_payment_paid(:'p1', 'billplz', 'HP-1', 15000) ->> 'result', 'mismatch', '网关不对：不算');
select is(public.mark_payment_paid(:'p1', 'hitpay', 'HP-999', 15000) ->> 'result', 'mismatch', '网关单号不对：不算');
select is(public.mark_payment_paid(gen_random_uuid(), 'hitpay', 'HP-1', 15000) ->> 'result', 'not_found', '没有这张付款单');
select (tests.sub('S1')).trial_ends_at as trial_end \gset
select is(public.mark_payment_paid(:'p1', 'hitpay', 'HP-1', 15000, 'fpx', '{"id": "HP-1"}') ->> 'result', 'paid', '已付');
select is((tests.sub('S1')).status::text || '/' || (tests.sub('S1')).locked_price_sen, 'active/5000', '试用 → active，价钱不变');
select is((tests.sub('S1')).current_period_start, :'trial_end'::timestamptz, '从试用结束那天开始算（试用的天数不会少）');
select is((tests.sub('S1')).current_period_end, :'trial_end'::timestamptz + interval '3 months', '加 3 个月');
select is((select status::text || '/' || method || '/' || (period_end = (tests.sub('S1')).current_period_end)
           from public.payments where id = :'p1'), 'paid/fpx/true', '付款单记下方法和付的是哪一段');
select is(public.mark_payment_paid(:'p1', 'hitpay', 'HP-1', 15000) ->> 'result', 'already_paid', '网关重复通知：只算一次');
select is((tests.sub('S1')).current_period_end, :'trial_end'::timestamptz + interval '3 months', '重复通知不会再加');
select is((select count(*)::int from public.notifications where shop_id = tests.uid('S1') and event_type = 'payment_received'), 1,
  '推送「收到付款」一次');

-- 一直续费：从这期结束接着算，锁定价不变（就算现在的月费涨了）
insert into public.pricing_plans (plan_code, amount_sen, is_founding, effective_from) values ('buyer_monthly', 6000, false, now() - interval '1 minute');
select (tests.sub('S1')).current_period_end as end1 \gset
select tests.login_as(tests.uid('buyer1'));
select is((public.get_buyer_billing(tests.uid('S1')) ->> 'renew_price_sen')::int, 5000, '月费涨到 RM60，我续费还是 RM50');
select is(public.get_buyer_billing(tests.uid('S1')) ->> 'price_locked', 'true', '显示「价钱锁定」');
select is(jsonb_array_length(public.get_buyer_billing(tests.uid('S1')) -> 'payments'), 1, '看得到付过的');
select tests.logout();
select tests.paid(tests.intent('buyer1', 'subscription', tests.uid('S1'))) ->> 'result' as r \gset
select is((tests.sub('S1')).current_period_end, :'end1'::timestamptz + interval '1 month', '续 1 个月：从上期结束接着算');
select is((tests.sub('S1')).locked_price_sen, 5000, '还是 RM50');

-- 逾期（宽限期内）补付：从原来的结束日算，原价保留
update public.subscriptions set current_period_end = now() - interval '2 days' where id = (tests.sub('S1')).id;
select public.run_subscription_maintenance();
select is((tests.sub('S1')).status::text, 'past_due', '过期没付 → 逾期');
select (tests.sub('S1')).current_period_end as end2 \gset
select tests.intent('buyer1', 'subscription', tests.uid('S1')) as p2 \gset
select is((select amount_sen from public.payments where id = :'p2'), 5000, '宽限期内：还是锁定的 RM50');
select is(tests.paid(:'p2') ->> 'result', 'paid', '补付');
select is((tests.sub('S1')).status::text || '/' || ((tests.sub('S1')).current_period_end = :'end2'::timestamptz + interval '1 month'),
  'active/true', '回到 active，从原来的结束日接着算');

-- 开了付款页（宽限期内），等到停了才付：钱照旧价收了 → 重新打开原来那条，价钱还是锁定的
update public.subscriptions set current_period_end = now() - interval '6 days' where id = (tests.sub('S1')).id;
select public.run_subscription_maintenance();
select tests.intent('buyer1', 'subscription', tests.uid('S1')) as p3 \gset
-- （测试在一个交易里，now() 不会走；把开单时间往前放，才看得出「开单之后才停」）
update public.payments set created_at = now() - interval '1 hour' where id = :'p3';
update public.subscriptions set grace_until = now() - interval '1 minute' where id = (tests.sub('S1')).id;
select public.run_subscription_maintenance();
select is((tests.sub('S1')).status::text, 'lapsed', '过了宽限期 → 已停');
select (tests.sub('S1')).id as s1_id \gset
select is(tests.paid(:'p3') ->> 'result', 'paid', '晚到的付款照样收');
select is((select status::text || '/' || locked_price_sen || '/' || (id = :'s1_id')::text from public.subscriptions
           where shop_id = tests.uid('S1') and status <> 'lapsed'), 'active/5000/true', '重新打开原来那条，RM50 不变');

-- 宽限期过了、定时任务还没跑：开单就按新价钱；付了 → 旧的停掉、新建一条
update public.subscriptions set status = 'past_due', current_period_end = now() - interval '8 days',
  grace_until = now() - interval '1 hour' where id = (tests.sub('S1')).id;
select tests.intent('buyer1', 'subscription', tests.uid('S1')) as p3b \gset
select is((select amount_sen || '/' || coalesce(reference_id::text, 'new') from public.payments where id = :'p3b'), '6000/new',
  '宽限期过了：按现在的 RM60');
select is(tests.paid(:'p3b') ->> 'result', 'paid', '付了');
select is((select count(*)::int || '/' || max(locked_price_sen) filter (where status = 'active')
           from public.subscriptions where shop_id = tests.uid('S1')), '2/6000', '旧的停了，新的一条锁 RM60');
update public.subscriptions set status = 'lapsed' where shop_id = tests.uid('S1') and locked_price_sen = 6000;
update public.subscriptions set status = 'active', lapsed_at = null, current_period_end = now() + interval '20 days'
where id = :'s1_id';

-- 停了再回来：按现在的 RM60
update public.subscriptions set status = 'lapsed', lapsed_at = now() - interval '1 day'
where shop_id = tests.uid('S2');
select tests.intent('buyer2', 'subscription', tests.uid('S2'), 2) as p4 \gset
select is((select amount_sen || '/' || coalesce(reference_id::text, 'new') from public.payments where id = :'p4'), '12000/new',
  '已停：按现在的 RM60 x 2，付了才建新的订阅');
select tests.login_as(tests.uid('buyer2'));
select is((public.get_buyer_billing(tests.uid('S2')) ->> 'renew_price_sen')::int || '/' ||
          (public.get_buyer_billing(tests.uid('S2')) ->> 'price_locked'), '6000/false', '买家看到的是新价钱');
select tests.logout();
select tests.paid(:'p4') ->> 'result' as r \gset
select is((select count(*)::int from public.subscriptions where shop_id = tests.uid('S2')), 2, '新建一条订阅（旧的留着）');
select is((tests.sub('S2')).status::text || '/' || (tests.sub('S2')).locked_price_sen || '/' || (tests.sub('S2')).is_founding_price,
  'active/6000/false', '锁定新价钱 RM60（不是创始价）');
select is((select reference_id from public.payments where id = :'p4'), (tests.sub('S2')).id, '付款单对到新的订阅');

-- 没有订阅的店（S3 从来没试用）也可以直接付
select tests.paid(tests.intent('buyer3', 'subscription', tests.uid('S3'))) ->> 'result' as r \gset
select is((tests.sub('S3')).status::text || '/' || (tests.sub('S3')).locked_price_sen, 'active/6000', 'S3 付了：active，RM60');
select ok(public.has_full_access(tests.uid('S3')), '付了就看得到全部价钱');

-- 金额对不上：记已付但要客服处理，订阅不动
select (tests.sub('S3')).current_period_end as end3 \gset
select tests.intent('buyer3', 'subscription', tests.uid('S3')) as p5 \gset
select is(tests.paid(:'p5', 100) ->> 'result', 'paid', '金额不对：钱还是记下来');
select is((select review_reason from public.payments where id = :'p5'), 'AMOUNT_MISMATCH', '标「要处理」');
select is((tests.sub('S3')).current_period_end, :'end3'::timestamptz, '订阅不会因为付错钱就延长');

-- 付款单失败 / 过期后钱才到：照样算
select tests.intent('buyer3', 'subscription', tests.uid('S3')) as p6 \gset
select ok(public.fail_payment(:'p6', 'EXPIRED'), 'pending → failed');
select ok(not public.fail_payment(:'p6', 'EXPIRED'), '已经 failed 的不再改');
select is(tests.paid(:'p6') ->> 'result', 'paid', '失败后钱才到：照样算已付');
select is((tests.sub('S3')).current_period_end, :'end3'::timestamptz + interval '1 month', '延长 1 个月');
select ok(not public.fail_payment(:'p6', 'X'), '已付的不能改成失败');

-- 看付款单
select tests.login_as(tests.uid('buyer3'));
select is(public.get_payment(:'p6') ->> 'status', 'paid', '老板看自己的付款单');
select tests.login_as(tests.uid('buyer1'));
select is(tests.error_of(format('select public.get_payment(%L)', :'p6')), 'NOT_ALLOWED', '看不到别家店的');
select tests.logout();

-- 按太多次
insert into public.payments (payer_type, shop_id, purpose, amount_sen, gateway, created_by)
select 'shop', tests.uid('S3'), 'subscription', 1, 'hitpay', tests.uid('buyer3') from generate_series(1, 20);
select is(public.create_payment_intent(tests.uid('buyer3'), 'subscription', tests.uid('S3'), 2) ->> 'result', 'too_many',
  '一小时开超过 20 张 → too_many');
delete from public.payments where amount_sen = 1;

-- =============================================================================
-- 创始上架费
-- =============================================================================
select tests.login_as(tests.uid('seller2'));
select is(public.get_seller_billing(tests.uid('W2')) -> 'listing_fee' ->> 'can_pay', 'true', '还有名额：W2 可以付上架费成为创始会员');
select tests.logout();
select is(public.create_payment_intent(tests.uid('seller1'), 'listing_fee', tests.uid('W2')) ->> 'result', 'not_allowed',
  '别家批发商不能替 W2 开');
select tests.intent('seller2', 'listing_fee', tests.uid('W2')) as p7 \gset
select is((select amount_sen from public.payments where id = :'p7'), 10000, '上架费 RM100（app_settings）');
select is(tests.paid(:'p7') ->> 'result', 'paid', '付了');
select is((select is_founding::text || '/' || (founding_no is not null) || '/' || (founding_fee_paid_at is not null)
           from public.wholesalers where id = tests.uid('W2')), 'true/true/true', '成为创始会员，自动编号');
select is((select rate_source::text from public.commission_rate_for(tests.uid('W2'))), 'founding', '佣金改用创始比例');
select is(public.create_payment_intent(tests.uid('seller2'), 'listing_fee', tests.uid('W2')) ->> 'result', 'nothing_due',
  '付过了不用再付');
update public.app_settings set founding_wholesaler_quota = (select count(*) from public.wholesalers where is_founding);
select is(public.create_payment_intent(tests.uid('seller3'), 'listing_fee', tests.uid('W3')) ->> 'result', 'founding_full',
  '名额满了：不能付');
select ok(public.create_payment_intent(tests.uid('seller1'), 'listing_fee', tests.uid('W1')) ->> 'result' = 'ok',
  '已经是创始会员（名额里）但还没付：可以付');

-- 客服手动标记上架费已付
select tests.login_as(tests.uid('seller1'));
select is(tests.error_of(format('select public.admin_mark_listing_fee_paid(%L)', tests.uid('W1'))), 'NOT_ALLOWED', '批发商不能自己标');
select tests.login_as(tests.uid('admin'));
select is(public.admin_mark_listing_fee_paid(tests.uid('W1'), 'duitnow', 'DN-LF1') ->> 'payment_id' is not null, true, '客服标已付');
select is(tests.error_of(format('select public.admin_mark_listing_fee_paid(%L)', tests.uid('W1'))), 'LISTING_FEE_ALREADY_PAID', '不能标两次');
select is((select count(*)::int from public.audit_logs where action = 'admin_mark_listing_fee_paid'
           and acting_for_wholesaler_id = tests.uid('W1')), 1, '记在操作记录');
select tests.logout();
update public.app_settings set founding_wholesaler_quota = 100;

-- =============================================================================
-- 每月佣金账单：月初自动生成并发出、批发商看 / 付、逾期、提醒
-- =============================================================================
select tests.add_to_cart('S1', 'P1', 2);
select public.place_order(tests.uid('S1'));
select public.confirm_order(tests.order_of('S1', 'W1'));
select public.set_order_status(tests.order_of('S1', 'W1'), 'delivered');
-- 当作上个月送达的
update public.commission_records set period_month = (date_trunc('month', public.today_myt()) - interval '1 month')::date
where wholesaler_id = tests.uid('W1');

update public.app_settings set invoice_auto_issue = false;
select public.run_billing_daily() as run0 \gset
select is((select status::text from public.commission_invoices where wholesaler_id = tests.uid('W1')), 'draft',
  '关掉自动发出：只生成草稿');
update public.app_settings set invoice_auto_issue = true;
select public.run_billing_daily() as run1 \gset
select is((:'run1'::jsonb ->> 'issued')::int, 1, '月初自动发出上个月的账单');
select is((select status::text || '/' || (due_date = public.today_myt() + 14) || '/' || commission_sen
           from public.commission_invoices where wholesaler_id = tests.uid('W1')), 'issued/true/255',
  '已发出，14 天内付，佣金 RM2.55（1.5% x RM170，不含运费）');
select is((select count(*)::int from public.notifications where wholesaler_id = tests.uid('W1') and event_type = 'invoice_issued'),
  1, '推送「新账单」');
select public.run_billing_daily() as run2 \gset
select is((select count(*)::int from public.notifications where wholesaler_id = tests.uid('W1') and event_type = 'invoice_issued'),
  1, '重复跑：不会再发');
select id as inv from public.commission_invoices where wholesaler_id = tests.uid('W1') \gset

select tests.login_as(tests.uid('seller1'));
select is((public.get_seller_billing(tests.uid('W1')) ->> 'outstanding_sen')::int, 255, '批发商看到还欠多少');
select is(public.get_seller_billing(tests.uid('W1')) -> 'invoices' -> 0 ->> 'status', 'issued', '账单列表');
select is(jsonb_array_length(public.get_commission_invoice(:'inv') -> 'lines'), 1, '账单明细：每张单一行');
select is((public.get_commission_invoice(:'inv') -> 'lines' -> 0 ->> 'base_amount_sen')::int, 17000, '明细：货价不含运费');
select tests.login_as(tests.uid('seller2'));
select is(tests.error_of(format('select public.get_commission_invoice(%L)', :'inv')), 'NOT_ALLOWED', '别家批发商看不到');
select tests.logout();

-- 快到期提醒（发出超过 1 天、3 天内到期，只提醒一次）
update public.commission_invoices set issued_at = now() - interval '2 days', due_date = public.today_myt() + 2 where id = :'inv';
select public.run_billing_daily();
select public.run_billing_daily();
select is((select count(*)::int from public.notifications where wholesaler_id = tests.uid('W1') and event_type = 'invoice_due_soon'),
  1, '快到期：推送一次');
-- 逾期
update public.commission_invoices set due_date = public.today_myt() - 1 where id = :'inv';
select public.run_billing_daily();
select public.run_billing_daily();
select is((select status::text from public.commission_invoices where id = :'inv'), 'overdue', '过了到期日 → 逾期');
select is((select count(*)::int from public.notifications where wholesaler_id = tests.uid('W1') and event_type = 'invoice_overdue'),
  1, '逾期：推送一次');

-- 网关付佣金账单
select tests.intent('seller1', 'commission_invoice', :'inv') as p8 \gset
select is((select amount_sen from public.payments where id = :'p8'), 255, '付款金额 = 账单佣金');
select is(tests.paid(:'p8') ->> 'result', 'paid', '付了');
select is((select status::text from public.commission_invoices where id = :'inv'), 'paid', '逾期的账单 → 已付');
select is(public.create_payment_intent(tests.uid('seller1'), 'commission_invoice', :'inv') ->> 'result', 'nothing_due',
  '付过了不能再开');

-- 开了付款页，客服又手动标已付，网关的钱才到 → 记下来，标「要处理」（多收了）
update public.commission_invoices set status = 'issued', paid_at = null where id = :'inv';
select tests.intent('seller1', 'commission_invoice', :'inv') as p9 \gset
select tests.login_as(tests.uid('admin'));
select public.admin_mark_invoice_paid(:'inv', 'other', 'CASH-1');
select tests.logout();
select is(tests.paid(:'p9') ->> 'result', 'paid', '钱照样记下来');
select is((select review_reason from public.payments where id = :'p9'), 'INVOICE_PAID', '账单已经付过：要客服退款');
select tests.login_as(tests.uid('admin'));
select ok((select bool_and(x ->> 'review_reason' is not null) and count(*) >= 2
           from jsonb_array_elements(public.admin_list_payments(p_review_only => true)) x), '客服看到要处理的付款');
select is(jsonb_array_length(public.admin_list_payments(p_purpose => 'listing_fee')), 3, '按用途筛选（W2 付了、W1 手动、W1 还没付的一张）');
select tests.logout();

-- =============================================================================
-- 买家快到期提醒、只用推送
-- =============================================================================
update public.subscriptions set trial_ends_at = now() + interval '2 days' where shop_id = tests.uid('S1') and status <> 'lapsed';
update public.subscriptions set status = 'trialing' where shop_id = tests.uid('S1') and status <> 'lapsed';
select public.run_billing_daily();
select public.run_billing_daily();
select is((select count(*)::int from public.notifications where shop_id = tests.uid('S1') and event_type = 'subscription_ending'),
  1, '试用 3 天内结束：推送一次');

update public.wholesalers set notify_channel = 'whatsapp', whatsapp_phone = '60111000011', whatsapp_opt_in_at = now()
where id = tests.uid('W1');
select is(public._notification_route(null, null, tests.uid('W1'), 'invoice_issued') ->> 'channel', null,
  '收费的通知不走 WhatsApp（没有模板）');
select is(public._notification_route(null, null, tests.uid('W1'), 'order_new') ->> 'channel', 'whatsapp',
  '订单通知照旧可以走 WhatsApp');

-- 客服手动标记月费（第五步的函数，现在用同一套规则）
select tests.login_as(tests.uid('admin'));
select public.admin_mark_subscription_paid((tests.sub('S2')).id, 1) as manual \gset
select is((:'manual'::jsonb ->> 'locked_price_sen')::int, 6000, '手动标记：锁定价不变');
select is((select period_end from public.payments where id = (:'manual'::jsonb ->> 'payment_id')::uuid),
  (tests.sub('S2')).current_period_end, '手动的付款也记下付的是哪一段');

select * from finish();
rollback;
