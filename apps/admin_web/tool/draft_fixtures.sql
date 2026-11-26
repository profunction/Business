-- 导出第六步（语音 / WhatsApp 订单草稿）的示范数据：packages/core/test/fixtures/order_draft*.json（手机 App）
-- 和 admin_order_draft*.json（客服后台）。由 tool/export_draft_fixtures.sh 在「全部迁移 + seed.sql」的本机数据库上跑：
-- 用服务器身份照 Edge Function 的步骤建草稿（reserve → create_order_draft），再用老板 / 客服的身份读出来。
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
\set QUIET 1

-- ---------- 账号 ----------
insert into auth.users (id, phone, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', '60120000001', '{"locale": "zh"}'),
  ('00000000-0000-4000-c000-000000000003', '60120000003', '{"locale": "zh"}');
update public.profiles set role = 'admin', full_name = '客服 Mei' where id = '00000000-0000-4000-c000-000000000003';

-- ---------- 阿明：App 语音草稿（服务器身份，跟 voice-order 一样的步骤） ----------
select (public.reserve_voice_order_run('00000000-0000-4000-b000-000000000001', '11111111-1111-4111-8111-111111111111',
  '22222222-0000-4000-8000-000000000001', 'app_voice',
  '00000000-0000-4000-b000-000000000001/33333333-0000-4000-8000-000000000001.wav') ->> 'result') = 'ok';
select public.create_order_draft('22222222-0000-4000-8000-000000000001',
  '两箱十六安士杯，两箱九五平盖，还有一包黑色吸管，明天早上十点前送', 'zh',
  (select jsonb_agg(jsonb_build_object('product_id', p.id, 'qty', v.qty, 'said', v.said, 'confidence', v.conf) order by v.ord)
   from (values (1, '16安士 PP杯 95口径', 2, '两箱十六安士杯', 0.93), (2, '95 平盖', 2, '两箱九五平盖', 0.9),
                (3, '黑色吸管 6mm 独立包', 1, '一包黑色吸管', 0.62)) as v(ord, name, qty, said, conf)
   join public.products p on p.name = v.name),
  '[{"said": "明天早上十点前送", "reason": "note"}]', '{"model": "claude-opus-5-5"}') is not null;

-- ---------- Siti：WhatsApp 文字（马来文），阿明：WhatsApp 语音（转文字没设定 → 空的，客服自己听） ----------
select public.record_whatsapp_message('60120000004', 'text', 'Salam boss, nak 3 kotak bekas 650ml esok pagi', null,
  'wamid.DEMO1', '{"id": "wamid.DEMO1"}') is not null;
select (public.reserve_whatsapp_order(m.id, '22222222-0000-4000-8000-000000000002') ->> 'result') = 'ok'
from public.whatsapp_messages m where m.wa_message_id = 'wamid.DEMO1';
select public.create_order_draft('22222222-0000-4000-8000-000000000002',
  'Salam boss, nak 3 kotak bekas 650ml esok pagi', 'ms',
  (select jsonb_agg(jsonb_build_object('product_id', p.id, 'qty', 3, 'said', 'nak 3 kotak bekas 650ml', 'confidence', 0.84))
   from public.products p where p.name = '650ml 长方饭盒连盖'),
  '[{"said": "esok pagi", "reason": "note"}]', '{"model": "claude-opus-5-5"}') is not null;
select public.record_whatsapp_message('60120000001', 'audio', null, 'MEDIA_DEMO', 'wamid.DEMO2', '{"id": "wamid.DEMO2"}') is not null;
select (public.reserve_whatsapp_order(m.id, '22222222-0000-4000-8000-000000000003') ->> 'result') = 'ok'
from public.whatsapp_messages m where m.wa_message_id = 'wamid.DEMO2';
select public.create_order_draft('22222222-0000-4000-8000-000000000003', null, null, '[]', '[]',
  '{"error_code": "STT_NOT_CONFIGURED"}') is not null;

-- ---------- 老板（阿明）看 ----------
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', false) is not null;
select set_config('role', 'authenticated', false) is not null;
\o :outdir/order_draft.json
select jsonb_pretty(public.get_order_draft(d.id)) from public.order_drafts d where d.run_id = '22222222-0000-4000-8000-000000000001';
\o :outdir/order_drafts.json
select jsonb_pretty(public.list_order_drafts('00000000-0000-4000-b000-000000000001'));
\o

-- ---------- 客服看 ----------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-c000-000000000003", "role": "authenticated"}', false) is not null;
\o :outdir/admin_order_drafts.json
select jsonb_pretty(public.admin_list_order_drafts());
\o :outdir/admin_order_draft.json
select jsonb_pretty(public.get_order_draft(d.id)) from public.order_drafts d where d.run_id = '22222222-0000-4000-8000-000000000002';
\o :outdir/admin_order_draft_voice.json
select jsonb_pretty(public.get_order_draft(d.id)) from public.order_drafts d where d.run_id = '22222222-0000-4000-8000-000000000003';
\o :outdir/admin_draft_offers.json
select jsonb_pretty(jsonb_agg(to_jsonb(t))) from public.get_offers('00000000-0000-4000-b000-000000000002') t;
\o
