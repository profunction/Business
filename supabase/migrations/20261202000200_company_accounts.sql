-- =============================================================================
-- 第八步第 1 期：公司账号、分店、角色、公司方案（docs/08-procurement-spec.md 第 2、3.1、3.2、7.1、7.7、11 节）
--
--   A. 新枚举（3.1 全部；旧枚举的新值在 20261202000100_procure_enums.sql）
--   B. 新表、旧表加栏位
--   C. 公司方案（价目）
--   D. 辅助函数：公司成员、角色、分店权限；扩充 my_shop_ids / is_shop_member / is_shop_owner / has_full_access
--   E. 公司分店不能走小店的下单路（USE_REQUISITION）
--   F. 登录：分店电话不会变成分店成员；自动接受邀请；批发商不能当公司成员
--   G. 公司资料、分店、成员、邀请
--   H. 公司方案：账单、续费（_extend_company_subscription）、付款（create_payment_intent / mark_payment_paid 扩充）
--   I. 每天的公司收费工作（run_company_billing_daily）
--   J. 收件箱
--   K. 客服
--   L. RLS
--   M. 定时任务
--   N. 函数权限
--
-- 规则：
--   * 公司的分店 / 工地 = 一行 shops（company_id 不是空的）。company_id 空 = 普通小店，什么都不变。
--   * 公司员工不写 shop_members，权限来自 company_members（角色）+ company_member_sites（能管哪几个分店）。
--   * 分店付不付费看公司的订阅（company_subscriptions），不看 subscriptions。
--   * 钱只在这里算：账单金额 = 锁定的价钱（一直续费不变）/ 停了再回来按当时的价钱。
--   * 客服（is_admin()）可以代任何公司操作，函数多写一行 audit_logs（acting_for_company_id）。
-- =============================================================================

-- =============================================================================
-- A. 新枚举
-- =============================================================================

create type public.company_type as enum ('corporate', 'factory', 'hotel', 'restaurant_chain', 'glc', 'other');
create type public.company_status as enum ('active', 'suspended');
create type public.company_role as enum ('admin', 'approver', 'finance', 'requester');
create type public.company_billing_cycle as enum ('monthly', 'annual');
create type public.requisition_status as enum (
  'draft', 'pending_approval', 'returned', 'rejected', 'approved', 'partially_ordered', 'ordered', 'closed', 'cancelled');
create type public.requisition_line_kind as enum ('catalog', 'free_text', 'quoted');
create type public.approval_decision as enum ('pending', 'approved', 'rejected', 'returned', 'skipped');
create type public.po_status as enum ('issued', 'acknowledged', 'partially_received', 'received', 'closed', 'cancelled');
create type public.grn_status as enum ('posted', 'void');
create type public.rfq_kind as enum ('quotation', 'sealed', 'reverse_auction');
create type public.rfq_status as enum ('draft', 'scheduled', 'open', 'closed', 'awarded', 'cancelled');
create type public.rfq_invite_status as enum ('invited', 'viewed', 'declined', 'quoted');
create type public.bid_status as enum ('draft', 'submitted', 'superseded', 'withdrawn', 'awarded', 'not_awarded', 'expired');
create type public.counter_status as enum ('open', 'accepted', 'rejected', 'superseded', 'expired');
create type public.supplier_invoice_status as enum (
  'draft', 'submitted', 'matched', 'exception', 'approved', 'disputed', 'paid', 'void');
create type public.match_result as enum ('matched', 'price_variance', 'qty_variance', 'not_received', 'not_ordered');
create type public.terms_status as enum ('requested', 'approved', 'declined', 'revoked');
create type public.statement_status as enum ('issued', 'settled', 'void');
create type public.proc_doc_kind as enum ('quote', 'invoice', 'delivery_order');
create type public.vendor_application_status as enum ('submitted', 'approved', 'rejected', 'spam');

-- =============================================================================
-- B. 表
-- =============================================================================

-- SSM 号码统一：大写、只留字母和数字（'202301012345 (1234567-x)' → '2023010123451234567X'）
create or replace function public._normalize_ssm(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g')), '');
$$;

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  legal_name text,
  ssm_no text unique check (ssm_no is null or ssm_no = public._normalize_ssm(ssm_no)),
  tin text,                                        -- 报税号（e-Invoice 用）
  sst_no text,
  company_type public.company_type not null default 'other',
  status public.company_status not null default 'active',
  status_note text,                                -- 客服停权的原因
  region_id uuid not null references public.regions (id),
  billing_email text,
  billing_address text,
  billing_contact text,
  phone text,
  locale public.app_locale not null default 'en',
  -- 设定
  auto_issue_po boolean not null default true,
  reissue_tolerance_bp int not null default 0 check (reissue_tolerance_bp between 0 and 10000),
  benchmark_tolerance_bp int not null default 1000 check (benchmark_tolerance_bp between 0 and 10000),
  match_price_tolerance_bp int not null default 0 check (match_price_tolerance_bp between 0 and 10000),
  match_qty_tolerance_bp int not null default 0 check (match_qty_tolerance_bp between 0 and 10000),
  auto_receive_days int default 14 check (auto_receive_days is null or auto_receive_days between 1 and 90),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.companies is '公司账号（公司、工厂、酒店、连锁餐厅、GLC）。分店 / 工地是 shops.company_id';

create table public.company_members (
  company_id uuid not null references public.companies (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  roles public.company_role[] not null check (cardinality(roles) > 0),
  all_sites boolean not null default true,
  title text,
  is_active boolean not null default true,
  invited_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id, user_id)
);
create index company_members_user_idx on public.company_members (user_id);

-- 不是 all_sites 的成员能管哪几个分店（admin、finance 永远全部）
create table public.company_member_sites (
  company_id uuid not null,
  user_id uuid not null,
  shop_id uuid not null references public.shops (id) on delete cascade,
  primary key (company_id, user_id, shop_id),
  foreign key (company_id, user_id) references public.company_members (company_id, user_id) on delete cascade
);
create index company_member_sites_shop_idx on public.company_member_sites (shop_id);

-- 邀请：号码还没有账号的，登录后自动接上（handle_new_user）。同一家公司同一个号码只能有一条没接受的
create table public.company_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  phone text not null check (phone ~ '^60[0-9]{9,10}$'),
  roles public.company_role[] not null check (cardinality(roles) > 0),
  all_sites boolean not null default true,
  shop_ids uuid[] not null default '{}',
  title text,
  invited_by uuid references public.profiles (id) on delete set null,
  expires_at timestamptz not null default now() + interval '14 days',
  accepted_at timestamptz,
  accepted_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index company_invites_one_open on public.company_invites (company_id, phone) where accepted_at is null;
create index company_invites_phone_idx on public.company_invites (phone) where accepted_at is null;

-- 公司方案的价目历史（跟 pricing_plans 一样：当天有效、effective_from 最新的那一行）。价钱是一期的价钱（仙）
create table public.company_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code in ('co_trial', 'co_starter', 'co_pro', 'co_enterprise')),
  name jsonb not null check (public.is_i18n_name(name)),
  monthly_price_sen int check (monthly_price_sen > 0),
  annual_price_sen int check (annual_price_sen > 0),
  max_sites int check (max_sites > 0),             -- 空 = 不限
  max_users int check (max_users > 0),
  features text[] not null default '{}' check (features <@ array[
    'requisitions', 'multi_tier', 'budgets', 'rfq', 'reverse_auction', 'ai_insights', 'ai_spend', 'statements']::text[]),
  is_public boolean not null default true,
  sort_order int not null default 0,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to > effective_from)
);
create index company_plans_code_idx on public.company_plans (code, effective_from desc);

-- 公司的订阅。locked_price_sen = 一期（月 / 年）的锁定价钱；试用中是 0。
-- pending_* = 公司自己换的方案，下一期才生效（价钱照换的那天锁定）
create table public.company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  plan_code text not null,
  billing_cycle public.company_billing_cycle not null default 'monthly',
  status public.subscription_status not null,
  started_at timestamptz not null default now(),
  trial_ends_at timestamptz,
  locked_price_sen int not null default 0 check (locked_price_sen >= 0),
  custom_price boolean not null default false,     -- 企业方案：客服设的自订价
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_until timestamptz,
  lapsed_at timestamptz,
  pending_plan_code text,
  pending_billing_cycle public.company_billing_cycle,
  pending_price_sen int check (pending_price_sen > 0),
  trial_reminded int[] not null default '{}',      -- 试用快结束提醒过的天数（7、1）
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index company_subscriptions_one_open on public.company_subscriptions (company_id) where status <> 'lapsed';
create index company_subscriptions_company_idx on public.company_subscriptions (company_id, created_at desc);

-- 一家公司（SSM）/ 一个号码只拿一次试用
create table public.company_trial_claims (
  id uuid primary key default gen_random_uuid(),
  ssm_no text unique,
  creator_phone text not null unique,
  company_id uuid not null references public.companies (id) on delete cascade,
  claimed_at timestamptz not null default now()
);

-- 公司方案的账单（CI2612-0001）。付款 = amount_sen + sst_sen
create table public.company_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text not null unique,
  company_id uuid not null references public.companies (id) on delete cascade,
  subscription_id uuid not null references public.company_subscriptions (id) on delete cascade,
  plan_code text not null,
  billing_cycle public.company_billing_cycle not null,
  period_start timestamptz,
  period_end timestamptz,
  amount_sen int not null check (amount_sen > 0),
  sst_sen int not null default 0 check (sst_sen >= 0),
  status public.invoice_status not null default 'issued',
  due_date date,
  issued_at timestamptz,
  paid_at timestamptz,
  overdue_notified_at timestamptz,
  void_reason text,
  pdf_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index company_invoices_company_idx on public.company_invoices (company_id, created_at desc);
create index company_invoices_open_idx on public.company_invoices (subscription_id) where status in ('issued', 'overdue');

-- 分店 / 工地
alter table public.shops
  add column company_id uuid references public.companies (id),
  add column site_code text,
  add column cost_center text;
create index shops_company_idx on public.shops (company_id) where company_id is not null;

-- 付款：公司付公司方案
alter table public.payments add column company_id uuid references public.companies (id) on delete set null;
alter table public.payments drop constraint payments_check;
alter table public.payments add constraint payments_payer_check check (
  (payer_type = 'shop' and shop_id is not null and wholesaler_id is null and company_id is null)
  or (payer_type = 'wholesaler' and wholesaler_id is not null and shop_id is null and company_id is null)
  or (payer_type = 'company' and company_id is not null and shop_id is null and wholesaler_id is null)
);
create index payments_company_idx on public.payments (company_id, created_at desc) where company_id is not null;

alter table public.audit_logs add column acting_for_company_id uuid;   -- 不加外键：公司删了记录也要留着
create index audit_logs_company_idx on public.audit_logs (acting_for_company_id, created_at desc)
  where acting_for_company_id is not null;

-- notifications.read_at 第二步就有了（网页收件箱用它）
create index notifications_user_unread_idx on public.notifications (user_id) where read_at is null and user_id is not null;

alter table public.app_settings
  add column company_trial_days int not null default 30 check (company_trial_days >= 0),
  add column company_grace_days int not null default 14 check (company_grace_days >= 0),
  add column company_invoice_lead_days int not null default 7 check (company_invoice_lead_days between 0 and 60);

-- 编号：PR / PO / GR / RFQ / ST / CI + YYMM（马来西亚时间）+ 流水号（每种一个 sequence）
create sequence public.doc_no_pr_seq;
create sequence public.doc_no_po_seq;
create sequence public.doc_no_gr_seq;
create sequence public.doc_no_rfq_seq;
create sequence public.doc_no_st_seq;
create sequence public.doc_no_ci_seq;

create or replace function public._next_doc_no(p_kind text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_width int := case p_kind when 'PR' then 5 when 'PO' then 5 when 'GR' then 5
                             when 'RFQ' then 4 when 'ST' then 4 when 'CI' then 4 end;
begin
  if v_width is null then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = coalesce(p_kind, 'null');
  end if;
  return p_kind || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-'
      || lpad(nextval(('public.doc_no_' || lower(p_kind) || '_seq')::regclass)::text, v_width, '0');
end;
$$;

-- 分店一定是这家公司的
create or replace function public.company_member_sites_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.shops s where s.id = new.shop_id and s.company_id = new.company_id) then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = new.shop_id::text;
  end if;
  return new;
end;
$$;

create trigger company_member_sites_check before insert or update on public.company_member_sites
  for each row execute function public.company_member_sites_check();

create trigger companies_updated_at before update on public.companies
  for each row execute function public.set_updated_at();
create trigger company_members_updated_at before update on public.company_members
  for each row execute function public.set_updated_at();
create trigger company_subscriptions_updated_at before update on public.company_subscriptions
  for each row execute function public.set_updated_at();
create trigger company_invoices_updated_at before update on public.company_invoices
  for each row execute function public.set_updated_at();

-- shops.company_id 只有客服 / 函数能改（protect_columns：security definer 函数里不检查）
drop trigger shops_protect on public.shops;
create trigger shops_protect before update on public.shops
  for each row execute function public.protect_columns('id', 'is_active', 'unlocks_changed_at', 'created_by', 'company_id');

-- =============================================================================
-- C. 公司方案（docs/08-procurement-spec.md 第 11 节；数字随时可以加新的一行改）
--   试用 30 天 = Pro 的功能；Starter RM290 / 月；Pro RM790 / 月；企业方案客服设自订价
-- =============================================================================

insert into public.company_plans
  (code, name, monthly_price_sen, annual_price_sen, max_sites, max_users, features, is_public, sort_order, effective_from)
values
  ('co_trial', '{"zh": "试用", "en": "Trial", "ms": "Percubaan"}', null, null, 3, 10,
   '{requisitions,multi_tier,budgets,rfq,reverse_auction,ai_insights,ai_spend,statements}', false, 0, '2026-01-01'),
  ('co_starter', '{"zh": "入门版", "en": "Starter", "ms": "Permulaan"}', 29000, 290000, 3, 15,
   '{requisitions,rfq,statements}', true, 1, '2026-01-01'),
  ('co_pro', '{"zh": "专业版", "en": "Pro", "ms": "Pro"}', 79000, 790000, 15, 60,
   '{requisitions,multi_tier,budgets,rfq,reverse_auction,ai_insights,ai_spend,statements}', true, 2, '2026-01-01'),
  ('co_enterprise', '{"zh": "企业版", "en": "Enterprise", "ms": "Perusahaan"}', null, null, null, null,
   '{requisitions,multi_tier,budgets,rfq,reverse_auction,ai_insights,ai_spend,statements}', true, 3, '2026-01-01');

-- 现在的方案（当天有效、最新的那一行）
create or replace function public._company_plan(p_code text)
returns public.company_plans
language sql
stable
security definer
set search_path = ''
as $$
  select cp.* from public.company_plans cp
  where cp.code = p_code and cp.effective_from <= now() and (cp.effective_to is null or cp.effective_to > now())
  order by cp.effective_from desc
  limit 1;
$$;

-- 现在一期的价钱（没有价钱 → null，例如企业方案要客服设）
create or replace function public._company_plan_price(p_code text, p_cycle public.company_billing_cycle)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select case p_cycle when 'annual' then p.annual_price_sen else p.monthly_price_sen end
  from public._company_plan(p_code) p;
$$;

create or replace function public._cycle_interval(p_cycle public.company_billing_cycle)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case p_cycle when 'annual' then interval '1 year' else interval '1 month' end;
$$;

-- =============================================================================
-- D. 辅助函数
-- =============================================================================

-- 这个人能管的公司分店：有效成员，而且 admin / finance / all_sites / 在 company_member_sites
create or replace function public._company_site_ids(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
  from public.company_members m
  join public.shops s on s.company_id = m.company_id
  where m.user_id = p_user_id and m.is_active
    and (m.all_sites or m.roles && '{admin,finance}'::public.company_role[]
         or exists (select 1 from public.company_member_sites x
                    where x.company_id = m.company_id and x.user_id = m.user_id and x.shop_id = s.id));
$$;

create or replace function public.my_company_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.company_id from public.company_members m where m.user_id = auth.uid() and m.is_active;
$$;

-- 我在这家公司的角色（不是有效成员 = 空）
create or replace function public.company_roles(p_company_id uuid)
returns public.company_role[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select m.roles from public.company_members m
    where m.company_id = p_company_id and m.user_id = auth.uid() and m.is_active
  ), '{}'::public.company_role[]);
$$;

create or replace function public.has_company_role(p_company_id uuid, p_roles public.company_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.company_roles(p_company_id) && p_roles;
$$;

create or replace function public.is_company_shop(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.shops s where s.id = p_shop_id and s.company_id is not null);
$$;

create or replace function public.can_access_site(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_shop_id in (select public._company_site_ids(auth.uid()));
$$;

-- 第二步的辅助函数，多包括公司分店（RLS、get_offers、get_order、list_orders、评价都不用改）
create or replace function public.my_shop_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select shop_id from public.shop_members where user_id = auth.uid()
  union
  select public._company_site_ids(auth.uid());
$$;

create or replace function public.is_shop_member(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.shop_members where shop_id = p_shop_id and user_id = auth.uid())
      or public.can_access_site(p_shop_id);
$$;

-- 公司的 admin 等于分店的老板
create or replace function public.is_shop_owner(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.shop_members
    where shop_id = p_shop_id and user_id = auth.uid() and member_role = 'owner'
  )
  or exists (
    select 1 from public.shops s
    join public.company_members m on m.company_id = s.company_id
    where s.id = p_shop_id and m.user_id = auth.uid() and m.is_active and 'admin' = any (m.roles)
  );
$$;

create or replace function public.can_access_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and (
        o.shop_id in (select public.my_shop_ids())
        or o.wholesaler_id in (select wholesaler_id from public.wholesaler_members where user_id = auth.uid())
        or public.is_admin()
      )
  );
$$;

-- 公司的订阅现在能不能用（公司没停权；试用中、有效、或宽限期内）
create or replace function public._company_plan_live(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.companies c
    join public.company_subscriptions s on s.company_id = c.id and s.status <> 'lapsed'
    cross join public.app_settings a
    where c.id = p_company_id and c.status = 'active'
      and (
        (s.status = 'trialing' and s.trial_ends_at > now())
        or (s.status = 'active'
            and s.current_period_end + make_interval(days => a.company_grace_days) > now())
        or (s.status = 'past_due'
            and coalesce(s.grace_until,
                         coalesce(s.current_period_end, s.trial_ends_at) + make_interval(days => a.company_grace_days)) > now())
      )
  );
$$;

-- 第二步的付费检查：公司分店看公司的订阅；小店照旧
create or replace function public.has_full_access(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when sh.company_id is not null then public._company_plan_live(sh.company_id)
      else exists (
        select 1
        from public.subscriptions s
        cross join public.app_settings a
        where s.shop_id = sh.id
          and (
            (s.status = 'trialing' and s.trial_ends_at > now())
            or (s.status = 'active'
                and s.current_period_end + make_interval(days => a.subscription_grace_days) > now())
            or (s.status = 'past_due'
                and coalesce(s.grace_until, s.current_period_end + make_interval(days => a.subscription_grace_days)) > now())
          )
      )
    end
    from public.shops sh where sh.id = p_shop_id
  ), false);
$$;

-- 现在这一条订阅（没停的；都停了就最新的那条）
create or replace function public._company_current_sub(p_company_id uuid)
returns public.company_subscriptions
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from public.company_subscriptions s
  where s.company_id = p_company_id
  order by (s.status <> 'lapsed') desc, s.created_at desc
  limit 1;
$$;

-- 功能看的方案：试用 = co_pro 全部功能
create or replace function public._company_feature_plan(p_company_id uuid)
returns public.company_plans
language sql
stable
security definer
set search_path = ''
as $$
  select p.* from public._company_current_sub(p_company_id) s
  cross join lateral public._company_plan(case when s.status = 'trialing' then 'co_pro' else s.plan_code end) p;
$$;

create or replace function public.company_has_feature(p_company_id uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public._company_plan_live(p_company_id)
     and coalesce(p_feature = any ((public._company_feature_plan(p_company_id)).features), false);
$$;

-- 要有这个功能才能做：订阅停了 → COMPANY_PLAN_INACTIVE；方案没有 → PLAN_FEATURE_REQUIRED（detail = 功能代码）
create or replace function public._require_company_feature(p_company_id uuid, p_feature text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public._company_plan_live(p_company_id) then
    raise exception 'COMPANY_PLAN_INACTIVE' using errcode = 'P0001';
  end if;
  if not public.company_has_feature(p_company_id, p_feature) then
    raise exception 'PLAN_FEATURE_REQUIRED' using errcode = 'P0001', detail = p_feature;
  end if;
end;
$$;

-- 方案上限（试用 / 现在的方案；停了看最后那条的方案）。空 = 不限
create or replace function public._company_limits(p_company_id uuid, out max_sites int, out max_users int)
language sql
stable
security definer
set search_path = ''
as $$
  select p.max_sites, p.max_users
  from public._company_current_sub(p_company_id) s
  cross join lateral public._company_plan(s.plan_code) p;
$$;

-- 有效成员、有其中一个角色，或客服。公司不存在 → COMPANY_NOT_FOUND；否则 NOT_ALLOWED
create or replace function public._require_company_role(p_company_id uuid, p_roles public.company_role[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null and not public.is_service_call() then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  if not exists (select 1 from public.companies c where c.id = p_company_id) then
    raise exception 'COMPANY_NOT_FOUND' using errcode = 'P0001';
  end if;
  if public.is_admin() or public.is_service_call() then
    return;
  end if;
  if not public.has_company_role(p_company_id, p_roles) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
end;
$$;

-- 停权的公司：成员不能改东西（客服可以）
create or replace function public._require_company_active(p_company_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin()
     and exists (select 1 from public.companies c where c.id = p_company_id and c.status = 'suspended') then
    raise exception 'COMPANY_SUSPENDED' using errcode = 'P0001';
  end if;
end;
$$;

-- 客服代公司操作：写一行 audit_logs（不是客服就不写）
create or replace function public._company_audit(
  p_action text,
  p_table text,
  p_record_id text,
  p_company_id uuid,
  p_before jsonb default null,
  p_after jsonb default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (actor_id, acting_for_company_id, action, table_name, record_id, before, after)
  select auth.uid(), p_company_id, p_action, p_table, p_record_id, p_before, p_after
  where public.is_admin();
$$;

-- 给公司的通知：排成每个人一条（有其中一个角色的有效成员），payload 多 company_id、company_name
create or replace function public._notify_company(
  p_company_id uuid,
  p_roles public.company_role[],
  p_event_type text,
  p_payload jsonb default '{}'
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  insert into public.notifications (user_id, event_type, payload)
  select m.user_id, p_event_type,
         coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('company_id', c.id, 'company_name', c.name)
  from public.company_members m
  join public.companies c on c.id = m.company_id
  where m.company_id = p_company_id and m.is_active and m.roles && p_roles;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public._uuid_or_null(p text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case when p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p::uuid end;
$$;

-- =============================================================================
-- E. 公司分店不能走小店的下单路：一定要开申请单（采购要有记录；客服、服务器也一样）
--   place_order（admin_place_order、submit_order_draft 都经过它）、reorder_last、reserve_voice_order_run、
--   购物车（cart_items 新增 / 修改的 trigger；admin_set_cart_item 也一样）、结账（checkouts 不是 procurement 的）
-- =============================================================================

create or replace function public._guard_not_company_shop(p_shop_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.shops s where s.id = p_shop_id and s.company_id is not null) then
    raise exception 'USE_REQUISITION' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.cart_items_company_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._guard_not_company_shop(new.shop_id);
  return new;
end;
$$;

create trigger cart_items_company_guard before insert or update on public.cart_items
  for each row execute function public.cart_items_company_guard();

create or replace function public.checkouts_company_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.source is distinct from 'procurement' then
    perform public._guard_not_company_shop(new.shop_id);
  end if;
  return new;
end;
$$;

create trigger checkouts_company_guard before insert on public.checkouts
  for each row execute function public.checkouts_company_guard();

-- 第二步的 place_order，权限检查之后多一行 _guard_not_company_shop（其他不变）
create or replace function public.place_order(
  p_shop_id uuid,
  p_expected_total_sen int default null,
  p_note text default null,
  p_source public.order_source default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  v_is_service boolean := public.is_service_call();
  v_source public.order_source;
  v_channel public.event_channel;
  v_quote jsonb;
  v_zone uuid;
  v_region_code text;
  v_checkout_id uuid;
  v_order_id uuid;
  g jsonb;
begin
  if not (public.is_shop_member(p_shop_id) or v_is_admin or v_is_service) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  perform public._guard_not_company_shop(p_shop_id);

  if v_is_admin or v_is_service then
    v_source := coalesce(p_source, 'admin');
    v_channel := case when v_is_admin then 'admin' else 'system' end;
  else
    v_source := coalesce(p_source, 'app');
    v_channel := 'app';
    if v_source not in ('app', 'voice', 'reorder') then
      raise exception 'INVALID_SOURCE' using errcode = 'P0001';
    end if;
  end if;

  -- 锁住购物车和商品，避免算钱的时候刚好有人改价
  perform 1 from public.cart_items c where c.shop_id = p_shop_id for update;
  perform 1 from public.products p
  where p.id in (select c.product_id from public.cart_items c where c.shop_id = p_shop_id)
  for share;

  v_quote := public._quote_cart(p_shop_id);
  if jsonb_array_length(v_quote -> 'groups') = 0 then
    raise exception 'CART_EMPTY' using errcode = 'P0001';
  end if;
  if not (v_quote ->> 'can_place')::boolean then
    raise exception 'CART_HAS_PROBLEMS' using errcode = 'P0001', detail = v_quote::text;
  end if;
  if p_expected_total_sen is not null and p_expected_total_sen <> (v_quote ->> 'total_sen')::int then
    raise exception 'PRICE_CHANGED' using errcode = 'P0001', detail = v_quote::text;
  end if;

  select s.zone_id, r.code into v_zone, v_region_code
  from public.shops s
  join public.delivery_zones z on z.id = s.zone_id
  join public.regions r on r.id = z.region_id
  where s.id = p_shop_id;

  insert into public.checkouts (shop_id, source, goods_total_sen, shipping_total_sen, created_by)
  values (p_shop_id, v_source, (v_quote ->> 'goods_total_sen')::int, (v_quote ->> 'shipping_total_sen')::int, v_uid)
  returning id into v_checkout_id;

  for g in select * from jsonb_array_elements(v_quote -> 'groups') loop
    insert into public.orders (
      order_no, checkout_id, shop_id, wholesaler_id, zone_id,
      goods_subtotal_sen, shipping_fee_sen, expected_delivery_date, note, source, created_by
    )
    values (
      public._next_order_no(v_region_code), v_checkout_id, p_shop_id, (g ->> 'wholesaler_id')::uuid, v_zone,
      (g ->> 'goods_subtotal_sen')::int, (g ->> 'shipping_fee_sen')::int,
      (g ->> 'expected_delivery_date')::date, nullif(trim(p_note), ''), v_source, v_uid
    )
    returning id into v_order_id;

    insert into public.order_items (
      order_id, product_id, catalog_item_id, name_snapshot, unit_snapshot, pack_qty_snapshot, unit_price_sen, qty
    )
    select v_order_id, p.id, p.catalog_item_id, p.name, p.unit, p.pack_qty, p.price_sen, c.qty
    from public.cart_items c
    join public.products p on p.id = c.product_id
    where c.shop_id = p_shop_id and p.wholesaler_id = (g ->> 'wholesaler_id')::uuid;

    insert into public.order_status_events (order_id, from_status, to_status, actor_id, channel)
    values (v_order_id, null, 'pending', v_uid, v_channel);
  end loop;

  delete from public.cart_items c where c.shop_id = p_shop_id;
  return v_checkout_id;
end;
$$;

-- 第二步的 reorder_last，权限检查之后多一行 _guard_not_company_shop（其他不变）
create or replace function public.reorder_last(p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checkout uuid;
  v_skipped jsonb;
  v_changes jsonb;
  v_added int;
begin
  if not (public.is_shop_member(p_shop_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  perform public._guard_not_company_shop(p_shop_id);

  select c.id into v_checkout
  from public.checkouts c
  where c.shop_id = p_shop_id
  order by c.created_at desc
  limit 1;
  if v_checkout is null then
    raise exception 'NO_PREVIOUS_ORDER' using errcode = 'P0001';
  end if;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'product_name', li.name_snapshot,
      'reason', case when p.id is null then 'PRODUCT_REMOVED' else 'PRODUCT_UNAVAILABLE' end
    )) filter (where p.id is null or p.status <> 'active'), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'product_id', p.id,
      'product_name', p.name,
      'old_price_sen', li.unit_price_sen,
      'new_price_sen', p.price_sen
    )) filter (where p.status = 'active' and p.price_sen <> li.unit_price_sen
                 and public.can_see_prices(p_shop_id, p.wholesaler_id)), '[]'::jsonb)
  into v_skipped, v_changes
  from public.order_items li
  join public.orders o on o.id = li.order_id
  left join public.products p on p.id = li.product_id
  where o.checkout_id = v_checkout;

  delete from public.cart_items c where c.shop_id = p_shop_id;
  insert into public.cart_items (shop_id, product_id, qty, added_by)
  select p_shop_id, li.product_id, li.qty, auth.uid()
  from public.order_items li
  join public.orders o on o.id = li.order_id
  join public.products p on p.id = li.product_id
  where o.checkout_id = v_checkout and p.status = 'active'
  on conflict (shop_id, product_id) do update set qty = excluded.qty;
  get diagnostics v_added = row_count;

  return jsonb_build_object(
    'source_checkout_id', v_checkout,
    'added_count', v_added,
    'skipped', v_skipped,
    'price_changes', v_changes,
    'quote', public._quote_cart(p_shop_id)
  );
end;
$$;

-- 第六步的 reserve_voice_order_run，找到店之后多一行：公司分店 → USE_REQUISITION（其他不变）
create or replace function public.reserve_voice_order_run(
  p_shop_id uuid,
  p_user_id uuid,
  p_run_id uuid,
  p_source public.draft_source,
  p_audio_path text default null,
  p_whatsapp_message_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_shop public.shops%rowtype;
  l record;
  v_wait int;
  v_window text;
  v_retry int;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if p_run_id is null then
    raise exception 'INVALID_RUN_ID' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.voice_order_runs r where r.run_id = p_run_id) then
    raise exception 'RUN_ID_USED' using errcode = 'P0001';
  end if;
  if p_source is null or p_source = 'admin' then
    raise exception 'INVALID_SOURCE' using errcode = 'P0001';
  end if;

  select * into v_shop from public.shops s where s.id = p_shop_id for no key update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_shop.company_id is not null then
    raise exception 'USE_REQUISITION' using errcode = 'P0001';
  end if;

  if p_source = 'app_voice' then
    if p_user_id is null or not (
      exists (select 1 from public.shop_members m where m.shop_id = v_shop.id and m.user_id = p_user_id)
      or exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'admin')
    ) then
      return jsonb_build_object('result', 'not_member');
    end if;
    if not public._voice_path_ok(v_shop.id, p_audio_path) then
      return jsonb_build_object('result', 'invalid_path');
    end if;
  else
    if p_whatsapp_message_id is null or not exists (
      select 1 from public.whatsapp_messages m
      where m.id = p_whatsapp_message_id and m.shop_id = v_shop.id and m.direction = 'inbound'
    ) then
      return jsonb_build_object('result', 'not_found');
    end if;
    if p_audio_path is not null and not public._voice_path_ok(v_shop.id, p_audio_path) then
      return jsonb_build_object('result', 'invalid_path');
    end if;
  end if;

  for l in select * from public._voice_run_limits() loop
    select greatest(1, ceil(extract(epoch from (x.created_at + l.window_len - v_now)))::int) into v_wait
    from (
      select r.created_at, row_number() over (order by r.created_at desc, r.id desc) as k
      from public.voice_order_runs r
      where r.shop_id = v_shop.id and r.created_at > v_now - l.window_len
    ) x
    where x.k = l.max_runs;
    if v_wait is not null and (v_retry is null or v_wait > v_retry) then
      v_window := l.window_name;
      v_retry := v_wait;
    end if;
  end loop;
  if v_window is not null then
    return jsonb_build_object('result', 'quota', 'window', v_window, 'retry_after_sec', v_retry, 'locale', v_shop.locale);
  end if;

  insert into public.voice_order_runs (run_id, shop_id, user_id, source, audio_path, whatsapp_message_id, created_at)
  values (p_run_id, v_shop.id, p_user_id, p_source, p_audio_path, p_whatsapp_message_id, v_now);

  return jsonb_build_object(
    'result', 'ok',
    'run_id', p_run_id,
    'shop_id', v_shop.id,
    'shop_name', v_shop.name,
    'locale', v_shop.locale,
    'full_access', public.has_full_access(v_shop.id)
  );
end;
$$;

-- 开始 14 天试用（第二步的，多一条）：公司分店不拿小店的试用（看公司的订阅）
create or replace function public._start_trial(p_shop_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(p_phone);
  v_plan record;
  v_days int;
begin
  if v_phone is null then
    return false;
  end if;
  if exists (select 1 from public.shops s where s.id = p_shop_id and s.company_id is not null) then
    return false;
  end if;
  if exists (select 1 from public.subscriptions where shop_id = p_shop_id) then
    return false;
  end if;

  insert into public.trial_claims (phone, shop_id) values (v_phone, p_shop_id)
  on conflict (phone) do nothing;
  if not found then
    return false;                                  -- 这个手机号用过试用了
  end if;

  select * into v_plan from public.current_plan('buyer_monthly');
  if v_plan.plan_id is null then
    raise exception 'NO_PRICING_PLAN' using errcode = 'P0001';
  end if;
  select trial_days into v_days from public.app_settings;

  insert into public.subscriptions (shop_id, status, started_at, trial_ends_at, locked_price_sen, is_founding_price)
  values (p_shop_id, 'trialing', now(), now() + make_interval(days => v_days), v_plan.amount_sen, v_plan.is_founding);
  return true;
end;
$$;

-- =============================================================================
-- F. 登录
-- =============================================================================

-- 接受一张邀请：加成员（已经是成员就照邀请改角色、重新启用）、能管的分店、记下接受了
create or replace function public._accept_company_invite(p_invite_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.company_invites%rowtype;
begin
  select * into i from public.company_invites where id = p_invite_id and accepted_at is null for update;
  if not found then
    return false;
  end if;
  insert into public.company_members (company_id, user_id, roles, all_sites, title, is_active, invited_by)
  values (i.company_id, p_user_id, i.roles, i.all_sites, i.title, true, i.invited_by)
  on conflict (company_id, user_id) do update
    set roles = excluded.roles, all_sites = excluded.all_sites, title = coalesce(excluded.title, public.company_members.title),
        is_active = true;
  delete from public.company_member_sites x where x.company_id = i.company_id and x.user_id = p_user_id;
  insert into public.company_member_sites (company_id, user_id, shop_id)
  select i.company_id, p_user_id, s.id
  from public.shops s
  where s.id = any (i.shop_ids) and s.company_id = i.company_id;
  update public.company_invites set accepted_at = now(), accepted_by = p_user_id where id = i.id;
  return true;
end;
$$;

-- 这个号码没过期的邀请全部接上（批发商账号不接：ROLE_MISMATCH 规则）。回传接了几张
create or replace function public._accept_company_invites(p_user_id uuid, p_phone text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(p_phone);
  v_count int := 0;
  r record;
begin
  if v_phone is null
     or exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'seller')
     or exists (select 1 from public.wholesaler_members m where m.user_id = p_user_id) then
    return 0;
  end if;
  for r in
    select i.id from public.company_invites i
    where i.phone = v_phone and i.accepted_at is null and i.expires_at > now()
    order by i.created_at
  loop
    if public._accept_company_invite(r.id, p_user_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- 新账号（第二步的，改两个地方）：自动接上店铺时跳过公司分店（分店电话不是员工）；自动接受公司邀请
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(new.phone);
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role public.user_role := 'buyer';
begin
  -- 注册时只能选买家或批发商，客服（admin）只能由客服设定
  if v_meta ->> 'role' = 'seller' then
    v_role := 'seller';
  end if;
  if v_phone is not null
     and exists (select 1 from public.wholesalers w where v_phone in (w.phone, w.whatsapp_phone)) then
    v_role := 'seller';
  end if;

  insert into public.profiles (id, role, phone, full_name, locale)
  values (
    new.id,
    v_role,
    v_phone,
    nullif(trim(v_meta ->> 'full_name'), ''),
    case when v_meta ->> 'locale' in ('zh', 'en', 'ms') then (v_meta ->> 'locale')::public.app_locale else 'zh' end
  );

  if v_phone is not null then
    insert into public.wholesaler_members (wholesaler_id, user_id, member_role)
    select w.id, new.id, 'owner'
    from public.wholesalers w
    where v_phone in (w.phone, w.whatsapp_phone)
      and not exists (select 1 from public.wholesaler_members m where m.wholesaler_id = w.id)
    on conflict do nothing;

    insert into public.shop_members (shop_id, user_id, member_role)
    select s.id, new.id, 'owner'
    from public.shops s
    where v_phone in (s.phone, s.whatsapp_phone)
      and s.company_id is null
      and not exists (select 1 from public.shop_members m where m.shop_id = s.id)
    on conflict do nothing;

    perform public._accept_company_invites(new.id, v_phone);
  end if;

  return new;
end;
$$;

-- 换了手机号：资料跟着改；新号码有公司邀请就接上
create or replace function public.handle_user_phone_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set phone = public.normalize_phone(new.phone) where id = new.id;
  perform public._accept_company_invites(new.id, new.phone);
  return new;
end;
$$;

-- 批发商自己注册（第四步的，多一条）：公司成员不能注册批发商（ROLE_MISMATCH）
create or replace function public.register_wholesaler(
  p_name text,
  p_region_id uuid,
  p_industry_id uuid,
  p_address text default null,
  p_contact_name text default null,
  p_whatsapp_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_pending uuid;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  select * into v_profile from public.profiles where id = v_uid for no key update;
  if v_profile.role = 'buyer' and exists (select 1 from public.shop_members m where m.user_id = v_uid) then
    raise exception 'ROLE_MISMATCH' using errcode = '42501';
  end if;
  if v_profile.role is distinct from 'admin'
     and exists (select 1 from public.company_members m where m.user_id = v_uid and m.is_active) then
    raise exception 'ROLE_MISMATCH' using errcode = '42501';
  end if;
  if v_profile.role is distinct from 'admin' then
    select w.id into v_pending
    from public.wholesalers w
    where w.status = 'pending'
      and (w.created_by = v_uid
           or exists (select 1 from public.wholesaler_members m
                      where m.wholesaler_id = w.id and m.user_id = v_uid and m.member_role = 'owner'))
    order by w.created_at
    limit 1;
    if v_pending is not null then
      raise exception 'WHOLESALER_ALREADY_PENDING' using errcode = 'P0001', detail = v_pending::text;
    end if;
  end if;

  insert into public.wholesalers (name, industry_id, region_id, address, contact_name, phone, whatsapp_phone, locale, status, created_by)
  values (
    trim(p_name), p_industry_id, p_region_id, p_address,
    coalesce(p_contact_name, v_profile.full_name),
    v_profile.phone,
    coalesce(p_whatsapp_phone, v_profile.phone),
    v_profile.locale,
    'pending',
    v_uid
  )
  returning id into v_id;

  insert into public.wholesaler_members (wholesaler_id, user_id, member_role) values (v_id, v_uid, 'owner');
  update public.profiles set role = 'seller' where id = v_uid and role = 'buyer';
  return v_id;
end;
$$;

-- 登录后：我是谁、我有哪些店 / 批发商（第三步的），多回传我是成员的公司
--   companies: [{id, name, status, roles, all_sites, sites: [{id, name}], plan_status, has_access}]
create or replace function public.get_my_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'profile', (
      select jsonb_build_object('id', p.id, 'role', p.role, 'full_name', p.full_name, 'phone', p.phone, 'locale', p.locale)
      from public.profiles p where p.id = v_uid
    ),
    'shops', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'member_role', m.member_role, 'zone_id', s.zone_id
      ) order by s.created_at)
      from public.shop_members m join public.shops s on s.id = m.shop_id
      where m.user_id = v_uid and s.is_active
    ), '[]'::jsonb),
    'wholesalers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id, 'name', w.name, 'member_role', m.member_role, 'status', w.status
      ) order by w.created_at)
      from public.wholesaler_members m join public.wholesalers w on w.id = m.wholesaler_id
      where m.user_id = v_uid
    ), '[]'::jsonb),
    'companies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'status', c.status,
        'roles', to_jsonb(m.roles),
        'all_sites', m.all_sites,
        'sites', coalesce((
          select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name, s.id)
          from public.shops s
          where s.company_id = c.id and s.is_active and s.id in (select public._company_site_ids(v_uid))
        ), '[]'::jsonb),
        'plan_status', (public._company_current_sub(c.id)).status,
        'has_access', public._company_plan_live(c.id)
      ) order by c.name, c.id)
      from public.company_members m join public.companies c on c.id = m.company_id
      where m.user_id = v_uid and m.is_active
    ), '[]'::jsonb)
  );
end;
$$;

-- =============================================================================
-- G. 公司资料、分店、成员、邀请
-- =============================================================================

create or replace function public._company_json(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(c) || jsonb_build_object('region_name', r.name)
  from public.companies c join public.regions r on r.id = c.region_id
  where c.id = p_company_id;
$$;

create or replace function public._company_site_json(p_shop_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s.id, 'company_id', s.company_id, 'name', s.name, 'site_code', s.site_code, 'cost_center', s.cost_center,
    'zone_id', s.zone_id, 'zone_name', z.name, 'address', s.address, 'contact_name', s.contact_name, 'phone', s.phone,
    'is_active', s.is_active, 'created_at', s.created_at)
  from public.shops s join public.delivery_zones z on z.id = s.zone_id
  where s.id = p_shop_id;
$$;

-- 订阅的样子：状态、方案（三语名字、功能、上限）、试用 / 这期到哪天、宽限期、下一期换的方案、现在能不能用
create or replace function public._company_subscription_json(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s.id,
    'status', s.status,
    'plan_code', s.plan_code,
    'plan_name', p.name,
    'billing_cycle', s.billing_cycle,
    'locked_price_sen', s.locked_price_sen,
    'custom_price', s.custom_price,
    'started_at', s.started_at,
    'trial_ends_at', s.trial_ends_at,
    'current_period_start', s.current_period_start,
    'current_period_end', s.current_period_end,
    'grace_until', s.grace_until,
    'lapsed_at', s.lapsed_at,
    'pending_plan_code', s.pending_plan_code,
    'pending_billing_cycle', s.pending_billing_cycle,
    'pending_price_sen', s.pending_price_sen,
    'has_access', public._company_plan_live(p_company_id),
    'features', to_jsonb(coalesce((public._company_feature_plan(p_company_id)).features, '{}'::text[])),
    'max_sites', p.max_sites,
    'max_users', p.max_users
  )
  from public._company_current_sub(p_company_id) s
  left join lateral public._company_plan(s.plan_code) p on true
  where s.id is not null;
$$;

create or replace function public._company_invoice_json(p_invoice_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', i.id, 'invoice_no', i.invoice_no, 'company_id', i.company_id, 'subscription_id', i.subscription_id,
    'plan_code', i.plan_code, 'plan_name', (public._company_plan(i.plan_code)).name, 'billing_cycle', i.billing_cycle,
    'period_start', i.period_start, 'period_end', i.period_end, 'amount_sen', i.amount_sen, 'sst_sen', i.sst_sen,
    'total_sen', i.amount_sen + i.sst_sen, 'status', i.status, 'due_date', i.due_date, 'issued_at', i.issued_at,
    'paid_at', i.paid_at, 'void_reason', i.void_reason, 'pdf_path', i.pdf_path, 'created_at', i.created_at)
  from public.company_invoices i where i.id = p_invoice_id;
$$;

-- 成员 + 邀请
create or replace function public._company_members_json(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'full_name', p.full_name, 'phone', p.phone, 'roles', to_jsonb(m.roles),
        'all_sites', m.all_sites,
        'shop_ids', coalesce((select jsonb_agg(x.shop_id order by x.shop_id) from public.company_member_sites x
                              where x.company_id = m.company_id and x.user_id = m.user_id), '[]'::jsonb),
        'title', m.title, 'is_active', m.is_active, 'created_at', m.created_at
      ) order by m.is_active desc, ('admin' = any (m.roles)) desc, m.created_at, m.user_id)
      from public.company_members m join public.profiles p on p.id = m.user_id
      where m.company_id = p_company_id
    ), '[]'::jsonb),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'phone', i.phone, 'roles', to_jsonb(i.roles), 'all_sites', i.all_sites, 'shop_ids', to_jsonb(i.shop_ids),
        'title', i.title, 'expires_at', i.expires_at, 'expired', i.expires_at <= now(),
        'invited_by_name', ib.full_name, 'created_at', i.created_at
      ) order by i.created_at desc, i.id)
      from public.company_invites i left join public.profiles ib on ib.id = i.invited_by
      where i.company_id = p_company_id and i.accepted_at is null
    ), '[]'::jsonb)
  );
$$;

-- 公司现在算几个用户：有效成员 + 没过期、没接受的邀请（p_except_phone 那个号码的旧邀请不算：会被换掉）
create or replace function public._company_user_count(p_company_id uuid, p_except_phone text default null)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select (select count(*)::int from public.company_members m where m.company_id = p_company_id and m.is_active)
       + (select count(*)::int from public.company_invites i
          where i.company_id = p_company_id and i.accepted_at is null and i.expires_at > now()
            and i.phone is distinct from p_except_phone);
$$;

-- 建一个分店（register_company、add_company_site 共用）。超过方案的分店数 → PLAN_LIMIT_SITES（detail = 上限）
create or replace function public._add_company_site(
  p_company_id uuid,
  p_name text,
  p_zone_id uuid,
  p_address text,
  p_contact_name text,
  p_phone text,
  p_site_code text default null,
  p_cost_center text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max int;
  v_id uuid;
begin
  if coalesce(trim(p_name), '') = '' then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'name';
  end if;
  if not exists (select 1 from public.delivery_zones z where z.id = p_zone_id and z.is_active) then
    raise exception 'INVALID_ZONE' using errcode = 'P0001';
  end if;
  perform 1 from public.companies c where c.id = p_company_id for no key update;   -- 同时加的排队算
  v_max := (public._company_limits(p_company_id)).max_sites;
  if v_max is not null
     and (select count(*) from public.shops s where s.company_id = p_company_id and s.is_active) >= v_max then
    raise exception 'PLAN_LIMIT_SITES' using errcode = 'P0001', detail = v_max::text;
  end if;
  insert into public.shops (company_id, name, shop_type, zone_id, address, contact_name, phone, locale, site_code, cost_center, created_by)
  select p_company_id, trim(p_name), 'other', p_zone_id, nullif(trim(p_address), ''), nullif(trim(p_contact_name), ''),
         nullif(trim(p_phone), ''), c.locale, nullif(trim(p_site_code), ''), nullif(trim(p_cost_center), ''), auth.uid()
  from public.companies c where c.id = p_company_id
  returning id into v_id;
  return v_id;
end;
$$;

-- 开一张公司方案账单（下一期）。没得收（试用还没选方案、企业方案没设价钱）或已经有没付的 → null。
--   没停的订阅：下一期从试用结束 / 这期结束开始，方案 = 换的方案（没换就照旧），价钱 = 换的那天锁定的 / 锁定价，
--               到期 = 下一期开始那天（马来西亚日期）
--   停了：从付款那天开始，价钱 = 今天的价钱（客服的自订价照旧），到期 = 今天
create or replace function public._issue_company_invoice(p_subscription_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.company_subscriptions%rowtype;
  v_plan text;
  v_cycle public.company_billing_cycle;
  v_amount int;
  v_start timestamptz;
  v_due date;
  v_id uuid;
begin
  select * into s from public.company_subscriptions where id = p_subscription_id for update;
  if not found then
    return null;
  end if;
  if exists (select 1 from public.company_invoices i where i.subscription_id = s.id and i.status in ('issued', 'overdue')) then
    return null;
  end if;

  v_plan := coalesce(s.pending_plan_code, s.plan_code);
  v_cycle := coalesce(s.pending_billing_cycle, s.billing_cycle);
  if s.status = 'lapsed' then
    if v_plan = 'co_trial' then
      v_plan := 'co_starter';
    end if;
    v_amount := case when s.custom_price and s.pending_plan_code is null then s.locked_price_sen
                     else public._company_plan_price(v_plan, v_cycle) end;
    v_start := now();
    v_due := public.today_myt();
  else
    if v_plan = 'co_trial' then
      return null;                                 -- 试用中还没选方案
    end if;
    v_amount := coalesce(s.pending_price_sen, nullif(s.locked_price_sen, 0));
    v_start := case when s.status = 'trialing' then s.trial_ends_at else s.current_period_end end;
    v_start := coalesce(v_start, now());
    v_due := (v_start at time zone 'Asia/Kuala_Lumpur')::date;
  end if;
  if v_amount is null or v_amount <= 0 then
    return null;
  end if;

  insert into public.company_invoices (
    invoice_no, company_id, subscription_id, plan_code, billing_cycle, period_start, period_end,
    amount_sen, status, due_date, issued_at
  )
  values (
    public._next_doc_no('CI'), s.company_id, s.id, v_plan, v_cycle, v_start, v_start + public._cycle_interval(v_cycle),
    v_amount, 'issued', v_due, now()
  )
  returning id into v_id;

  perform public._notify_company(s.company_id, '{admin,finance}', 'company_invoice_issued', (
    select jsonb_build_object('invoice_id', i.id, 'invoice_no', i.invoice_no, 'amount_sen', i.amount_sen + i.sst_sen,
                              'due_date', i.due_date, 'plan_code', i.plan_code)
    from public.company_invoices i where i.id = v_id));
  return v_id;
end;
$$;

-- 没付的账单作废（换方案、停了）
create or replace function public._void_company_invoices(p_subscription_id uuid, p_reason text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  update public.company_invoices set status = 'void', void_reason = p_reason
  where subscription_id = p_subscription_id and status in ('issued', 'overdue');
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 注册公司：自己当 admin（全部角色）、开 co_trial（company_trial_days 天；SSM 或号码拿过就不送试用：
-- 订阅是 lapsed、马上开第一期 Starter 账单，要先付）；p_first_site = {name, zone_id, address, contact_name, phone}
create or replace function public.register_company(
  p_name text,
  p_company_type public.company_type,
  p_region_id uuid,
  p_ssm_no text default null,
  p_billing_email text default null,
  p_first_site jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_ssm text := public._normalize_ssm(p_ssm_no);
  v_id uuid;
  v_sub uuid;
  v_trial boolean := true;
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  select * into v_profile from public.profiles where id = v_uid for no key update;
  if v_profile.role = 'seller' or exists (select 1 from public.wholesaler_members m where m.user_id = v_uid) then
    raise exception 'ROLE_MISMATCH' using errcode = '42501';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'name';
  end if;
  if not exists (select 1 from public.regions r where r.id = p_region_id and r.is_active) then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'region_id';
  end if;
  if v_ssm is not null and exists (select 1 from public.companies c where c.ssm_no = v_ssm) then
    raise exception 'SSM_ALREADY_REGISTERED' using errcode = 'P0001';
  end if;

  insert into public.companies (name, company_type, region_id, ssm_no, billing_email, phone, created_by)
  values (trim(p_name), coalesce(p_company_type, 'other'), p_region_id, v_ssm, nullif(trim(p_billing_email), ''),
          v_profile.phone, v_uid)
  returning id into v_id;
  insert into public.company_members (company_id, user_id, roles, all_sites, invited_by)
  values (v_id, v_uid, '{admin,approver,finance,requester}', true, v_uid);

  -- 试用：一家公司（SSM）/ 一个号码只送一次
  if v_profile.phone is null
     or exists (select 1 from public.company_trial_claims t
                where t.creator_phone = v_profile.phone or (v_ssm is not null and t.ssm_no = v_ssm)) then
    v_trial := false;
  else
    begin
      insert into public.company_trial_claims (ssm_no, creator_phone, company_id) values (v_ssm, v_profile.phone, v_id);
    exception when unique_violation then
      v_trial := false;
    end;
  end if;

  if v_trial then
    insert into public.company_subscriptions (company_id, plan_code, billing_cycle, status, trial_ends_at, current_period_start)
    select v_id, 'co_trial', 'monthly', 'trialing', now() + make_interval(days => a.company_trial_days), now()
    from public.app_settings a;
  else
    insert into public.company_subscriptions (company_id, plan_code, billing_cycle, status, locked_price_sen, lapsed_at)
    values (v_id, 'co_starter', 'monthly', 'lapsed', coalesce(public._company_plan_price('co_starter', 'monthly'), 0), now())
    returning id into v_sub;
    perform public._issue_company_invoice(v_sub);
  end if;

  if p_first_site is not null and jsonb_typeof(p_first_site) = 'object' then
    perform public._add_company_site(
      v_id, p_first_site ->> 'name', public._uuid_or_null(p_first_site ->> 'zone_id'), p_first_site ->> 'address',
      p_first_site ->> 'contact_name', p_first_site ->> 'phone', p_first_site ->> 'site_code', p_first_site ->> 'cost_center');
  end if;
  perform public._company_audit('register_company', 'companies', v_id::text, v_id, null, public._company_json(v_id));
  return v_id;
end;
$$;

-- 改公司资料和设定。p_fields 只能有这些栏，其他 → INVALID_FIELD（detail = 哪一栏）；值不对 → INVALID_VALUE
create or replace function public.update_company(p_company_id uuid, p_fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.companies%rowtype;
  n public.companies%rowtype;
  k text;
  v_before jsonb;
begin
  perform public._require_company_role(p_company_id, '{admin}');
  perform public._require_company_active(p_company_id);
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then
    raise exception 'INVALID_FIELD' using errcode = 'P0001';
  end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('name', 'legal_name', 'ssm_no', 'tin', 'sst_no', 'company_type', 'region_id', 'billing_email',
                 'billing_address', 'billing_contact', 'phone', 'locale', 'auto_issue_po', 'reissue_tolerance_bp',
                 'benchmark_tolerance_bp', 'match_price_tolerance_bp', 'match_qty_tolerance_bp', 'auto_receive_days') then
      raise exception 'INVALID_FIELD' using errcode = 'P0001', detail = k;
    end if;
  end loop;
  select * into c from public.companies where id = p_company_id for update;
  v_before := to_jsonb(c);
  begin
    n := jsonb_populate_record(c, p_fields);
  exception when others then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = sqlerrm;
  end;
  if coalesce(trim(n.name), '') = '' then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'name';
  end if;
  n.ssm_no := public._normalize_ssm(n.ssm_no);
  if n.ssm_no is not null and exists (select 1 from public.companies x where x.ssm_no = n.ssm_no and x.id <> c.id) then
    raise exception 'SSM_ALREADY_REGISTERED' using errcode = 'P0001';
  end if;
  begin
    update public.companies set
      name = trim(n.name), legal_name = nullif(trim(n.legal_name), ''), ssm_no = n.ssm_no,
      tin = nullif(trim(n.tin), ''), sst_no = nullif(trim(n.sst_no), ''), company_type = n.company_type,
      region_id = n.region_id, billing_email = nullif(trim(n.billing_email), ''),
      billing_address = nullif(trim(n.billing_address), ''), billing_contact = nullif(trim(n.billing_contact), ''),
      phone = public.normalize_phone(n.phone), locale = n.locale, auto_issue_po = coalesce(n.auto_issue_po, true),
      reissue_tolerance_bp = n.reissue_tolerance_bp, benchmark_tolerance_bp = n.benchmark_tolerance_bp,
      match_price_tolerance_bp = n.match_price_tolerance_bp, match_qty_tolerance_bp = n.match_qty_tolerance_bp,
      auto_receive_days = n.auto_receive_days
    where id = c.id;
  exception when check_violation or not_null_violation or foreign_key_violation then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = sqlerrm;
  end;
  perform public._company_audit('update_company', 'companies', c.id::text, c.id, v_before, p_fields);
  return public._company_json(c.id);
end;
$$;

create or replace function public.add_company_site(
  p_company_id uuid,
  p_name text,
  p_zone_id uuid,
  p_address text,
  p_contact_name text,
  p_phone text,
  p_site_code text default null,
  p_cost_center text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform public._require_company_role(p_company_id, '{admin}');
  perform public._require_company_active(p_company_id);
  v_id := public._add_company_site(p_company_id, p_name, p_zone_id, p_address, p_contact_name, p_phone, p_site_code, p_cost_center);
  perform public._company_audit('add_company_site', 'shops', v_id::text, p_company_id, null, public._company_site_json(v_id));
  return v_id;
end;
$$;

-- 改分店资料。p_fields 只能有 name, zone_id, address, contact_name, phone, site_code, cost_center
create or replace function public.update_company_site(p_shop_id uuid, p_fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.shops%rowtype;
  n public.shops%rowtype;
  k text;
  v_before jsonb;
begin
  select * into s from public.shops where id = p_shop_id and company_id is not null for update;
  if not found then
    raise exception 'SHOP_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform public._require_company_role(s.company_id, '{admin}');
  perform public._require_company_active(s.company_id);
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then
    raise exception 'INVALID_FIELD' using errcode = 'P0001';
  end if;
  for k in select jsonb_object_keys(p_fields) loop
    if k not in ('name', 'zone_id', 'address', 'contact_name', 'phone', 'site_code', 'cost_center') then
      raise exception 'INVALID_FIELD' using errcode = 'P0001', detail = k;
    end if;
  end loop;
  v_before := public._company_site_json(s.id);
  begin
    n := jsonb_populate_record(s, p_fields);
  exception when others then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = sqlerrm;
  end;
  if coalesce(trim(n.name), '') = '' then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'name';
  end if;
  if not exists (select 1 from public.delivery_zones z where z.id = n.zone_id and z.is_active) then
    raise exception 'INVALID_ZONE' using errcode = 'P0001';
  end if;
  update public.shops set
    name = trim(n.name), zone_id = n.zone_id, address = nullif(trim(n.address), ''),
    contact_name = nullif(trim(n.contact_name), ''), phone = nullif(trim(n.phone), ''),
    site_code = nullif(trim(n.site_code), ''), cost_center = nullif(trim(n.cost_center), '')
  where id = s.id;
  perform public._company_audit('update_company_site', 'shops', s.id::text, s.company_id, v_before, p_fields);
  return public._company_site_json(s.id);
end;
$$;

-- 封存分店：还有没完成的单（待确认 / 已确认 / 送货中）→ SITE_HAS_OPEN_DOCUMENTS（第 2 期起也看申请单、采购单）
create or replace function public.archive_company_site(p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.shops%rowtype;
begin
  select * into s from public.shops where id = p_shop_id and company_id is not null for update;
  if not found then
    raise exception 'SHOP_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform public._require_company_role(s.company_id, '{admin}');
  perform public._require_company_active(s.company_id);
  if exists (select 1 from public.orders o where o.shop_id = s.id and o.status in ('pending', 'confirmed', 'delivering')) then
    raise exception 'SITE_HAS_OPEN_DOCUMENTS' using errcode = 'P0001';
  end if;
  update public.shops set is_active = false where id = s.id;
  perform public._company_audit('archive_company_site', 'shops', s.id::text, s.company_id,
    jsonb_build_object('is_active', s.is_active), jsonb_build_object('is_active', false));
  return public._company_site_json(s.id);
end;
$$;

-- 检查角色和分店：角色不能空、分店一定是这家公司的（还开着的）
create or replace function public._check_member_input(
  p_company_id uuid,
  p_roles public.company_role[],
  p_shop_ids uuid[],
  out roles public.company_role[],
  out shop_ids uuid[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  roles := array(select distinct r from unnest(coalesce(p_roles, '{}'::public.company_role[])) as t(r) where r is not null order by r);
  if cardinality(roles) = 0 then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'roles';
  end if;
  shop_ids := array(select distinct x from unnest(coalesce(p_shop_ids, '{}'::uuid[])) as t(x) where x is not null order by x);
  if exists (
    select 1 from unnest(shop_ids) as t(x)
    where not exists (select 1 from public.shops s where s.id = t.x and s.company_id = p_company_id and s.is_active)
  ) then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = 'shop_ids';
  end if;
end;
$$;

-- 邀请成员：号码已经有账号就直接加成员（邀请当场接受）；没有就留邀请（14 天内登录自动接上）。回传邀请 id。
-- 批发商的号码 → ROLE_MISMATCH；已经是成员 → ALREADY_MEMBER；超过 max_users（成员 + 没过期的邀请）→ PLAN_LIMIT_USERS
create or replace function public.invite_company_member(
  p_company_id uuid,
  p_phone text,
  p_roles public.company_role[],
  p_all_sites boolean,
  p_shop_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(p_phone);
  v_in record;
  v_user public.profiles%rowtype;
  v_max int;
  v_id uuid;
begin
  perform public._require_company_role(p_company_id, '{admin}');
  perform public._require_company_active(p_company_id);
  if v_phone is null or v_phone !~ '^601[0-9]{8,9}$' then
    raise exception 'INVALID_PHONE' using errcode = 'P0001';
  end if;
  v_in := public._check_member_input(p_company_id, p_roles, p_shop_ids);
  perform 1 from public.companies c where c.id = p_company_id for no key update;

  select * into v_user from public.profiles p where p.phone = v_phone order by p.created_at limit 1;
  if v_user.id is not null then
    if v_user.role = 'seller' or exists (select 1 from public.wholesaler_members m where m.user_id = v_user.id) then
      raise exception 'ROLE_MISMATCH' using errcode = '42501';
    end if;
    if exists (select 1 from public.company_members m
               where m.company_id = p_company_id and m.user_id = v_user.id and m.is_active) then
      raise exception 'ALREADY_MEMBER' using errcode = 'P0001';
    end if;
  end if;
  v_max := (public._company_limits(p_company_id)).max_users;
  if v_max is not null and public._company_user_count(p_company_id, v_phone) + 1 > v_max then
    raise exception 'PLAN_LIMIT_USERS' using errcode = 'P0001', detail = v_max::text;
  end if;

  delete from public.company_invites i where i.company_id = p_company_id and i.phone = v_phone and i.accepted_at is null;
  insert into public.company_invites (company_id, phone, roles, all_sites, shop_ids, invited_by)
  values (p_company_id, v_phone, v_in.roles, coalesce(p_all_sites, true), v_in.shop_ids, auth.uid())
  returning id into v_id;
  if v_user.id is not null then
    perform public._accept_company_invite(v_id, v_user.id);
  end if;
  perform public._company_audit('invite_company_member', 'company_invites', v_id::text, p_company_id, null,
    jsonb_build_object('phone', v_phone, 'roles', v_in.roles, 'all_sites', coalesce(p_all_sites, true),
                       'shop_ids', v_in.shop_ids, 'accepted', v_user.id is not null));
  return v_id;
end;
$$;

-- 公司一定要有一个有效的 admin
create or replace function public._check_last_admin(p_company_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.company_members m
                 where m.company_id = p_company_id and m.is_active and 'admin' = any (m.roles)) then
    raise exception 'LAST_COMPANY_ADMIN' using errcode = 'P0001';
  end if;
end;
$$;

-- 改成员的角色、能管的分店、停用 / 启用。回传成员 + 邀请
create or replace function public.set_company_member(
  p_company_id uuid,
  p_user_id uuid,
  p_roles public.company_role[],
  p_all_sites boolean,
  p_shop_ids uuid[],
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.company_members%rowtype;
  v_in record;
  v_max int;
  v_before jsonb;
begin
  perform public._require_company_role(p_company_id, '{admin}');
  perform public._require_company_active(p_company_id);
  select * into m from public.company_members x where x.company_id = p_company_id and x.user_id = p_user_id for update;
  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0001';
  end if;
  v_in := public._check_member_input(p_company_id, p_roles, p_shop_ids);
  if not m.is_active and coalesce(p_is_active, true) then
    v_max := (public._company_limits(p_company_id)).max_users;
    if v_max is not null and public._company_user_count(p_company_id) + 1 > v_max then
      raise exception 'PLAN_LIMIT_USERS' using errcode = 'P0001', detail = v_max::text;
    end if;
  end if;
  v_before := to_jsonb(m);
  update public.company_members set
    roles = v_in.roles, all_sites = coalesce(p_all_sites, true), is_active = coalesce(p_is_active, true)
  where company_id = p_company_id and user_id = p_user_id;
  delete from public.company_member_sites x where x.company_id = p_company_id and x.user_id = p_user_id;
  insert into public.company_member_sites (company_id, user_id, shop_id)
  select p_company_id, p_user_id, t.x from unnest(v_in.shop_ids) as t(x);
  perform public._check_last_admin(p_company_id);
  perform public._company_audit('set_company_member', 'company_members', p_user_id::text, p_company_id, v_before,
    jsonb_build_object('roles', v_in.roles, 'all_sites', coalesce(p_all_sites, true), 'shop_ids', v_in.shop_ids,
                       'is_active', coalesce(p_is_active, true)));
  return public._company_members_json(p_company_id);
end;
$$;

create or replace function public.remove_company_member(p_company_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.company_members%rowtype;
begin
  perform public._require_company_role(p_company_id, '{admin}');
  perform public._require_company_active(p_company_id);
  delete from public.company_members x where x.company_id = p_company_id and x.user_id = p_user_id returning * into m;
  if m.user_id is null then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform public._check_last_admin(p_company_id);
  perform public._company_audit('remove_company_member', 'company_members', p_user_id::text, p_company_id, to_jsonb(m), null);
  return public._company_members_json(p_company_id);
end;
$$;

create or replace function public.cancel_company_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.company_invites%rowtype;
begin
  select * into i from public.company_invites where id = p_invite_id and accepted_at is null for update;
  if not found then
    raise exception 'INVITE_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform public._require_company_role(i.company_id, '{admin}');
  perform public._require_company_active(i.company_id);
  delete from public.company_invites where id = i.id;
  perform public._company_audit('cancel_company_invite', 'company_invites', i.id::text, i.company_id, to_jsonb(i), null);
  return public._company_members_json(i.company_id);
end;
$$;

-- 公司首页要的：公司、我的角色、我能管的分店、订阅、待我审批几张（第 2 期才有）、各种数字
create or replace function public.get_company_context(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  m public.company_members%rowtype;
  v_all boolean;
begin
  perform public._require_company_role(p_company_id, '{admin,approver,finance,requester}');
  select * into m from public.company_members x
  where x.company_id = p_company_id and x.user_id = auth.uid() and x.is_active;
  v_all := m.user_id is null or m.all_sites or m.roles && '{admin,finance}'::public.company_role[];
  return jsonb_build_object(
    'company', public._company_json(p_company_id),
    'my_roles', to_jsonb(coalesce(m.roles, '{}'::public.company_role[])),
    'all_sites', v_all,
    'acting_as_admin', m.user_id is null,
    'sites', coalesce((
      select jsonb_agg(public._company_site_json(s.id) order by s.is_active desc, s.name, s.id)
      from public.shops s
      where s.company_id = p_company_id
        and (v_all or exists (select 1 from public.company_member_sites x
                              where x.company_id = p_company_id and x.user_id = m.user_id and x.shop_id = s.id))
    ), '[]'::jsonb),
    'subscription', public._company_subscription_json(p_company_id),
    'pending_approvals', 0,
    'counts', jsonb_build_object(
      'sites', (select count(*) from public.shops s where s.company_id = p_company_id and s.is_active),
      'members', (select count(*) from public.company_members x where x.company_id = p_company_id and x.is_active),
      'open_invites', (select count(*) from public.company_invites i
                       where i.company_id = p_company_id and i.accepted_at is null and i.expires_at > now()),
      'unread_inbox', (select count(*) from public.notifications n
                       where n.user_id = auth.uid() and n.read_at is null and n.payload ->> 'company_id' = p_company_id::text)
    )
  );
end;
$$;

create or replace function public.list_company_members(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_company_role(p_company_id, '{admin,finance}');
  return public._company_members_json(p_company_id);
end;
$$;

-- =============================================================================
-- H. 公司方案：账单、续费、付款
-- =============================================================================

-- 方案页：订阅、可以选的方案（公开的、现在的价钱）、账单、付款
create or replace function public._company_billing_json(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'company_id', p_company_id,
    'subscription', public._company_subscription_json(p_company_id),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', p.code, 'name', p.name, 'monthly_price_sen', p.monthly_price_sen, 'annual_price_sen', p.annual_price_sen,
        'max_sites', p.max_sites, 'max_users', p.max_users, 'features', to_jsonb(p.features)
      ) order by p.sort_order, p.code)
      from (select distinct on (cp.code) cp.* from public.company_plans cp
            where cp.is_public and cp.effective_from <= now() and (cp.effective_to is null or cp.effective_to > now())
            order by cp.code, cp.effective_from desc) p
    ), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(public._company_invoice_json(i.id) order by i.created_at desc, i.invoice_no desc)
      from public.company_invoices i where i.company_id = p_company_id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(public._payment_json(x.id) order by x.created_at desc)
      from (select p.id, p.created_at from public.payments p
            where p.company_id = p_company_id order by p.created_at desc limit 50) x
    ), '[]'::jsonb)
  );
$$;

create or replace function public.get_company_billing(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_company_role(p_company_id, '{admin,finance}');
  return public._company_billing_json(p_company_id);
end;
$$;

-- 公司 admin 换方案：只能选公开的（co_enterprise 只能客服设 → NOT_ALLOWED）；下一期生效，价钱照今天锁定。
-- 已经开了的下一期账单作废、照新方案重开。订阅停了：马上开一张新方案的账单（付了从付款那天开始）
create or replace function public.change_company_plan(
  p_company_id uuid,
  p_plan_code text,
  p_billing_cycle public.company_billing_cycle
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.company_plans%rowtype;
  s public.company_subscriptions%rowtype;
  v_cycle public.company_billing_cycle := coalesce(p_billing_cycle, 'monthly');
  v_price int;
  v_voided int;
begin
  perform public._require_company_role(p_company_id, '{admin}');
  perform public._require_company_active(p_company_id);
  if p_plan_code = 'co_enterprise' and not public.is_admin() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  p := public._company_plan(p_plan_code);
  v_price := public._company_plan_price(p_plan_code, v_cycle);
  if p.id is null or not p.is_public or p.code = 'co_trial' or v_price is null then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = coalesce(p_plan_code, 'null');
  end if;
  perform pg_advisory_xact_lock(hashtext('public.company_subscriptions:' || p_company_id::text));

  s := public._company_current_sub(p_company_id);
  select * into s from public.company_subscriptions where id = s.id for update;
  if s.status <> 'trialing' and s.plan_code = p.code and s.billing_cycle = v_cycle and s.status <> 'lapsed' then
    -- 选回现在的方案：不换了
    update public.company_subscriptions set pending_plan_code = null, pending_billing_cycle = null, pending_price_sen = null
    where id = s.id;
  else
    update public.company_subscriptions set pending_plan_code = p.code, pending_billing_cycle = v_cycle, pending_price_sen = v_price
    where id = s.id;
  end if;
  v_voided := public._void_company_invoices(s.id, 'PLAN_CHANGED');
  if s.status = 'lapsed' or v_voided > 0
     or coalesce(case when s.status = 'trialing' then s.trial_ends_at else s.current_period_end end, now())
          <= now() + make_interval(days => (select a.company_invoice_lead_days from public.app_settings a)) then
    perform public._issue_company_invoice(s.id);
  end if;
  perform public._company_audit('change_company_plan', 'company_subscriptions', s.id::text, p_company_id,
    jsonb_build_object('plan_code', s.plan_code, 'billing_cycle', s.billing_cycle, 'pending_plan_code', s.pending_plan_code),
    jsonb_build_object('pending_plan_code', p.code, 'pending_billing_cycle', v_cycle, 'pending_price_sen', v_price));
  return public._company_billing_json(p_company_id);
end;
$$;

-- 付清一张账单：延长一期（规则跟 _extend_subscription 一样）。
--   没停的订阅（试用中 → 从试用结束 / 现在开始；有效 / 宽限期内 → 从这期结束接着算），方案和价钱照账单（锁定价不变）
--   停了（或宽限期已经过了、定时任务还没跑到）→ 新建一条，从现在开始，价钱照账单（账单是停了之后按当时价钱开的）
-- 回传 {subscription_id, period_start, period_end, created}
create or replace function public._extend_company_subscription(p_subscription_id uuid, p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.company_invoices%rowtype;
  s public.company_subscriptions%rowtype;
  v_company uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_created boolean := false;
begin
  select * into i from public.company_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  select x.company_id into v_company from public.company_subscriptions x where x.id = coalesce(p_subscription_id, i.subscription_id);
  if v_company is distinct from i.company_id then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.company_subscriptions:' || i.company_id::text));

  select * into s from public.company_subscriptions where company_id = i.company_id and status <> 'lapsed' for update;
  if found and s.status = 'past_due' and s.grace_until <= now() then
    update public.company_subscriptions set status = 'lapsed', lapsed_at = now() where id = s.id;
    s := null;
  end if;

  if s.id is not null then
    v_start := case when s.status = 'trialing' then greatest(now(), coalesce(s.trial_ends_at, now()))
                    else coalesce(s.current_period_end, now()) end;
    v_end := v_start + public._cycle_interval(i.billing_cycle);
    update public.company_subscriptions set
      status = 'active', plan_code = i.plan_code, billing_cycle = i.billing_cycle, locked_price_sen = i.amount_sen,
      custom_price = s.custom_price and s.plan_code = i.plan_code and s.pending_plan_code is null,
      current_period_start = v_start, current_period_end = v_end, grace_until = null,
      pending_plan_code = null, pending_billing_cycle = null, pending_price_sen = null
    where id = s.id;
  else
    v_start := now();
    v_end := v_start + public._cycle_interval(i.billing_cycle);
    insert into public.company_subscriptions (
      company_id, plan_code, billing_cycle, status, started_at, locked_price_sen, custom_price,
      current_period_start, current_period_end
    )
    select i.company_id, i.plan_code, i.billing_cycle, 'active', now(), i.amount_sen,
           coalesce(l.custom_price and l.plan_code = i.plan_code and l.pending_plan_code is null, false), v_start, v_end
    from (select 1) one
    left join public.company_subscriptions l on l.id = i.subscription_id
    returning * into s;
    v_created := true;
  end if;
  update public.company_invoices set period_start = v_start, period_end = v_end, subscription_id = s.id where id = i.id;
  return jsonb_build_object('subscription_id', s.id, 'period_start', v_start, 'period_end', v_end, 'created', v_created);
end;
$$;

-- 付款单的样子（第七步的，多 company_id）
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
    'company_id', p.company_id,
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

-- 开一张付款单（第七步的，多一种）：
--   p_purpose = company_plan：p_target_id = company_invoices.id（issued / overdue），只有那家公司的 admin / finance（或客服）
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
  v_company uuid;
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
  ci public.company_invoices%rowtype;
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
    if exists (select 1 from public.shops x where x.id = p_target_id and x.company_id is not null) then
      return jsonb_build_object('result', 'not_allowed');          -- 公司分店看公司的方案，没有小店月费
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

  elsif p_purpose = 'company_plan' then
    select * into ci from public.company_invoices x where x.id = p_target_id;
    if not found then
      return jsonb_build_object('result', 'not_found');
    end if;
    if not (v_admin or exists (
      select 1 from public.company_members m
      where m.company_id = ci.company_id and m.user_id = p_user_id and m.is_active
        and m.roles && '{admin,finance}'::public.company_role[])) then
      return jsonb_build_object('result', 'not_allowed');
    end if;
    if ci.status not in ('issued', 'overdue') then
      return jsonb_build_object('result', 'nothing_due');
    end if;
    v_payer := 'company';
    v_company := ci.company_id;
    v_ref := ci.id;
    v_amount := ci.amount_sen + ci.sst_sen;
    v_desc := 'Company plan invoice ' || ci.invoice_no;

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
    and p.company_id is not distinct from v_company
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
    payer_type, shop_id, wholesaler_id, company_id, purpose, reference_id, amount_sen, gateway, status,
    months, unit_price_sen, description, expires_at, created_by, meta
  )
  values (
    v_payer, v_shop, v_wholesaler, v_company, p_purpose, v_ref, v_amount, p_gateway, 'pending',
    case when p_purpose = 'subscription' then v_months end,
    case when p_purpose = 'subscription' then v_unit end,
    v_desc, now() + make_interval(hours => v_settings.payment_link_hours), p_user_id, v_meta
  )
  returning id into v_id;

  if v_admin then
    insert into public.audit_logs (
      actor_id, acting_for_shop_id, acting_for_wholesaler_id, acting_for_company_id, action, table_name, record_id, after)
    values (p_user_id, v_shop, v_wholesaler, v_company, 'admin_create_payment_link', 'payments', v_id::text,
            jsonb_build_object('purpose', p_purpose, 'amount_sen', v_amount, 'months', v_months));
  end if;

  return jsonb_build_object('result', 'ok', 'reuse', false, 'payment', public._payment_json(v_id));
end;
$$;

-- 收到网关「已付」（第七步的，多一种）：company_plan → 账单 paid → _extend_company_subscription；
-- 「收到付款」排给公司的 admin、finance（每个人一条）
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
  ci public.company_invoices%rowtype;
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
  elsif p.purpose = 'company_plan' then
    select * into ci from public.company_invoices where id = p.reference_id for update;
    if not found then
      v_review := 'INVOICE_NOT_FOUND';
    elsif ci.status in ('issued', 'overdue') then
      update public.company_invoices set status = 'paid', paid_at = now() where id = ci.id;
      v_ext := public._extend_company_subscription(ci.subscription_id, ci.id);
      v_period_start := (v_ext ->> 'period_start')::timestamptz;
      v_period_end := (v_ext ->> 'period_end')::timestamptz;
    else
      v_review := 'INVOICE_' || upper(ci.status::text);  -- 已经付了 / 作废（换了方案、停了）：客服退款或补登
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

  if p.company_id is not null then
    perform public._notify_company(p.company_id, '{admin,finance}', 'payment_received', jsonb_build_object(
      'payment_id', p.id, 'purpose', p.purpose, 'amount_sen', p_amount_sen, 'period_end', v_period_end,
      'invoice_no', ci.invoice_no, 'invoice_id', ci.id));
  else
    insert into public.notifications (shop_id, wholesaler_id, event_type, payload)
    values (p.shop_id, p.wholesaler_id, 'payment_received', jsonb_build_object(
      'payment_id', p.id, 'purpose', p.purpose, 'amount_sen', p_amount_sen, 'period_end', v_period_end,
      'invoice_no', i.invoice_no, 'invoice_id', i.id));
  end if;

  return jsonb_build_object('result', 'paid', 'payment', public._payment_json(p.id));
end;
$$;

-- 付完回到网页 / App：看这张付款单（第七步的，多公司的 admin / finance）
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
          or (p.wholesaler_id is not null and public.is_wholesaler_member(p.wholesaler_id))
          or (p.company_id is not null and public.has_company_role(p.company_id, '{admin,finance}'))) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  return public._payment_json(p.id);
end;
$$;

-- =============================================================================
-- I. 每天的公司收费工作（定时任务 procurement-daily；客服也可以手动跑）
--   1. 期末前 company_invoice_lead_days 天开下一期账单（到期 = 期末）
--   2. 过了期末还没付：有账单 → past_due（grace_until = 期末 + company_grace_days，账单 overdue，通知一次）；
--      试用结束还没选方案（没有账单）→ lapsed
--   3. 过了宽限期 → lapsed（没付的账单作废，回来要按当时的价钱新开）
--   4. 试用结束前 7 天、1 天各通知一次（admin、finance）
-- =============================================================================

create or replace function public.run_company_billing_daily()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.app_settings%rowtype;
  v_issued int := 0;
  v_past_due int := 0;
  v_lapsed int := 0;
  v_trial_notices int := 0;
  v_end timestamptz;
  r record;
  inv record;
begin
  if not (public.is_admin() or public.is_service_call()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into a from public.app_settings;

  for r in
    select s.id from public.company_subscriptions s
    where s.status in ('trialing', 'active')
      and coalesce(case when s.status = 'trialing' then s.trial_ends_at else s.current_period_end end, now())
          <= now() + make_interval(days => a.company_invoice_lead_days)
    order by s.created_at
  loop
    if public._issue_company_invoice(r.id) is not null then
      v_issued := v_issued + 1;
    end if;
  end loop;

  for r in
    select s.* from public.company_subscriptions s
    where s.status in ('trialing', 'active')
      and coalesce(case when s.status = 'trialing' then s.trial_ends_at else s.current_period_end end, now()) <= now()
    order by s.created_at
    for update
  loop
    v_end := coalesce(case when r.status = 'trialing' then r.trial_ends_at else r.current_period_end end, now());
    if exists (select 1 from public.company_invoices i where i.subscription_id = r.id and i.status in ('issued', 'overdue')) then
      update public.company_subscriptions set status = 'past_due', grace_until = v_end + make_interval(days => a.company_grace_days)
      where id = r.id;
      for inv in
        update public.company_invoices i set status = 'overdue', overdue_notified_at = now()
        where i.subscription_id = r.id and i.status = 'issued'
        returning i.*
      loop
        perform public._notify_company(r.company_id, '{admin,finance}', 'company_invoice_overdue', jsonb_build_object(
          'invoice_id', inv.id, 'invoice_no', inv.invoice_no, 'amount_sen', inv.amount_sen + inv.sst_sen,
          'due_date', inv.due_date, 'grace_until', v_end + make_interval(days => a.company_grace_days)));
      end loop;
      v_past_due := v_past_due + 1;
    else
      update public.company_subscriptions set status = 'lapsed', lapsed_at = now() where id = r.id;
      v_lapsed := v_lapsed + 1;
    end if;
  end loop;

  for r in
    update public.company_subscriptions s set status = 'lapsed', lapsed_at = now()
    where s.status = 'past_due' and s.grace_until <= now()
    returning s.id
  loop
    perform public._void_company_invoices(r.id, 'LAPSED');
    v_lapsed := v_lapsed + 1;
  end loop;

  for r in
    select s.id, s.company_id, s.trial_ends_at, s.pending_plan_code,
           case when s.trial_ends_at <= now() + interval '1 day' then 1 else 7 end as days
    from public.company_subscriptions s
    where s.status = 'trialing' and s.trial_ends_at > now() and s.trial_ends_at <= now() + interval '7 days'
      and not ((case when s.trial_ends_at <= now() + interval '1 day' then 1 else 7 end) = any (s.trial_reminded))
  loop
    update public.company_subscriptions
    set trial_reminded = case when r.days = 1 then '{7,1}'::int[] else array_append(trial_reminded, 7) end
    where id = r.id;
    perform public._notify_company(r.company_id, '{admin,finance}', 'company_trial_ending', jsonb_build_object(
      'subscription_id', r.id, 'trial_ends_at', r.trial_ends_at, 'days', r.days, 'plan_chosen', r.pending_plan_code is not null));
    v_trial_notices := v_trial_notices + 1;
  end loop;

  return jsonb_build_object('issued', v_issued, 'past_due', v_past_due, 'lapsed', v_lapsed, 'trial_notices', v_trial_notices);
end;
$$;

-- =============================================================================
-- J. 收件箱（网页用；notifications.user_id = 我，不管有没有推送出去）
-- =============================================================================

-- 新到旧。p_before = 上一页最后一条的 created_at。回传 {items, unread_count}
create or replace function public.list_my_inbox(p_limit int default 30, p_before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'event_type', x.event_type, 'payload', x.payload, 'created_at', x.created_at, 'read_at', x.read_at
      ) order by x.created_at desc, x.id)
      from (
        select n.* from public.notifications n
        where n.user_id = v_uid and (p_before is null or n.created_at < p_before)
        order by n.created_at desc, n.id
        limit greatest(least(coalesce(p_limit, 30), 100), 1)
      ) x
    ), '[]'::jsonb),
    'unread_count', (select count(*) from public.notifications n where n.user_id = v_uid and n.read_at is null)
  );
end;
$$;

-- 标成已读。p_ids 空 = 全部。回传改了几条
create or replace function public.mark_inbox_read(p_ids uuid[] default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if auth.uid() is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  update public.notifications n set read_at = now()
  where n.user_id = auth.uid() and n.read_at is null and (p_ids is null or n.id = any (p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- =============================================================================
-- K. 客服
-- =============================================================================

create or replace function public._admin_company_row(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'legal_name', c.legal_name, 'ssm_no', c.ssm_no, 'company_type', c.company_type,
    'status', c.status, 'status_note', c.status_note, 'phone', c.phone, 'billing_email', c.billing_email,
    'region_id', c.region_id, 'created_at', c.created_at,
    'site_count', (select count(*) from public.shops s where s.company_id = c.id and s.is_active),
    'member_count', (select count(*) from public.company_members m where m.company_id = c.id and m.is_active),
    'subscription', public._company_subscription_json(c.id),
    'open_invoice_sen', (select coalesce(sum(i.amount_sen + i.sst_sen), 0) from public.company_invoices i
                         where i.company_id = c.id and i.status in ('issued', 'overdue')))
  from public.companies c where c.id = p_company_id;
$$;

-- 公司列表（名字、公司全名、SSM、电话搜索），新到旧
create or replace function public.admin_list_companies(
  p_search text default null,
  p_status public.company_status default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := public._like_pattern(p_search);
  v_phone text := public._phone_pattern(p_search);
  v_ssm text := public._normalize_ssm(p_search);
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(public._admin_company_row(x.id) order by x.created_at desc, x.id)
    from (
      select c.id, c.created_at from public.companies c
      where (p_status is null or c.status = p_status)
        and (v_like is null or c.name ilike v_like escape '\' or c.legal_name ilike v_like escape '\'
             or (v_ssm is not null and c.ssm_no like '%' || v_ssm || '%')
             or (v_phone is not null and c.phone like v_phone))
      order by c.created_at desc, c.id
      limit greatest(least(coalesce(p_limit, 50), 200), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 一家公司的全部：资料、订阅（和以前的）、分店（包括封存的）、成员和邀请、账单、付款
create or replace function public.admin_get_company(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._require_admin();
  if not exists (select 1 from public.companies c where c.id = p_company_id) then
    raise exception 'COMPANY_NOT_FOUND' using errcode = 'P0001';
  end if;
  return public._admin_company_row(p_company_id)
    || jsonb_build_object(
      'company', public._company_json(p_company_id),
      'subscriptions', coalesce((
        select jsonb_agg(to_jsonb(s) order by s.created_at desc) from public.company_subscriptions s
        where s.company_id = p_company_id), '[]'::jsonb),
      'sites', coalesce((
        select jsonb_agg(public._company_site_json(s.id) order by s.is_active desc, s.name, s.id) from public.shops s
        where s.company_id = p_company_id), '[]'::jsonb)
    )
    || public._company_members_json(p_company_id)
    || jsonb_build_object(
      'invoices', (public._company_billing_json(p_company_id)) -> 'invoices',
      'payments', (public._company_billing_json(p_company_id)) -> 'payments'
    );
end;
$$;

-- 停权 / 恢复。停权要写原因（INVALID_NOTE）
create or replace function public.admin_set_company_status(
  p_company_id uuid,
  p_status public.company_status,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.companies%rowtype;
  v_note text := nullif(trim(p_note), '');
begin
  perform public._require_admin();
  select * into c from public.companies where id = p_company_id for update;
  if not found then
    raise exception 'COMPANY_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_status is null then
    raise exception 'INVALID_VALUE' using errcode = 'P0001';
  end if;
  if p_status = 'suspended' and v_note is null then
    raise exception 'INVALID_NOTE' using errcode = 'P0001';
  end if;
  update public.companies set status = p_status, status_note = case when p_status = 'suspended' then v_note end
  where id = c.id;
  perform public._company_audit('admin_set_company_status', 'companies', c.id::text, c.id,
    jsonb_build_object('status', c.status), jsonb_build_object('status', p_status, 'note', v_note));
  return public.admin_get_company(c.id);
end;
$$;

-- 客服设方案（马上生效，包括 co_enterprise）。p_price_sen = 自订价（custom_price = true）；空 = 现在的价钱。
-- 已经开了没付的账单作废，照新的价钱重开
create or replace function public.admin_set_company_plan(
  p_company_id uuid,
  p_plan_code text,
  p_billing_cycle public.company_billing_cycle,
  p_price_sen int default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.company_plans%rowtype;
  s public.company_subscriptions%rowtype;
  v_cycle public.company_billing_cycle := coalesce(p_billing_cycle, 'monthly');
  v_price int;
  v_voided int;
begin
  perform public._require_admin();
  if not exists (select 1 from public.companies c where c.id = p_company_id) then
    raise exception 'COMPANY_NOT_FOUND' using errcode = 'P0001';
  end if;
  p := public._company_plan(p_plan_code);
  if p.id is null or p.code = 'co_trial' then
    raise exception 'INVALID_VALUE' using errcode = 'P0001', detail = coalesce(p_plan_code, 'null');
  end if;
  v_price := coalesce(p_price_sen, public._company_plan_price(p.code, v_cycle));
  if v_price is null or v_price <= 0 then
    raise exception 'INVALID_AMOUNT' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.company_subscriptions:' || p_company_id::text));
  s := public._company_current_sub(p_company_id);
  select * into s from public.company_subscriptions where id = s.id for update;
  update public.company_subscriptions set
    plan_code = p.code, billing_cycle = v_cycle, locked_price_sen = v_price, custom_price = p_price_sen is not null,
    pending_plan_code = null, pending_billing_cycle = null, pending_price_sen = null
  where id = s.id;
  v_voided := public._void_company_invoices(s.id, 'PLAN_CHANGED');
  if v_voided > 0 then
    perform public._issue_company_invoice(s.id);
  end if;
  perform public._company_audit('admin_set_company_plan', 'company_subscriptions', s.id::text, p_company_id,
    jsonb_build_object('plan_code', s.plan_code, 'billing_cycle', s.billing_cycle, 'locked_price_sen', s.locked_price_sen,
                       'custom_price', s.custom_price),
    jsonb_build_object('plan_code', p.code, 'billing_cycle', v_cycle, 'locked_price_sen', v_price,
                       'custom_price', p_price_sen is not null));
  return public.admin_get_company(p_company_id);
end;
$$;

-- 延长试用（1–90 天）：试用中 → 加天数；试用过期、从来没付过的 → 重开试用（从今天算）
create or replace function public.admin_extend_company_trial(p_company_id uuid, p_days int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.company_subscriptions%rowtype;
begin
  perform public._require_admin();
  if not exists (select 1 from public.companies c where c.id = p_company_id) then
    raise exception 'COMPANY_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_days is null or p_days < 1 or p_days > 90 then
    raise exception 'INVALID_DAYS' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('public.company_subscriptions:' || p_company_id::text));
  s := public._company_current_sub(p_company_id);
  if s.status = 'trialing' then
    update public.company_subscriptions
    set trial_ends_at = greatest(trial_ends_at, now()) + make_interval(days => p_days), trial_reminded = '{}'
    where id = s.id;
  elsif s.status = 'lapsed'
        and not exists (select 1 from public.company_invoices i where i.company_id = p_company_id and i.status = 'paid') then
    perform public._void_company_invoices(s.id, 'TRIAL_EXTENDED');
    update public.company_subscriptions set
      status = 'trialing', trial_ends_at = now() + make_interval(days => p_days), lapsed_at = null, trial_reminded = '{}',
      plan_code = case when custom_price then plan_code else 'co_trial' end,
      current_period_start = now(), current_period_end = null, grace_until = null
    where id = s.id;
  else
    raise exception 'INVALID_SUBSCRIPTION_STATE' using errcode = 'P0001', detail = coalesce(s.status::text, 'none');
  end if;
  perform public._company_audit('admin_extend_company_trial', 'company_subscriptions', s.id::text, p_company_id,
    jsonb_build_object('status', s.status, 'trial_ends_at', s.trial_ends_at),
    (select jsonb_build_object('status', x.status, 'trial_ends_at', x.trial_ends_at, 'days', p_days)
     from public.company_subscriptions x where x.id = s.id));
  return public.admin_get_company(p_company_id);
end;
$$;

-- 马上开下一期账单（不等开单期）。已经有没付的 → 回传那一张；没得收 → NOTHING_DUE
create or replace function public.admin_issue_company_invoice(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.company_subscriptions%rowtype;
  v_id uuid;
begin
  perform public._require_admin();
  if not exists (select 1 from public.companies c where c.id = p_company_id) then
    raise exception 'COMPANY_NOT_FOUND' using errcode = 'P0001';
  end if;
  s := public._company_current_sub(p_company_id);
  v_id := public._issue_company_invoice(s.id);
  if v_id is null then
    select i.id into v_id from public.company_invoices i
    where i.subscription_id = s.id and i.status in ('issued', 'overdue') order by i.created_at desc limit 1;
    if v_id is null then
      raise exception 'NOTHING_DUE' using errcode = 'P0001';
    end if;
  else
    perform public._company_audit('admin_issue_company_invoice', 'company_invoices', v_id::text, p_company_id, null,
      public._company_invoice_json(v_id));
  end if;
  return public._company_invoice_json(v_id);
end;
$$;

-- 公司转账给我们：客服标记已付（跟网关付款一样延长订阅），记一笔付款
create or replace function public.admin_mark_company_invoice_paid(
  p_invoice_id uuid,
  p_method public.payment_method default 'other',
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.company_invoices%rowtype;
  v_ext jsonb;
  v_payment uuid;
  v_ref text := nullif(trim(p_reference), '');
begin
  perform public._require_admin();
  select * into i from public.company_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'INVOICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if i.status not in ('issued', 'overdue') then
    raise exception 'INVALID_INVOICE_STATE' using errcode = 'P0001', detail = i.status::text;
  end if;
  update public.company_invoices set status = 'paid', paid_at = now() where id = i.id;
  v_ext := public._extend_company_subscription(i.subscription_id, i.id);
  begin
    insert into public.payments (
      payer_type, company_id, purpose, reference_id, amount_sen, gateway, method, gateway_ref, status, paid_at, raw,
      period_start, period_end, description, created_by
    )
    values ('company', i.company_id, 'company_plan', i.id, i.amount_sen + i.sst_sen, 'manual', coalesce(p_method, 'other'),
            v_ref, 'paid', now(), jsonb_build_object('recorded_by', auth.uid()),
            (v_ext ->> 'period_start')::timestamptz, (v_ext ->> 'period_end')::timestamptz,
            'Company plan invoice ' || i.invoice_no, auth.uid())
    returning id into v_payment;
  exception when unique_violation then
    raise exception 'DUPLICATE_PAYMENT_REFERENCE' using errcode = 'P0001', detail = v_ref;
  end;
  perform public._notify_company(i.company_id, '{admin,finance}', 'payment_received', jsonb_build_object(
    'payment_id', v_payment, 'purpose', 'company_plan', 'amount_sen', i.amount_sen + i.sst_sen,
    'period_end', v_ext ->> 'period_end', 'invoice_no', i.invoice_no, 'invoice_id', i.id));
  perform public._company_audit('admin_mark_company_invoice_paid', 'company_invoices', i.id::text, i.company_id,
    jsonb_build_object('status', i.status),
    jsonb_build_object('status', 'paid', 'payment_id', v_payment, 'method', coalesce(p_method, 'other'), 'reference', v_ref));
  return public._company_invoice_json(i.id) || jsonb_build_object('payment_id', v_payment);
end;
$$;

-- 付款记录（第七步的，多公司的名字和公司账单号码）
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
               'payer_name', coalesce(sh.name, w.name, co.name),
               'invoice_no', coalesce(i.invoice_no, ci.invoice_no)
             ) as j
      from public.payments p
      left join public.shops sh on sh.id = p.shop_id
      left join public.wholesalers w on w.id = p.wholesaler_id
      left join public.companies co on co.id = p.company_id
      left join public.commission_invoices i on p.purpose = 'commission_invoice' and i.id = p.reference_id
      left join public.company_invoices ci on p.purpose = 'company_plan' and ci.id = p.reference_id
      where (p_status is null or p.status = p_status)
        and (p_purpose is null or p.purpose = p_purpose)
        and (not coalesce(p_review_only, false) or p.review_reason is not null)
      order by p.created_at desc, p.id
      limit greatest(least(coalesce(p_limit, 100), 500), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

-- =============================================================================
-- L. RLS：全部表只开 select，新增 / 修改全部走函数
-- =============================================================================

alter table public.companies enable row level security;
alter table public.company_members enable row level security;
alter table public.company_member_sites enable row level security;
alter table public.company_invites enable row level security;
alter table public.company_plans enable row level security;
alter table public.company_subscriptions enable row level security;
alter table public.company_trial_claims enable row level security;
alter table public.company_invoices enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'companies', 'company_members', 'company_member_sites', 'company_invites', 'company_plans',
    'company_subscriptions', 'company_trial_claims', 'company_invoices'
  ] loop
    execute format(
      'create policy "admin: read" on public.%I for select to authenticated using ((select public.is_admin()))', t);
  end loop;
end;
$$;

create policy "member: read own companies" on public.companies for select to authenticated
  using (id in (select public.my_company_ids()));
create policy "member: read company members" on public.company_members for select to authenticated
  using (company_id in (select public.my_company_ids()));
create policy "member: read company member sites" on public.company_member_sites for select to authenticated
  using (company_id in (select public.my_company_ids()));
create policy "member: read company invites" on public.company_invites for select to authenticated
  using (company_id in (select public.my_company_ids()));
create policy "everyone: read public company plans" on public.company_plans for select to anon, authenticated
  using (is_public);
create policy "admin finance: read company subscriptions" on public.company_subscriptions for select to authenticated
  using (public.has_company_role(company_id, '{admin,finance}'));
create policy "admin finance: read company invoices" on public.company_invoices for select to authenticated
  using (public.has_company_role(company_id, '{admin,finance}'));
create policy "company admin finance: read payments" on public.payments for select to authenticated
  using (company_id is not null and public.has_company_role(company_id, '{admin,finance}'));

-- =============================================================================
-- M. 定时任务：每天 00:40（马来西亚时间，UTC 16:40）procurement-daily。
-- 第 1 期只有 run_company_billing_daily；之后几期同名更新（多 run_procurement_daily 等）
-- =============================================================================

create or replace function public._schedule_procurement_jobs()
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return false;
  end if;
  perform cron.schedule('procurement-daily', '40 16 * * *', 'select public.run_company_billing_daily()');
  return true;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform public._schedule_procurement_jobs();
  else
    raise notice 'pg_cron 不可用，跳过定时任务';
  end if;
end;
$$;

-- =============================================================================
-- N. 函数权限
-- =============================================================================

revoke execute on function
  public._normalize_ssm(text),
  public._next_doc_no(text),
  public.company_member_sites_check(),
  public._company_plan(text),
  public._company_plan_price(text, public.company_billing_cycle),
  public._cycle_interval(public.company_billing_cycle),
  public._company_site_ids(uuid),
  public.my_company_ids(),
  public.company_roles(uuid),
  public.has_company_role(uuid, public.company_role[]),
  public.is_company_shop(uuid),
  public.can_access_site(uuid),
  public.my_shop_ids(),
  public.is_shop_member(uuid),
  public.is_shop_owner(uuid),
  public.can_access_order(uuid),
  public._company_plan_live(uuid),
  public.has_full_access(uuid),
  public._company_current_sub(uuid),
  public._company_feature_plan(uuid),
  public.company_has_feature(uuid, text),
  public._require_company_feature(uuid, text),
  public._company_limits(uuid),
  public._require_company_role(uuid, public.company_role[]),
  public._require_company_active(uuid),
  public._company_audit(text, text, text, uuid, jsonb, jsonb),
  public._notify_company(uuid, public.company_role[], text, jsonb),
  public._uuid_or_null(text),
  public._guard_not_company_shop(uuid),
  public.cart_items_company_guard(),
  public.checkouts_company_guard(),
  public.place_order(uuid, int, text, public.order_source),
  public.reorder_last(uuid),
  public.reserve_voice_order_run(uuid, uuid, uuid, public.draft_source, text, uuid),
  public._start_trial(uuid, text),
  public._accept_company_invite(uuid, uuid),
  public._accept_company_invites(uuid, text),
  public.handle_new_user(),
  public.handle_user_phone_change(),
  public.register_wholesaler(text, uuid, uuid, text, text, text),
  public.get_my_context(),
  public._company_json(uuid),
  public._company_site_json(uuid),
  public._company_subscription_json(uuid),
  public._company_invoice_json(uuid),
  public._company_members_json(uuid),
  public._company_user_count(uuid, text),
  public._add_company_site(uuid, text, uuid, text, text, text, text, text),
  public._issue_company_invoice(uuid),
  public._void_company_invoices(uuid, text),
  public.register_company(text, public.company_type, uuid, text, text, jsonb),
  public.update_company(uuid, jsonb),
  public.add_company_site(uuid, text, uuid, text, text, text, text, text),
  public.update_company_site(uuid, jsonb),
  public.archive_company_site(uuid),
  public._check_member_input(uuid, public.company_role[], uuid[]),
  public.invite_company_member(uuid, text, public.company_role[], boolean, uuid[]),
  public._check_last_admin(uuid),
  public.set_company_member(uuid, uuid, public.company_role[], boolean, uuid[], boolean),
  public.remove_company_member(uuid, uuid),
  public.cancel_company_invite(uuid),
  public.get_company_context(uuid),
  public.list_company_members(uuid),
  public._company_billing_json(uuid),
  public.get_company_billing(uuid),
  public.change_company_plan(uuid, text, public.company_billing_cycle),
  public._extend_company_subscription(uuid, uuid),
  public._payment_json(uuid),
  public.create_payment_intent(uuid, public.payment_purpose, uuid, int, text),
  public.mark_payment_paid(uuid, text, text, int, public.payment_method, jsonb),
  public.get_payment(uuid),
  public.run_company_billing_daily(),
  public.list_my_inbox(int, timestamptz),
  public.mark_inbox_read(uuid[]),
  public._admin_company_row(uuid),
  public.admin_list_companies(text, public.company_status, int),
  public.admin_get_company(uuid),
  public.admin_set_company_status(uuid, public.company_status, text),
  public.admin_set_company_plan(uuid, text, public.company_billing_cycle, int),
  public.admin_extend_company_trial(uuid, int),
  public.admin_issue_company_invoice(uuid),
  public.admin_mark_company_invoice_paid(uuid, public.payment_method, text),
  public.admin_list_payments(public.payment_status, public.payment_purpose, boolean, int),
  public._schedule_procurement_jobs()
from public, anon, authenticated;

-- RLS 规则、受保护字段要用到的辅助函数（第二步的照旧开放）
grant execute on function
  public.my_company_ids(),
  public.company_roles(uuid),
  public.has_company_role(uuid, public.company_role[]),
  public.is_company_shop(uuid),
  public.can_access_site(uuid),
  public.my_shop_ids(),
  public.is_shop_member(uuid),
  public.is_shop_owner(uuid),
  public.can_access_order(uuid),
  public.company_has_feature(uuid, text)
to authenticated;

-- App / 网页（函数里面再检查角色）
grant execute on function
  public.place_order(uuid, int, text, public.order_source),
  public.reorder_last(uuid),
  public.register_wholesaler(text, uuid, uuid, text, text, text),
  public.get_my_context(),
  public.register_company(text, public.company_type, uuid, text, text, jsonb),
  public.update_company(uuid, jsonb),
  public.add_company_site(uuid, text, uuid, text, text, text, text, text),
  public.update_company_site(uuid, jsonb),
  public.archive_company_site(uuid),
  public.invite_company_member(uuid, text, public.company_role[], boolean, uuid[]),
  public.set_company_member(uuid, uuid, public.company_role[], boolean, uuid[], boolean),
  public.remove_company_member(uuid, uuid),
  public.cancel_company_invite(uuid),
  public.get_company_context(uuid),
  public.list_company_members(uuid),
  public.get_company_billing(uuid),
  public.change_company_plan(uuid, text, public.company_billing_cycle),
  public.get_payment(uuid),
  public.list_my_inbox(int, timestamptz),
  public.mark_inbox_read(uuid[]),
  public.run_company_billing_daily(),
  public.admin_list_companies(text, public.company_status, int),
  public.admin_get_company(uuid),
  public.admin_set_company_status(uuid, public.company_status, text),
  public.admin_set_company_plan(uuid, text, public.company_billing_cycle, int),
  public.admin_extend_company_trial(uuid, int),
  public.admin_issue_company_invoice(uuid),
  public.admin_mark_company_invoice_paid(uuid, public.payment_method, text),
  public.admin_list_payments(public.payment_status, public.payment_purpose, boolean, int)
to authenticated;

-- 服务器（create-payment、payment-webhook、定时任务）
grant execute on function
  public.create_payment_intent(uuid, public.payment_purpose, uuid, int, text),
  public.mark_payment_paid(uuid, text, text, int, public.payment_method, jsonb),
  public.reserve_voice_order_run(uuid, uuid, uuid, public.draft_source, text, uuid),
  public.run_company_billing_daily()
to service_role;
