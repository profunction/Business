-- =============================================================================
-- 4/8 收费：月费价目、订阅、试用、免费可看的批发商、付款、佣金、佣金账单
--
-- 月费「跟着账号锁定」的规则：
--   注册时建一条订阅，locked_price_sen = 当时的月费。一直按时续费就一直用这条。
--   过了宽限期还没付 -> lapsed（已停）。回来时新建一条订阅，按当时的新价钱锁定。
-- =============================================================================

create type public.subscription_status as enum ('trialing', 'active', 'past_due', 'lapsed');
create type public.payer_type as enum ('shop', 'wholesaler');
create type public.payment_purpose as enum ('subscription', 'listing_fee', 'commission_invoice');
create type public.payment_status as enum ('pending', 'paid', 'failed', 'refunded');
create type public.payment_method as enum ('fpx', 'duitnow', 'ewallet', 'card', 'other');
create type public.commission_rate_source as enum ('override', 'founding', 'industry');
create type public.invoice_status as enum ('draft', 'issued', 'paid', 'overdue', 'void');

-- 月费价目历史：当天有效、effective_from 最新的那一行就是「当时的价钱」
create table public.pricing_plans (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null default 'buyer_monthly',
  amount_sen int not null check (amount_sen > 0),
  is_founding boolean not null default false,      -- 这个价钱算不算「创始价」
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to > effective_from)
);
create index pricing_plans_code_idx on public.pricing_plans (plan_code, effective_from desc);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  status public.subscription_status not null,
  started_at timestamptz not null default now(), -- 开始日期
  trial_ends_at timestamptz,
  locked_price_sen int not null check (locked_price_sen > 0),
  is_founding_price boolean not null default false,
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_until timestamptz,                         -- 逾期后，补付还能保留原价的最后时间
  lapsed_at timestamptz,
  gateway text,
  gateway_subscription_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- 每家店同时只能有一条还没停的订阅
create unique index subscriptions_one_open_per_shop on public.subscriptions (shop_id) where status <> 'lapsed';
create index subscriptions_shop_idx on public.subscriptions (shop_id, created_at desc);

-- 一个手机号只能试用一次
create table public.trial_claims (
  phone text primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  claimed_at timestamptz not null default now()
);

-- 未付费用户可以完整看到价钱的批发商（最多 app_settings.free_unlocked_wholesalers 家）
create table public.unlocked_wholesalers (
  shop_id uuid not null references public.shops (id) on delete cascade,
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key (shop_id, wholesaler_id)
);

-- 收到的每一笔钱（月费、创始上架费、佣金账单）
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  payer_type public.payer_type not null,
  shop_id uuid references public.shops (id) on delete set null,
  wholesaler_id uuid references public.wholesalers (id) on delete set null,
  purpose public.payment_purpose not null,
  reference_id uuid,                               -- 订阅 id 或佣金账单 id
  amount_sen int not null check (amount_sen > 0),
  gateway text,
  method public.payment_method,
  gateway_ref text,
  status public.payment_status not null default 'pending',
  paid_at timestamptz,
  raw jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (payer_type = 'shop' and shop_id is not null and wholesaler_id is null)
    or (payer_type = 'wholesaler' and wholesaler_id is not null and shop_id is null)
  ),
  unique (gateway, gateway_ref)
);
create index payments_shop_idx on public.payments (shop_id, created_at desc);
create index payments_wholesaler_idx on public.payments (wholesaler_id, created_at desc);

create sequence public.invoice_no_seq;

-- 每家批发商每月一张佣金账单
create table public.commission_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text not null unique,                 -- 例：INV2611-0007
  wholesaler_id uuid not null references public.wholesalers (id),
  period_month date not null check (extract(day from period_month) = 1),
  order_count int not null default 0,
  gmv_sen bigint not null default 0,
  commission_sen bigint not null default 0,
  status public.invoice_status not null default 'draft',
  issued_at timestamptz,
  due_date date,
  paid_at timestamptz,
  pdf_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (wholesaler_id, period_month)
);

-- 每张已送达的订单一条佣金记录（送达时自动生成，比例当时就存下来）
create table public.commission_records (
  order_id uuid primary key references public.orders (id) on delete restrict,
  wholesaler_id uuid not null references public.wholesalers (id),
  period_month date not null check (extract(day from period_month) = 1),
  base_amount_sen int not null check (base_amount_sen >= 0),  -- 货价，不含运费
  rate numeric(5, 4) not null,
  rate_source public.commission_rate_source not null,
  commission_sen int not null check (commission_sen >= 0),
  invoice_id uuid references public.commission_invoices (id) on delete set null,
  created_at timestamptz not null default now()
);
create index commission_records_wholesaler_period_idx on public.commission_records (wholesaler_id, period_month);
create index commission_records_invoice_idx on public.commission_records (invoice_id);

create trigger subscriptions_updated_at before update on public.subscriptions
  for each row execute function public.set_updated_at();
create trigger payments_updated_at before update on public.payments
  for each row execute function public.set_updated_at();
create trigger commission_invoices_updated_at before update on public.commission_invoices
  for each row execute function public.set_updated_at();
