-- =============================================================================
-- 第四步：批发商端、通知发送（推送 / WhatsApp）、WhatsApp 接单、价目表导入
-- 规格见 docs/04-seller-spec.md 第 2 节。
--
--   A. 结构变动
--   B. 批发商读取（App 用）：get_seller_home、list_seller_orders、get_delivery_summary
--   C. 价目表导入：suggest_import_matches（服务器）、apply_price_list_import（批发商 / 客服）
--   D. 通知发送（服务器）：claim_notifications、complete_notification、remove_device_tokens，
--      推送 token 登记 register_device_token
--   E. WhatsApp 回传（服务器）：handle_whatsapp_button、record_whatsapp_message、update_whatsapp_status
--   F. 定时任务：enqueue_daily_summaries、enqueue_unconfirmed_alerts、叫 dispatcher（pg_net + Vault）
--   G. Storage：price-lists、product-photos
--   H. 函数权限
--
-- 本机测试环境（scripts/test-db.sh）没有 storage / vault / net / cron，
-- 用到它们的地方都先检查，有才做，没有就跳过，不报错。
-- =============================================================================

-- =============================================================================
-- A. 结构变动
-- =============================================================================

-- 商品名比对（价目表导入）
create extension if not exists pg_trgm with schema extensions;

alter table public.notifications
  add column next_attempt_at timestamptz,
  add column claimed_at timestamptz,
  add column wa_message_id text;
comment on column public.notifications.next_attempt_at is '发送失败后，下一次可以重试的时间';
comment on column public.notifications.claimed_at is 'dispatcher 领走的时间（超过 10 分钟还在「发送中」就当成卡住，重新领）';
comment on column public.notifications.wa_message_id is '发出去的 WhatsApp 消息 id（wamid...）';
-- 还没发完的通知（排队、失败待重试、发送中）
create index notifications_dispatch_idx on public.notifications (status, created_at)
  where status not in ('sent', 'skipped');
create index notifications_wa_message_idx on public.notifications (wa_message_id)
  where wa_message_id is not null;

alter table public.orders add column unconfirmed_alert_at timestamptz;
comment on column public.orders.unconfirmed_alert_at is '订单太久没确认，已经提醒过客服的时间';

-- Firebase 2026 年起改用 Firebase Installation ID（FID），旧的 registration token 还能用
alter table public.device_tokens
  add column kind text not null default 'token' check (kind in ('token', 'fid'));
comment on column public.device_tokens.fcm_token is 'FCM registration token 或 Firebase Installation ID（看 kind）';

-- Meta 规定要先取得对方同意才能发 WhatsApp：没有这个时间就不发
alter table public.wholesalers add column whatsapp_opt_in_at timestamptz;
alter table public.shops add column whatsapp_opt_in_at timestamptz;
comment on column public.wholesalers.whatsapp_opt_in_at is '同意用 WhatsApp 收订单的时间；空的就不发 WhatsApp';
comment on column public.shops.whatsapp_opt_in_at is '同意用 WhatsApp 收通知的时间；空的就不发 WhatsApp';

-- 2026 年起 Meta 的用户 ID（BSUID）：有些用户没有电话号码，只有这个
alter table public.whatsapp_messages
  add column from_user_id text,
  add column context_wa_message_id text,
  add column error_code int,
  alter column phone drop not null;
comment on column public.whatsapp_messages.from_user_id is 'Meta 的 business-scoped user ID（BSUID），例如 MY.1234...';
comment on column public.whatsapp_messages.context_wa_message_id is '按钮 / 回复是按在哪一条消息上（我们发出去的 wamid）';
comment on column public.whatsapp_messages.error_code is 'WhatsApp 发送失败的错误代码（例如 131026 号码不在 WhatsApp）';
create index whatsapp_messages_context_idx on public.whatsapp_messages (context_wa_message_id);

-- 价目表档案的路径只能是 <这家批发商的 id>/<uuid>.<副档名>（App 照这个格式上传到 price-lists）。
-- parse-price-list 用服务器身份下载（不受 Storage 规则限制），批发商自己又可以写这一栏，
-- 所以要在这里确定路径在自己的文件夹里，而且没有 %、..、反斜线这些能绕到别家文件夹的字。
alter table public.price_list_imports
  add constraint price_list_imports_file_path_check check (
    file_path ~ ('^' || wholesaler_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]{1,8}$')
  );

-- =============================================================================
-- 商品名相似度
-- pg_trgm 只把数据库「认得的字母和数字」切成三个字一组；数据库的 locale 是 C（本机测试、
-- 部分主机）时，中文字全部被当成空白，「95 平盖」和「95 拱形盖」会被当成一模一样。
-- 所以：全部是英文 / 数字的名字直接用 extensions.similarity()；有中文等其他文字的，
-- 用下面同样规则（每个词前面补两个空格、后面补一个，三个字一组，取交集 / 并集）
-- 自己切，中文字也算字。两种算法对英文名字的结果完全一样。
-- =============================================================================

create or replace function public._name_trgms(p_name text)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_chars text[];
  v_word text[] := '{}';
  v_out text[] := '{}';
  c text;
  b bytea;
  b0 int;
  cp int;
  i int;
begin
  if p_name is null then
    return '{}';
  end if;
  if current_setting('server_encoding') = 'UTF8' then
    v_chars := regexp_split_to_array(p_name, '');
  else
    -- SQL_ASCII（本机测试库）：照 UTF-8 的字节规则切成一个一个字
    select array_agg(m[1] order by t.ord) into v_chars
    from regexp_matches(p_name, '([\x01-\x7f]|[\xc0-\xff][\x80-\xbf]*|[\x80-\xbf])', 'g') with ordinality as t(m, ord);
  end if;

  -- 最后补一个空白，把最后一个词也收进来
  foreach c in array coalesce(v_chars, '{}'::text[]) || array[' '] loop
    if c is null or c = '' then
      continue;
    end if;
    b := textsend(c);
    b0 := get_byte(b, 0);
    cp := case
      when b0 < 128 then b0
      when b0 >= 240 and length(b) >= 4 then
        ((b0 & 7) << 18) | ((get_byte(b, 1) & 63) << 12) | ((get_byte(b, 2) & 63) << 6) | (get_byte(b, 3) & 63)
      when b0 >= 224 and length(b) >= 3 then
        ((b0 & 15) << 12) | ((get_byte(b, 1) & 63) << 6) | (get_byte(b, 2) & 63)
      when b0 >= 192 and length(b) >= 2 then
        ((b0 & 31) << 6) | (get_byte(b, 1) & 63)
      else -1
    end;
    -- 全形字母数字（ＡＢＣ１２３）当成半形；英文字母一律小写
    if cp between 65281 and 65374 then
      cp := cp - 65248;
      c := chr(cp);
    end if;
    if cp between 65 and 90 then
      cp := cp + 32;
      c := chr(cp);
    end if;

    if cp between 48 and 57 or cp between 97 and 122
       or (cp between 192 and 591 and cp not in (215, 247))   -- 拉丁字母（é、ñ……）
       or cp between 12352 and 12543                          -- 日文假名
       or cp between 13312 and 19903                          -- 中文扩展 A
       or cp between 19968 and 40959                          -- 中文
       or cp between 63744 and 64255                          -- 中文兼容字
       or cp between 44032 and 55215                          -- 韩文
       or cp between 131072 and 196607 then                   -- 中文扩展 B 以后
      v_word := v_word || c;
    elsif cardinality(v_word) > 0 then
      v_word := array[' ', ' '] || v_word || array[' '];
      for i in 1 .. cardinality(v_word) - 2 loop
        v_out := v_out || (v_word[i] || v_word[i + 1] || v_word[i + 2]);
      end loop;
      v_word := '{}';
    end if;
  end loop;

  return array(select distinct x from unnest(v_out) as t(x) order by 1);
end;
$$;

-- 两组三字组的相似度：交集 / 并集（跟 pg_trgm 的 similarity 一样）
create or replace function public._trgm_sim(a text[], b text[])
returns real
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(cardinality(a), 0) = 0 or coalesce(cardinality(b), 0) = 0 then 0::real
    else (s.common::real / (cardinality(a) + cardinality(b) - s.common)::real)
  end
  from (select count(*)::int as common from unnest(a) as t(x) where t.x = any (b)) s;
$$;

create or replace function public._name_similarity(a text, b text)
returns real
language sql
immutable
set search_path = ''
as $$
  select case
    when a is null or b is null then 0::real
    when a !~ '[^\x01-\x7f]' and b !~ '[^\x01-\x7f]' then extensions.similarity(lower(a), lower(b))
    else public._trgm_sim(public._name_trgms(a), public._name_trgms(b))
  end;
$$;

-- 名字里的数字（排好、不重复；全形数字当半形，016 = 16，1.50 = 1.5）。
-- 包装材料不同尺寸的名字通常只差一个数字（12oz / 16oz 杯、90mm / 95mm 盖），三字组相似度会很高，
-- 所以比对时两边的数字要「一边包含另一边」才算同一样（「95 平盖」和「95 平盖 1000个」可以；12oz 和 16oz 不行）。
create or replace function public._name_numbers(p_name text)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text := coalesce(p_name, '');
  v_fullwidth text[] := array['０', '１', '２', '３', '４', '５', '６', '７', '８', '９'];
  i int;
begin
  -- 用 replace 不用 translate：SQL_ASCII 的库（本机测试）一个字节算一个字
  for i in 1 .. 10 loop
    v_name := replace(v_name, v_fullwidth[i], (i - 1)::text);
  end loop;
  v_name := replace(v_name, '．', '.');
  return array(
    select distinct pg_catalog.trim_scale(m[1]::numeric)::text
    from regexp_matches(v_name, '([0-9]+(\.[0-9]+)?)', 'g') as m
    order by 1
  );
end;
$$;

-- 单位的三语叫法（WhatsApp / 推送的文字用）
create or replace function public._unit_label(p_unit public.sell_unit, p_locale public.app_locale)
returns text
language sql
immutable
set search_path = ''
as $$
  select case coalesce(p_locale, 'zh')
    when 'en' then case p_unit
      when 'carton' then 'carton' when 'pack' then 'pack' when 'bag' then 'bag' when 'roll' then 'roll'
      when 'bundle' then 'bundle' when 'box' then 'box' when 'piece' then 'piece' when 'dozen' then 'dozen'
      when 'kg' then 'kg' end
    when 'ms' then case p_unit
      when 'carton' then 'karton' when 'pack' then 'paket' when 'bag' then 'beg' when 'roll' then 'gulung'
      when 'bundle' then 'ikat' when 'box' then 'kotak' when 'piece' then 'biji' when 'dozen' then 'dozen'
      when 'kg' then 'kg' end
    else case p_unit
      when 'carton' then '箱' when 'pack' then '包' when 'bag' then '袋' when 'roll' then '卷'
      when 'bundle' then '扎' when 'box' then '盒' when 'piece' then '个' when 'dozen' then '打'
      when 'kg' then '公斤' end
  end;
$$;

-- =============================================================================
-- B. 批发商读取（App 用）
-- =============================================================================

create or replace function public.get_seller_home(p_wholesaler_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public.today_myt();
  v_w public.wholesalers%rowtype;
begin
  if not (public.is_wholesaler_member(p_wholesaler_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into v_w from public.wholesalers where id = p_wholesaler_id;
  if not found then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'wholesaler', jsonb_build_object(
      'id', v_w.id, 'name', v_w.name, 'status', v_w.status, 'is_founding', v_w.is_founding,
      'notify_channel', v_w.notify_channel),
    'pending_count', (
      select count(*) from public.orders o where o.wholesaler_id = p_wholesaler_id and o.status = 'pending'),
    'oldest_pending_at', (
      select min(o.created_at) from public.orders o where o.wholesaler_id = p_wholesaler_id and o.status = 'pending'),
    'today', v_today,
    'today_order_count', (
      select count(*) from public.orders o
      where o.wholesaler_id = p_wholesaler_id and o.status in ('confirmed', 'delivering')
        and o.expected_delivery_date = v_today),
    'today_total_sen', (
      select coalesce(sum(o.total_sen), 0) from public.orders o
      where o.wholesaler_id = p_wholesaler_id and o.status in ('confirmed', 'delivering')
        and o.expected_delivery_date = v_today),
    -- 缺货 / 快卖完只算上架中的商品
    'product_counts', (
      select jsonb_build_object(
        'active', count(*) filter (where p.status = 'active'),
        'draft', count(*) filter (where p.status = 'draft'),
        'out_of_stock', count(*) filter (where p.status = 'active' and p.stock_status = 'out_of_stock'),
        'low_stock', count(*) filter (where p.status = 'active' and p.stock_status = 'low_stock'))
      from public.products p where p.wholesaler_id = p_wholesaler_id),
    'latest_import', (
      select jsonb_build_object('id', i.id, 'status', i.status, 'created_at', i.created_at)
      from public.price_list_imports i
      where i.wholesaler_id = p_wholesaler_id
      order by i.created_at desc, i.id
      limit 1)
  );
end;
$$;

-- 订单列表：pending 按下单时间旧到新（先来先做），其他按新到旧；pending 排最前面
create or replace function public.list_seller_orders(
  p_wholesaler_id uuid,
  p_statuses public.order_status[] default null,
  p_delivery_date date default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (public.is_wholesaler_member(p_wholesaler_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(x.j order by x.rn)
    from (
      select row_number() over (
               order by (o.status = 'pending') desc,
                        case when o.status = 'pending' then o.created_at end asc,
                        case when o.status = 'pending' then o.order_no end asc,
                        o.created_at desc,
                        o.order_no desc) as rn,
             jsonb_build_object(
               'id', o.id,
               'order_no', o.order_no,
               'status', o.status,
               'shop_name', s.name,
               'zone_name', z.name,
               'item_count', (select count(*) from public.order_items i where i.order_id = o.id),
               'out_of_stock_count', (select count(*) from public.order_items i where i.order_id = o.id and i.is_out_of_stock),
               'goods_subtotal_sen', o.goods_subtotal_sen,
               'shipping_fee_sen', o.shipping_fee_sen,
               'total_sen', o.total_sen,
               'note', o.note,
               'created_at', o.created_at,
               'expected_delivery_date', o.expected_delivery_date
             ) as j
      from public.orders o
      join public.shops s on s.id = o.shop_id
      join public.delivery_zones z on z.id = o.zone_id
      where o.wholesaler_id = p_wholesaler_id
        and (p_statuses is null or cardinality(p_statuses) = 0 or o.status = any (p_statuses))
        and (p_delivery_date is null or o.expected_delivery_date = p_delivery_date)
      order by rn
      limit greatest(least(coalesce(p_limit, 50), 200), 1)
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 当天送货总结：拣货单（不含缺货）+ 每张单（按送货区、再按店名排，方便排路线）
create or replace function public.get_delivery_summary(p_wholesaler_id uuid, p_date date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_date date := coalesce(p_date, public.today_myt());
  v_w public.wholesalers%rowtype;
begin
  if not (public.is_wholesaler_member(p_wholesaler_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into v_w from public.wholesalers where id = p_wholesaler_id;
  if not found then
    raise exception 'WHOLESALER_NOT_FOUND' using errcode = 'P0001';
  end if;

  return (
    with day_orders as (
      select o.*, s.name as shop_name, s.contact_name as shop_contact_name,
             coalesce(s.phone, s.whatsapp_phone) as shop_phone, s.address as shop_address,
             z.name as zone_name, z.sort_order as zone_sort, z.code as zone_code
      from public.orders o
      join public.shops s on s.id = o.shop_id
      join public.delivery_zones z on z.id = o.zone_id
      where o.wholesaler_id = p_wholesaler_id
        and o.expected_delivery_date = v_date
        and o.status in ('confirmed', 'delivering')
    )
    select jsonb_build_object(
      'date', v_date,
      'wholesaler', jsonb_build_object('id', v_w.id, 'name', v_w.name, 'phone', coalesce(v_w.phone, v_w.whatsapp_phone)),
      'order_count', (select count(*) from day_orders),
      'pending_count', (
        select count(*) from public.orders o
        where o.wholesaler_id = p_wholesaler_id and o.expected_delivery_date = v_date and o.status = 'pending'),
      'goods_total_sen', (select coalesce(sum(d.goods_subtotal_sen), 0) from day_orders d),
      'shipping_total_sen', (select coalesce(sum(d.shipping_fee_sen), 0) from day_orders d),
      'total_sen', (select coalesce(sum(d.total_sen), 0) from day_orders d),
      'picking', coalesce((
        select jsonb_agg(jsonb_build_object('name', p.name, 'unit', p.unit, 'pack_qty', p.pack_qty, 'qty', p.qty)
                         order by p.name, p.unit, p.pack_qty)
        from (
          select i.name_snapshot as name, i.unit_snapshot as unit, i.pack_qty_snapshot as pack_qty, sum(i.qty)::int as qty
          from day_orders d
          join public.order_items i on i.order_id = d.id and not i.is_out_of_stock
          group by i.name_snapshot, i.unit_snapshot, i.pack_qty_snapshot
        ) p
      ), '[]'::jsonb),
      'orders', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', d.id,
          'order_no', d.order_no,
          'status', d.status,
          'shop', jsonb_build_object(
            'name', d.shop_name, 'contact_name', d.shop_contact_name, 'phone', d.shop_phone,
            'address', d.shop_address, 'zone_name', d.zone_name),
          'items', coalesce((
            select jsonb_agg(jsonb_build_object(
              'name', i.name_snapshot, 'unit', i.unit_snapshot, 'pack_qty', i.pack_qty_snapshot, 'qty', i.qty,
              'unit_price_sen', i.unit_price_sen, 'line_total_sen', i.line_total_sen,
              'is_out_of_stock', i.is_out_of_stock
            ) order by i.is_out_of_stock, i.name_snapshot)
            from public.order_items i where i.order_id = d.id
          ), '[]'::jsonb),
          'goods_subtotal_sen', d.goods_subtotal_sen,
          'shipping_fee_sen', d.shipping_fee_sen,
          'total_sen', d.total_sen,
          'note', d.note,
          'payment_terms', to_jsonb(v_w.payment_terms)
        ) order by d.zone_sort, d.zone_code, d.shop_name, d.order_no)
        from day_orders d
      ), '[]'::jsonb)
    )
  );
end;
$$;

-- =============================================================================
-- C. 价目表导入
-- =============================================================================

-- 服务器（parse-price-list）写完每一行之后调用：
--   * 同一家批发商的商品里找名字最像的（> 0.45）→ matched_product_id，action = update；
--     一样商品只对给最像的那一行（避免两行改同一样商品）；一样像时，单位、包装数量也相同的优先
--   * 标准商品里找最像的（zh / en / ms 取最高，> 0.3）→ suggested_catalog_item_id
--   * 两边名字里的数字对不上（一边不包含另一边，例如 12oz / 16oz）就不算同一样（_name_numbers）
--   * 没名字或没价钱 → skip；对到商品 → update；其他 → create
-- 速度：每个名字的三字组只切一次（materialized），再用三字组 join 算出每一对有几个共同的三字组，
-- 不是每一对都重新切（几百行 × 几千样商品时那样要几十秒，Edge Function 会超时）。
-- 算出来的相似度跟 _trgm_sim 一模一样（交集 / 并集）；全英文的照样用 extensions.similarity。
create or replace function public.suggest_import_matches(p_import_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_import public.price_list_imports%rowtype;
  v_rows_done uuid[] := '{}';
  v_products_used uuid[] := '{}';
  pr record;
  v_rows int;
  v_matched int;
  v_suggested int;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into v_import from public.price_list_imports where id = p_import_id for update;
  if not found then
    raise exception 'IMPORT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_import.status = 'applied' then
    raise exception 'IMPORT_ALREADY_APPLIED' using errcode = 'P0001';
  end if;

  update public.price_list_import_rows r
  set matched_product_id = null, suggested_catalog_item_id = null
  where r.import_id = p_import_id;

  -- 1. 对到自己的商品
  for pr in
    with r as materialized (
      select row_number() over ()::int as k, r.id, r.name, r.unit, r.pack_qty,
             public._name_trgms(r.name) as t, public._name_numbers(r.name) as nums,
             r.name !~ '[^\x01-\x7f]' as is_ascii
      from public.price_list_import_rows r
      where r.import_id = p_import_id and nullif(trim(r.name), '') is not null
    ),
    p as materialized (
      select row_number() over ()::int as k, p.id, p.name, p.unit, p.pack_qty, p.status,
             public._name_trgms(p.name) as t, public._name_numbers(p.name) as nums,
             p.name !~ '[^\x01-\x7f]' as is_ascii
      from public.products p
      where p.wholesaler_id = v_import.wholesaler_id
    ),
    -- 有共同三字组的每一对，共同几个（_name_trgms 没有重复的三字组）
    common as (
      select rt.k as rk, pt.k as pk, count(*)::int as n
      from (select r.k, u.x from r cross join lateral unnest(r.t) as u(x)) rt
      join (select p.k, u.x from p cross join lateral unnest(p.t) as u(x)) pt on pt.x = rt.x
      group by rt.k, pt.k
    ),
    pairs as (
      select r.id as row_id, p.id as product_id, p.status,
             case when r.is_ascii and p.is_ascii then extensions.similarity(lower(r.name), lower(p.name))
                  else c.n::real / (cardinality(r.t) + cardinality(p.t) - c.n)::real end as sim,
             (r.unit is not distinct from p.unit) as same_unit,
             (r.pack_qty is not distinct from p.pack_qty) as same_pack
      from common c
      join r on r.k = c.rk
      join p on p.k = c.pk
      where r.nums <@ p.nums or p.nums <@ r.nums
    )
    select pairs.row_id, pairs.product_id
    from pairs
    where pairs.sim > 0.45
    order by pairs.sim
               + case when pairs.same_unit then 0.05 else 0 end
               + case when pairs.same_pack then 0.05 else 0 end desc,
             (pairs.status = 'archived'),
             pairs.row_id, pairs.product_id
  loop
    if not (pr.row_id = any (v_rows_done)) and not (pr.product_id = any (v_products_used)) then
      update public.price_list_import_rows set matched_product_id = pr.product_id where id = pr.row_id;
      v_rows_done := v_rows_done || pr.row_id;
      v_products_used := v_products_used || pr.product_id;
    end if;
  end loop;

  -- 2. 对到标准商品（每样标准商品有三个名字，各自比对，取最像的）
  with r as materialized (
    select row_number() over ()::int as k, r.id, r.name,
           public._name_trgms(r.name) as t, public._name_numbers(r.name) as nums,
           r.name !~ '[^\x01-\x7f]' as is_ascii
    from public.price_list_import_rows r
    where r.import_id = p_import_id and nullif(trim(r.name), '') is not null
  ),
  c as materialized (
    select row_number() over ()::int as k, ci.id, ci.sort_order, n.name,
           public._name_trgms(n.name) as t, public._name_numbers(n.name) as nums,
           n.name !~ '[^\x01-\x7f]' as is_ascii
    from public.catalog_items ci
    cross join lateral unnest(array[ci.name ->> 'zh', ci.name ->> 'en', ci.name ->> 'ms']) as n(name)
    where ci.is_active and n.name is not null
  ),
  common as (
    select rt.k as rk, ct.k as ck, count(*)::int as n
    from (select r.k, u.x from r cross join lateral unnest(r.t) as u(x)) rt
    join (select c.k, u.x from c cross join lateral unnest(c.t) as u(x)) ct on ct.x = rt.x
    group by rt.k, ct.k
  ),
  best as (
    select distinct on (r.id) r.id as row_id, c.id as catalog_item_id
    from common m
    join r on r.k = m.rk
    join c on c.k = m.ck
    cross join lateral (
      select case when r.is_ascii and c.is_ascii then extensions.similarity(lower(r.name), lower(c.name))
                  else m.n::real / (cardinality(r.t) + cardinality(c.t) - m.n)::real end as sim
    ) s
    where s.sim > 0.3 and (r.nums <@ c.nums or c.nums <@ r.nums)
    order by r.id, s.sim desc, c.sort_order, c.id
  )
  update public.price_list_import_rows x
  set suggested_catalog_item_id = best.catalog_item_id
  from best
  where x.id = best.row_id;

  -- 3. 决定每一行要做什么
  update public.price_list_import_rows r
  set action = case
    when nullif(trim(r.name), '') is null or r.price_sen is null then 'skip'::public.import_row_action
    when r.matched_product_id is not null then 'update'::public.import_row_action
    else 'create'::public.import_row_action
  end
  where r.import_id = p_import_id;

  select count(*), count(r.matched_product_id), count(r.suggested_catalog_item_id)
  into v_rows, v_matched, v_suggested
  from public.price_list_import_rows r where r.import_id = p_import_id;

  return jsonb_build_object('rows', v_rows, 'matched', v_matched, 'suggested', v_suggested);
end;
$$;

-- 批发商确认后上架：create 行新增商品，update 行改对到的商品，skip 不动
create or replace function public.apply_price_list_import(p_import_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_import public.price_list_imports%rowtype;
  v_row record;
  v_product public.products%rowtype;
  v_created int := 0;
  v_updated int := 0;
  v_skipped int := 0;
  v_dup int;
begin
  select * into v_import from public.price_list_imports where id = p_import_id for update;
  if not found then
    raise exception 'IMPORT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not (public.is_wholesaler_member(v_import.wholesaler_id) or public.is_admin()) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if v_import.status <> 'review' then
    raise exception 'IMPORT_NOT_IN_REVIEW' using errcode = 'P0001', detail = v_import.status::text;
  end if;

  -- 两行改同一样商品：后面那行会盖掉前面的，要批发商先改好
  select min(x.row_no) into v_dup
  from (
    select r.row_no, count(*) over (partition by r.matched_product_id) as n
    from public.price_list_import_rows r
    where r.import_id = p_import_id and r.action = 'update' and r.matched_product_id is not null
  ) x
  where x.n > 1;
  if v_dup is not null then
    raise exception 'IMPORT_DUPLICATE_PRODUCT' using errcode = 'P0001', detail = v_dup::text;
  end if;

  for v_row in
    select * from public.price_list_import_rows x
    where x.import_id = p_import_id
    order by x.row_no
  loop
    if v_row.action = 'skip' then
      v_skipped := v_skipped + 1;

    elsif v_row.action = 'create' then
      if nullif(trim(v_row.name), '') is null or v_row.unit is null or v_row.pack_qty is null or v_row.price_sen is null then
        raise exception 'IMPORT_ROW_INCOMPLETE' using errcode = 'P0001', detail = v_row.row_no::text;
      end if;
      insert into public.products (
        wholesaler_id, catalog_item_id, category_id, name, unit, pack_qty, price_sen, min_order_qty, status, created_by
      )
      values (
        v_import.wholesaler_id,
        v_row.suggested_catalog_item_id,
        (select ci.category_id from public.catalog_items ci where ci.id = v_row.suggested_catalog_item_id),
        trim(v_row.name), v_row.unit, v_row.pack_qty, v_row.price_sen, coalesce(v_row.min_order_qty, 1), 'active', auth.uid()
      );
      v_created := v_created + 1;

    else -- update
      if v_row.matched_product_id is null or v_row.price_sen is null then
        raise exception 'IMPORT_ROW_INCOMPLETE' using errcode = 'P0001', detail = v_row.row_no::text;
      end if;
      select * into v_product from public.products p where p.id = v_row.matched_product_id for update;
      -- 行是批发商自己可以改的，要确认对到的商品真的是这家批发商的
      if not found or v_product.wholesaler_id <> v_import.wholesaler_id then
        raise exception 'IMPORT_ROW_INVALID_PRODUCT' using errcode = 'P0001', detail = v_row.row_no::text;
      end if;
      update public.products p set
        price_sen = v_row.price_sen,
        min_order_qty = coalesce(v_row.min_order_qty, p.min_order_qty),
        unit = coalesce(v_row.unit, p.unit),
        pack_qty = coalesce(v_row.pack_qty, p.pack_qty),
        status = 'active'
      where p.id = v_product.id;
      v_updated := v_updated + 1;
    end if;
  end loop;

  update public.price_list_imports set status = 'applied', applied_at = now() where id = p_import_id;

  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;

-- =============================================================================
-- D. 通知发送（只给服务器的 dispatcher 用）
-- =============================================================================

-- 选渠道：收件人是批发商 / 店铺 / 用户
--   「可以发 WhatsApp」= 有 whatsapp_phone（没有就用 phone）而且 whatsapp_opt_in_at 不是空的
--   whatsapp → 可以发才发；push → 有 token 才发；auto → 有 token 推送，否则可以发就 WhatsApp
--   用户（客服提醒）只有推送；daily_summary、order_unconfirmed 不走 WhatsApp
-- 回传 {channel, push_targets, whatsapp_phone, locale}，channel 是 null 就是没办法发
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
    and coalesce(p_event_type, '') not in ('daily_summary', 'order_unconfirmed');

  v_channel := case
    when p_user_id is not null then case when v_has_push then 'push' end
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

-- 订单类通知附上的订单资料。items_text 例如「16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱」，
-- 单位按收件人语言，最多 900 个字（太长就截到某一样为止，后面加「; …」）
create or replace function public._notification_order_details(p_order_id uuid, p_locale public.app_locale)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  o record;
  it record;
  v_parts text[] := '{}';
  v_full text;
  v_text text;
  v_oos_label text := case coalesce(p_locale, 'zh')
    when 'en' then ' (out of stock)' when 'ms' then ' (habis stok)' else '（缺货）' end;
  i int;
begin
  select ord.*, s.name as shop_name, s.address as shop_address, coalesce(s.phone, s.whatsapp_phone) as shop_phone,
         w.name as wholesaler_name
  into o
  from public.orders ord
  join public.shops s on s.id = ord.shop_id
  join public.wholesalers w on w.id = ord.wholesaler_id
  where ord.id = p_order_id;
  if not found then
    return null;
  end if;

  for it in
    select i.name_snapshot, i.unit_snapshot, i.qty, i.is_out_of_stock
    from public.order_items i where i.order_id = p_order_id
    order by i.is_out_of_stock, i.name_snapshot, i.id
  loop
    -- WhatsApp 模板的参数不能有换行、不能有一串空白
    v_parts := v_parts || (
      regexp_replace(trim(it.name_snapshot), '\s+', ' ', 'g') || ' x' || it.qty || ' '
      || public._unit_label(it.unit_snapshot, p_locale)
      || case when it.is_out_of_stock then v_oos_label else '' end);
  end loop;

  v_full := array_to_string(v_parts, '; ');
  if length(v_full) <= 900 then
    v_text := v_full;
  else
    v_text := null;
    for i in 1 .. cardinality(v_parts) loop
      exit when length(array_to_string(v_parts[1:i], '; ') || '; …') > 900;
      v_text := array_to_string(v_parts[1:i], '; ') || '; …';
    end loop;
    v_text := coalesce(v_text, left(v_full, 899) || '…');
  end if;

  return jsonb_build_object(
    'order_id', o.id,
    'order_no', o.order_no,
    'status', o.status,
    'shop_name', o.shop_name,
    'shop_address', o.shop_address,
    'shop_phone', o.shop_phone,
    'wholesaler_name', o.wholesaler_name,
    'items_text', coalesce(v_text, ''),
    'item_count', cardinality(v_parts),
    'total_sen', o.total_sen,
    'expected_delivery_date', o.expected_delivery_date,
    'out_of_stock_count', (select count(*) from public.order_items i where i.order_id = o.id and i.is_out_of_stock)
  );
end;
$$;

-- 领走要发的通知：排队中的、失败了到时间重试的（最多 5 次）、「发送中」超过 10 分钟卡住的。
-- 同一个 WhatsApp 号码一次只领一条（Meta 对同一个收件人大约每 6 秒只能发 1 条），
-- 那个号码还有别的 WhatsApp 正在发送中也先不领；其他的留着下一轮再发。
create or replace function public.claim_notifications(p_limit int default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit int := greatest(least(coalesce(p_limit, 50), 500), 1);
  v_out jsonb := '[]'::jsonb;
  v_phones text[] := '{}';
  v_seen uuid[] := '{}';
  v_batch uuid[];
  v_count int := 0;
  n record;
  v_route jsonb;
  v_channel text;
  v_phone text;
  v_attempts int;
  v_details jsonb;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  -- 每一轮只锁「还差几条」那么多行（用 FOR 循环直接跑 FOR UPDATE 的话，游标会一次预取几十行
  -- 全部锁住，同时在跑的另一个 dispatcher 就领不到了）。同号码领不了的那几行会锁到交易结束。
  loop
    exit when v_count >= v_limit or cardinality(v_seen) >= v_limit * 5;
    select coalesce(array_agg(c.id order by c.created_at, c.id), '{}'::uuid[]) into v_batch
    from (
      select x.id, x.created_at
      from public.notifications x
      where (x.status = 'queued'
             or (x.status = 'failed' and x.attempts < 5 and x.next_attempt_at <= now())
             or (x.status = 'sending' and x.claimed_at < now() - interval '10 minutes'))
        and not (x.id = any (v_seen))
      order by x.created_at, x.id
      limit v_limit - v_count
      for update skip locked
    ) c;
    exit when cardinality(v_batch) = 0;
    v_seen := v_seen || v_batch;

    for n in
      select x.* from public.notifications x where x.id = any (v_batch) order by x.created_at, x.id
    loop
      v_attempts := n.attempts;

      -- 卡住的那次算失败一次；失败太多次就不再发。最后的错误一定是 STUCK_IN_SENDING
      -- （之前某一次的错误，例如 FCM 503，不是这次放弃的原因）
      if n.status = 'sending' then
        v_attempts := v_attempts + 1;
        if v_attempts >= 5 then
          update public.notifications
          set status = 'failed', attempts = v_attempts, next_attempt_at = null,
              last_error = 'STUCK_IN_SENDING'
          where id = n.id;
          continue;
        end if;
      end if;

      v_route := public._notification_route(n.user_id, n.shop_id, n.wholesaler_id, n.event_type);
      v_channel := v_route ->> 'channel';
      v_phone := v_route ->> 'whatsapp_phone';

      if v_channel = 'whatsapp' then
        -- 这一轮已经领了这个号码的
        if v_phone = any (v_phones) then
          continue;
        end if;
        -- 另一个同时在跑的 dispatcher 正在领这个号码的（还没提交，看不到）
        if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('public.claim_notifications:' || v_phone)) then
          continue;
        end if;
        -- 这个号码还有别的 WhatsApp 正在发送中
        if exists (
          select 1
          from public.notifications m
          left join public.wholesalers w on w.id = m.wholesaler_id
          left join public.shops s on s.id = m.shop_id
          where m.status = 'sending' and m.channel = 'whatsapp' and m.id <> n.id
            and m.claimed_at >= now() - interval '10 minutes'
            and coalesce(w.whatsapp_phone, w.phone, s.whatsapp_phone, s.phone) = v_phone
        ) then
          continue;
        end if;
        v_phones := v_phones || v_phone;
      end if;

      update public.notifications
      set status = 'sending', claimed_at = now(), attempts = v_attempts,
          channel = v_channel::public.notification_channel
      where id = n.id;

      v_details := case
        when coalesce(n.payload ->> 'order_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then public._notification_order_details((n.payload ->> 'order_id')::uuid, (v_route ->> 'locale')::public.app_locale)
      end;

      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', n.id,
        'event_type', n.event_type,
        'payload', n.payload,
        'locale', v_route ->> 'locale',
        'channel', v_channel,
        'push_targets', v_route -> 'push_targets',
        'whatsapp_phone', v_phone,
        'attempts', v_attempts,
        'details', v_details
      ));
      v_count := v_count + 1;
    end loop;
  end loop;

  return v_out;
end;
$$;

-- 发完了：sent / failed / skipped。只改「发送中」的那条（回传 true）；
-- 不是发送中（例如卡住后被别的 dispatcher 重新领走、已经发完）就不改（回传 false）。
-- failed：p_retry 时 next_attempt_at = 现在 + 2^attempts 分钟（attempts 是加 1 之后的：2、4、8、16 分钟）；
-- p_retry = false 是永久失败（号码不在 WhatsApp、模板没批准……），attempts 设为 5，不再重试。
-- WhatsApp 发出去的写一行 whatsapp_messages（按钮回传要用 context id 对回这张订单）。
-- 送达状态可能比这里先到：那一行已经是 failed（例如号码不在 WhatsApp）的话，错误也写进这条通知的 last_error。
create or replace function public.complete_notification(
  p_id uuid,
  p_status public.notification_status,
  p_channel public.notification_channel,
  p_error text default null,
  p_wa_message_id text default null,
  p_retry boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  n public.notifications%rowtype;
  v_attempts int;
  v_retry boolean := coalesce(p_retry, true);
  v_wa_id text := nullif(trim(p_wa_message_id), '');
  v_order uuid;
  v_wa_status text;
  v_wa_code int;
  v_wa_raw jsonb;
  v_wa_error text;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  if p_status is null or p_status::text not in ('sent', 'failed', 'skipped') then
    raise exception 'INVALID_STATUS' using errcode = 'P0001', detail = coalesce(p_status::text, 'null');
  end if;

  select * into n from public.notifications where id = p_id for update;
  if not found then
    raise exception 'NOTIFICATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  if p_status = 'sent' and p_channel = 'whatsapp' then
    if coalesce(n.payload ->> 'order_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select o.id into v_order from public.orders o where o.id = (n.payload ->> 'order_id')::uuid;
    end if;
    insert into public.whatsapp_messages (
      direction, wa_message_id, phone, shop_id, wholesaler_id, message_type, order_id
    )
    values (
      'outbound',
      v_wa_id,
      coalesce(
        (select coalesce(w.whatsapp_phone, w.phone) from public.wholesalers w where w.id = n.wholesaler_id),
        (select coalesce(s.whatsapp_phone, s.phone) from public.shops s where s.id = n.shop_id)),
      n.shop_id,
      n.wholesaler_id,
      'template',
      v_order
    )
    on conflict (wa_message_id) do update set
      direction = 'outbound',
      message_type = 'template',
      phone = coalesce(public.whatsapp_messages.phone, excluded.phone),
      shop_id = coalesce(public.whatsapp_messages.shop_id, excluded.shop_id),
      wholesaler_id = coalesce(public.whatsapp_messages.wholesaler_id, excluded.wholesaler_id),
      order_id = coalesce(public.whatsapp_messages.order_id, excluded.order_id)
    returning delivery_status, error_code, raw into v_wa_status, v_wa_code, v_wa_raw;

    -- 「failed」状态比这里先到（update_whatsapp_status 先建了那一行）：照它的写法记进通知
    if v_wa_status = 'failed' then
      v_wa_error := coalesce(case when jsonb_typeof(v_wa_raw) = 'object' then v_wa_raw ->> 'status_error' end, 'WHATSAPP_FAILED')
        || coalesce(' (' || v_wa_code || ')', '');
    end if;
  end if;

  if n.status::text <> 'sending' then
    return false;
  end if;

  v_attempts := n.attempts + 1;
  update public.notifications set
    status = p_status,
    channel = p_channel,
    attempts = case when p_status = 'failed' and not v_retry then greatest(v_attempts, 5) else v_attempts end,
    next_attempt_at = case
      when p_status = 'failed' and v_retry and v_attempts < 5
        then now() + make_interval(mins => power(2, v_attempts)::int)
    end,
    last_error = case when p_status = 'sent' then coalesce(v_wa_error, last_error) else coalesce(p_error, last_error) end,
    sent_at = case when p_status = 'sent' then now() else sent_at end,
    wa_message_id = case when p_status = 'sent' then coalesce(v_wa_id, wa_message_id) else wa_message_id end
  where id = p_id;
  return true;
end;
$$;

-- FCM 说已经失效的 token / FID
create or replace function public.remove_device_tokens(p_tokens text[])
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  delete from public.device_tokens t where t.fcm_token = any (coalesce(p_tokens, '{}'::text[]));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 推送 token 登记（旧的两个参数版本删掉，免得重载混乱）。同一部手机换人登录时，token 转给新的人。
drop function if exists public.register_device_token(text, text);

create or replace function public.register_device_token(p_token text, p_platform text, p_kind text default 'token')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := nullif(trim(p_token), '');
  v_kind text := coalesce(nullif(trim(p_kind), ''), 'token');
begin
  if auth.uid() is null then
    raise exception 'NOT_LOGGED_IN' using errcode = '42501';
  end if;
  if v_token is null then
    raise exception 'INVALID_TOKEN' using errcode = 'P0001';
  end if;
  if v_kind not in ('token', 'fid') then
    raise exception 'INVALID_TOKEN_KIND' using errcode = 'P0001', detail = v_kind;
  end if;
  if p_platform is null or p_platform not in ('ios', 'android', 'web') then
    raise exception 'INVALID_PLATFORM' using errcode = 'P0001', detail = coalesce(p_platform, 'null');
  end if;

  insert into public.device_tokens (user_id, fcm_token, platform, kind)
  values (auth.uid(), v_token, p_platform, v_kind)
  on conflict (fcm_token) do update
    set user_id = excluded.user_id, platform = excluded.platform, kind = excluded.kind, last_seen_at = now();
end;
$$;

-- =============================================================================
-- E. WhatsApp 回传（只给服务器的 whatsapp-webhook 用）
-- =============================================================================

-- 批发商在 WhatsApp 按「确认」/「缺货」。Meta 会重送 webhook 长达 7 天，用 wa_message_id 去重。
-- 授权：发信人号码是这家批发商的 phone / whatsapp_phone 或其成员的电话；
-- 或者没有号码（用户只有 BSUID），但按钮是按在我们发给这家批发商、这张订单的那条消息上。
create or replace function public.handle_whatsapp_button(
  p_from text,
  p_from_user_id text,
  p_context_id text,
  p_payload text,
  p_wa_message_id text,
  p_raw jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(p_from);
  v_context text := nullif(trim(p_context_id), '');
  v_payload text := trim(coalesce(p_payload, ''));
  v_msg_id uuid;
  v_sender_wholesaler public.wholesalers%rowtype;
  v_sender_shop public.shops%rowtype;
  v_sender_locale public.app_locale;
  v_kind text;
  o public.orders%rowtype;
  v_w public.wholesalers%rowtype;
  v_authorized boolean := false;
  v_status public.order_status;
  v_result text;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  if v_phone is not null then
    select * into v_sender_wholesaler from public.wholesalers w
    where v_phone in (w.phone, w.whatsapp_phone) order by w.created_at, w.id limit 1;
    select * into v_sender_shop from public.shops s
    where v_phone in (s.phone, s.whatsapp_phone) order by s.created_at, s.id limit 1;
  end if;
  v_sender_locale := coalesce(v_sender_wholesaler.locale, v_sender_shop.locale);

  insert into public.whatsapp_messages (
    direction, wa_message_id, phone, from_user_id, context_wa_message_id,
    shop_id, wholesaler_id, message_type, body, raw
  )
  values (
    'inbound', nullif(trim(p_wa_message_id), ''), v_phone, nullif(trim(p_from_user_id), ''), v_context,
    v_sender_shop.id, v_sender_wholesaler.id, 'button', p_payload, p_raw
  )
  on conflict (wa_message_id) do nothing
  returning id into v_msg_id;
  if v_msg_id is null then
    return jsonb_build_object('result', 'duplicate');
  end if;

  if v_payload !~ '^(CONFIRM|OOS):[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return jsonb_build_object('result', 'invalid_payload', 'locale', v_sender_locale);
  end if;
  v_kind := split_part(v_payload, ':', 1);

  select * into o from public.orders where id = split_part(v_payload, ':', 2)::uuid for update;
  if not found then
    return jsonb_build_object('result', 'order_not_found', 'locale', v_sender_locale);
  end if;
  select * into v_w from public.wholesalers where id = o.wholesaler_id;

  if v_phone is not null then
    v_authorized := coalesce(v_phone in (v_w.phone, v_w.whatsapp_phone), false)
      or exists (
        select 1 from public.wholesaler_members m
        join public.profiles p on p.id = m.user_id
        where m.wholesaler_id = o.wholesaler_id and p.phone = v_phone
      );
  elsif v_context is not null then
    v_authorized := exists (
      select 1 from public.whatsapp_messages x
      where x.wa_message_id = v_context
        and x.direction = 'outbound'
        and x.wholesaler_id = o.wholesaler_id
        and x.order_id = o.id
    );
  end if;
  if not v_authorized then
    return jsonb_build_object('result', 'not_authorized', 'locale', v_sender_locale);
  end if;

  update public.whatsapp_messages set order_id = o.id, wholesaler_id = o.wholesaler_id where id = v_msg_id;

  if o.status = 'pending' then
    if v_kind = 'CONFIRM' then
      v_status := public.confirm_order(o.id, '{}', 'whatsapp');
    else
      perform public.set_order_status(o.id, 'out_of_stock', null, 'whatsapp');
      v_status := 'out_of_stock';
    end if;
    v_result := v_status::text;
  else
    v_status := o.status;
    v_result := 'already_' || o.status::text;
  end if;

  return jsonb_build_object('result', v_result, 'order_no', o.order_no, 'status', v_status, 'locale', v_w.locale);
end;
$$;

-- 其他进来的消息（文字、语音……）：只记录，按号码对上店 / 批发商；重复的 id 忽略。
-- 第六步再处理成订单草稿。媒体 id 记在 raw.media_id（第六步下载后再填 media_path）。
create or replace function public.record_whatsapp_message(
  p_from text,
  p_type public.wa_message_type,
  p_body text,
  p_media_id text,
  p_wa_message_id text,
  p_raw jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := public.normalize_phone(p_from);
  v_shop uuid;
  v_wholesaler uuid;
  v_id uuid;
  v_raw jsonb := p_raw;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  if v_phone is not null then
    select s.id into v_shop from public.shops s
    where v_phone in (s.phone, s.whatsapp_phone) order by s.created_at, s.id limit 1;
    select w.id into v_wholesaler from public.wholesalers w
    where v_phone in (w.phone, w.whatsapp_phone) order by w.created_at, w.id limit 1;
  end if;
  if nullif(trim(p_media_id), '') is not null then
    v_raw := case when jsonb_typeof(p_raw) = 'object' then p_raw else '{}'::jsonb end
      || jsonb_build_object('media_id', trim(p_media_id));
  end if;

  insert into public.whatsapp_messages (
    direction, wa_message_id, phone, from_user_id, context_wa_message_id,
    shop_id, wholesaler_id, message_type, body, raw
  )
  values (
    'inbound', nullif(trim(p_wa_message_id), ''), v_phone,
    case when jsonb_typeof(p_raw) = 'object' then nullif(p_raw ->> 'from_user_id', '') end,
    case when jsonb_typeof(p_raw) = 'object' then nullif(p_raw -> 'context' ->> 'id', '') end,
    v_shop, v_wholesaler, coalesce(p_type, 'other'), p_body, v_raw
  )
  on conflict (wa_message_id) do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('result', 'duplicate');
  end if;
  return jsonb_build_object('result', 'recorded', 'id', v_id, 'shop_id', v_shop, 'wholesaler_id', v_wholesaler);
end;
$$;

-- 发出去的消息的送达状态。状态可能乱序到达：只往前走（sent < delivered < read < played），
-- failed 永远覆盖。还没记录的 id（状态比 complete_notification 先到）先建一行，之后会补上资料。
create or replace function public.update_whatsapp_status(
  p_wa_message_id text,
  p_status text,
  p_error_code int default null,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := nullif(trim(p_wa_message_id), '');
  v_status text := lower(trim(coalesce(p_status, '')));
  v_rank int;
  v_cur record;
  v_new_id uuid;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  v_rank := case v_status when 'sent' then 1 when 'delivered' then 2 when 'read' then 3 when 'played' then 4
                          when 'failed' then 9 end;
  if v_rank is null or v_id is null then
    return jsonb_build_object('result', 'ignored');
  end if;

  insert into public.whatsapp_messages (direction, wa_message_id, message_type, delivery_status, error_code, raw)
  values ('outbound', v_id, 'other', v_status, p_error_code,
          case when p_error is not null then jsonb_build_object('status_error', p_error) end)
  on conflict (wa_message_id) do nothing
  returning id into v_new_id;

  if v_new_id is null then
    select x.id, x.direction, x.delivery_status into v_cur
    from public.whatsapp_messages x where x.wa_message_id = v_id for update;
    if v_cur.direction <> 'outbound' then
      return jsonb_build_object('result', 'ignored');
    end if;
    if coalesce(case v_cur.delivery_status when 'sent' then 1 when 'delivered' then 2 when 'read' then 3
                                           when 'played' then 4 when 'failed' then 9 end, 0) >= v_rank then
      return jsonb_build_object('result', 'stale', 'delivery_status', v_cur.delivery_status);
    end if;
    update public.whatsapp_messages x set
      delivery_status = v_status,
      error_code = coalesce(p_error_code, x.error_code),
      raw = case when p_error is not null
                 then case when jsonb_typeof(x.raw) = 'object' then x.raw else '{}'::jsonb end
                      || jsonb_build_object('status_error', p_error)
                 else x.raw end
    where x.id = v_cur.id;
  end if;

  if v_status = 'failed' then
    update public.notifications n
    set last_error = coalesce(p_error, 'WHATSAPP_FAILED') || coalesce(' (' || p_error_code || ')', '')
    where n.wa_message_id = v_id;
  end if;

  return jsonb_build_object('result', 'updated', 'delivery_status', v_status);
end;
$$;

-- =============================================================================
-- F. 定时任务调用的函数
-- =============================================================================

-- 每天早上：今天有要送的单（或还有今天的单没确认）的批发商，各发一条当天总结。
-- 同一天重复跑不会重复发。
create or replace function public.enqueue_daily_summaries()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.today_myt();
  v_count int;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  insert into public.notifications (wholesaler_id, event_type, payload)
  select w.id, 'daily_summary', jsonb_build_object(
    'date', v_today, 'order_count', s.order_count, 'pending_count', s.pending_count, 'total_sen', s.total_sen)
  from public.wholesalers w
  cross join lateral (
    select
      count(*) filter (where o.status in ('confirmed', 'delivering'))::int as order_count,
      count(*) filter (where o.status = 'pending')::int as pending_count,
      coalesce(sum(o.total_sen) filter (where o.status in ('confirmed', 'delivering')), 0)::int as total_sen
    from public.orders o
    where o.wholesaler_id = w.id and o.expected_delivery_date = v_today
  ) s
  where w.status = 'active'
    and (s.order_count > 0 or s.pending_count > 0)
    and not exists (
      select 1 from public.notifications n
      where n.wholesaler_id = w.id and n.event_type = 'daily_summary'
        and n.payload ->> 'date' = to_char(v_today, 'YYYY-MM-DD')
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 太久没确认的订单（app_settings.order_confirm_alert_minutes）：提醒每个客服，每张单只提醒一次。
-- 还没有客服账号时先不标记，等有客服再提醒。
create or replace function public.enqueue_unconfirmed_alerts()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_minutes int;
  v_admins uuid[];
  r record;
  v_count int := 0;
begin
  if not public.is_service_call() then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;

  select a.order_confirm_alert_minutes into v_minutes from public.app_settings a;
  select array_agg(p.id order by p.id) into v_admins from public.profiles p where p.role = 'admin';
  if v_admins is null then
    return 0;
  end if;

  for r in
    select o.id, o.order_no, o.created_at, o.wholesaler_id, w.name as wholesaler_name,
           coalesce(w.whatsapp_phone, w.phone) as wholesaler_phone, s.name as shop_name
    from public.orders o
    join public.wholesalers w on w.id = o.wholesaler_id
    join public.shops s on s.id = o.shop_id
    where o.status = 'pending'
      and o.unconfirmed_alert_at is null
      and o.created_at <= now() - make_interval(mins => coalesce(v_minutes, 30))
    order by o.created_at, o.id
    for update of o skip locked
  loop
    insert into public.notifications (user_id, event_type, payload)
    select a.id, 'order_unconfirmed', jsonb_build_object(
      'order_id', r.id, 'order_no', r.order_no, 'wholesaler_id', r.wholesaler_id,
      'wholesaler_name', r.wholesaler_name, 'wholesaler_phone', r.wholesaler_phone,
      'shop_name', r.shop_name, 'created_at', r.created_at,
      'pending_minutes', floor(extract(epoch from now() - r.created_at) / 60)::int)
    from unnest(v_admins) as a(id);
    update public.orders set unconfirmed_alert_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- 叫 Edge Function dispatch-notifications（pg_net，异步：交易提交后才真的发出去，不会拖慢下单）。
-- 网址和钥匙放在 Vault（project_url、secret_key），部署时在 SQL editor 用 vault.create_secret 建。
-- 没有 Vault / pg_net / 秘密还没建 → 回传 null，不报错（本机测试环境就是这样）。
-- p_only_if_due = true（每分钟的定时任务）：没有要发的通知就不叫，省调用次数。
create or replace function public._request_notification_dispatch(p_only_if_due boolean default false)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_key text;
  v_request_id bigint;
begin
  if coalesce(p_only_if_due, false) and not exists (
    select 1 from public.notifications x
    where x.status = 'queued'
       or (x.status = 'failed' and x.attempts < 5 and x.next_attempt_at <= now())
       or (x.status = 'sending' and x.claimed_at < now() - interval '10 minutes')
  ) then
    return null;
  end if;

  if to_regclass('vault.decrypted_secrets') is null
     or not exists (
       select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'net' and p.proname = 'http_post'
     ) then
    return null;
  end if;

  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1' into v_url using 'project_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1' into v_key using 'secret_key';
  if nullif(trim(v_url), '') is null or nullif(trim(v_key), '') is null then
    return null;
  end if;

  execute 'select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := $4)'
  into v_request_id
  using rtrim(trim(v_url), '/') || '/functions/v1/dispatch-notifications',
        jsonb_build_object('Content-Type', 'application/json', 'apikey', trim(v_key)),
        '{}'::jsonb,
        10000;
  return v_request_id;
exception when others then
  raise warning '_request_notification_dispatch: %', sqlerrm;
  return null;
end;
$$;

-- 新增通知时立刻叫一次 dispatcher（每个 insert 语句叫一次）。出任何错都不能挡住下单。
create or replace function public.notifications_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from new_notifications) then
    perform public._request_notification_dispatch(false);
  end if;
  return null;
exception when others then
  raise warning 'notifications_after_insert: %', sqlerrm;
  return null;
end;
$$;

create trigger notifications_dispatch
  after insert on public.notifications
  referencing new table as new_notifications
  for each statement execute function public.notifications_after_insert();

-- 建定时任务（有 pg_cron 才建；同名的会更新）。pg_cron 用 UTC：马来西亚 05:30 = UTC 21:30
create or replace function public._schedule_seller_jobs()
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    return false;
  end if;
  perform cron.schedule('daily-delivery-summary', '30 21 * * *', 'select public.enqueue_daily_summaries()');
  perform cron.schedule('unconfirmed-order-alerts', '*/5 * * * *', 'select public.enqueue_unconfirmed_alerts()');
  perform cron.schedule('dispatch-notifications', '* * * * *', 'select public._request_notification_dispatch(true)');
  return true;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net with schema extensions;
  else
    raise notice 'pg_net 不可用，跳过（通知要等 dispatcher 被别的方式叫）';
  end if;

  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform public._schedule_seller_jobs();
  else
    raise notice 'pg_cron 不可用，跳过定时任务';
  end if;
end;
$$;

-- =============================================================================
-- G. Storage（有 storage schema 才建）
--   price-lists     私人：<wholesaler_id>/<uuid>.<ext>，价目表照片 / PDF / Excel / CSV，10 MB
--   product-photos  公开读：<wholesaler_id>/<uuid>.<ext>，商品照片，5 MB
-- 第一层文件夹 = 批发商 id：该批发商的成员可以上传 / 读取 / 改 / 删；客服全部。
-- =============================================================================

create or replace function public._setup_seller_storage()
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null
     or to_regprocedure('storage.foldername(text)') is null then
    return false;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values
    ('price-lists', 'price-lists', false, 10485760, array[
      'image/jpeg', 'image/png', 'image/webp', 'application/pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel', 'text/csv']),
    ('product-photos', 'product-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

  drop policy if exists "seller files: member read" on storage.objects;
  drop policy if exists "seller files: member upload" on storage.objects;
  drop policy if exists "seller files: member update" on storage.objects;
  drop policy if exists "seller files: member delete" on storage.objects;
  drop policy if exists "seller files: admin full access" on storage.objects;

  create policy "seller files: member read" on storage.objects for select to authenticated
    using (
      bucket_id in ('price-lists', 'product-photos')
      and (storage.foldername(name))[1] in (select t.id::text from public.my_wholesaler_ids() as t(id))
    );
  create policy "seller files: member upload" on storage.objects for insert to authenticated
    with check (
      bucket_id in ('price-lists', 'product-photos')
      and (storage.foldername(name))[1] in (select t.id::text from public.my_wholesaler_ids() as t(id))
    );
  create policy "seller files: member update" on storage.objects for update to authenticated
    using (
      bucket_id in ('price-lists', 'product-photos')
      and (storage.foldername(name))[1] in (select t.id::text from public.my_wholesaler_ids() as t(id))
    )
    with check (
      bucket_id in ('price-lists', 'product-photos')
      and (storage.foldername(name))[1] in (select t.id::text from public.my_wholesaler_ids() as t(id))
    );
  create policy "seller files: member delete" on storage.objects for delete to authenticated
    using (
      bucket_id in ('price-lists', 'product-photos')
      and (storage.foldername(name))[1] in (select t.id::text from public.my_wholesaler_ids() as t(id))
    );
  create policy "seller files: admin full access" on storage.objects for all to authenticated
    using (bucket_id in ('price-lists', 'product-photos') and (select public.is_admin()))
    with check (bucket_id in ('price-lists', 'product-photos') and (select public.is_admin()));
  return true;
end;
$$;

do $$
begin
  if not public._setup_seller_storage() then
    raise notice '没有 storage schema，跳过 bucket 和规则';
  end if;
end;
$$;

-- =============================================================================
-- H. 函数权限：先全部收回，再只开放需要的
-- =============================================================================

revoke execute on function
  public._name_trgms(text),
  public._trgm_sim(text[], text[]),
  public._name_similarity(text, text),
  public._name_numbers(text),
  public._unit_label(public.sell_unit, public.app_locale),
  public.get_seller_home(uuid),
  public.list_seller_orders(uuid, public.order_status[], date, int),
  public.get_delivery_summary(uuid, date),
  public.suggest_import_matches(uuid),
  public.apply_price_list_import(uuid),
  public._notification_route(uuid, uuid, uuid, text),
  public._notification_order_details(uuid, public.app_locale),
  public.claim_notifications(int),
  public.complete_notification(uuid, public.notification_status, public.notification_channel, text, text, boolean),
  public.remove_device_tokens(text[]),
  public.register_device_token(text, text, text),
  public.handle_whatsapp_button(text, text, text, text, text, jsonb),
  public.record_whatsapp_message(text, public.wa_message_type, text, text, text, jsonb),
  public.update_whatsapp_status(text, text, int, text),
  public.enqueue_daily_summaries(),
  public.enqueue_unconfirmed_alerts(),
  public._request_notification_dispatch(boolean),
  public.notifications_after_insert(),
  public._schedule_seller_jobs(),
  public._setup_seller_storage()
from public, anon, authenticated;

-- 部署用的：只有迁移（postgres）能跑
revoke execute on function public._schedule_seller_jobs(), public._setup_seller_storage() from service_role;

-- App 调用的函数（每个函数里面都会再检查是谁在调用）
grant execute on function
  public.get_seller_home(uuid),
  public.list_seller_orders(uuid, public.order_status[], date, int),
  public.get_delivery_summary(uuid, date),
  public.apply_price_list_import(uuid),
  public.register_device_token(text, text, text)
to authenticated;

-- 服务器（Edge Functions、定时任务）用的
grant execute on function
  public._name_trgms(text),
  public._trgm_sim(text[], text[]),
  public._name_similarity(text, text),
  public._name_numbers(text),
  public._unit_label(public.sell_unit, public.app_locale),
  public.get_seller_home(uuid),
  public.list_seller_orders(uuid, public.order_status[], date, int),
  public.get_delivery_summary(uuid, date),
  public.suggest_import_matches(uuid),
  public.apply_price_list_import(uuid),
  public._notification_route(uuid, uuid, uuid, text),
  public._notification_order_details(uuid, public.app_locale),
  public.claim_notifications(int),
  public.complete_notification(uuid, public.notification_status, public.notification_channel, text, text, boolean),
  public.remove_device_tokens(text[]),
  public.register_device_token(text, text, text),
  public.handle_whatsapp_button(text, text, text, text, text, jsonb),
  public.record_whatsapp_message(text, public.wa_message_type, text, text, text, jsonb),
  public.update_whatsapp_status(text, text, int, text),
  public.enqueue_daily_summaries(),
  public.enqueue_unconfirmed_alerts(),
  public._request_notification_dispatch(boolean)
to service_role;
