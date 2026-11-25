-- =============================================================================
-- 5/8 WhatsApp 消息、AI 订单草稿、通知队列、操作记录
-- =============================================================================

create type public.wa_direction as enum ('inbound', 'outbound');
create type public.wa_message_type as enum ('text', 'audio', 'image', 'document', 'button', 'template', 'other');
create type public.draft_source as enum ('app_voice', 'whatsapp_text', 'whatsapp_voice', 'admin');
create type public.draft_status as enum ('pending_review', 'confirmed', 'rejected');
create type public.notification_channel as enum ('push', 'whatsapp');
create type public.notification_status as enum ('queued', 'sent', 'failed', 'skipped');

-- 所有进出的 WhatsApp 消息（只有客服看得到）
create table public.whatsapp_messages (
  id uuid primary key default gen_random_uuid(),
  direction public.wa_direction not null,
  wa_message_id text unique,
  phone text not null,
  shop_id uuid references public.shops (id) on delete set null,
  wholesaler_id uuid references public.wholesalers (id) on delete set null,
  message_type public.wa_message_type not null,
  body text,
  media_path text,
  template_name text,
  order_id uuid references public.orders (id) on delete set null,
  delivery_status text,                            -- sent / delivered / read / failed
  raw jsonb,
  created_at timestamptz not null default now()
);
create index whatsapp_messages_phone_idx on public.whatsapp_messages (phone, created_at desc);
create index whatsapp_messages_order_idx on public.whatsapp_messages (order_id);

-- AI 把文字或语音转成的订单草稿：App 语音由老板自己确认，WhatsApp 由客服确认
create table public.order_drafts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid references public.shops (id) on delete cascade, -- 不认识的号码发来时是空的
  source public.draft_source not null,
  whatsapp_message_id uuid references public.whatsapp_messages (id) on delete set null,
  sender_phone text,
  audio_path text,
  transcript text,
  -- [{"product_id": "...", "qty": 2, "said": "两箱十六安士杯", "confidence": 0.9}, ...]
  parsed_lines jsonb not null default '[]',
  status public.draft_status not null default 'pending_review',
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  checkout_id uuid references public.checkouts (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index order_drafts_status_idx on public.order_drafts (status, created_at);
create index order_drafts_shop_idx on public.order_drafts (shop_id, created_at desc);

-- 通知队列：发送函数（第四步）按「有没有装 App」决定用推送还是 WhatsApp
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  shop_id uuid references public.shops (id) on delete cascade,
  wholesaler_id uuid references public.wholesalers (id) on delete cascade,
  event_type text not null,                        -- order_new / order_status_changed / order_cancelled / ...
  payload jsonb not null default '{}',
  channel public.notification_channel,             -- 发出去之后才填
  status public.notification_status not null default 'queued',
  attempts int not null default 0,
  last_error text,
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check (num_nonnulls(user_id, shop_id, wholesaler_id) = 1)
);
create index notifications_queue_idx on public.notifications (created_at) where status = 'queued';
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_shop_idx on public.notifications (shop_id, created_at desc);
create index notifications_wholesaler_idx on public.notifications (wholesaler_id, created_at desc);

-- 操作记录：客服的每个改动都记下来（出纠纷时查得到）
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles (id) on delete set null,
  acting_for_shop_id uuid,                         -- 不加外键：店铺删了记录也要留着
  acting_for_wholesaler_id uuid,
  action text not null,                            -- insert / update / delete
  table_name text,
  record_id text,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs (created_at desc);
create index audit_logs_actor_idx on public.audit_logs (actor_id, created_at desc);

create trigger order_drafts_updated_at before update on public.order_drafts
  for each row execute function public.set_updated_at();
