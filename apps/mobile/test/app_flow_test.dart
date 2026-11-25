// 用示范模式（DemoApi，数据是本机数据库导出的真实样本）把整个 App 跑起来，模拟老板一步一步点。
// 手机宽度 400：大字把画面撑爆（overflow）的话，测试会直接失败。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/app/providers.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/demo/demo_session.dart';
import 'package:jb_wholesale/main.dart';
import 'package:jb_wholesale/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<DemoApi> startApp(
  WidgetTester tester, {
  String? locale = 'zh',
  bool free = false,
  bool newUser = false,
  bool loggedIn = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'locale': ?locale});
  final prefs = await SharedPreferences.getInstance();
  final api = DemoApi(freeUser: free, newUser: newUser)..loggedIn = loggedIn;
  final session = DemoSession(api: api, prefs: prefs);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
      child: WholesaleApp(session: session),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

/// 列表比屏幕长的时候，先滚到看得见
Future<void> scrollTo(WidgetTester tester, Finder f, {bool up = false}) async {
  await tester.scrollUntilVisible(f, up ? -200 : 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('第一次打开：先选语言，然后到首页', (tester) async {
    await startApp(tester, locale: null);
    expect(find.text('华文'), findsOneWidget);
    expect(find.text('Bahasa Melayu'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('lang-zh')));
    expect(find.text('跟上次一样'), findsOneWidget);
    expect(find.text('买东西'), findsOneWidget);
    expect(find.text('我的订单'), findsOneWidget);
    expect(find.textContaining('免费试用还有'), findsOneWidget);
  });

  testWidgets('马来文首页', (tester) async {
    await startApp(tester, locale: 'ms');
    expect(find.text('Sama macam lepas'), findsOneWidget);
    expect(find.text('Pesanan saya'), findsOneWidget);
  });

  testWidgets('手机号 + 验证码登录', (tester) async {
    final api = await startApp(tester, loggedIn: false);
    expect(find.text('用手机号登录'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phone-field')), '07-123 4567');
    await tapAndSettle(tester, find.byKey(const Key('send-code')));
    expect(find.text('这不像手机号码，请再检查一次'), findsOneWidget, reason: '固线电话不能登录');

    await tester.enterText(find.byKey(const Key('phone-field')), '012-000 0001');
    await tapAndSettle(tester, find.byKey(const Key('send-code')));
    expect(api.calls, contains('sendOtp +60120000001'));
    expect(find.text('验证码已经发到 012-000 0001'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    expect(find.text('跟上次一样'), findsOneWidget, reason: '登录后到首页');
  });

  testWidgets('新老板：一页一个问题开店', (tester) async {
    final api = await startApp(tester, newUser: true);
    expect(find.text('你的店叫什么名字？'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('shop-name')), '阿明茶餐室');
    await tester.pump();
    await tapAndSettle(tester, find.byKey(const Key('register-next')));
    await tapAndSettle(tester, find.text('餐馆'));
    await tapAndSettle(tester, find.byKey(const Key('register-next')));
    expect(find.text('你的店在哪一区？'), findsOneWidget);
    await tapAndSettle(tester, find.text('士古来'));
    await tapAndSettle(tester, find.byKey(const Key('register-next')));
    await tapAndSettle(tester, find.byKey(const Key('register-next'))); // 地址可以不填
    expect(api.calls, contains('registerShop 阿明茶餐室'));
    expect(find.text('跟上次一样'), findsOneWidget);
  });

  testWidgets('跟上次一样：一键回到确认页，总额写在按钮上，按了就下单', (tester) async {
    final api = await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('reorder')));
    expect(api.calls, contains('reorderLast'));
    expect(find.text('确认订单'), findsOneWidget);
    expect(find.text('确认下单 RM281.00'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('place-order')));
    expect(api.calls, contains('placeOrder 28100 reorder'));
    expect(find.text('下单成功！'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('placed-home')));
    expect(find.text('跟上次一样'), findsOneWidget);
  });

  testWidgets('下单时价钱刚好改了：提示老板再看一次，不会照旧价下单', (tester) async {
    final api = await startApp(tester);
    api.failNextPlaceOrderWithPriceChange = true;
    await tapAndSettle(tester, find.byKey(const Key('reorder')));
    await tapAndSettle(tester, find.byKey(const Key('place-order')));
    expect(find.text('价钱改了'), findsOneWidget);
    expect(find.text('下单成功！'), findsNothing);
  });

  testWidgets('比价：试用中看得到每家的价钱，最便宜的排第一', (tester) async {
    await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('go-shop')));
    await tapAndSettle(tester, find.byKey(const Key('category-cups')));
    await tapAndSettle(tester, find.text('16oz PP 透明杯（95mm 口径）'));
    expect(find.text('比价钱'), findsNothing);
    expect(find.text('每个 8.2 仙'), findsOneWidget);
    expect(find.text('每个 8.5 仙'), findsOneWidget);
    expect(find.byType(LockedPrice), findsNothing);
    // 第一张卡就是最便宜的
    final first = tester.getTopLeft(find.text('每个 8.2 仙'));
    final second = tester.getTopLeft(find.text('每个 8.5 仙'));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('未付费：锁住的批发商价钱是模糊的，可以把它加进免费名单', (tester) async {
    final api = await startApp(tester, free: true);
    expect(find.textContaining('免费版：可以选 3 家批发商看价钱'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('go-shop')));
    await tapAndSettle(tester, find.byKey(const Key('category-cups')));
    await tapAndSettle(tester, find.text('16oz PP 透明杯（95mm 口径）'));
    expect(find.text('每个 8.5 仙'), findsOneWidget, reason: '已选的 A 看得到');
    expect(find.byType(LockedPrice), findsOneWidget, reason: '没选的 C 是模糊的');
    expect(find.text('每个 8.2 仙'), findsNothing, reason: 'C 的价钱根本没有');

    await tapAndSettle(tester, find.byKey(const Key('unlock-00000000-0000-4000-a000-00000000000c')));
    expect(api.calls, contains('setUnlocked 2'));
    expect(find.byType(LockedPrice), findsNothing);
    await scrollTo(tester, find.text('每个 8.2 仙'));
    expect(find.text('每个 8.2 仙'), findsOneWidget);
  });

  testWidgets('放进购物车：用 + / - 选数量', (tester) async {
    final api = await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('go-shop')));
    await tapAndSettle(tester, find.byKey(const Key('category-cups')));
    await tapAndSettle(tester, find.text('16oz PP 透明杯（95mm 口径）'));
    await tapAndSettle(tester, find.byKey(const Key('offer-24bd92c6-4d48-41f6-8efc-f3a4ebe776ad')).first);
    await tapAndSettle(tester, find.byTooltip('+'));
    expect(find.text('RM170.00'), findsOneWidget, reason: '2 箱 x RM85');
    await tapAndSettle(tester, find.byKey(const Key('confirm-add')));
    expect(api.calls, contains('setCartQty 24bd92c6-4d48-41f6-8efc-f3a4ebe776ad 2'));
  });

  testWidgets('购物车：未到最低消费会标红，不能下一步', (tester) async {
    await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('go-shop')));
    await tapAndSettle(tester, find.byKey(const Key('cart-button')));
    expect(find.text('购物车'), findsOneWidget);
    expect(find.textContaining('才到最低消费'), findsOneWidget);
    expect(find.text('请先处理红色的问题'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(const Key('go-checkout')));
    expect(button.onPressed, isNull);
  });

  testWidgets('订单：状态、缺货的那一样、「收到了」', (tester) async {
    final api = await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('go-orders')));
    expect(find.text('已确认'), findsOneWidget);
    expect(find.text('送货中'), findsOneWidget);
    expect(find.text('1 样缺货'), findsOneWidget);
    await scrollTo(tester, find.text('待确认'));
    await scrollTo(tester, find.text('已送达'));
    await scrollTo(tester, find.text('已确认'), up: true);

    await tapAndSettle(tester, find.text('已确认'));
    expect(find.text('缺货（不算钱）'), findsOneWidget);
    await scrollTo(tester, find.text('取消订单'));
    expect(find.text('取消订单'), findsOneWidget, reason: '还没送货，老板可以取消');
    await tapAndSettle(tester, find.byKey(const Key('mark-received')));
    expect(find.text('确定货已经收到了？'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '收到了').last);
    expect(api.calls.any((c) => c.startsWith('received ')), isTrue);
  });

  testWidgets('评价：5 颗星 + 标签', (tester) async {
    final api = await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('go-orders')));
    await scrollTo(tester, find.text('已送达'));
    await tapAndSettle(tester, find.text('已送达'));
    await tapAndSettle(tester, find.byKey(const Key('write-review')));
    expect(find.text('这家批发商怎么样？'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('star-4')));
    await tapAndSettle(tester, find.text('准时'));
    await tapAndSettle(tester, find.byKey(const Key('submit-review')));
    expect(api.calls, contains('review 4 1'));
  });

  testWidgets('设定：换语言马上生效', (tester) async {
    await startApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('open-settings')));
    await tapAndSettle(tester, find.byKey(const Key('settings-lang-en')));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });
}
