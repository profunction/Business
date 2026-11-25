-- =============================================================================
-- 3/8 购物车、结账、订单、订单明细、状态记录、评价
-- 订单只能通过数据库函数（place_order、set_order_status……）建立和修改，
-- App 不能直接改这些表。
-- =============================================================================

create type public.order_status as enum (
  'pending',       -- 待确认
  'confirmed',     -- 已确认（部分缺货也算已确认，缺货的那几样不算钱）
  'out_of_stock',  -- 整张单都缺货
  'delivering',    -- 送货中
  'delivered',     -- 已送达
  'cancelled'      -- 已取消
);
create type public.order_source as enum ('app', 'voice', 'whatsapp', 'admin', 'reorder');
create type public.event_channel as enum ('app', 'whatsapp', 'admin', 'system');

-- 购物车放在服务器：客服也能帮老板加货，换手机也不会丢
create table public.cart_items (
  shop_id uuid not null references public.shops (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  qty int not null check (qty > 0 and qty <= 100000),
  added_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (shop_id, product_id)
);

-- 一次结账，可能包含几家批发商；「跟上次一样」就是复制最近一次结账
create table public.checkouts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  source public.order_source not null,
  goods_total_sen int not null default 0,
  shipping_total_sen int not null default 0,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index checkouts_shop_idx on public.checkouts (shop_id, created_at desc);

create sequence public.order_no_seq;

-- 每家批发商一张订单
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique,                   -- 例：JHB261125-00042
  checkout_id uuid not null references public.checkouts (id),
  shop_id uuid not null references public.shops (id),
  wholesaler_id uuid not null references public.wholesalers (id),
  zone_id uuid not null references public.delivery_zones (id),
  status public.order_status not null default 'pending',
  goods_subtotal_sen int not null check (goods_subtotal_sen >= 0),
  shipping_fee_sen int not null check (shipping_fee_sen >= 0),
  total_sen int generated always as (goods_subtotal_sen + shipping_fee_sen) stored,
  expected_delivery_date date,
  note text check (length(note) <= 500),
  source public.order_source not null,
  created_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,
  delivering_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_shop_idx on public.orders (shop_id, created_at desc);
create index orders_wholesaler_status_idx on public.orders (wholesaler_id, status);
create index orders_wholesaler_delivery_idx on public.orders (wholesaler_id, expected_delivery_date);
create index orders_checkout_idx on public.orders (checkout_id);
create index orders_pending_idx on public.orders (created_at) where status = 'pending';
comment on column public.orders.shipping_fee_sen is '下单时就定好的运费，之后部分缺货也不再加收';

-- 订单明细：下单时的快照，之后批发商改价也不影响
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  catalog_item_id uuid references public.catalog_items (id) on delete set null,
  name_snapshot text not null,
  unit_snapshot public.sell_unit not null,
  pack_qty_snapshot int not null,
  unit_price_sen int not null check (unit_price_sen >= 0),
  qty int not null check (qty > 0),
  line_total_sen int generated always as (unit_price_sen * qty) stored,
  is_out_of_stock boolean not null default false,
  created_at timestamptz not null default now()
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_product_idx on public.order_items (product_id);

-- 状态变化记录：App 里的进度条、出纠纷时查谁按的
create table public.order_status_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders (id) on delete cascade,
  from_status public.order_status,
  to_status public.order_status not null,
  actor_id uuid references public.profiles (id) on delete set null,
  channel public.event_channel not null,
  note text,
  created_at timestamptz not null default now()
);
create index order_status_events_order_idx on public.order_status_events (order_id, created_at);

-- 评价：一张已送达的订单评一次
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders (id) on delete cascade,
  shop_id uuid not null references public.shops (id) on delete cascade,
  wholesaler_id uuid not null references public.wholesalers (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  -- 一键点选的标签，App 按代码显示三语文字
  tags text[] not null default '{}' check (tags <@ array[
    'on_time', 'good_quality', 'well_packed', 'good_price', 'friendly',
    'late', 'wrong_items', 'damaged', 'missing_items'
  ]::text[]),
  comment text check (length(comment) <= 1000),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index reviews_wholesaler_idx on public.reviews (wholesaler_id, created_at desc);

create trigger cart_items_updated_at before update on public.cart_items
  for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders
  for each row execute function public.set_updated_at();
create trigger reviews_updated_at before update on public.reviews
  for each row execute function public.set_updated_at();
