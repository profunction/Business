-- =============================================================================
-- 2/8 商品：标准商品（用来比价）、批发商的商品、改价记录、价目表导入
-- =============================================================================

create type public.sell_unit as enum ('carton', 'pack', 'bag', 'roll', 'bundle', 'box', 'piece', 'dozen', 'kg');
create type public.stock_status as enum ('in_stock', 'low_stock', 'out_of_stock');
create type public.product_status as enum ('draft', 'active', 'archived');
create type public.import_file_type as enum ('image', 'pdf', 'excel');
create type public.import_status as enum ('processing', 'review', 'applied', 'failed');
create type public.import_row_action as enum ('create', 'update', 'skip');

-- 标准商品：把不同批发商卖的「同一样东西」对在一起，例如「16oz PP 透明杯（95mm 口径）」
create table public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  code text unique,                                -- 'cup_pp_16oz_95'，方便客服和 AI 对应
  category_id uuid not null references public.categories (id),
  name jsonb not null check (public.is_i18n_name(name)),
  spec jsonb not null default '{}',                -- {"capacity_oz": 16, "material": "PP", "diameter_mm": 95}
  base_unit text not null default 'pcs' check (base_unit in ('pcs', 'sheet', 'm', 'kg', 'g', 'ml')),
  image_path text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index catalog_items_category_idx on public.catalog_items (category_id);
comment on table public.catalog_items is '标准商品，由客服维护。比价按「每个 base_unit 多少钱」来比';

-- 批发商实际在卖的商品
create table public.products (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  catalog_item_id uuid references public.catalog_items (id) on delete set null,
  category_id uuid references public.categories (id),
  name text not null check (length(trim(name)) > 0), -- 批发商自己的叫法，照原文显示
  description text,
  photo_paths text[] not null default '{}',
  unit public.sell_unit not null,                  -- 卖的单位：箱 / 包 / 条……
  pack_qty int not null default 1 check (pack_qty > 0), -- 一个单位里有几个 base_unit
  price_sen int not null check (price_sen > 0),
  min_order_qty int not null default 1 check (min_order_qty > 0),
  stock_status public.stock_status not null default 'in_stock',
  lead_time_days_override smallint check (lead_time_days_override between 0 and 30),
  status public.product_status not null default 'draft',
  sort_order int not null default 0,
  price_updated_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_wholesaler_status_idx on public.products (wholesaler_id, status);
create index products_catalog_item_idx on public.products (catalog_item_id) where status = 'active';
create index products_category_idx on public.products (category_id) where status = 'active';
comment on table public.products is '买家不能直接查这张表（价钱要经过付费检查），要用 get_offers() 等函数';
comment on column public.products.status is 'draft 草稿（AI 导入后等确认）/ active 上架 / archived 下架';

create table public.product_price_history (
  id bigint generated always as identity primary key,
  product_id uuid not null references public.products (id) on delete cascade,
  old_price_sen int,
  new_price_sen int not null,
  changed_by uuid references public.profiles (id) on delete set null,
  changed_at timestamptz not null default now()
);
create index product_price_history_product_idx on public.product_price_history (product_id, changed_at desc);

-- 上传的价目表（照片 / PDF / Excel），AI 识别后等人确认
create table public.price_list_imports (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  file_path text not null,
  file_type public.import_file_type not null,
  status public.import_status not null default 'processing',
  error_message text,
  ai_raw jsonb,
  created_by uuid references public.profiles (id) on delete set null,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index price_list_imports_wholesaler_idx on public.price_list_imports (wholesaler_id, created_at desc);

create table public.price_list_import_rows (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.price_list_imports (id) on delete cascade,
  row_no int not null,
  raw_text text,
  name text,
  unit public.sell_unit,
  pack_qty int check (pack_qty > 0),
  price_sen int check (price_sen > 0),
  min_order_qty int check (min_order_qty > 0),
  matched_product_id uuid references public.products (id) on delete set null,
  suggested_catalog_item_id uuid references public.catalog_items (id) on delete set null,
  action public.import_row_action not null default 'create',
  confidence numeric(3, 2) check (confidence between 0 and 1),
  created_at timestamptz not null default now(),
  unique (import_id, row_no)
);

-- ---------- 触发器 ----------

create trigger catalog_items_updated_at before update on public.catalog_items
  for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();
create trigger price_list_imports_updated_at before update on public.price_list_imports
  for each row execute function public.set_updated_at();

-- 改价时记下时间，并写进改价记录
create or replace function public.products_before_price_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.price_sen is distinct from old.price_sen then
    new.price_updated_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.products_log_price_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.price_sen is distinct from old.price_sen then
    insert into public.product_price_history (product_id, old_price_sen, new_price_sen, changed_by)
    values (new.id, case when tg_op = 'UPDATE' then old.price_sen end, new.price_sen, auth.uid());
  end if;
  return null;
end;
$$;

create trigger products_price_timestamp before update of price_sen on public.products
  for each row execute function public.products_before_price_change();
create trigger products_price_history after insert or update of price_sen on public.products
  for each row execute function public.products_log_price_change();
