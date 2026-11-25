-- =============================================================================
-- 1/8 基础：枚举、通用函数、地区和行业设定、用户、店铺、批发商
-- 金额一律用「仙」存整数（RM12.50 = 1250），时间一律 timestamptz，
-- 业务上的「今天」按马来西亚时间（Asia/Kuala_Lumpur）计算。
-- =============================================================================

-- ---------- 枚举 ----------
create type public.user_role as enum ('buyer', 'seller', 'admin');
create type public.app_locale as enum ('zh', 'en', 'ms');
create type public.shop_type as enum ('restaurant', 'drink_stall', 'grocery', 'other');
create type public.member_role as enum ('owner', 'staff');
-- auto：有装 App 就推送，没装就 WhatsApp
create type public.notify_channel as enum ('auto', 'push', 'whatsapp');
create type public.wholesaler_status as enum ('pending', 'active', 'suspended');

-- ---------- 通用函数 ----------

-- 自动更新 updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 手机号统一成国际格式、只留数字（Supabase Auth 也是这样存）：
-- '012-345 6789' / '+60 12-345 6789' -> '60123456789'
create or replace function public.normalize_phone(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p is null or regexp_replace(p, '\D', '', 'g') = '' then null
    when regexp_replace(p, '\D', '', 'g') like '0%' then '6' || regexp_replace(p, '\D', '', 'g')
    else regexp_replace(p, '\D', '', 'g')
  end;
$$;

-- 马来西亚时间的「今天」
create or replace function public.today_myt()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Kuala_Lumpur')::date;
$$;

-- 三语名称检查：{"zh": "...", "en": "...", "ms": "..."}
create or replace function public.is_i18n_name(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p) = 'object'
     and coalesce(p ->> 'zh', '') <> ''
     and coalesce(p ->> 'en', '') <> ''
     and coalesce(p ->> 'ms', '') <> '';
$$;

-- ---------- 地区、送货区、行业、分类、全局设定 ----------

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                       -- 'JHB'
  name jsonb not null check (public.is_i18n_name(name)),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table public.regions is '地区，第一阶段只有新山（JHB）';

create table public.delivery_zones (
  id uuid primary key default gen_random_uuid(),
  region_id uuid not null references public.regions (id),
  code text not null,
  name jsonb not null check (public.is_i18n_name(name)),
  postcodes text[] not null default '{}',
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (region_id, code)
);
create index delivery_zones_region_idx on public.delivery_zones (region_id);
comment on table public.delivery_zones is '地区里的送货区，例如 Skudai、Tebrau、Mount Austin';

create table public.industries (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                       -- 'food_packaging'
  name jsonb not null check (public.is_i18n_name(name)),
  default_commission_rate numeric(5, 4) not null check (default_commission_rate between 0 and 0.2),
  founding_commission_rate numeric(5, 4) not null check (founding_commission_rate between 0 and 0.2),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (founding_commission_rate <= default_commission_rate)
);
comment on table public.industries is '行业和它的佣金比例（0.0200 = 2%）';

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  industry_id uuid not null references public.industries (id),
  parent_id uuid references public.categories (id),
  code text not null,
  name jsonb not null check (public.is_i18n_name(name)),
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (industry_id, code)
);
create index categories_industry_idx on public.categories (industry_id);

-- 只有一行的全局设定表
create table public.app_settings (
  id boolean primary key default true check (id),
  trial_days int not null default 14 check (trial_days >= 0),
  subscription_grace_days int not null default 7 check (subscription_grace_days >= 0),
  free_unlocked_wholesalers int not null default 3 check (free_unlocked_wholesalers >= 0),
  unlock_change_cooldown_days int not null default 30 check (unlock_change_cooldown_days >= 0),
  founding_wholesaler_quota int not null default 100 check (founding_wholesaler_quota >= 0),
  founding_listing_fee_sen int not null default 10000 check (founding_listing_fee_sen >= 0),
  order_confirm_alert_minutes int not null default 30 check (order_confirm_alert_minutes > 0),
  commission_invoice_due_days int not null default 14 check (commission_invoice_due_days >= 0),
  updated_at timestamptz not null default now()
);
insert into public.app_settings default values;
comment on table public.app_settings is '全局设定：试用天数、宽限期、免费可看几家批发商、创始名额和上架费等';

-- ---------- 用户 ----------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null default 'buyer',
  full_name text,
  phone text,
  locale public.app_locale not null default 'zh',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_phone_idx on public.profiles (phone);
comment on table public.profiles is '每个登录账号一行；role 只能由客服（admin）修改';

-- ---------- 店铺（买家） ----------

create table public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  shop_type public.shop_type not null default 'other',
  zone_id uuid not null references public.delivery_zones (id),
  address text,
  contact_name text,
  phone text,
  whatsapp_phone text,
  locale public.app_locale not null default 'zh',
  notify_channel public.notify_channel not null default 'auto',
  is_active boolean not null default true,
  unlocks_changed_at timestamptz,                  -- 上次更换「免费可看的批发商」的时间
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index shops_zone_idx on public.shops (zone_id);
create index shops_phone_idx on public.shops (phone);
create index shops_whatsapp_phone_idx on public.shops (whatsapp_phone);
comment on table public.shops is '买家的店。没装 App 的店也有一行（只有 WhatsApp 号码，没有成员账号）';

create table public.shop_members (
  shop_id uuid not null references public.shops (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  member_role public.member_role not null default 'owner',
  created_at timestamptz not null default now(),
  primary key (shop_id, user_id)
);
create index shop_members_user_idx on public.shop_members (user_id);

-- ---------- 批发商 ----------

create table public.wholesalers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  industry_id uuid not null references public.industries (id),
  region_id uuid not null references public.regions (id),
  description text,
  logo_path text,
  address text,
  contact_name text,
  phone text,
  whatsapp_phone text,
  locale public.app_locale not null default 'zh',
  notify_channel public.notify_channel not null default 'auto',
  status public.wholesaler_status not null default 'pending',
  is_founding boolean not null default false,      -- 创始会员（头 100 家）
  founding_no smallint unique check (founding_no > 0),
  founding_fee_paid_at timestamptz,
  rating_avg numeric(3, 2) not null default 0,
  rating_count int not null default 0,
  order_cutoff_time time,                          -- 过了这个时间的订单算明天
  payment_terms text[] not null default '{cod}'
    check (payment_terms <@ array['cod', 'transfer', 'credit']::text[]),
  approved_at timestamptz,
  approved_by uuid references public.profiles (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index wholesalers_region_status_idx on public.wholesalers (region_id, status);
create index wholesalers_phone_idx on public.wholesalers (phone);
create index wholesalers_whatsapp_phone_idx on public.wholesalers (whatsapp_phone);
comment on column public.wholesalers.payment_terms is '老板怎么付货款给批发商（只做显示，平台不经手）：cod 货到付款 / transfer 转账 / credit 月结';

-- 批发商的私密资料：买家看不到
create table public.wholesaler_private (
  wholesaler_id uuid primary key references public.wholesalers (id) on delete cascade,
  commission_rate_override numeric(5, 4) check (commission_rate_override between 0 and 0.2),
  billing_name text,
  billing_email text,
  billing_address text,
  ssm_no text,
  updated_at timestamptz not null default now()
);
comment on table public.wholesaler_private is '佣金单独调整的比例、开账单用的资料。只有批发商自己和客服看得到';

create table public.wholesaler_members (
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  member_role public.member_role not null default 'owner',
  created_at timestamptz not null default now(),
  primary key (wholesaler_id, user_id)
);
create index wholesaler_members_user_idx on public.wholesaler_members (user_id);

-- 每家批发商送哪些区、运费多少
create table public.wholesaler_delivery_zones (
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  zone_id uuid not null references public.delivery_zones (id),
  shipping_fee_sen int not null default 0 check (shipping_fee_sen >= 0),
  free_shipping_min_sen int check (free_shipping_min_sen > 0),   -- 满多少免运费
  min_order_sen int check (min_order_sen > 0),                   -- 最低消费
  lead_time_days smallint not null default 1 check (lead_time_days between 0 and 30),
  -- 哪几天送货：1 = 星期一 ... 7 = 星期日
  delivery_weekdays smallint[] not null default '{1,2,3,4,5,6}'
    check (delivery_weekdays <@ '{1,2,3,4,5,6,7}'::smallint[] and cardinality(delivery_weekdays) > 0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (wholesaler_id, zone_id)
);
create index wholesaler_delivery_zones_zone_idx on public.wholesaler_delivery_zones (zone_id);

-- 推送用的手机 token
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  fcm_token text not null unique,
  platform text not null check (platform in ('ios', 'android', 'web')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

-- ---------- 触发器：updated_at、手机号格式 ----------

create or replace function public.normalize_phone_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name in ('shops', 'wholesalers') then
    new.phone := public.normalize_phone(new.phone);
    new.whatsapp_phone := public.normalize_phone(new.whatsapp_phone);
  elsif tg_table_name = 'profiles' then
    new.phone := public.normalize_phone(new.phone);
  end if;
  return new;
end;
$$;

create trigger profiles_normalize_phone before insert or update of phone on public.profiles
  for each row execute function public.normalize_phone_columns();
create trigger shops_normalize_phone before insert or update of phone, whatsapp_phone on public.shops
  for each row execute function public.normalize_phone_columns();
create trigger wholesalers_normalize_phone before insert or update of phone, whatsapp_phone on public.wholesalers
  for each row execute function public.normalize_phone_columns();

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger shops_updated_at before update on public.shops
  for each row execute function public.set_updated_at();
create trigger wholesalers_updated_at before update on public.wholesalers
  for each row execute function public.set_updated_at();
create trigger wholesaler_private_updated_at before update on public.wholesaler_private
  for each row execute function public.set_updated_at();
create trigger wholesaler_delivery_zones_updated_at before update on public.wholesaler_delivery_zones
  for each row execute function public.set_updated_at();
create trigger app_settings_updated_at before update on public.app_settings
  for each row execute function public.set_updated_at();
