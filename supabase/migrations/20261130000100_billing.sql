-- =============================================================================
-- 第七步：收费（付款网关、月费续费、创始上架费、每月佣金账单自动发出和提醒）
--
--   A. 新字段：payments（付款单）、commission_invoices（提醒）、subscriptions（续费提醒）
--   B. 续费的规则（只有一份）：_extend_subscription
--   C. 付款单：create_payment_intent / attach_payment_checkout / fail_payment / mark_payment_paid（只给服务器）
--   D. App 看的：get_payment、get_buyer_billing、get_seller_billing、get_commission_invoice
--   E. 客服：admin_list_payments、admin_mark_listing_fee_paid；admin_mark_subscription_paid、admin_issue_invoice 改用共用规则
--   F. 每天的收费工作（pg_cron，马来西亚时间 00:20）：月初自动生成并发出上个月的佣金账单、逾期、提醒
--   G. 通知：收费的通知只用推送（WhatsApp 要另外送审模板）
--   H. 函数权限
--
-- 钱的规则：
--   * 金额只在这里算：月费 = 锁定的价钱 x 月数（停了再回来 = 当时的新价钱），上架费 = app_settings，佣金 = 账单金额。
--   * 网关通知（webhook）可能重复、可能很晚才到：mark_payment_paid 同一笔只算一次；钱已经收到就一定记下来，
--     对不上的（金额不对、账单已经付过……）记在 review_reason 让客服处理（退款或补登）。
-- =============================================================================

-- =============================================================================
-- A. 新字段
-- =============================================================================

alter table public.payments
  add column months int check (months between 1 and 24),          -- 月费付几个月
  add column unit_price_sen int check (unit_price_sen > 0),       -- 每个月多少（锁定的价钱）
  add column description text,
  add column checkout_url text,                                    -- 网关的付款页
  add column expires_at timestamptz,                               -- 付款页过了这个时间就不再拿出来用
  add column created_by uuid references public.profiles (id) on delete set null,
  add column failure_reason text,
  add column review_reason text,                                   -- 收到钱但不能照常处理（客服要看）
  add column period_start timestamptz,                             -- 付了之后：这次付的是哪一段
  add column period_end timestamptz,
  add column meta jsonb not null default '{}';
create index payments_pending_idx on public.payments (purpose, reference_id, created_at desc) where status = 'pending';
create index payments_review_idx on public.payments (created_at desc) where review_reason is not null;
create index payments_created_by_idx on public.payments (created_by, created_at desc);

alter table public.commission_invoices
  add column reminded_at timestamptz,                              -- 快到期提醒（一次）
  add column overdue_notified_at timestamptz;                      -- 逾期提醒（一次）

alter table public.subscriptions
  add column renewal_reminded_for timestamptz;                     -- 已经提醒过的「到期时间」（试用结束 / 这期结束）

alter table public.app_settings
  add column invoice_auto_issue boolean not null default true,     -- 月初生成后自动发出（不用客服按）
  add column invoice_reminder_days int not null default 3 check (invoice_reminder_days between 0 and 30),
  add column renewal_reminder_days int not null default 3 check (renewal_reminder_days between 0 and 30),
  add column payment_link_hours int not null default 24 check (payment_link_hours between 1 and 720);

-- =============================================================================
-- B. 续费的规则（网关付款、客服手动标记都用这个）
--   有没停的订阅：
--     试用中        → active，从试用结束（还没到就从结束那天，过了就从现在）开始算，锁定价不变
--     active / 逾期 → 从原来的结束日接着算（宽限期内补付保留原价）
--   没有（全部 lapsed）：
--     p_reopen_id 那条是在 p_paid_since 之后才停的（付款页是在还没停时开的，钱照旧价收了）→ 重新打开那条，从现在算
--     否则 → 新建一条，按 p_new_price_sen 锁定（停了再回来 = 当时的新价钱）
-- 回传 {subscription_id, period_start, period_end, reopened, created}
-- =============================================================================

create or replace function public._extend_subscription(
  p_shop_id uuid,
  p_months int,
  p_new_price_sen int,
  p_new_is_founding boolean,
  p_reopen_id uuid default null,
  p_paid_since timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
  v_start timestamptz;
  v_end timestamptz;
  v_reopened boolean := false;
  v_created boolean := false;
begin
  if p_months is null or p_months < 1 or p_months > 24 then
    raise exception 'INVALID_MONTHS' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.subscriptions:' || p_shop_id::text));

  select * into s from public.subscriptions
  where shop_id = p_shop_id and status <> 'lapsed'
  for update;

  -- 逾期、宽限期已经过了（定时任务还没跑到）：当作已停（付款页是宽限期过了才开的 → 按新价钱）
  if found and s.status = 'past_due' and s.grace_until <= coalesce(p_paid_since, now()) then
    update public.subscriptions set status = 'lapsed', lapsed_at = now() where id = s.id;
    s := null;
  end if;

  if s.id is not null then
    v_start := case
      when s.status = 'trialing' then greatest(now(), coalesce(s.trial_ends_at, now()))
      else coalesce(s.current_period_end, now())
    end;
    v_end := v_start + make_interval(months => p_months);
    update public.subscriptions set
      status = 'active', current_period_start = v_start, current_period_end = v_end, grace_until = null
    where id = s.id;
  else
    select * into s from public.subscriptions
    where id = p_reopen_id and shop_id = p_shop_id and status = 'lapsed'
      and p_paid_since is not null and lapsed_at > p_paid_since
    for update;
    v_start := now();
    v_end := v_start + make_interval(months => p_months);
    if found then
      update public.subscriptions set
        status = 'active', current_period_start = v_start, current_period_end = v_end,
        grace_until = null, lapsed_at = null
      where id = s.id;
      v_reopened := true;
    else
      if p_new_price_sen is null or p_new_price_sen <= 0 then
        raise exception 'NO_PRICING_PLAN' using errcode = 'P0001';
      end if;
      insert into public.subscriptions (
        shop_id, status, started_at, locked_price_sen, is_founding_price, current_period_start, current_period_end
      )
      values (p_shop_id, 'active', now(), p_new_price_sen, coalesce(p_new_is_founding, false), v_start, v_end)
      returning * into s;
      v_created := true;
    end if;
  end if;

  return jsonb_build_object('subscription_id', s.id, 'period_start', v_start, 'period_end', v_end,
                            'reopened', v_reopened, 'created', v_created);
end;
$$;

-- =============================================================================
-- C. 付款单（Edge Function create-payment / payment-webhook 用服务器身份叫）
-- =============================================================================

-- 付款单的样子（App 看的，不含网关原始资料）
create or replace function public._payment_json(p_payment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'payer_type', p.payer_type,
    'shop_id', p.shop_id,
    'wholesaler_id', p.wholesaler_id,
    'purpose', p.purpose,
    'reference_id', p.reference_id,
    'amount_sen', p.amount_sen,
    'months', p.months,
    'unit_price_sen', p.unit_price_sen,
    'description', p.description,
    'gateway', p.gateway,
    'method', p.method,
    'status', p.status,
    'checkout_url', case when p.status = 'pending' and p.expires_at > now() then p.checkout_url end,
    'expires_at', p.expires_at,
    'paid_at', p.paid_at,
    'period_start', p.period_start,
    'period_end', p.period_end,
    'failure_reason', p.failure_reason,
    'review_reason', p.review_reason,
    'created_at', p.created_at
  )
  from public.payments p where p.id = p_payment_id;
$$;

-- 开一张付款单（还没去网关）。p_user_id = 按「付款」的人（Edge Function 验过 JWT）；客服可以代任何人开
-- （例如复制付款链接用 WhatsApp 发给没装 App 的老板）。
--   p_purpose = subscription：p_target_id = 店的 id，p_months 1–12
--   p_purpose = listing_fee：p_target_id = 批发商 id（创始会员上架费；还没是创始会员而且名额还有 → 付了就是创始会员）
--   p_purpose = commission_invoice：p_target_id = 账单 id（已发出 / 逾期）
-- 回传 {result, payment, reuse}：result = ok | not_found | not_allowed | invalid | nothing_due | founding_full | too_many。
-- 同一样东西、同样金额、付款页还有效（还有 10 分钟以上）→ 拿回同一张（reuse = true），不会重复开网关的单。
create or replace function public.create_payment_intent(
  p_user_id uuid,
  p_purpose public.payment_purpose,
  p_target_id uuid,
  p_months int default 1,
  p_gateway text default 'hitpay'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin boolean;
  v_settings public.app_settings%rowtype;
  v_payer public.payer_type;
  v_shop uuid;
  v_wholesaler uuid;
  v_ref uuid;
  v_amount int;
  v_unit int;
  v_months int;
  v_desc text;
  v_meta jsonb := '{}';
  v_plan record;
  s public.subscriptions%rowtype;
  w public.wholesalers%rowtype;
  i public.commission_invoices%rowtype;
  v_existing uuid;
  v_id uuid;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if p_user_id is null or p_purpose is null or p_target_id is null
     or coalesce(p_gateway, '') !~ '^[a-z0-9_]{1,30}$' then
    return jsonb_build_object('result', 'invalid');
  end if;
  select exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'admin') into v_admin;
  select * into v_settings from public.app_settings;

  if p_purpose = 'subscription' then
    v_months := coalesce(p_months, 1);
    if v_months < 1 or v_months > 12 then
      return jsonb_build_object('result', 'invalid');
    end if;
    if not exists (select 1 from public.shops x where x.id = p_target_id) then
      return jsonb_build_object('result', 'not_found');
    end if;
    if not (v_admin or exists (select 1 from public.shop_members m where m.shop_id = p_target_id and m.user_id = p_user_id)) then
      return jsonb_build_object('result', 'not_allowed');
    end if;
    v_payer := 'shop';
    v_shop := p_target_id;
    select * into s from public.subscriptions x
    where x.shop_id = p_target_id and x.status <> 'lapsed'
      and not (x.status = 'past_due' and x.grace_until <= now());   -- 宽限期过了：当作已停
    if found then
      v_unit := s.locked_price_sen;                -- 一直续费：锁定的价钱
      v_ref := s.id;
      v_meta := jsonb_build_object('locked', true);
    else
      select * into v_plan from public.current_plan('buyer_monthly');
      if v_plan.plan_id is null then
        return jsonb_build_object('result', 'nothing_due');
      end if;
      v_unit := v_plan.amount_sen;                 -- 停了再回来：现在的价钱
      v_meta := jsonb_build_object('locked', false, 'plan_id', v_plan.plan_id, 'plan_is_founding', v_plan.is_founding);
    end if;
    v_amount := v_unit * v_months;
    v_desc := 'Monthly subscription x' || v_months;

  elsif p_purpose = 'listing_fee' then
    select * into w from public.wholesalers x where x.id = p_target_id;
    if not found then
      return jsonb_build_object('result', 'not_found');
    end if;
    if not (v_admin or exists (select 1 from public.wholesaler_members m where m.wholesaler_id = w.id and m.user_id = p_user_id)) then
      return jsonb_build_object('result', 'not_allowed');
    end if;
    if w.status = 'suspended' then
      return jsonb_build_object('result', 'not_allowed');
    end if;
    if w.founding_fee_paid_at is not null or v_settings.founding_listing_fee_sen <= 0 then
      return jsonb_build_object('result', 'nothing_due');
    end if;
    if not w.is_founding
       and (select count(*) from public.wholesalers x where x.is_founding) >= v_settings.founding_wholesaler_quota then
      return jsonb_build_object('result', 'founding_full');
    end if;
    v_payer := 'wholesaler';
    v_wholesaler := w.id;
    v_ref := w.id;
    v_amount := v_settings.founding_listing_fee_sen;
    v_desc := 'Founding member listing fee';

  else
    select * into i from public.commission_invoices x where x.id = p_target_id;
    if not found then
      return jsonb_build_object('result', 'not_found');
    end if;
    if not (v_admin or exists (select 1 from public.wholesaler_members m where m.wholesaler_id = i.wholesaler_id and m.user_id = p_user_id)) then
      return jsonb_build_object('result', 'not_allowed');
    end if;
    if i.status not in ('issued', 'overdue') or i.commission_sen <= 0 then
      return jsonb_build_object('result', 'nothing_due');
    end if;
    v_payer := 'wholesaler';
    v_wholesaler := i.wholesaler_id;
    v_ref := i.id;
    v_amount := i.commission_sen::int;
    v_desc := 'Commission invoice ' || i.invoice_no;
  end if;

  -- 同一个付款对象同时只开一张：锁住再找
  perform pg_advisory_xact_lock(hashtext('public.payments:' || p_purpose::text || ':' || p_target_id::text));
  select p.id into v_existing
  from public.payments p
  where p.status = 'pending' and p.purpose = p_purpose and p.gateway = p_gateway
    and p.shop_id is not distinct from v_shop and p.wholesaler_id is not distinct from v_wholesaler
    and p.reference_id is not distinct from v_ref
    and p.amount_sen = v_amount and p.months is not distinct from case when p_purpose = 'subscription' then v_months end
    and p.checkout_url is not null and p.expires_at > now() + interval '10 minutes'
  order by p.created_at desc
  limit 1;
  if v_existing is not null then
    return jsonb_build_object('result', 'ok', 'reuse', true, 'payment', public._payment_json(v_existing));
  end if;

  -- 每个人每小时最多开 20 张（按来按去不会塞爆网关）
  if (select count(*) from public.payments p where p.created_by = p_user_id and p.created_at > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('result', 'too_many');
  end if;

  insert into public.payments (
    payer_type, shop_id, wholesaler_id, purpose, reference_id, amount_sen, gateway, status,
    months, unit_price_sen, description, expires_at, created_by, meta
  )
  values (
    v_payer, v_shop, v_wholesaler, p_purpose, v_ref, v_amount, p_gateway, 'pending',
    case when p_purpose = 'subscription' then v_months end,
    case when p_purpose = 'subscription' then v_unit end,
    v_desc, now() + make_interval(hours => v_settings.payment_link_hours), p_user_id, v_meta
  )
  returning id into v_id;

  if v_admin then
    insert into public.audit_logs (actor_id, acting_for_shop_id, acting_for_wholesaler_id, action, table_name, record_id, after)
    values (p_user_id, v_shop, v_wholesaler, 'admin_create_payment_link', 'payments', v_id::text,
            jsonb_build_object('purpose', p_purpose, 'amount_sen', v_amount, 'months', v_months));
  end if;

  return jsonb_build_object('result', 'ok', 'reuse', false, 'payment', public._payment_json(v_id));
end;
$$;

-- 网关开好单之后记下网关的单号和付款页
create or replace function public.attach_payment_checkout(p_payment_id uuid, p_gateway_ref text, p_checkout_url text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if coalesce(trim(p_gateway_ref), '') = '' or coalesce(p_checkout_url, '') !~ '^https://' then
    raise exception 'INVALID_CHECKOUT' using errcode = 'P0001';
  end if;
  update public.payments set gateway_ref = trim(p_gateway_ref), checkout_url = p_checkout_url
  where id = p_payment_id and status = 'pending' and gateway_ref is null;
  return found;
end;
$$;

-- 没付成（网关开单失败、付款失败 / 过期）：pending → failed。已经付了的不动
create or replace function public.fail_payment(p_payment_id uuid, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  update public.payments set status = 'failed', failure_reason = left(coalesce(nullif(trim(p_reason), ''), 'FAILED'), 100)
  where id = p_payment_id and status = 'pending';
  return found;
end;
$$;

-- 收到网关「已付」（签名 Edge Function 验过了）。同一笔只算一次（再来一次回 already_paid）。
-- 对不上：网关不同 / 单号不同 → mismatch（什么都不改）；金额不同 → 记成已付但 review_reason = AMOUNT_MISMATCH（客服处理）。
-- 付款单之前标了 failed（例如过期）但钱还是到了 → 照样算已付。
-- 回传 {result: paid | already_paid | not_found | mismatch, payment}
create or replace function public.mark_payment_paid(
  p_payment_id uuid,
  p_gateway text,
  p_gateway_ref text,
  p_amount_sen int,
  p_method public.payment_method default 'other',
  p_raw jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.payments%rowtype;
  v_ext jsonb;
  v_review text;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_ref_id uuid;
  i public.commission_invoices%rowtype;
  w public.wholesalers%rowtype;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into p from public.payments where id = p_payment_id for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if p.gateway is distinct from p_gateway
     or (p.gateway_ref is not null and p.gateway_ref is distinct from nullif(trim(p_gateway_ref), '')) then
    return jsonb_build_object('result', 'mismatch');
  end if;
  if p.status in ('paid', 'refunded') then
    return jsonb_build_object('result', 'already_paid', 'payment', public._payment_json(p.id));
  end if;

  if p_amount_sen is distinct from p.amount_sen then
    v_review := 'AMOUNT_MISMATCH';
  elsif p.purpose = 'subscription' then
    v_ext := public._extend_subscription(
      p.shop_id, p.months, p.unit_price_sen, coalesce((p.meta ->> 'plan_is_founding')::boolean, false),
      p.reference_id, p.created_at);
    v_ref_id := (v_ext ->> 'subscription_id')::uuid;
    v_period_start := (v_ext ->> 'period_start')::timestamptz;
    v_period_end := (v_ext ->> 'period_end')::timestamptz;
    -- 开单时没停、付的时候已经新建了一条（例如开单后等太久）：锁定价照付的钱（unit_price_sen）
  elsif p.purpose = 'listing_fee' then
    select * into w from public.wholesalers where id = p.wholesaler_id for update;
    if w.founding_fee_paid_at is not null then
      v_review := 'ALREADY_PAID';
    else
      begin
        update public.wholesalers set founding_fee_paid_at = now(), is_founding = true where id = w.id;
      exception when others then
        if sqlerrm = 'FOUNDING_QUOTA_FULL' then
          v_review := 'FOUNDING_QUOTA_FULL';     -- 付了但名额刚好满了：客服退款或手动处理
        else
          raise;
        end if;
      end;
    end if;
  else
    select * into i from public.commission_invoices where id = p.reference_id for update;
    if not found then
      v_review := 'INVOICE_NOT_FOUND';
    elsif i.status in ('issued', 'overdue') then
      update public.commission_invoices set status = 'paid', paid_at = now() where id = i.id;
    else
      v_review := 'INVOICE_' || upper(i.status::text);   -- 已经付了 / 作废：钱多收了
    end if;
  end if;

  update public.payments set
    status = 'paid',
    paid_at = now(),
    gateway_ref = coalesce(gateway_ref, nullif(trim(p_gateway_ref), '')),
    method = coalesce(p_method, 'other'),
    reference_id = coalesce(v_ref_id, reference_id),
    period_start = v_period_start,
    period_end = v_period_end,
    review_reason = v_review,
    failure_reason = null,
    raw = p_raw
  where id = p.id;

  insert into public.notifications (shop_id, wholesaler_id, event_type, payload)
  values (p.shop_id, p.wholesaler_id, 'payment_received', jsonb_build_object(
    'payment_id', p.id, 'purpose', p.purpose, 'amount_sen', p_amount_sen, 'period_end', v_period_end,
    'invoice_no', i.invoice_no, 'invoice_id', i.id));

  return jsonb_build_object('result', 'paid', 'payment', public._payment_json(p.id));
end;
$$;

-- =============================================================================
-- D. App 看的
-- =============================================================================

-- 付完回到 App：看这张付款单的状态（自己店 / 自己批发商的，或客服）
create or replace function public.get_payment(p_payment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  p public.payments%rowtype;
begin
  select * into p from public.payments where id = p_payment_id;
  if not found then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not (public.is_admin()
          or (p.shop_id is not null and public.is_shop_member(p.shop_id))
          or (p.wholesaler_id is not null and public.is_wholesaler_member(p.wholesaler_id))) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  return public._payment_json(p.id);
end;
$$;

-- 买家「我的订阅」页：状态、试用 / 这期还剩几天、续费的价钱（锁定的还是现在的）、最近的付款
create or replace function public.get_buyer_billing(p_shop_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
  v_status jsonb;
  v_end timestamptz;
  v_current int;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  v_status := public.get_subscription_status(p_shop_id);
  select * into s from public.subscriptions x where x.shop_id = p_shop_id and x.status <> 'lapsed';
  select cp.amount_sen into v_current from public.current_plan('buyer_monthly') cp;
  v_end := case
    when s.status = 'trialing' then s.trial_ends_at
    when s.status = 'active' then s.current_period_end
    when s.status = 'past_due' then s.grace_until
  end;
  return v_status || jsonb_build_object(
    'access_until', v_end,
    'days_left', case when v_end is not null
      then greatest(0, ceil(extract(epoch from (v_end - now())) / 86400.0))::int end,
    'renew_price_sen', coalesce(s.locked_price_sen, v_current),
    'price_locked', s.id is not null,
    'month_options', '[1, 3, 6, 12]'::jsonb,
    'grace_days', (select a.subscription_grace_days from public.app_settings a),
    'payments', coalesce((
      select jsonb_agg(public._payment_json(x.id) order by x.created_at desc)
      from (
        select p.id, p.created_at from public.payments p
        where p.shop_id = p_shop_id and p.purpose = 'subscription' and p.status = 'paid'
        order by p.created_at desc limit 12
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

-- 批发商的「收费」页：创始上架费、佣金比例、这个月到现在的佣金、账单（不含草稿）
create or replace function public.get_seller_billing(p_wholesaler_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w public.wholesalers%rowtype;
  a public.app_settings%rowtype;
  v_month date := date_trunc('month', public.today_myt())::date;
  v_founding_count int;
begin
  if not (public.is_wholesaler_member(p_wholesaler_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into w from public.wholesalers where id = p_wholesaler_id;
  if not found then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  select * into a from public.app_settings;
  select count(*) into v_founding_count from public.wholesalers x where x.is_founding;

  return jsonb_build_object(
    'wholesaler_id', w.id,
    'listing_fee', jsonb_build_object(
      'is_founding', w.is_founding,
      'founding_no', w.founding_no,
      'fee_sen', a.founding_listing_fee_sen,
      'paid_at', w.founding_fee_paid_at,
      'seats_left', greatest(a.founding_wholesaler_quota - v_founding_count, 0),
      'can_pay', w.founding_fee_paid_at is null and a.founding_listing_fee_sen > 0 and w.status <> 'suspended'
                 and (w.is_founding or v_founding_count < a.founding_wholesaler_quota)
    ),
    'commission', (select jsonb_build_object('rate', r.rate, 'rate_source', r.rate_source)
                   from public.commission_rate_for(w.id) r),
    'this_month', (
      select jsonb_build_object('period_month', v_month, 'order_count', count(*),
                                'gmv_sen', coalesce(sum(cr.base_amount_sen), 0),
                                'commission_sen', coalesce(sum(cr.commission_sen), 0))
      from public.commission_records cr where cr.wholesaler_id = w.id and cr.period_month = v_month
    ),
    'outstanding_sen', (
      select coalesce(sum(i.commission_sen), 0) from public.commission_invoices i
      where i.wholesaler_id = w.id and i.status in ('issued', 'overdue')
    ),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'invoice_no', i.invoice_no, 'period_month', i.period_month, 'order_count', i.order_count,
        'gmv_sen', i.gmv_sen, 'commission_sen', i.commission_sen, 'status', i.status, 'issued_at', i.issued_at,
        'due_date', i.due_date, 'paid_at', i.paid_at
      ) order by i.period_month desc, i.invoice_no desc)
      from public.commission_invoices i
      where i.wholesaler_id = w.id and i.status <> 'draft'
    ), '[]'::jsonb)
  );
end;
$$;

-- 一张佣金账单（印 PDF 用）：表头、批发商开账单的资料、每张订单一行、付款
create or replace function public.get_commission_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  i public.commission_invoices%rowtype;
begin
  select * into i from public.commission_invoices where id = p_invoice_id;
  if not found then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not (public.is_admin() or (public.is_wholesaler_member(i.wholesaler_id) and i.status <> 'draft')) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  return (
    select jsonb_build_object(
      'id', i.id, 'invoice_no', i.invoice_no, 'wholesaler_id', i.wholesaler_id, 'period_month', i.period_month,
      'order_count', i.order_count, 'gmv_sen', i.gmv_sen, 'commission_sen', i.commission_sen, 'status', i.status,
      'issued_at', i.issued_at, 'due_date', i.due_date, 'paid_at', i.paid_at,
      'wholesaler_name', w.name,
      'billing', jsonb_build_object('name', coalesce(wp.billing_name, w.name), 'email', wp.billing_email,
                                    'address', coalesce(wp.billing_address, w.address), 'ssm_no', wp.ssm_no),
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
          'order_id', o.id, 'order_no', o.order_no, 'shop_name', s.name, 'delivered_at', o.delivered_at,
          'base_amount_sen', cr.base_amount_sen, 'shipping_fee_sen', o.shipping_fee_sen,
          'rate', cr.rate, 'rate_source', cr.rate_source, 'commission_sen', cr.commission_sen
        ) order by o.delivered_at, o.order_no)
        from public.commission_records cr
        join public.orders o on o.id = cr.order_id
        join public.shops s on s.id = o.shop_id
        where cr.invoice_id = i.id
      ), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(public._payment_json(p.id) order by p.created_at)
        from public.payments p
        where p.purpose = 'commission_invoice' and p.reference_id = i.id and p.status = 'paid'
      ), '[]'::jsonb)
    )
    from public.wholesalers w
    left join public.wholesaler_private wp on wp.wholesaler_id = w.id
    where w.id = i.wholesaler_id
  );
end;
$$;

-- =============================================================================
-- E. 客服
-- =============================================================================

-- 付款记录（新到旧）。p_review_only = 只看收到钱但要处理的
create or replace function public.admin_list_payments(
  p_status public.payment_status default null,
  p_purpose public.payment_purpose default null,
  p_review_only boolean default false,
  p_limit int default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(x.j order by x.created_at desc, x.id)
    from (
      select p.created_at, p.id,
             public._payment_json(p.id) || jsonb_build_object(
               'gateway_ref', p.gateway_ref,
               'payer_name', coalesce(sh.name, w.name),
               'invoice_no', i.invoice_no
             ) as j
      from public.payments p
      left join public.shops sh on sh.id = p.shop_id
      left join public.wholesalers w on w.id = p.wholesaler_id
      left join public.commission_invoices i on p.purpose = 'commission_invoice' and i.id = p.reference_id
      where (p_status is null or p.status = p_status)
        and (p_purpose is null or p.purpose = p_purpose)
        and (not coalesce(p_review_only, false) or p.review_reason is not null)
      order by p.created_at desc, p.id
      limit greatest(least(coalesce(p_limit, 100), 500), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 批发商的样子（第五步的，加上创始上架费付了没有）
create or replace function public._admin_wholesaler_json(p_wholesaler_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', w.id,
    'name', w.name,
    'status', w.status,
    'is_founding', w.is_founding,
    'founding_no', w.founding_no,
    'founding_fee_paid_at', w.founding_fee_paid_at,
    'contact_name', w.contact_name,
    'phone', w.phone,
    'whatsapp_phone', w.whatsapp_phone,
    'whatsapp_opt_in_at', w.whatsapp_opt_in_at,
    'notify_channel', w.notify_channel,
    'region_name', r.name,
    'industry_name', i.name,
    'commission_rate', cr.rate,
    'commission_rate_source', cr.rate_source,
    'commission_rate_override', wp.commission_rate_override,
    'industry_default_rate', i.default_commission_rate,
    'industry_founding_rate', i.founding_commission_rate,
    'active_product_count', (select count(*) from public.products p where p.wholesaler_id = w.id and p.status = 'active'),
    'pending_order_count', (select count(*) from public.orders o where o.wholesaler_id = w.id and o.status = 'pending'),
    'member_count', (select count(*) from public.wholesaler_members m where m.wholesaler_id = w.id),
    'rating_avg', w.rating_avg,
    'rating_count', w.rating_count,
    'approved_at', w.approved_at,
    'created_at', w.created_at
  )
  from public.wholesalers w
  join public.regions r on r.id = w.region_id
  join public.industries i on i.id = w.industry_id
  left join public.wholesaler_private wp on wp.wholesaler_id = w.id
  cross join lateral public.commission_rate_for(w.id) cr
  where w.id = p_wholesaler_id;
$$;

-- 批发商转账 / 现金付了创始上架费：记一笔（gateway = manual），标记已付；还不是创始会员的自动编号
create or replace function public.admin_mark_listing_fee_paid(
  p_wholesaler_id uuid,
  p_method public.payment_method default 'other',
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  w public.wholesalers%rowtype;
  v_fee int;
  v_payment uuid;
  v_ref text := nullif(trim(p_reference), '');
begin
  perform public._require_admin();
  select * into w from public.wholesalers where id = p_wholesaler_id for update;
  if not found then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if w.founding_fee_paid_at is not null then
    raise exception 'LISTING_FEE_ALREADY_PAID' using errcode = 'P0001';
  end if;
  select a.founding_listing_fee_sen into v_fee from public.app_settings a;
  update public.wholesalers set founding_fee_paid_at = now(), is_founding = true where id = w.id;  -- 名额满 → FOUNDING_QUOTA_FULL
  if v_fee > 0 then
    begin
      insert into public.payments (
        payer_type, wholesaler_id, purpose, reference_id, amount_sen, gateway, method, gateway_ref, status, paid_at,
        description, created_by, raw
      )
      values ('wholesaler', w.id, 'listing_fee', w.id, v_fee, 'manual', coalesce(p_method, 'other'), v_ref, 'paid', now(),
              'Founding member listing fee', auth.uid(), jsonb_build_object('recorded_by', auth.uid()))
      returning id into v_payment;
    exception when unique_violation then
      raise exception 'DUPLICATE_PAYMENT_REFERENCE' using errcode = 'P0001', detail = v_ref;
    end;
  end if;
  perform public._admin_audit('admin_mark_listing_fee_paid', 'wholesalers', w.id::text, null, w.id,
    jsonb_build_object('is_founding', w.is_founding, 'founding_fee_paid_at', w.founding_fee_paid_at),
    jsonb_build_object('payment_id', v_payment, 'amount_sen', v_fee, 'method', coalesce(p_method, 'other'), 'reference', v_ref));
  return public._admin_wholesaler_json(w.id) || jsonb_build_object('payment_id', v_payment);
end;
$$;

-- 手动标记月费已付：规则改用 _extend_subscription（跟网关付款一样）。参数和回传跟第五步一样
create or replace function public.admin_mark_subscription_paid(
  p_subscription_id uuid,
  p_months int default 1,
  p_amount_sen int default null,
  p_method public.payment_method default 'other',
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.subscriptions%rowtype;
  v_plan record;
  v_ext jsonb;
  v_sub_id uuid;
  v_price int;
  v_founding boolean := false;
  v_amount int;
  v_payment uuid;
  v_ref text := nullif(trim(p_reference), '');
begin
  perform public._require_admin();
  if p_months is null or p_months < 1 or p_months > 24 then
    raise exception 'INVALID_MONTHS' using errcode = 'P0001';
  end if;
  if p_amount_sen is not null and p_amount_sen <= 0 then
    raise exception 'INVALID_AMOUNT' using errcode = 'P0001';
  end if;
  select * into s from public.subscriptions where id = p_subscription_id for update;
  if not found then
    raise exception 'SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;
  if s.status = 'lapsed' then
    if exists (select 1 from public.subscriptions x where x.shop_id = s.shop_id and x.status <> 'lapsed') then
      raise exception 'SUBSCRIPTION_ALREADY_OPEN' using errcode = 'P0001';
    end if;
    select * into v_plan from public.current_plan('buyer_monthly');
    if v_plan.plan_id is null then
      raise exception 'NO_PRICING_PLAN' using errcode = 'P0001';
    end if;
    v_price := v_plan.amount_sen;
    v_founding := v_plan.is_founding;
  else
    v_price := s.locked_price_sen;
  end if;
  v_ext := public._extend_subscription(s.shop_id, p_months, v_price, v_founding);
  v_sub_id := (v_ext ->> 'subscription_id')::uuid;

  v_amount := coalesce(p_amount_sen, v_price * p_months);
  begin
    insert into public.payments (
      payer_type, shop_id, purpose, reference_id, amount_sen, gateway, method, gateway_ref, status, paid_at, raw,
      months, unit_price_sen, period_start, period_end, created_by
    )
    values ('shop', s.shop_id, 'subscription', v_sub_id, v_amount, 'manual', coalesce(p_method, 'other'), v_ref,
            'paid', now(), jsonb_build_object('months', p_months, 'recorded_by', auth.uid()),
            p_months, v_price, (v_ext ->> 'period_start')::timestamptz, (v_ext ->> 'period_end')::timestamptz, auth.uid())
    returning id into v_payment;
  exception when unique_violation then
    raise exception 'DUPLICATE_PAYMENT_REFERENCE' using errcode = 'P0001', detail = v_ref;
  end;

  perform public._admin_audit('admin_mark_subscription_paid', 'subscriptions', v_sub_id::text, s.shop_id, null,
    jsonb_build_object('subscription_id', s.id, 'status', s.status, 'current_period_end', s.current_period_end,
                       'locked_price_sen', s.locked_price_sen),
    (select jsonb_build_object('subscription_id', x.id, 'status', x.status, 'current_period_end', x.current_period_end,
                               'locked_price_sen', x.locked_price_sen, 'payment_id', v_payment, 'amount_sen', v_amount,
                               'months', p_months, 'method', coalesce(p_method, 'other'), 'reference', v_ref)
     from public.subscriptions x where x.id = v_sub_id));
  return public._admin_subscription_json(v_sub_id) || jsonb_build_object('payment_id', v_payment);
end;
$$;

-- 发出一张草稿账单（客服按、或月初自动）：draft → issued，到期日 = 今天 + 天数，推送给批发商
create or replace function public._issue_invoice(p_invoice_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.commission_invoices%rowtype;
begin
  update public.commission_invoices set
    status = 'issued',
    issued_at = now(),
    due_date = public.today_myt() + (select a.commission_invoice_due_days from public.app_settings a)
  where id = p_invoice_id and status = 'draft'
  returning * into i;
  if not found then
    return false;
  end if;
  insert into public.notifications (wholesaler_id, event_type, payload)
  values (i.wholesaler_id, 'invoice_issued', jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'period_month', i.period_month,
    'commission_sen', i.commission_sen, 'due_date', i.due_date));
  return true;
end;
$$;

create or replace function public.admin_issue_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.commission_invoices%rowtype;
begin
  perform public._require_admin();
  select * into i from public.commission_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if i.status <> 'draft' then
    raise exception 'INVALID_INVOICE_STATE' using errcode = 'P0001', detail = i.status::text;
  end if;
  perform public._issue_invoice(i.id);
  perform public._admin_audit('admin_issue_invoice', 'commission_invoices', i.id::text, null, i.wholesaler_id,
    jsonb_build_object('status', i.status), jsonb_build_object('status', 'issued'));
  return public._admin_invoice_json(i.id);
end;
$$;

-- =============================================================================
-- F. 每天的收费工作（定时任务；客服也可以手动跑）
--   1. 上个月（马来西亚时间）的佣金：生成草稿；app_settings.invoice_auto_issue → 马上发出（推送「新账单」）
--      每天都跑：月初那天生成，之后的日子没有新的佣金记录就什么都不做（generate 可以重复跑）
--   2. 已发出、过了到期日 → overdue（推送一次「逾期」）
--   3. 快到期（invoice_reminder_days 天内）→ 推送一次提醒
--   4. 买家：试用 / 这期在 renewal_reminder_days 天内结束、还没提醒过这个到期时间 → 推送「快到期」
-- =============================================================================

create or replace function public.run_billing_daily()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.app_settings%rowtype;
  v_today date := public.today_myt();
  v_last_month date := (date_trunc('month', public.today_myt()) - interval '1 month')::date;
  v_generated int := 0;
  v_issued int := 0;
  v_overdue int := 0;
  v_reminded int := 0;
  v_renewal int := 0;
  r record;
begin
  if not (public.is_admin() or public.is_service_call()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into a from public.app_settings;

  v_generated := public.generate_commission_invoices(v_last_month);
  if a.invoice_auto_issue then
    for r in
      select i.id from public.commission_invoices i
      where i.status = 'draft' and i.period_month <= v_last_month and i.commission_sen > 0
      order by i.invoice_no
    loop
      if public._issue_invoice(r.id) then
        v_issued := v_issued + 1;
      end if;
    end loop;
  end if;

  for r in
    update public.commission_invoices i set status = 'overdue', overdue_notified_at = now()
    where i.status = 'issued' and i.due_date < v_today
    returning i.*
  loop
    insert into public.notifications (wholesaler_id, event_type, payload)
    values (r.wholesaler_id, 'invoice_overdue', jsonb_build_object(
      'invoice_id', r.id, 'invoice_no', r.invoice_no, 'commission_sen', r.commission_sen, 'due_date', r.due_date));
    v_overdue := v_overdue + 1;
  end loop;

  for r in
    update public.commission_invoices i set reminded_at = now()
    where i.status = 'issued' and i.reminded_at is null
      and i.due_date >= v_today and i.due_date <= v_today + a.invoice_reminder_days
      and i.issued_at < now() - interval '1 day'            -- 刚发出的不用马上又提醒
    returning i.*
  loop
    insert into public.notifications (wholesaler_id, event_type, payload)
    values (r.wholesaler_id, 'invoice_due_soon', jsonb_build_object(
      'invoice_id', r.id, 'invoice_no', r.invoice_no, 'commission_sen', r.commission_sen, 'due_date', r.due_date));
    v_reminded := v_reminded + 1;
  end loop;

  for r in
    update public.subscriptions s set renewal_reminded_for = x.ends_at
    from (
      select s2.id, case when s2.status = 'trialing' then s2.trial_ends_at else s2.current_period_end end as ends_at
      from public.subscriptions s2
      where s2.status in ('trialing', 'active')
    ) x
    where s.id = x.id and x.ends_at is not null
      and x.ends_at > now() and x.ends_at <= now() + make_interval(days => a.renewal_reminder_days)
      and s.renewal_reminded_for is distinct from x.ends_at
    returning s.*, x.ends_at
  loop
    insert into public.notifications (shop_id, event_type, payload)
    values (r.shop_id, 'subscription_ending', jsonb_build_object(
      'subscription_id', r.id, 'status', r.status, 'ends_at', r.ends_at, 'locked_price_sen', r.locked_price_sen));
    v_renewal := v_renewal + 1;
  end loop;

  return jsonb_build_object('period_month', v_last_month, 'generated', v_generated, 'issued', v_issued,
                            'overdue', v_overdue, 'reminded', v_reminded, 'renewal_reminders', v_renewal);
end;
$$;

-- =============================================================================
-- G. 通知：收费的通知只用推送（WhatsApp 发这些要另外送审模板；没装 App 的批发商由客服打电话 / 手动发）
-- =============================================================================

create or replace function public._push_only_event(p_event_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_event_type, '') in (
    'daily_summary', 'order_unconfirmed',
    'invoice_issued', 'invoice_due_soon', 'invoice_overdue', 'subscription_ending', 'payment_received');
$$;

-- 跟第六步一样，只是「不走 WhatsApp 的事件」改成看 _push_only_event
create or replace function public._notification_route(
  p_user_id uuid,
  p_shop_id uuid,
  p_wholesaler_id uuid,
  p_event_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pref public.notify_channel := 'push';
  v_locale public.app_locale := 'zh';
  v_phone text;
  v_opt_in timestamptz;
  v_targets jsonb;
  v_can_wa boolean;
  v_has_push boolean;
  v_channel text;
begin
  if p_event_type = 'whatsapp_reply' then
    v_phone := case when p_shop_id is not null then public._whatsapp_window_phone(p_shop_id) end;
    select s.locale into v_locale from public.shops s where s.id = p_shop_id;
    return jsonb_build_object(
      'channel', case when v_phone is not null then 'whatsapp' end,
      'push_targets', '[]'::jsonb,
      'whatsapp_phone', v_phone,
      'locale', coalesce(v_locale, 'zh'));
  end if;

  if p_user_id is not null then
    select p.locale into v_locale from public.profiles p where p.id = p_user_id;
    select jsonb_agg(jsonb_build_object('target', t.fcm_token, 'kind', t.kind) order by t.last_seen_at desc, t.fcm_token)
    into v_targets
    from public.device_tokens t
    where t.user_id = p_user_id and t.last_seen_at > now() - interval '60 days';
  elsif p_wholesaler_id is not null then
    select w.notify_channel, w.locale, coalesce(w.whatsapp_phone, w.phone), w.whatsapp_opt_in_at
    into v_pref, v_locale, v_phone, v_opt_in
    from public.wholesalers w where w.id = p_wholesaler_id;
    select jsonb_agg(jsonb_build_object('target', t.fcm_token, 'kind', t.kind) order by t.last_seen_at desc, t.fcm_token)
    into v_targets
    from public.wholesaler_members m
    join public.device_tokens t on t.user_id = m.user_id
    where m.wholesaler_id = p_wholesaler_id and t.last_seen_at > now() - interval '60 days';
  elsif p_shop_id is not null then
    select s.notify_channel, s.locale, coalesce(s.whatsapp_phone, s.phone), s.whatsapp_opt_in_at
    into v_pref, v_locale, v_phone, v_opt_in
    from public.shops s where s.id = p_shop_id;
    select jsonb_agg(jsonb_build_object('target', t.fcm_token, 'kind', t.kind) order by t.last_seen_at desc, t.fcm_token)
    into v_targets
    from public.shop_members m
    join public.device_tokens t on t.user_id = m.user_id
    where m.shop_id = p_shop_id and t.last_seen_at > now() - interval '60 days';
  end if;

  v_has_push := v_targets is not null;
  v_can_wa := p_user_id is null
    and v_phone is not null
    and v_opt_in is not null
    and not public._push_only_event(p_event_type);

  v_channel := case
    when p_user_id is not null then case when v_has_push then 'push' end
    when p_shop_id is not null and v_has_push then 'push'
    when v_pref = 'whatsapp' then case when v_can_wa then 'whatsapp' end
    when v_pref = 'push' then case when v_has_push then 'push' end
    else case when v_has_push then 'push' when v_can_wa then 'whatsapp' end
  end;

  return jsonb_build_object(
    'channel', v_channel,
    'push_targets', case when v_channel = 'push' then v_targets else '[]'::jsonb end,
    'whatsapp_phone', case when v_channel = 'whatsapp' then v_phone end,
    'locale', coalesce(v_locale, 'zh')
  );
end;
$$;

-- =============================================================================
-- 定时任务：每天 00:20（马来西亚时间，UTC 16:20）跑 run_billing_daily；
-- 原来每月 1 号只生成草稿的 monthly-commission-invoices 不要了（run_billing_daily 月初那天会生成并发出）
-- =============================================================================

create or replace function public._schedule_billing_jobs()
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return false;
  end if;
  if exists (select 1 from cron.job where jobname = 'monthly-commission-invoices') then
    perform cron.unschedule('monthly-commission-invoices');
  end if;
  perform cron.schedule('billing-daily', '20 16 * * *', 'select public.run_billing_daily()');
  return true;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform public._schedule_billing_jobs();
  else
    raise notice 'pg_cron 不可用，跳过定时任务';
  end if;
end;
$$;

-- =============================================================================
-- H. 函数权限
-- =============================================================================

revoke execute on function
  public._extend_subscription(uuid, int, int, boolean, uuid, timestamptz),
  public._payment_json(uuid),
  public.create_payment_intent(uuid, public.payment_purpose, uuid, int, text),
  public.attach_payment_checkout(uuid, text, text),
  public.fail_payment(uuid, text),
  public.mark_payment_paid(uuid, text, text, int, public.payment_method, jsonb),
  public.get_payment(uuid),
  public.get_buyer_billing(uuid),
  public.get_seller_billing(uuid),
  public.get_commission_invoice(uuid),
  public.admin_list_payments(public.payment_status, public.payment_purpose, boolean, int),
  public.admin_mark_listing_fee_paid(uuid, public.payment_method, text),
  public.admin_mark_subscription_paid(uuid, int, int, public.payment_method, text),
  public._issue_invoice(uuid),
  public.admin_issue_invoice(uuid),
  public.run_billing_daily(),
  public._push_only_event(text),
  public._notification_route(uuid, uuid, uuid, text),
  public._schedule_billing_jobs()
from public, anon, authenticated;

-- 服务器（create-payment、payment-webhook）用 service_role
grant execute on function
  public.create_payment_intent(uuid, public.payment_purpose, uuid, int, text),
  public.attach_payment_checkout(uuid, text, text),
  public.fail_payment(uuid, text),
  public.mark_payment_paid(uuid, text, text, int, public.payment_method, jsonb),
  public.run_billing_daily()
to service_role;

-- App 和客服后台（函数里面再检查是不是自己的 / 是不是客服）
grant execute on function
  public.get_payment(uuid),
  public.get_buyer_billing(uuid),
  public.get_seller_billing(uuid),
  public.get_commission_invoice(uuid),
  public.admin_list_payments(public.payment_status, public.payment_purpose, boolean, int),
  public.admin_mark_listing_fee_paid(uuid, public.payment_method, text),
  public.admin_mark_subscription_paid(uuid, int, int, public.payment_method, text),
  public.admin_issue_invoice(uuid),
  public.run_billing_daily()
to authenticated;
