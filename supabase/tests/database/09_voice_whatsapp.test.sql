-- 第六步：语音下单、WhatsApp 下单（订单草稿）：服务器占位 / 用量、AI 用的商品资料、建草稿、
-- 老板看 / 改 / 送出 / 不要、客服的 WhatsApp 订单、WhatsApp 回复（24 小时窗口）、推送优先、不通知自己、Storage、权限
begin;
\ir _helpers.psql
select plan(103);
select tests.setup_world();

-- S3（未付费）免费开放 W1
insert into public.unlocked_wholesalers (shop_id, wholesaler_id) values (tests.uid('S3'), tests.uid('W1'));

create function tests.vpath(p_shop text) returns text language sql as $$
  select tests.uid(p_shop)::text || '/' || gen_random_uuid()::text || '.wav';
$$;
-- 服务器身份占位，回传 run_id
create function tests.reserve(p_shop text, p_user text) returns uuid language plpgsql as $$
declare
  v_run uuid := gen_random_uuid();
  v jsonb;
begin
  v := public.reserve_voice_order_run(tests.uid(p_shop), tests.uid(p_user), v_run, 'app_voice', tests.vpath(p_shop));
  if v ->> 'result' <> 'ok' then
    raise exception 'reserve failed: %', v;
  end if;
  return v_run;
end;
$$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- =============================================================================
-- 权限
-- =============================================================================
select tests.login_as(tests.uid('buyer1'));
select throws_ok(format('select public.reserve_voice_order_run(%L, %L, gen_random_uuid(), %L, %L)',
  tests.uid('S1'), tests.uid('buyer1'), 'app_voice', tests.vpath('S1')), '42501', null, '买家不能自己占位（只给服务器）');
select throws_ok(format('select public.create_order_draft(gen_random_uuid(), %L)', 'x'), '42501', null,
  '买家不能自己建草稿');
select throws_ok(format('select public.get_voice_order_context(%L)', tests.uid('S1')), '42501', null,
  '买家拿不到 AI 用的商品资料');
select is(tests.error_of('select public.admin_list_order_drafts()'), 'NOT_ALLOWED', '买家不能看客服的 WhatsApp 订单');
select tests.login_as_anon();
select throws_ok(format('select public.get_order_draft(%L)', gen_random_uuid()), '42501', null, '没登录不能看草稿');
select tests.logout();
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('reserve_voice_order_run', 'reserve_whatsapp_order', 'get_voice_order_context',
        'create_order_draft', 'fail_voice_order_run', 'get_order_draft', 'list_order_drafts', 'save_order_draft',
        'submit_order_draft', 'reject_order_draft', 'admin_list_order_drafts', '_draft_for', '_order_draft_json',
        '_draft_quote', '_load_draft_into_cart', '_orderable_products', '_queue_whatsapp_reply')
      and (has_function_privilege('anon', p.oid, 'execute') or not p.prosecdef
           or not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false))
  ),
  '新函数：security definer、固定 search_path、anon 不能叫'
);
select ok(not has_function_privilege('authenticated', 'public._draft_quote(uuid, uuid)', 'execute'),
  '算草稿报价的小工具 App 叫不到');
select ok((select relrowsecurity from pg_class where oid = 'public.order_draft_items'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.voice_order_runs'::regclass), '新表都开了 RLS');

-- =============================================================================
-- 占位和用量（服务器身份）
-- =============================================================================
select is(public.reserve_voice_order_run(tests.uid('S1'), tests.uid('buyer2'), gen_random_uuid(), 'app_voice',
  tests.vpath('S1')) ->> 'result', 'not_member', '别家店的老板不能用这家店');
select is(public.reserve_voice_order_run(tests.uid('S1'), tests.uid('buyer1'), gen_random_uuid(), 'app_voice',
  tests.uid('S2') || '/' || gen_random_uuid() || '.wav') ->> 'result', 'invalid_path', '录音一定要在自己店的文件夹');
select is(public.reserve_voice_order_run(tests.uid('S1'), tests.uid('buyer1'), gen_random_uuid(), 'app_voice',
  tests.uid('S1') || '/../x.wav') ->> 'result', 'invalid_path', '路径不能绕出去');
select is(public.reserve_voice_order_run(gen_random_uuid(), tests.uid('buyer1'), gen_random_uuid(), 'app_voice',
  null) ->> 'result', 'not_found', '没有这家店');
select is(tests.error_of(format('select public.reserve_voice_order_run(%L, %L, gen_random_uuid(), %L)',
  tests.uid('S1'), tests.uid('admin'), 'admin')), 'INVALID_SOURCE', '来源只能是语音 / WhatsApp');
select is(tests.error_of(format('select public.reserve_voice_order_run(%L, %L, null, %L)',
  tests.uid('S1'), tests.uid('buyer1'), 'app_voice')), 'INVALID_RUN_ID', '一定要给 run_id');

select public.reserve_voice_order_run(tests.uid('S1'), tests.uid('buyer1'), gen_random_uuid(), 'app_voice',
  tests.vpath('S1')) as r1 \gset
select is(:'r1'::jsonb ->> 'result', 'ok', '自己店的老板、路径对 → ok');
select is((:'r1'::jsonb ->> 'full_access')::boolean, true, '回传有没有付费（试用中）');
select is(tests.error_of(format('select public.reserve_voice_order_run(%L, %L, %L, %L, %L)',
  tests.uid('S1'), tests.uid('buyer1'), :'r1'::jsonb ->> 'run_id', 'app_voice', tests.vpath('S1'))),
  'RUN_ID_USED', '同一个 run_id 不能用两次');
select is(public.reserve_voice_order_run(tests.uid('S1'), tests.uid('admin'), gen_random_uuid(), 'app_voice',
  tests.vpath('S1')) ->> 'result', 'ok', '客服也可以替店录音');

-- 10 分钟最多 6 次（已经 2 次，再 4 次就满）
select tests.reserve('S1', 'buyer1') from generate_series(1, 4);
select public.reserve_voice_order_run(tests.uid('S1'), tests.uid('buyer1'), gen_random_uuid(), 'app_voice',
  tests.vpath('S1')) as rq \gset
select is(:'rq'::jsonb ->> 'result', 'quota', '10 分钟第 7 次 → quota');
select is(:'rq'::jsonb ->> 'window', '10m', '回传哪一段满了');
select ok((:'rq'::jsonb ->> 'retry_after_sec')::int between 1 and 600, '要等几秒');
select is(public.reserve_voice_order_run(tests.uid('S2'), tests.uid('buyer2'), gen_random_uuid(), 'app_voice',
  tests.vpath('S2')) ->> 'result', 'ok', '用量按店算：别家店不受影响');
delete from public.voice_order_runs;

-- =============================================================================
-- AI 用的商品资料
-- =============================================================================
select public.get_voice_order_context(tests.uid('S1')) as ctx1 \gset
select is(
  (select string_agg(e ->> 'name', ',' order by e ->> 'name') from jsonb_array_elements(:'ctx1'::jsonb -> 'products') e),
  'W1 16oz 杯,W1 平盖,W2 16oz 杯 小包,W3 16oz 杯,W3 平盖',
  '试用中：送这一区的已上架商品（没有草稿、没有待审核批发商的）');
select is(
  (select string_agg(e ->> 'name', ',' order by e ->> 'name')
   from jsonb_array_elements(public.get_voice_order_context(tests.uid('S3')) -> 'products') e),
  'W1 16oz 杯,W1 平盖', '未付费：只有免费开放的那家（不能向其他家下单）');

-- =============================================================================
-- 建草稿
-- =============================================================================
select tests.reserve('S1', 'buyer1') as run1 \gset
select public.create_order_draft(:'run1', '两箱十六安士杯，一箱平盖，还有吸管', 'zh',
  jsonb_build_array(
    jsonb_build_object('product_id', tests.uid('P1'), 'qty', 2, 'said', '两箱十六安士杯', 'confidence', 0.92),
    jsonb_build_object('product_id', tests.uid('P2'), 'qty', 'one', 'said', '一箱平盖', 'confidence', 0.9),
    jsonb_build_object('product_id', tests.uid('P7'), 'qty', 1, 'said', 'W4 的杯'),
    jsonb_build_object('product_id', 'not-a-uuid', 'qty', 1, 'said', '乱写的')),
  jsonb_build_array(jsonb_build_object('said', '还有吸管', 'reason', 'no product'), jsonb_build_object('said', '  ')),
  '{"model": "claude-opus-5-5"}') as cd1 \gset
select tests.logout();
select is(:'cd1'::jsonb ->> 'result', 'created', '建好了');
select is((:'cd1'::jsonb ->> 'item_count')::int, 2, '两样对得上（P1、P2）');
select is((:'cd1'::jsonb ->> 'unmatched_count')::int, 3, '不能下单的 W4、乱写的 id、AI 对不上的「吸管」放进 unmatched');
select :'cd1'::jsonb ->> 'draft_id' as d1 \gset
select is((select qty || '/' || confidence from public.order_draft_items where draft_id = :'d1' and product_id = tests.uid('P2')),
  '1/0.30', '数量不对的当 1，confidence 降到 0.3');
select is((select status from public.voice_order_runs where run_id = :'run1'), 'done', '这一次记成 done');
select is((select source::text || '/' || created_by from public.order_drafts where id = :'d1'),
  'app_voice/' || tests.uid('buyer1'), '来源 App 语音，记下是谁录的');
select is(tests.error_of(format('select public.create_order_draft(%L, %L)', :'run1', 'x')), 'RUN_NOT_RUNNING',
  '做过的不能再建一次');
select tests.reserve('S1', 'buyer1') as run_fail \gset
select ok(public.fail_voice_order_run(:'run_fail', 'STT_FAILED'), '失败：记下原因');
select ok(not public.fail_voice_order_run(:'run_fail', 'X'), '不是处理中的不改');
select is((select error_code from public.voice_order_runs where run_id = :'run_fail'), 'STT_FAILED', '失败原因');

-- =============================================================================
-- 老板看草稿、改、送出
-- =============================================================================
select tests.add_to_cart('S1', 'P4', 1); -- 老板原本购物车里有 W3 的杯
select tests.login_as(tests.uid('buyer1'));
select public.get_order_draft(:'d1') as g1 \gset
select is(jsonb_array_length(:'g1'::jsonb -> 'items'), 2, '老板看得到两行');
select is((:'g1'::jsonb -> 'items' -> 0 ->> 'unit_price_sen')::int, 8500, '有价钱（看得到价钱的批发商）');
select is((:'g1'::jsonb -> 'quote' ->> 'total_sen')::int, 21500, '草稿的报价：P1 x2 + P2 x1，满 RM150 免运费');
select is(:'g1'::jsonb ->> 'sender_phone', null, '老板看不到客服用的栏位');
select is((select count(*)::int from public.cart_items where shop_id = tests.uid('S1')), 1, '算报价不会动到购物车');
select is(jsonb_array_length(public.list_order_drafts(tests.uid('S1'))), 1, '首页：一张还没确认的语音草稿');
select tests.login_as(tests.uid('buyer2'));
select is(tests.error_of(format('select public.get_order_draft(%L)', :'d1')), 'DRAFT_NOT_FOUND', '别家店看不到');
select is(tests.error_of(format('select public.save_order_draft(%L, %L)', :'d1', '[]')), 'DRAFT_NOT_FOUND', '别家店改不到');
select is(tests.error_of(format('select public.list_order_drafts(%L)', tests.uid('S1'))), 'NOT_ALLOWED', '别家店的列表');

select tests.login_as(tests.uid('buyer1'));
select is(tests.error_of(format('select public.save_order_draft(%L, %L)', :'d1',
  jsonb_build_array(jsonb_build_object('product_id', tests.uid('P7'), 'qty', 1)))),
  'INVALID_PRODUCT:' || tests.uid('P7'), '不能换成不能下单的商品');
select is(tests.error_of(format('select public.save_order_draft(%L, %L)', :'d1',
  jsonb_build_array(jsonb_build_object('product_id', tests.uid('P1'), 'qty', 0)))), 'INVALID_QTY:0', '数量至少 1');
select is(tests.error_of(format('select public.save_order_draft(%L, %L)', :'d1',
  jsonb_build_array(jsonb_build_object('product_id', tests.uid('P1'), 'qty', 1.5)))), 'INVALID_QTY:1.5', '数量要整数');
select public.save_order_draft(:'d1', jsonb_build_array(
    jsonb_build_object('product_id', tests.uid('P1'), 'qty', 3, 'said', '两箱十六安士杯', 'confidence', 0.92),
    jsonb_build_object('product_id', tests.uid('P3'), 'qty', 5)),
  '[]') as s1 \gset
select is(
  (select string_agg((e ->> 'product_name') || ' x' || (e ->> 'qty'), ', ') from jsonb_array_elements(:'s1'::jsonb -> 'items') e),
  'W1 16oz 杯 x3, W2 16oz 杯 小包 x5', '改数量、换商品、删掉、加：整份换掉');
select is(jsonb_array_length(:'s1'::jsonb -> 'unmatched'), 0, '没听懂的处理完了');
select is((:'s1'::jsonb -> 'quote' ->> 'total_sen')::int, 25500 + 2400 + 1000, '新报价：W1 RM255 免运费，W2 RM24 + 运费 RM10');

select ok(tests.error_of(format('select public.submit_order_draft(%L, 100)', :'d1')) like 'PRICE_CHANGED:%',
  '总额对不上 → PRICE_CHANGED');
select is((select string_agg(product_id::text, ',') from public.cart_items where shop_id = tests.uid('S1')),
  tests.uid('P4')::text, '下单失败：原来的购物车不变');
select is((select status::text from public.order_drafts where id = :'d1'), 'pending_review', '草稿还在');
select public.submit_order_draft(:'d1', 28900, '语音下单') as sub1 \gset
select is((select count(*)::int from public.orders where checkout_id = (:'sub1'::jsonb ->> 'checkout_id')::uuid), 2,
  '照批发商拆成两张单');
select is((select string_agg(distinct source::text, ',') from public.orders
  where checkout_id = (:'sub1'::jsonb ->> 'checkout_id')::uuid), 'voice', '订单来源 voice');
select is((:'sub1'::jsonb ->> 'total_sen')::int, 28900, '回传总额');
select is((select string_agg(product_id::text || ':' || qty, ',') from public.cart_items where shop_id = tests.uid('S1')),
  tests.uid('P4')::text || ':1', '下单后原来购物车里的东西还在');
select is(:'sub1'::jsonb -> 'draft' ->> 'status', 'confirmed', '草稿变成已确认');
select is(:'sub1'::jsonb -> 'draft' -> 'quote', 'null'::jsonb, '确认了就不再算报价');
select is(tests.error_of(format('select public.submit_order_draft(%L, 28900)', :'d1')), 'DRAFT_NOT_PENDING:confirmed',
  '不能送两次');
select is(jsonb_array_length(public.list_order_drafts(tests.uid('S1'))), 0, '首页的草稿提醒没有了');

-- 不要了
select tests.logout();
select tests.reserve('S1', 'buyer1') as run2 \gset
select public.create_order_draft(:'run2', '一箱盖', 'zh',
  jsonb_build_array(jsonb_build_object('product_id', tests.uid('P2'), 'qty', 1))) ->> 'draft_id' as d2 \gset
select tests.reserve('S1', 'buyer1') as run3 \gset
select public.create_order_draft(:'run3', '嗯', 'zh') ->> 'draft_id' as d_empty \gset
select tests.login_as(tests.uid('buyer1'));
select is(tests.error_of(format('select public.submit_order_draft(%L, 0)', :'d_empty')), 'DRAFT_EMPTY', '空的草稿不能送');
select is(public.reject_order_draft(:'d2', '说错了') ->> 'status', 'rejected', '老板按「不要了」');
select is((select count(*)::int from public.notifications where event_type = 'whatsapp_reply'), 0,
  'App 语音的草稿不会回 WhatsApp');

-- =============================================================================
-- WhatsApp 下单
-- =============================================================================
select tests.logout();
update public.wholesalers set whatsapp_phone = '60111000012' where id = tests.uid('W2');
select public.record_whatsapp_message('+60 111-000 002', 'text', '老板，明天要 5 包 W2 的杯', null, 'wamid.T1',
  '{"id": "wamid.T1"}') ->> 'id' as m1 \gset
select public.reserve_whatsapp_order(:'m1', gen_random_uuid()) as w1 \gset
select is(:'w1'::jsonb ->> 'result', 'ok', '店的号码发文字 → 占位');
select is(:'w1'::jsonb ->> 'message_type', 'text', '回传消息类型和内容');
select is((select source::text from public.voice_order_runs where run_id = (:'w1'::jsonb ->> 'run_id')::uuid),
  'whatsapp_text', '来源 whatsapp_text');

select public.record_whatsapp_message('60199999999', 'text', 'hi', null, 'wamid.U1', '{}') ->> 'id' as mu1 \gset
select public.record_whatsapp_message('60199999999', 'text', 'hello?', null, 'wamid.U2', '{}') ->> 'id' as mu2 \gset
update public.whatsapp_messages set created_at = now() + interval '1 minute' where id = :'mu2';
select is(public.reserve_whatsapp_order(:'mu1', gen_random_uuid()), '{"reply": true, "result": "unknown_sender"}'::jsonb,
  '不认识的号码：回「请先注册」');
select is(public.reserve_whatsapp_order(:'mu2', gen_random_uuid()) ->> 'reply', 'false', '24 小时内第二条不再回（不会一直回）');
select is(public.reserve_whatsapp_order(
  (public.record_whatsapp_message('60111000012', 'text', 'ok', null, 'wamid.W1', '{}') ->> 'id')::uuid, gen_random_uuid()) ->> 'result',
  'wholesaler', '批发商的号码：不是下单');
select is(public.reserve_whatsapp_order(
  (public.record_whatsapp_message('60111000002', 'image', null, 'media-1', 'wamid.I1', '{}') ->> 'id')::uuid, gen_random_uuid()) ->> 'result',
  'unsupported', '照片：不做草稿');

select public.create_order_draft((:'w1'::jsonb ->> 'run_id')::uuid, '老板，明天要 5 包 W2 的杯', 'zh',
  jsonb_build_array(jsonb_build_object('product_id', tests.uid('P3'), 'qty', 5, 'said', '5 包 W2 的杯', 'confidence', 0.8)))
  ->> 'draft_id' as dw \gset
select is((select sender_phone || '/' || whatsapp_message_id from public.order_drafts where id = :'dw'),
  '60111000002/' || :'m1', '记下发信人和那条消息');
select isnt((select whatsapp_opt_in_at from public.shops where id = tests.uid('S2')), null,
  '老板自己发 WhatsApp 来下单：当成同意用 WhatsApp 收通知');

select tests.login_as(tests.uid('buyer2'));
select is(public.get_order_draft(:'dw') ->> 'source', 'whatsapp_text', '老板看得到自己 WhatsApp 的草稿');
select is(tests.error_of(format('select public.submit_order_draft(%L, 3400)', :'dw')), 'NOT_ALLOWED',
  'WhatsApp 的草稿由客服送出');
select is(jsonb_array_length(public.list_order_drafts(tests.uid('S2'))), 0, '首页只提醒 App 语音的草稿');

select tests.login_as(tests.uid('admin'));
select public.admin_list_order_drafts() as q1 \gset
select is(jsonb_array_length(:'q1'::jsonb), 1, '客服的 WhatsApp 订单：一张');
select is(:'q1'::jsonb -> 0 ->> 'whatsapp_window_open', 'true', '24 小时窗口还开着');
select is(jsonb_array_length(public.admin_list_order_drafts(null, null)), 4, '全部（App + WhatsApp、全部状态）');
select is(public.get_order_draft(:'dw') ->> 'sender_phone', '60111000002', '客服看得到发信人');
select public.save_order_draft(:'dw', jsonb_build_array(jsonb_build_object('product_id', tests.uid('P3'), 'qty', 6))) as sw \gset
select is((select actor_id from public.audit_logs where action = 'admin_save_order_draft' order by id desc limit 1),
  tests.uid('admin'), '客服改草稿：操作记录');
select is(tests.error_of(format('select public.submit_order_draft(%L)', :'dw')), 'EXPECTED_TOTAL_REQUIRED',
  '客服一定要给看到的总额');
select public.submit_order_draft(:'dw', (:'sw'::jsonb -> 'quote' ->> 'total_sen')::int) as subw \gset
select is((select string_agg(source::text, ',') from public.orders
  where checkout_id = (:'subw'::jsonb ->> 'checkout_id')::uuid), 'whatsapp', '订单来源 whatsapp');
select is((select acting_for_shop_id from public.audit_logs where action = 'admin_submit_order_draft' order by id desc limit 1),
  tests.uid('S2'), '操作记录：代 S2');
select ok((select payload ->> 'text' from public.notifications where event_type = 'whatsapp_reply' and shop_id = tests.uid('S2'))
  like '已经帮您下单：' || (:'subw'::jsonb ->> 'order_nos') || '%', '排了一条 WhatsApp 回复（店的语言、订单号）');

-- 不处理的 WhatsApp 草稿：回原因
select tests.logout();
update public.shops set locale = 'en' where id = tests.uid('S2');
select public.record_whatsapp_message('60111000002', 'audio', null, 'media-2', 'wamid.A1', '{}') ->> 'id' as m2 \gset
select public.reserve_whatsapp_order(:'m2', gen_random_uuid()) as w2 \gset
select is(:'w2'::jsonb ->> 'media_id', 'media-2', '语音：回传 media id（Edge Function 去下载）');
select public.create_order_draft((:'w2'::jsonb ->> 'run_id')::uuid, null, null, '[]', '[]', '{"error_code": "STT_FAILED"}',
  tests.uid('S2') || '/' || gen_random_uuid() || '.ogg') ->> 'draft_id' as dw2 \gset
select is((select media_path like 'voice-orders/' || tests.uid('S2') || '/%' from public.whatsapp_messages where id = :'m2'),
  true, '语音存了一份（路径记在消息上）');
select tests.login_as(tests.uid('admin'));
select is(public.get_order_draft(:'dw2') ->> 'error_code', 'STT_FAILED', 'AI 失败的也放进队列，客服自己听');
select is(public.reject_order_draft(:'dw2', 'we do not sell straws') ->> 'status', 'rejected', '客服不处理');
select is((select payload ->> 'text' from public.notifications where event_type = 'whatsapp_reply'
  and payload ->> 'draft_id' = :'dw2'), 'Sorry, we could not process this order: we do not sell straws. Just reply to this message if you have questions.',
  '回原因（英文店）');

-- =============================================================================
-- 通知渠道
-- =============================================================================
select tests.logout();
select is(public._notification_route(null, tests.uid('S2'), null, 'whatsapp_reply'),
  '{"locale": "en", "channel": "whatsapp", "push_targets": [], "whatsapp_phone": "60111000002"}'::jsonb,
  'WhatsApp 回复：窗口内用 WhatsApp 回那个号码');
update public.whatsapp_messages set created_at = now() - interval '25 hours' where shop_id = tests.uid('S2');
select is(public._notification_route(null, tests.uid('S2'), null, 'whatsapp_reply') ->> 'channel', null,
  '窗口过了：不发（不能发普通文字）');
select tests.login_as(tests.uid('admin'));
select is(public.get_order_draft(:'dw2') ->> 'whatsapp_window_open', 'false', '客服看得到窗口关了（要打电话）');
select tests.logout();

update public.shops set notify_channel = 'whatsapp', whatsapp_opt_in_at = now() where id = tests.uid('S1');
select is(public._notification_route(null, tests.uid('S1'), null, 'order_status_changed') ->> 'channel', 'whatsapp',
  '买家没装 App：WhatsApp');
insert into public.device_tokens (user_id, fcm_token, platform, kind) values (tests.uid('buyer1'), 'tok-buyer1', 'android', 'token');
select is(public._notification_route(null, tests.uid('S1'), null, 'order_status_changed') ->> 'channel', 'push',
  '买家有 App：一定推送（就算设成 whatsapp）');
update public.wholesalers set notify_channel = 'whatsapp', whatsapp_opt_in_at = now(), whatsapp_phone = '60111000011'
where id = tests.uid('W1');
insert into public.device_tokens (user_id, fcm_token, platform, kind) values (tests.uid('seller1'), 'tok-seller1', 'android', 'token');
select is(public._notification_route(null, null, tests.uid('W1'), 'order_new') ->> 'channel', 'whatsapp',
  '批发商照旧：客服可以替他设成 WhatsApp');

-- 不通知自己：老板按「收到了」
select tests.order_of('S1', 'W1') as ow1 \gset
select tests.login_as(tests.uid('seller1'));
select public.confirm_order(:'ow1');
select tests.logout();
select is((select count(*)::int from public.notifications where shop_id = tests.uid('S1')
  and event_type = 'order_status_changed' and payload ->> 'order_id' = :'ow1'), 1, '批发商确认：通知老板');
select tests.login_as(tests.uid('buyer1'));
select public.set_order_status(:'ow1', 'delivered');
select tests.logout();
select is((select count(*)::int from public.notifications where shop_id = tests.uid('S1')
  and event_type = 'order_status_changed' and payload ->> 'order_id' = :'ow1'), 1, '老板自己按「收到了」：不通知自己');

-- =============================================================================
-- Storage
-- =============================================================================
select tests.logout();
select to_regnamespace('storage') is null as fake_storage \gset
\if :fake_storage
select is(public._setup_voice_storage(), false, '没有 storage schema：跳过');
create schema storage;
create table storage.buckets (
  id text primary key, name text not null, public boolean not null default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id),
  name text not null, owner uuid default auth.uid()
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language plpgsql as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end;
$$;
grant usage on schema storage to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;
select ok(public._setup_voice_storage(), '有 storage：建 bucket 和规则（可以重复跑）');
select is((select public || ':' || file_size_limit from storage.buckets where id = 'voice-orders'), 'false:3145728',
  '录音私人，3 MB');
select tests.login_as(tests.uid('buyer1'));
select lives_ok(format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'voice-orders', tests.vpath('S1')),
  '老板上传录音到自己店的文件夹');
select throws_ok(format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'voice-orders', tests.vpath('S2')),
  '42501', null, '不能上传到别家店的文件夹');
select tests.login_as(tests.uid('buyer2'));
select is((select count(*)::int from storage.objects where bucket_id = 'voice-orders'), 0, '别家店听不到');
\else
select ok(public._setup_voice_storage(), '有 storage：建 bucket 和规则（可以重复跑）');
select is((select public || ':' || file_size_limit from storage.buckets where id = 'voice-orders'), 'false:3145728',
  '录音私人，3 MB');
select skip('真的 Storage：上传 / 读取的规则要经过 Storage API，在这里不测', 4);
\endif

select * from finish();
rollback;
