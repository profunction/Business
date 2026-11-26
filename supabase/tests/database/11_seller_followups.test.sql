-- 第四步补完：订单详情的店 WhatsApp 号码（只给批发商 / 客服）、通知带收件的 wholesaler_id、
-- 批发商订单列表的游标分页、上架后的导入锁住、导入行「看过了」存在数据库
begin;
\ir _helpers.psql
select plan(42);
select tests.setup_world();

-- S1 的 WhatsApp 号码跟电话不一样
update public.shops set whatsapp_phone = '60177000001' where id = tests.uid('S1');

-- 准备 6 张 W1 的单（S1 / S2 / S3 各两次）
select tests.add_to_cart('S1', 'P1', 2);
select public.place_order(tests.uid('S1')) as _ \gset
select tests.add_to_cart('S2', 'P1', 1);
select public.place_order(tests.uid('S2')) as _ \gset
select tests.add_to_cart('S1', 'P1', 2);
select public.place_order(tests.uid('S1')) as _ \gset
select tests.add_to_cart('S2', 'P1', 1);
select public.place_order(tests.uid('S2')) as _ \gset
select tests.add_to_cart('S1', 'P1', 2);
select public.place_order(tests.uid('S1')) as _ \gset
select tests.add_to_cart('S2', 'P1', 1);
select public.place_order(tests.uid('S2')) as _ \gset

-- 下单时间：n 越大越早；n = 3 和 5 是同一个时间（要按 id 排）
create table tests.w1_orders as
select o.id, row_number() over (order by o.order_no) as n
from public.orders o where o.wholesaler_id = tests.uid('W1');
update public.orders o set created_at = now() - (w.n || ' hours')::interval
from tests.w1_orders w where w.id = o.id;
update public.orders o set created_at = (select created_at from public.orders where id = (select id from tests.w1_orders where n = 3))
where o.id = (select id from tests.w1_orders where n = 5);
-- 三张确认（不是 pending），三张还是 pending
update public.orders set status = 'confirmed', confirmed_at = now()
where id in (select id from tests.w1_orders where n in (1, 3, 5));
grant select on tests.w1_orders to authenticated;

-- =============================================================================
-- A. 订单详情：店的 WhatsApp 号码
-- =============================================================================
select (select id from tests.w1_orders where n = 1) as o1 \gset

select tests.login_as(tests.uid('seller1'));
select is(public.get_order(:'o1') -> 'shop' ->> 'whatsapp_phone', '60177000001', '批发商看得到店的 WhatsApp 号码');
select is(public.get_order(:'o1') -> 'shop' ->> 'phone', '60111000001', '电话照旧');

select tests.login_as(tests.uid('admin'));
select is(public.get_order(:'o1') -> 'shop' ->> 'whatsapp_phone', '60177000001', '客服也看得到');

select tests.login_as(tests.uid('buyer1'));
select is((public.get_order(:'o1') -> 'shop') ? 'whatsapp_phone', false, '买家那边不回传 whatsapp_phone');
select is(public.get_order(:'o1') -> 'shop' ->> 'name', 'S1 店', '（买家照样看得到订单）');

select tests.login_as(tests.uid('seller2'));
select throws_ok(format('select public.get_order(%L)', :'o1'), '42501', 'NOT_ALLOWED', '别家批发商看不到');

-- 没有 WhatsApp 号码：null（App 就用电话）
select tests.logout();
update public.shops set whatsapp_phone = null where id = tests.uid('S2');
select tests.login_as(tests.uid('seller1'));
select is(
  (select (public.get_order(id) -> 'shop') -> 'whatsapp_phone' from tests.w1_orders where n = 2),
  'null'::jsonb, '店没有 WhatsApp 号码：回传 null'
);

-- =============================================================================
-- B. claim_notifications 带收件的 wholesaler_id / shop_id
-- =============================================================================
select tests.logout();
delete from public.notifications;
insert into public.device_tokens (user_id, fcm_token, platform, kind) values (tests.uid('seller1'), 'tok-s1', 'android', 'token');
insert into public.device_tokens (user_id, fcm_token, platform, kind) values (tests.uid('buyer1'), 'tok-b1', 'android', 'token');
insert into public.notifications (wholesaler_id, event_type, payload, created_at) values
  (tests.uid('W1'), 'order_new', jsonb_build_object('order_id', :'o1'), now() - interval '3 minutes'),
  (tests.uid('W1'), 'daily_summary', '{"date": "2026-11-26", "order_count": 1, "pending_count": 0, "total_sen": 100}',
   now() - interval '2 minutes');
insert into public.notifications (shop_id, event_type, payload, created_at) values
  (tests.uid('S1'), 'order_status_changed', jsonb_build_object('order_id', :'o1', 'status', 'confirmed'),
   now() - interval '1 minute');
select public.claim_notifications(10, gen_random_uuid()) as claimed \gset
select is(jsonb_array_length(:'claimed'::jsonb), 3, '领到三条');
select is(
  (select string_agg(e ->> 'event_type' || ':' || coalesce(e ->> 'wholesaler_id', '-') || ':' || coalesce(e ->> 'shop_id', '-'),
                     ',' order by ord)
   from jsonb_array_elements(:'claimed'::jsonb) with ordinality t(e, ord)),
  'order_new:' || tests.uid('W1') || ':-,daily_summary:' || tests.uid('W1') || ':-,order_status_changed:-:' || tests.uid('S1'),
  '每条都带收件的 wholesaler_id / shop_id（顺序跟原来一样）'
);
select is(
  (select count(*)::int from jsonb_array_elements(:'claimed'::jsonb) e where e ? 'push_targets' and e ? 'details' and e ? 'locale'),
  3, '原来的栏位都还在'
);
select is((select count(*)::int from public.notifications where status = 'sending' and claim_id is not null), 3,
  '照旧记下 claim_id');
select is(public.claim_notifications(10, gen_random_uuid()), '[]'::jsonb, '没得领：空的 array');

select tests.login_as(tests.uid('seller1'));
select throws_ok('select public.claim_notifications(10, null)', '42501', null, '普通用户不能领通知');

-- =============================================================================
-- C. list_seller_orders 游标分页
-- =============================================================================
select tests.login_as(tests.uid('seller1'));
select public.list_seller_orders(tests.uid('W1'), p_limit => 200) as full_list \gset
select is(jsonb_array_length(:'full_list'::jsonb), 6, '全部 6 张');
select is(
  (select string_agg(e ->> 'status', ',' order by ord) from jsonb_array_elements(:'full_list'::jsonb) with ordinality t(e, ord)),
  'pending,pending,pending,confirmed,confirmed,confirmed', 'pending 在最前面'
);
-- pending：旧到新；其他：新到旧（n 大 = 早）
select is(
  (select array_agg(w.n order by ord) from jsonb_array_elements(:'full_list'::jsonb) with ordinality t(e, ord)
   join tests.w1_orders w on w.id = (e ->> 'id')::uuid),
  array[6, 4, 2, 1]::bigint[] || (select array_agg(n order by id desc) from tests.w1_orders where n in (3, 5)),
  'pending 旧到新、其他新到旧（同一个时间按 id）'
);
select matches(:'full_list'::jsonb -> 0 ->> 'cursor', '^p\|\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\|', 'pending 的 cursor 是 p|…');
select matches(:'full_list'::jsonb -> 5 ->> 'cursor', '^o\|', '其他的 cursor 是 o|…');

-- 一页 2 张，一页一页读，接起来跟一次读完一样
with recursive pages(page, list) as (
  select 1, public.list_seller_orders(tests.uid('W1'), null, null, 2, null)
  union all
  select page + 1, public.list_seller_orders(tests.uid('W1'), null, null, 2, list -> -1 ->> 'cursor')
  from pages where jsonb_array_length(list) > 0 and page < 10
)
select (select count(*)::int from pages where jsonb_array_length(list) > 0) as page_count,
       (select jsonb_agg(e order by p.page, t.ord) from pages p, jsonb_array_elements(p.list) with ordinality t(e, ord))
         as paged \gset
select is(:page_count, 3, '一页 2 张：3 页');
select is(:'paged'::jsonb, :'full_list'::jsonb, '一页一页读接起来 = 一次读完（同一个时间的按 id 排，不重复不漏）');

-- 一页 4 张：第二页从 pending 那一段的最后接到其他那一段
select public.list_seller_orders(tests.uid('W1'), p_limit => 4,
  p_after => (:'full_list'::jsonb -> 1 ->> 'cursor')) as from_p \gset
select is(
  (select array_agg(e ->> 'id' order by ord) from jsonb_array_elements(:'from_p'::jsonb) with ordinality t(e, ord)),
  (select array_agg(e ->> 'id' order by ord) from jsonb_array_elements(:'full_list'::jsonb) with ordinality t(e, ord) where ord between 3 and 6),
  '停在 pending 那一段：后面的 pending + 全部其他的'
);
select is(
  jsonb_array_length(public.list_seller_orders(tests.uid('W1'), p_after => (:'full_list'::jsonb -> 5 ->> 'cursor'))),
  0, '最后一张之后：空的'
);

-- 读完第一页之后，下一张 pending 被确认了：照 cursor 记的那一段继续，不会整段跳掉
select tests.logout();
update public.orders set status = 'confirmed' where id = (select id from tests.w1_orders where n = 4);
select tests.login_as(tests.uid('seller1'));
select is(
  (select array_agg(w.n order by ord)
   from jsonb_array_elements(public.list_seller_orders(tests.uid('W1'), p_after => (:'full_list'::jsonb -> 0 ->> 'cursor')))
        with ordinality t(e, ord)
   join tests.w1_orders w on w.id = (e ->> 'id')::uuid),
  array[2, 1]::bigint[] || (select array_agg(n order by id desc) from tests.w1_orders where n in (3, 5)) || array[4]::bigint[],
  '中间改了状态：剩下的照新的状态排，一张都不漏'
);

-- 筛选 + 分页
select is(
  jsonb_array_length(public.list_seller_orders(tests.uid('W1'), array['confirmed']::public.order_status[], null, 50,
    (:'full_list'::jsonb -> 3 ->> 'cursor'))),
  3, '只看已确认 + 游标'
);

select throws_ok(format('select public.list_seller_orders(%L, p_after => %L)', tests.uid('W1'), 'x|bad'),
  'P0001', 'INVALID_CURSOR', 'cursor 格式不对');
select is(jsonb_array_length(public.list_seller_orders(tests.uid('W1'), p_after => '')), 6, '空字串 = 第一页');
select throws_ok(format('select public.list_seller_orders(%L)', tests.uid('W2')), '42501', 'NOT_ALLOWED', '别家的不能看');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'list_seller_orders'),
  1, '旧的 4 个参数版本删掉了（不会重载混乱）'
);
select is(has_function_privilege('authenticated', 'public._seller_order_cursor(boolean, timestamptz, uuid)', 'execute'), false,
  '_seller_order_cursor 是内部的');

-- =============================================================================
-- D. 价目表导入：checked_at、上架后锁住
-- =============================================================================
select tests.logout();
\set imp '99999999-0000-4000-8000-000000000011'
insert into public.price_list_imports (id, wholesaler_id, file_path, file_type, created_by, status)
values (:'imp', tests.uid('W1'), 'cccccccc-0000-4000-8000-000000000001/5b0f2c1e-8a7d-4c1e-9a3b-2f6d1e0c9a12.jpg', 'image', tests.uid('seller1'), 'review');
insert into public.price_list_import_rows (import_id, row_no, name, unit, pack_qty, price_sen, action, confidence) values
  (:'imp', 1, '新杯子', 'carton', 1000, 9000, 'create', 0.4),
  (:'imp', 2, '新盖子', 'carton', 1000, 5000, 'create', 0.9);
select is((select count(*)::int from public.price_list_import_rows where import_id = :'imp' and checked_at is null), 2,
  '服务器写的行：还没看过');

select tests.login_as(tests.uid('seller1'));
update public.price_list_import_rows set price_sen = 9100 where import_id = :'imp' and row_no = 1;
select isnt((select checked_at from public.price_list_import_rows where import_id = :'imp' and row_no = 1), null,
  '批发商改了一行：看过了（存在数据库，重开 App 也记得）');
select is((select checked_at from public.price_list_import_rows where import_id = :'imp' and row_no = 2), null, '没改的那行不算');
update public.price_list_import_rows set checked_at = '2000-01-01' where import_id = :'imp' and row_no = 2;
select ok((select checked_at > now() - interval '1 minute' from public.price_list_import_rows where import_id = :'imp' and row_no = 2),
  '时间由服务器定（不信手机）');
update public.price_list_import_rows set checked_at = null where import_id = :'imp' and row_no = 2;
select is((select checked_at from public.price_list_import_rows where import_id = :'imp' and row_no = 2), null, '可以取消');

select is(public.apply_price_list_import(:'imp'), '{"created": 2, "updated": 0, "skipped": 0}'::jsonb, '上架');

-- 上架之后：行不能改、不能新增、不能删（App、客服、服务器都一样）
select throws_ok(format('update public.price_list_import_rows set price_sen = 1 where import_id = %L', :'imp'),
  'P0001', 'IMPORT_ALREADY_APPLIED', '上架后批发商不能改行');
select throws_ok(format('delete from public.price_list_import_rows where import_id = %L', :'imp'),
  'P0001', 'IMPORT_ALREADY_APPLIED', '上架后批发商不能删行');
select tests.login_as(tests.uid('admin'));
select throws_ok(format('update public.price_list_import_rows set checked_at = null where import_id = %L', :'imp'),
  'P0001', 'IMPORT_ALREADY_APPLIED', '客服也不能改');
select tests.logout();
select throws_ok(
  format('insert into public.price_list_import_rows (import_id, row_no, name, action) values (%L, 9, %L, %L)', :'imp', 'x', 'skip'),
  'P0001', 'IMPORT_ALREADY_APPLIED', '服务器也不能再加行');
select throws_ok(format('update public.price_list_imports set ai_raw = %L where id = %L', '{"x": 1}', :'imp'),
  'P0001', 'IMPORT_ALREADY_APPLIED', '上架后 ai_raw 不能改（服务器也不行）');
select throws_ok(format('update public.price_list_imports set status = %L where id = %L', 'review', :'imp'),
  'P0001', 'IMPORT_ALREADY_APPLIED', '上架后不能改回 review');

-- 整份删掉（连带删行）可以
delete from public.price_list_imports where id = :'imp';
select is((select count(*)::int from public.price_list_import_rows where import_id = :'imp'), 0, '删掉整份导入：行跟着删掉');

select * from finish();
rollback;
