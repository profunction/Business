// 第六步：订单草稿（本机数据库真实返回的 JSON）、送出去的请求、WAV 打包
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

/// 记下送出去的请求；回传 reply(path, body)
(WholesaleApi, List<(String, Object?)>) mockApi(Object? Function(String path, Object? body) reply, {int status = 200}) {
  final sent = <(String, Object?)>[];
  final api = AdminApi(
    SupabaseClient(
      'http://sb.test',
      'test-key',
      httpClient: MockClient((req) async {
        final body = req.body.isEmpty ? null : jsonDecode(req.body);
        sent.add((req.url.path, body));
        return http.Response(
          jsonEncode(reply(req.url.path, body)),
          status,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      }),
    ),
  );
  return (api, sent);
}

void main() {
  test('老板看到的语音草稿：每一行、AI 有多确定、没听懂的、报价', () {
    final d = OrderDraft.fromJson(asJson(fixture('order_draft')));
    expect(d.source, DraftSource.appVoice);
    expect(d.isPending, isTrue);
    expect(d.transcript, contains('十六安士杯'));
    expect(d.items.map((i) => '${i.productName} x${i.qty}'), ['16安士 PP杯 95口径 x2', '95 平盖 x2', '黑色吸管 6mm 独立包 x1']);
    expect(d.items.first.unitPriceSen, 8500);
    expect(d.items.first.isUnsure, isFalse);
    expect(d.items.last.isUnsure, isTrue);
    expect(d.unmatched.single.isNote, isTrue);
    expect(d.senderPhone, isNull, reason: '老板看不到客服用的栏位');
    final q = d.quote!;
    expect(q.canPlace, isFalse, reason: '吸管未到起订量（2 包）');
    expect(q.groups.single.lines.where((l) => l.problem == CartProblem.belowMinQty), hasLength(1));
    expect(d.items.last.toSaveJson(), {
      'product_id': d.items.last.productId,
      'qty': 1,
      'said': '一包黑色吸管',
      'confidence': 0.62,
    });
  });

  test('首页的草稿列表、客服的 WhatsApp 订单', () {
    final mine = asJsonList(fixture('order_drafts')).map(DraftSummary.fromJson).toList();
    expect(mine.single.itemCount, 3);
    final queue = asJsonList(fixture('admin_order_drafts')).map(DraftSummary.fromJson).toList();
    expect(queue.map((q) => q.source), [DraftSource.whatsappText, DraftSource.whatsappVoice]);
    expect(queue.first.shopName, 'Kedai Runcit Siti');
    expect(queue.first.whatsappWindowOpen, isTrue);
    expect(queue.last.errorCode, 'STT_NOT_CONFIGURED');
    final d = OrderDraft.fromJson(asJson(fixture('admin_order_draft')));
    expect(d.source.isWhatsapp, isTrue);
    expect(d.senderPhone, '60120000004');
    expect(d.items.single.qty, 3);
    expect(d.quote!.totalSen, greaterThan(0));
  });

  test('改草稿 / 送出 / 不要：参数名照 SQL', () async {
    final draft = asJson(fixture('order_draft'));
    final (api, sent) = mockApi(
      (path, body) => path.endsWith('submit_order_draft')
          ? {'checkout_id': 'c1', 'order_nos': 'JHB1, JHB2', 'total_sen': 22000, 'draft': draft}
          : draft,
    );
    final d = OrderDraft.fromJson(draft);
    await api.saveOrderDraft(d.id, [d.items.first.copyWith(qty: 5)], unmatched: const []);
    expect(sent.last.$1, '/rest/v1/rpc/save_order_draft');
    expect(sent.last.$2, {
      'p_draft_id': d.id,
      'p_items': [
        {'product_id': d.items.first.productId, 'qty': 5, 'said': '两箱十六安士杯', 'confidence': 0.93},
      ],
      'p_unmatched': <Object>[],
    });
    final r = await api.submitOrderDraft(d.id, expectedTotalSen: 22000);
    expect((r.checkoutId, r.orderNos, r.totalSen), ('c1', 'JHB1, JHB2', 22000));
    expect(sent.last.$2, {'p_draft_id': d.id, 'p_expected_total_sen': 22000, 'p_note': null});
    await api.rejectOrderDraft(d.id, reason: '说错了');
    expect(sent.last.$2, {'p_draft_id': d.id, 'p_reason': '说错了'});
    await (api as AdminApi).listOrderDraftQueue();
    expect(sent.last.$2, {'p_status': 'pending_review', 'p_channel': 'whatsapp'});
  });

  test('语音下单：叫 voice-order；用量满了 → TOO_MANY_VOICE_ORDERS（detail = 几秒）', () async {
    final (api, sent) = mockApi((path, body) => {'draft': fixture('order_draft')});
    final d = await api.createVoiceDraft('shop-1', 'shop-1/a.wav');
    expect(d.items, hasLength(3));
    expect(sent.single.$1, '/functions/v1/voice-order');
    expect(sent.single.$2, {'shop_id': 'shop-1', 'audio_path': 'shop-1/a.wav'});

    final (busy, _) = mockApi((path, body) => {'error': 'TOO_MANY_VOICE_ORDERS', 'retry_after': 42}, status: 429);
    await expectLater(
      busy.createVoiceDraft('shop-1', 'shop-1/a.wav'),
      throwsA(
        isA<AppError>().having((e) => e.code, 'code', 'TOO_MANY_VOICE_ORDERS').having((e) => e.detail, 'detail', '42'),
      ),
    );
    final (nostt, _) = mockApi((path, body) => {'error': 'STT_NOT_CONFIGURED'}, status: 503);
    await expectLater(
      nostt.createVoiceDraft('shop-1', 'shop-1/a.wav'),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'STT_NOT_CONFIGURED')),
    );
  });

  test('PCM 包成 WAV：44 字节的头、长度、16 kHz 单声道', () {
    final pcm = Uint8List.fromList(List.generate(32001, (i) => i % 256));
    final wav = pcm16ToWav(pcm);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final b = ByteData.sublistView(wav);
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint32(40, Endian.little), 32000, reason: '单数字节去掉最后一个');
    expect(wav.length, 44 + 32000);
    expect(pcm16Duration(32000), const Duration(seconds: 1));
  });
}
