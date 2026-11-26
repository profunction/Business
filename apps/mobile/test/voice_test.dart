// 第六步：语音下单。假的录音（不用真的麦克风）+ 示范模式（草稿是本机数据库导出的 order_draft.json）。
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/app/providers.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/demo/demo_session.dart';
import 'package:jb_wholesale/features/voice/mic_button.dart';
import 'package:jb_wholesale/features/voice/voice_recorder.dart';
import 'package:jb_wholesale/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRecorder implements VoiceRecorder {
  bool permission = true;
  Duration length = const Duration(seconds: 4);
  final events = <String>[];

  @override
  Future<bool> ensurePermission() async {
    events.add('permission');
    return permission;
  }

  @override
  Future<void> start() async => events.add('start');

  @override
  Future<RecordedAudio?> stop() async {
    events.add('stop');
    return RecordedAudio(Uint8List(1000), length);
  }

  @override
  Future<void> cancel() async => events.add('cancel');
}

Future<(DemoApi, FakeRecorder)> start(WidgetTester tester, {String locale = 'zh'}) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final api = DemoApi();
  final rec = FakeRecorder();
  final session = DemoSession(api: api, prefs: prefs);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => session),
        voiceRecorderProvider.overrideWithValue(rec),
      ],
      child: WholesaleApp(session: session),
    ),
  );
  await tester.pumpAndSettle();
  return (api, rec);
}

FilledButton placeButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(of: find.byKey(const Key('voice-place')), matching: find.byType(FilledButton)),
);

/// 首页比屏幕长：先滚到看得见（ListView 只建看得到的）
Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// 按住麦克风 hold 那么久再放开
Future<void> holdMic(WidgetTester tester, {Duration hold = const Duration(seconds: 2)}) async {
  final mic = find.byKey(const Key('voice-mic')).first;
  await tester.ensureVisible(mic);
  await tester.pumpAndSettle();
  final g = await tester.startGesture(tester.getCenter(mic));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(hold);
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页：按住说话 → 录音中 → 放开 → AI 做好草稿 → 确认语音订单页', (tester) async {
    final (api, rec) = await start(tester);
    expect(find.text('按住说话下单'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('voice-pending')));
    expect(find.text('你有 1 张语音订单还没确认'), findsOneWidget, reason: '上次录完还没确认的草稿');

    final mic = find.byKey(const Key('voice-mic'));
    await tester.ensureVisible(mic);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('正在录音'), findsOneWidget);
    expect(rec.events, ['permission', 'start']);
    await g.up();
    await tester.pump();
    expect(find.text('AI 正在听…'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(rec.events.last, 'stop');
    expect(api.calls, contains('voice 1000'));
    expect(find.text('确认语音订单'), findsOneWidget);
    expect(find.byKey(const Key('voice-transcript')), findsOneWidget);
    expect(find.textContaining('两箱十六安士杯'), findsWidgets);
    expect(find.text('16安士 PP杯 95口径'), findsOneWidget);
    await scrollTo(tester, find.text('AI 不太确定，请看一下对不对'));
    expect(find.text('AI 不太确定，请看一下对不对'), findsOneWidget, reason: '吸管那行 confidence 0.62');
    // AI 说「明天早上十点前送」是备注：先放进备注栏
    await scrollTo(tester, find.byKey(const Key('voice-note')));
    expect(tester.widget<TextField>(find.byKey(const Key('voice-note'))).controller!.text, '明天早上十点前送');
    // 吸管未到起订量：不能下单
    expect(placeButton(tester).onPressed, isNull);
  });

  testWidgets('改草稿：加数量、删掉、换一样，然后确认下单（不会自己下单）', (tester) async {
    final (api, _) = await start(tester);
    await holdMic(tester);
    expect(api.calls.where((c) => c.startsWith('submitDraft')), isEmpty, reason: '没按确认就不下单');

    // 吸管加到 2 包（起订量）
    await scrollTo(tester, find.byKey(const Key('voice-qty-2')));
    await tapAndSettle(
      tester,
      find.descendant(of: find.byKey(const Key('voice-qty-2')), matching: find.byIcon(Icons.add)),
    );
    expect(api.calls.last, contains('黑色吸管 6mm 独立包x2'));
    expect(placeButton(tester).onPressed, isNotNull);

    // 删掉平盖
    await tester.scrollUntilVisible(
      find.byKey(const Key('voice-remove-1')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapAndSettle(tester, find.byKey(const Key('voice-remove-1')));
    expect(api.calls.last, isNot(contains('95 平盖')));
    expect(find.text('95 平盖'), findsNothing);

    // 换一样：第一行换成搜到的商品
    await tester.scrollUntilVisible(
      find.byKey(const Key('voice-swap-0')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapAndSettle(tester, find.byKey(const Key('voice-swap-0')));
    expect(find.text('选商品'), findsOneWidget);
    final first = find.byWidgetPredicate((w) => w is ListTile && (w.key.toString()).contains('voice-pick-')).first;
    final pickedName = ((tester.widget<ListTile>(first).title! as Text).data)!;
    await tapAndSettle(tester, first);
    expect(api.calls.last, contains('${pickedName}x2'), reason: '换了商品，数量照旧');

    final place = find.byKey(const Key('voice-place'));
    final label = ((placeButton(tester).child! as Text).data)!;
    expect(label, startsWith('确认下单 RM'));
    await tapAndSettle(tester, place);
    expect(api.calls.last, startsWith('submitDraft '));
    expect(api.calls.last, endsWith('明天早上十点前送'), reason: '备注一起送');
    expect(find.text('下单成功！'), findsOneWidget);
  });

  testWidgets('首页的草稿提醒 → 打开；加一样找不到；不要了 → 回首页（英文）', (tester) async {
    final (api, _) = await start(tester, locale: 'en');
    await scrollTo(tester, find.byKey(const Key('voice-pending')));
    await tapAndSettle(tester, find.byKey(const Key('voice-pending')));
    expect(find.text('Check your voice order'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('voice-add')));
    await tapAndSettle(tester, find.byKey(const Key('voice-add')));
    await tester.enterText(find.byKey(const Key('voice-pick-search')), 'zzzz-not-there');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Nothing found. Try another name'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('voice-pick-search')))).pop(); // 关掉
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('saveDraft')), isEmpty, reason: '没选就不改');

    await tapAndSettle(tester, find.byKey(const Key('voice-discard')));
    await tapAndSettle(tester, find.byKey(const Key('voice-discard-yes')));
    expect(api.calls.last, 'rejectDraft');
    expect(find.text('Hold to order by voice'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-pending'), skipOffstage: false), findsNothing);
  });

  testWidgets('太短不送；没麦克风权限；AI 听不到声音 → 显示原因（马来文）', (tester) async {
    final (api, rec) = await start(tester, locale: 'ms');
    rec.length = const Duration(milliseconds: 300);
    await holdMic(tester, hold: const Duration(milliseconds: 100));
    expect(find.text('Terlalu pendek. Tahan butang dan sebut sekali lagi'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('voice')), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    rec.permission = false;
    await holdMic(tester);
    expect(find.text('Sila benarkan mikrofon untuk pesan dengan suara'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    rec
      ..permission = true
      ..length = const Duration(seconds: 3);
    api.failNextVoiceWith = 'NO_SPEECH';
    await holdMic(tester);
    expect(find.textContaining('Kami tidak dapat mendengar'), findsOneWidget);
    expect(find.text('Semak pesanan suara'), findsNothing, reason: '没有草稿就不打开');
  });

  testWidgets('购物车也有麦克风（小的）', (tester) async {
    await start(tester);
    await scrollTo(tester, find.byKey(const Key('go-shop')));
    await tapAndSettle(tester, find.byKey(const Key('go-shop')));
    await tapAndSettle(tester, find.byKey(const Key('cart-button')));
    expect(find.byType(MicButton), findsOneWidget);
    expect(tester.widget<MicButton>(find.byType(MicButton)).compact, isTrue);
  });
}
