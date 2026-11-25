// 推送通知：点通知打开哪一页、什么时候登记、什么时候问权限。用假的 PushService（不连 Firebase）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jb_wholesale/app/providers.dart';
import 'package:jb_wholesale/app/router.dart';
import 'package:jb_wholesale/app/session.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/demo/demo_session.dart';
import 'package:jb_wholesale/features/seller/seller_home_page.dart';
import 'package:jb_wholesale/main.dart';
import 'package:jb_wholesale/push/push_config.dart';
import 'package:jb_wholesale/push/push_routes.dart';
import 'package:jb_wholesale/push/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePush implements PushService {
  final tapController = StreamController<Map<String, String>>();
  final calls = <String>[];
  PushPermission status = PushPermission.notDetermined;
  PushPermission answer = PushPermission.denied;

  @override
  bool get isEnabled => true;

  @override
  Stream<Map<String, String>> get taps => tapController.stream;

  @override
  Future<void> registerDevice({String? localeCode}) async => calls.add('register $localeCode');

  @override
  Future<void> unregisterDevice() async => calls.add('unregister');

  @override
  Future<void> setLocale(String localeCode) async => calls.add('locale $localeCode');

  @override
  Future<PushPermission> permissionStatus() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    calls.add('ask');
    return status = answer;
  }
}

class Started {
  Started(this.tester, this.api, this.push, this.session);

  final WidgetTester tester;
  final DemoApi api;
  final FakePush push;
  final SessionController session;

  GoRouter get router => tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig! as GoRouter;

  String get location => currentLocation(router).toString();

  Future<void> tap(Map<String, String> data) async {
    push.tapController.add(data);
    await settle(tester);
  }
}

/// 换页是非同步的，示范资料也要等 150ms：多 pump 几次
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }
}

Future<Started> start(
  WidgetTester tester, {
  bool seller = false,
  Map<String, Object> prefs = const {},
  List<Map<String, String>> tapsBeforeStart = const [],
  PushPermission status = PushPermission.notDetermined,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'locale': 'zh', ...prefs});
  final p = await SharedPreferences.getInstance();
  final api = DemoApi(seller: seller);
  final push = FakePush()..status = status;
  tapsBeforeStart.forEach(push.tapController.add);
  final session = DemoSession(api: api, prefs: p, push: push);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => session),
        pushServiceProvider.overrideWithValue(push),
      ],
      child: WholesaleApp(session: session, push: push),
    ),
  );
  await settle(tester);
  return Started(tester, api, push, session);
}

const buyerOrderId = '16a949f8-2a00-4b39-9145-93d57a303400'; // order_detail_confirmed 样本
const sellerOrderId = '1cf81f7b-9e34-42dd-9f8e-fe096bcf807c'; // seller_order_detail 样本

void main() {
  group('点通知打开哪一页', () {
    test('批发商', () {
      expect(
        pushRoute({'type': 'order_new', 'order_id': sellerOrderId}, isSeller: true),
        '/seller/orders/$sellerOrderId',
      );
      expect(pushRoute({'type': 'order_new'}, isSeller: true), '/seller/orders?tab=pending');
      expect(
        pushRoute({'type': 'order_cancelled', 'order_id': sellerOrderId}, isSeller: true),
        '/seller/orders/$sellerOrderId',
      );
      expect(
        pushRoute({'type': 'daily_summary', 'date': '2026-11-26'}, isSeller: true),
        '/seller/summary?date=2026-11-26',
      );
      expect(pushRoute({'type': 'daily_summary', 'date': 'x/../y'}, isSeller: true), '/seller/summary');
    });

    test('买家', () {
      expect(
        pushRoute({'type': 'order_status_changed', 'order_id': buyerOrderId}, isSeller: false),
        '/orders/$buyerOrderId',
      );
      expect(
        pushRoute({'type': 'order_cancelled', 'order_id': buyerOrderId}, isSeller: false),
        '/orders/$buyerOrderId',
      );
      expect(pushRoute({'type': 'order_new', 'order_id': buyerOrderId}, isSeller: false), isNull);
      expect(pushRoute({'type': 'daily_summary'}, isSeller: false), isNull);
    });

    test('不用跳页：客服提醒、不认识的、奇怪的 order_id', () {
      expect(pushRoute({'type': 'order_unconfirmed', 'order_id': sellerOrderId}, isSeller: true), isNull);
      expect(pushRoute({'type': 'something_else'}, isSeller: true), isNull);
      expect(pushRoute({'type': 'order_status_changed', 'order_id': '../settings'}, isSeller: false), isNull);
      expect(pushRoute(const {}, isSeller: false), isNull);
    });
  });

  group('Firebase 设定', () {
    const full = (
      apiKey: 'k',
      appIdAndroid: '1:1:android:1',
      appIdIos: '1:1:ios:1',
      messagingSenderId: '1',
      projectId: 'p',
      iosBundleId: 'my.jbwholesale.app',
    );

    PushSetup? setup(TargetPlatform p, {bool web = false, bool complete = true, bool native = false}) =>
        PushConfig.setupFor(
          p,
          isWeb: web,
          apiKey: complete ? full.apiKey : '',
          appIdAndroid: full.appIdAndroid,
          appIdIos: full.appIdIos,
          messagingSenderId: full.messagingSenderId,
          projectId: full.projectId,
          iosBundleId: full.iosBundleId,
          useNativeConfig: native,
        );

    test('dart-define 齐全 → 用那些值', () {
      final a = setup(TargetPlatform.android)!;
      expect(a.options!.appId, full.appIdAndroid);
      expect(a.options!.iosBundleId, isNull);
      expect(a.platformCode, 'android');
      final i = setup(TargetPlatform.iOS)!;
      expect(i.options!.appId, full.appIdIos);
      expect(i.options!.iosBundleId, full.iosBundleId);
      expect(i.platformCode, 'ios');
    });

    test('网页版、桌面版永远不启用；没设定就不启用；FIREBASE_NATIVE_CONFIG 用原生设定档', () {
      expect(setup(TargetPlatform.android, web: true), isNull);
      expect(setup(TargetPlatform.android, web: true, native: true), isNull);
      expect(setup(TargetPlatform.macOS), isNull);
      expect(setup(TargetPlatform.android, complete: false), isNull);
      final n = setup(TargetPlatform.android, complete: false, native: true)!;
      expect(n.options, isNull);
      expect(PushConfig.current, isNull, reason: '测试没有传 dart-define');
    });
  });

  testWidgets('登录后登记推送；登出前先删掉', (tester) async {
    final s = await start(tester);
    expect(s.push.calls, contains('register zh'));
    unawaited(s.session.signOut());
    await settle(tester);
    expect(s.push.calls.last, 'unregister');
    expect(find.text('用手机号登录'), findsOneWidget);
  });

  testWidgets('买家点「订单有更新」：打开那张订单，按返回回到首页', (tester) async {
    final s = await start(tester);
    await s.tap({'type': 'order_status_changed', 'order_id': buyerOrderId, 'order_no': 'JHB261125-00004'});
    expect(s.location, '/orders/$buyerOrderId');
    expect(find.text('缺货（不算钱）'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(s.location, '/home');
    expect(find.text('跟上次一样'), findsOneWidget);
  });

  testWidgets('App 被通知叫醒：等读完登录资料再打开那张订单', (tester) async {
    final s = await start(
      tester,
      tapsBeforeStart: [
        {'type': 'order_cancelled', 'order_id': buyerOrderId},
      ],
    );
    expect(s.location, '/orders/$buyerOrderId');
  });

  testWidgets('批发商点「新订单」：打开 /seller/orders/<id>；客服提醒不跳页', (tester) async {
    final s = await start(tester, seller: true, prefs: {'push_permission_asked': true});
    expect(s.session.stage, SessionStage.seller);
    expect(s.location, '/seller');
    await s.tap({'type': 'order_unconfirmed', 'order_id': sellerOrderId});
    expect(s.location, '/seller');
    await s.tap({'type': 'order_new', 'order_id': sellerOrderId});
    expect(s.location, '/seller/orders/$sellerOrderId');
  });

  testWidgets('批发商点另一家（也是成员）的「今天要送」：先换到那一家，再打开送货总结', (tester) async {
    final s = await start(tester, seller: true, prefs: {'push_permission_asked': true});
    const other = '00000000-0000-4000-a000-0000000000bb';
    s.api.sellerData.otherWholesalers.add({'id': other, 'name': '示范批发 B', 'status': 'active', 'member_role': 'owner'});
    unawaited(s.session.refresh()); // 示范资料要等（假的时间），不能直接 await
    await settle(tester);
    final first = s.session.wholesalerId;
    expect(first, isNot(other));

    await s.tap({'type': 'daily_summary', 'date': '2026-11-25', 'wholesaler_id': other});
    expect(s.session.wholesalerId, other, reason: '换到通知说的那一家');
    expect(s.location, '/seller/summary?date=2026-11-25');

    // 不是我的批发商、或是现在这一家：不换
    await s.tap({
      'type': 'daily_summary',
      'date': '2026-11-26',
      'wholesaler_id': '00000000-0000-4000-a000-0000000000cc',
    });
    expect(s.session.wholesalerId, other);
    expect(s.location, '/seller/summary?date=2026-11-26');
  });

  testWidgets('买家打不开批发商的页面', (tester) async {
    final s = await start(tester);
    s.router.go('/seller/summary');
    await settle(tester);
    expect(s.location, '/home');
  });

  testWidgets('批发商第一次打开首页：先说明再问权限，拒绝了也照样能用，只问一次', (tester) async {
    final s = await start(tester, seller: true);
    expect(find.text('打开通知？'), findsOneWidget);
    expect(find.text('有新订单时手机会响，不会漏单。'), findsOneWidget);
    await tester.tap(find.text('打开通知'));
    await settle(tester);
    expect(s.push.calls, contains('ask'));
    expect(find.textContaining('通知没有打开'), findsOneWidget);
    expect(find.byType(SellerHomePage), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('push_permission_asked'), isTrue);
  });

  testWidgets('已经问过就不再问', (tester) async {
    await start(tester, seller: true, prefs: {'push_permission_asked': true});
    expect(find.text('打开通知？'), findsNothing);
  });

  testWidgets('「以后再说」不会跳系统询问', (tester) async {
    final s = await start(tester, seller: true);
    await tester.tap(find.text('以后再说'));
    await settle(tester);
    expect(s.push.calls, isNot(contains('ask')));
    expect(find.text('打开通知？'), findsNothing);
  });

  testWidgets('已经允许了（例如在别的地方打开过）：不问', (tester) async {
    await start(tester, seller: true, status: PushPermission.granted);
    expect(find.text('打开通知？'), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('push_permission_asked'), isTrue);
  });

  testWidgets('示范模式（不做推送）不会问权限', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'locale': 'zh'});
    final prefs = await SharedPreferences.getInstance();
    final api = DemoApi(seller: true);
    final session = DemoSession(api: api, prefs: prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
        child: WholesaleApp(session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开通知？'), findsNothing);
    expect(find.text('示范批发 A：新山包装行'), findsOneWidget, reason: '?seller=1 进批发商端');
  });
}
