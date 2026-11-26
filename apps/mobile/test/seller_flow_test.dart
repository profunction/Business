// 批发商端：用示范模式（DemoApi(seller: true)，数据是本机数据库导出的真实样本）把订单流程点一遍。
// 手机宽度 400：大字把画面撑爆（overflow）的话，测试会直接失败。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/app/router.dart';
import 'package:jb_wholesale/push/push_service.dart';
import 'package:jb_wholesale/widgets/common.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'seller_harness.dart';

// 样本里的订单（packages/core/test/fixtures/seller_orders.json）
const kopitiamPending = '544a4c20-a4b5-486f-b3a7-99fc9cd0c3f5'; // 待确认，最早的一张（JHB261125-00004）
const amingPending = '1cf81f7b-9e34-42dd-9f8e-fe096bcf807c'; // 待确认（seller_order_detail 样本，JHB261125-00005）
const spoonItem = 'b3316f06-a13e-4ab6-a6d3-f9d3ea32717f'; // 上面那张的「白色塑料汤匙 ×5」
const amingConfirmed = '5c372e2f-2712-415e-bfdb-314c0d0985a3'; // 已确认，今天送（JHB261125-00002）
const sitiDelivering = '7880e5cf-34f0-4a69-a98e-82cece368564'; // 送货中，今天送
const delivered = '5a0a6317-4e51-4888-8472-50cf475568bf'; // 已送达

void main() {
  testWidgets('首页：新订单、今天要送、商品和价钱、上传价目表的数字', (tester) async {
    final api = await startSeller(tester);
    expect(find.text('示范批发 A：新山包装行'), findsOneWidget);
    expect(find.text('新订单（2）'), findsOneWidget);
    expect(find.textContaining('最久的一张等了'), findsOneWidget);
    expect(find.text('今天要送（2）'), findsOneWidget);
    expect(find.text('总额 RM579.00'), findsOneWidget, reason: '今天要送：RM390 + RM189');
    expect(find.text('商品和价钱'), findsOneWidget);
    expect(find.text('上架 6 样 · 1 样缺货 · 1 样快卖完'), findsOneWidget);
    expect(find.text('上传价目表'), findsOneWidget);
    expect(find.text('AI 读好了，去确认上架'), findsOneWidget);
    expect(find.byKey(const Key('seller-status-banner')), findsNothing, reason: '已经审核好了');
    expect(api.orderWatcherCount, 1, reason: '首页在听订单的 Realtime');
  });

  testWidgets('Realtime：订单在别的地方变了（例如 WhatsApp 按了确认），首页数字自己更新', (tester) async {
    final api = await startSeller(tester);
    api.sellerData.confirm(amingPending, const []); // 服务器那边确认了
    api.simulateOrderChange();
    await settle(tester);
    expect(find.text('新订单（1）'), findsOneWidget);
    expect(find.text('今天要送（3）'), findsOneWidget);
  });

  testWidgets('等客服审核：上面有提示，商品和价目表照样可以打开', (tester) async {
    await startSeller(tester, status: 'pending');
    expect(find.byKey(const Key('seller-status-banner')), findsOneWidget);
    expect(find.textContaining('客服正在审核你的资料'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('seller-products')));
    expect(find.text('商品和价钱'), findsOneWidget, reason: '商品页的标题');
    await back(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-import')));
    expect(routerOf(tester).state.uri.path, startsWith('/seller/import'));
  });

  testWidgets('新订单：先来先做（最早的在最上面），打开一张看店的资料和明细', (tester) async {
    final launcher = fakeLauncher();
    final api = await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-new-orders')));
    expect(find.text('订单'), findsOneWidget);
    expect(find.text('新订单（2）'), findsOneWidget, reason: '按钮上有数字');
    final older = tester.getTopLeft(find.byKey(const Key('seller-order-$kopitiamPending'))).dy;
    final newer = tester.getTopLeft(find.byKey(const Key('seller-order-$amingPending'))).dy;
    expect(older, lessThan(newer));
    expect(find.textContaining('等了'), findsNWidgets(2));

    await tapAndSettle(tester, find.byKey(const Key('seller-order-$amingPending')));
    expect(find.text('阿明茶餐室'), findsNWidgets(2), reason: '标题 + 店的资料');
    expect(find.text('订单 JHB261125-00005'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('Jalan Demo 10, Taman Molek'), findsOneWidget);
    expect(find.text('联络人：阿明'), findsOneWidget);
    expect(find.text('012-000 0001'), findsOneWidget);
    expect(find.text('买家备注：老样子，谢谢'), findsOneWidget);
    expect(find.text('16安士 PP杯 95口径  ×2 箱'), findsOneWidget);
    expect(find.text('白色塑料汤匙  ×5 包'), findsOneWidget);
    expect(amount('总额', 'RM191.00'), findsOneWidget);
    expect(find.byKey(const Key('seller-confirm')), findsOneWidget);
    expect(find.byKey(const Key('seller-oos')), findsOneWidget);
    expect(api.orderWatcherCount, 1, reason: '几个页面共用一个 Realtime channel');

    // 打电话、WhatsApp：用别的 App 打开，WhatsApp 先打好一句话
    await tapAndSettle(tester, find.byKey(const Key('seller-call')));
    await tapAndSettle(tester, find.byKey(const Key('seller-whatsapp')));
    expect(launcher.launched, [
      'externalApplication tel:+60120000001',
      'externalApplication https://wa.me/60120000001?text=${Uri.encodeQueryComponent('你好，关于你的订单 JHB261125-00005：')}',
    ]);

    // 手机没装 WhatsApp：不会闪退，告诉老板打不开
    launcher.fail = true;
    await tapAndSettle(tester, find.byKey(const Key('seller-whatsapp')));
    expect(find.text('打不开，请检查手机有没有装这个 App'), findsOneWidget);
  });

  testWidgets('确认，勾一样缺货：那样划掉不算钱，变成「出发送货」/「已送达」', (tester) async {
    final api = await startSeller(tester);
    await openOrder(tester, tile: 'seller-new-orders', id: amingPending);

    // 先问哪几样缺货；按取消什么都不做
    await tapAndSettle(tester, find.byKey(const Key('seller-confirm')));
    expect(find.text('哪几样缺货？'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('oos-checklist-cancel')));
    expect(api.calls.where((c) => c.startsWith('confirm ')), isEmpty);

    await tapAndSettle(tester, find.byKey(const Key('seller-confirm')));
    expect(find.text('全部有货，确认'), findsOneWidget, reason: '不勾 = 全部有货');
    await tapAndSettle(tester, find.byKey(const Key('oos-item-$spoonItem')));
    expect(find.text('确认（1 样缺货）'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('oos-checklist-done')));

    expect(api.calls, contains('confirm $amingPending 1'));
    expect(find.text('已确认，买家会收到通知'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
    await scrollTo(tester, find.text('总额'));
    final spoon = tester.widget<Text>(find.text('白色塑料汤匙  ×5 包'));
    expect(spoon.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('缺货（不算钱）'), findsOneWidget);
    expect(amount('总额', 'RM170.00'), findsOneWidget, reason: '汤匙的 RM21 不算');
    expect(find.byKey(const Key('seller-confirm')), findsNothing);
    expect(find.byKey(const Key('seller-start-delivery')), findsOneWidget);
    expect(find.byKey(const Key('seller-mark-delivered')), findsOneWidget);

    // 回到列表、首页：数字跟着变
    await back(tester);
    expect(find.byKey(const Key('seller-order-$amingPending')), findsNothing);
    expect(find.text('新订单（1）'), findsOneWidget);
    await back(tester);
    expect(find.text('新订单（1）'), findsOneWidget);
    expect(find.text('今天要送（3）'), findsOneWidget);
  });

  testWidgets('全部都勾缺货 = 整张单缺货', (tester) async {
    final api = await startSeller(tester);
    await openOrder(tester, tile: 'seller-new-orders', id: amingPending);
    await tapAndSettle(tester, find.byKey(const Key('seller-confirm')));
    await tapAndSettle(tester, find.byKey(const Key('oos-item-$spoonItem')));
    await tapAndSettle(tester, find.byKey(const Key('oos-item-b4926530-9b59-49fc-bcb8-2ff0ed069751')));
    expect(find.text('全部都缺货'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('oos-checklist-done')));
    expect(api.calls, contains('confirm $amingPending 2'));
    expect(find.text('已标缺货，买家会收到通知'), findsOneWidget);
    expect(find.byKey(const Key('seller-start-delivery')), findsNothing);
  });

  testWidgets('整张单缺货：先问一次，确定了才改', (tester) async {
    final api = await startSeller(tester);
    await openOrder(tester, tile: 'seller-new-orders', id: kopitiamPending);
    expect(find.text('新山咖啡店 Kopitiam JB'), findsNWidgets(2));

    await tapAndSettle(tester, find.byKey(const Key('seller-oos')));
    expect(find.text('整张单都缺货？'), findsOneWidget);
    expect(find.text('买家会收到通知，这张单不会送。'), findsOneWidget);
    await tapAndSettle(tester, find.text('取消'));
    expect(api.calls.where((c) => c.startsWith('outOfStock')), isEmpty);
    expect(find.byKey(const Key('seller-oos')), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('seller-oos')));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '整张单缺货'));
    expect(api.calls, contains('outOfStock $kopitiamPending'));
    expect(find.text('已标缺货，买家会收到通知'), findsOneWidget);
    expect(find.widgetWithText(StatusChip, '缺货'), findsOneWidget);
    expect(find.byKey(const Key('seller-oos')), findsNothing, reason: '没有按钮了');
    expect(find.byKey(const Key('seller-confirm')), findsNothing);
    expect(find.byKey(const Key('seller-start-delivery')), findsNothing);

    await back(tester);
    expect(find.byKey(const Key('seller-order-$kopitiamPending')), findsNothing, reason: '不在新订单里了');
  });

  testWidgets('今天要送：出发送货，再按已送达（先问一次）', (tester) async {
    final api = await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-today')));
    expect(find.text('2 张单，总额 RM579.00'), findsOneWidget);
    expect(find.byKey(const Key('seller-open-summary')), findsOneWidget);
    expect(find.byKey(const Key('seller-order-$sitiDelivering')), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('seller-order-$amingConfirmed')));
    expect(find.widgetWithText(StatusChip, '已确认'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('seller-start-delivery')));
    expect(api.calls, contains('delivering $amingConfirmed'));
    expect(find.text('已出发，买家会收到通知'), findsOneWidget);
    expect(find.widgetWithText(StatusChip, '送货中'), findsOneWidget);
    expect(find.byKey(const Key('seller-start-delivery')), findsNothing);

    await tapAndSettle(tester, find.byKey(const Key('seller-mark-delivered')));
    expect(find.text('确定货已经送到了？'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '已送达').last);
    expect(api.calls, contains('delivered $amingConfirmed'));
    expect(find.text('送到了，谢谢！'), findsOneWidget);
    expect(find.widgetWithText(StatusChip, '已送达'), findsOneWidget);
    expect(find.byKey(const Key('seller-mark-delivered')), findsNothing);

    await back(tester);
    expect(find.text('1 张单，总额 RM189.00'), findsOneWidget, reason: '送到了就不在今天要送里');
  });

  testWidgets('订单列表：?tab= 打开指定的分页，三个按钮可以切换', (tester) async {
    await startSeller(tester);
    routerOf(tester).push('/seller/orders?tab=all');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('seller-order-$delivered')));
    expect(find.widgetWithText(StatusChip, '已送达'), findsOneWidget, reason: '「全部」也有已送达的');
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-pending')));
    expect(find.byKey(const Key('seller-order-$delivered'), skipOffstage: false), findsNothing);
    expect(find.byKey(const Key('seller-order-$kopitiamPending')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-today')));
    expect(find.byKey(const Key('seller-order-$sitiDelivering')), findsOneWidget);
    expect(find.byKey(const Key('seller-order-$kopitiamPending')), findsNothing);
  });

  testWidgets('「全部」只读最近的 100 张：读满了在最后说只显示最近的，没满就不说', (tester) async {
    final api = await startSeller(tester);
    routerOf(tester).push('/seller/orders?tab=all');
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const Key('seller-orders-limited'), skipOffstage: false), findsNothing);

    api.sellerData.addPastOrders(150);
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-pending')));
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-all')));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('seller-orders-limited')), 2000, scrollable: pageScrollable);
    await tester.pumpAndSettle();
    expect(find.text('这里只显示最近的 100 张单'), findsOneWidget);
  });

  testWidgets('英文：订单明细、缺货勾选的数量有复数（×2 cartons，跟送货单一样）', (tester) async {
    await startSeller(tester, locale: 'en');
    await openOrder(tester, tile: 'seller-new-orders', id: amingPending);
    await scrollTo(tester, find.text('16安士 PP杯 95口径  ×2 cartons'));
    expect(find.text('16安士 PP杯 95口径  ×2 cartons'), findsOneWidget);
    expect(find.textContaining('×2 carton '), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('seller-confirm')));
    expect(find.textContaining('×5 packs'), findsNWidgets(2), reason: '白色塑料汤匙 ×5：明细 + 缺货勾选');
    expect(find.textContaining('×5 pack '), findsNothing);
  });

  testWidgets('从链接打开某张单（还在读登录资料）：读完就打开那张，按返回回到批发商首页', (tester) async {
    await startSeller(tester, settle: false);
    routerOf(tester).go('/seller/orders/$amingPending');
    await tester.pumpAndSettle();
    expect(routerOf(tester).state.uri.toString(), '/seller/orders/$amingPending');
    expect(find.text('订单 JHB261125-00005'), findsOneWidget);
    await back(tester);
    expect(find.text('新订单（2）'), findsOneWidget);
  });

  testWidgets('设定：换语言马上生效；示范模式说这部手机收不到推送', (tester) async {
    await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    expect(find.text('设定'), findsOneWidget);
    expect(find.text('新订单怎么通知你？'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('logout')));
    expect(find.text('这部手机收不到 App 推送，可以改用 WhatsApp 收订单'), findsOneWidget);
    expect(find.textContaining('订阅', skipOffstage: false), findsNothing, reason: '批发商端没有付费按钮');

    // 滚回最上面（设定页有「收费和账单」之后变长了）
    await tester.drag(pageScrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const Key('settings-lang-en')));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('My business'), findsOneWidget);
    expect(find.text('How should we tell you about new orders?'), findsOneWidget);
    await back(tester);
    expect(find.text('New orders (2)'), findsOneWidget);
    expect(find.text('Deliver today (2)'), findsOneWidget);
  });

  testWidgets('设定：老板改通知方式（选 WhatsApp = 同意用 WhatsApp 收订单）', (tester) async {
    final api = await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    expect(find.text('发到 012-000 0002'), findsOneWidget);
    expect(find.byKey(const Key('whatsapp-opt-in')), findsOneWidget, reason: '「自动」时要另外同意');

    await tapAndSettle(tester, find.byKey(const Key('notify-whatsapp')));
    expect(api.calls, contains('notifyChannel whatsapp'));
    expect(find.text('保存好了'), findsOneWidget);
    expect(api.sellerData.settings().whatsappOptedIn, isTrue);
    expect(find.byKey(const Key('whatsapp-opt-in')), findsNothing, reason: '选了 WhatsApp 就是同意');

    await tapAndSettle(tester, find.byKey(const Key('notify-auto')));
    expect(api.calls, contains('notifyChannel auto'));
    await tapAndSettle(tester, find.byKey(const Key('whatsapp-opt-in')));
    expect(api.sellerData.settings().whatsappOptedIn, isFalse);
  });

  testWidgets('设定：选 WhatsApp 时回应在路上断了（服务器其实改好了）：画面显示服务器上真的设定，不是旧的', (tester) async {
    final api = await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    api.loseNextSettingsReply = true;
    await tapAndSettle(tester, find.byKey(const Key('notify-whatsapp')));
    await settle(tester);
    expect(find.text('连不上网络，请检查网络再试'), findsOneWidget);
    final group = tester.widget<RadioGroup<NotifyChannel>>(find.byType(RadioGroup<NotifyChannel>));
    expect(group.groupValue, NotifyChannel.whatsapp, reason: '重新读了设定');
    expect(api.sellerData.settings().whatsappOptedIn, isTrue);
  });

  testWidgets('设定：老板换语言，批发商收到的通知也换语言（wholesalers.locale）；员工换不会改', (tester) async {
    final api = await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await tapAndSettle(tester, find.byKey(const Key('settings-lang-ms')));
    expect(api.calls, contains('wholesalerLocale ${api.sellerData.wholesalerId} ms'));
  });

  testWidgets('设定：员工换语言，不改批发商的通知语言', (tester) async {
    final api = await startSeller(tester, role: 'staff');
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await tapAndSettle(tester, find.byKey(const Key('settings-lang-en')));
    expect(api.calls.where((c) => c.startsWith('wholesalerLocale')), isEmpty);
  });

  testWidgets('设定：照提示去手机「设定」打开通知再回来：马上显示已经打开', (tester) async {
    final push = FakePush()..status = PushPermission.denied;
    await startSeller(tester, push: push);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await scrollTo(tester, find.byKey(const Key('push-enable')));
    expect(find.byKey(const Key('push-off')), findsOneWidget);
    // 去手机的设定（App 到背景），打开通知，再回来
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    push.status = PushPermission.granted;
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settle(tester);
    expect(find.byKey(const Key('push-on')), findsOneWidget);
    expect(find.byKey(const Key('push-off')), findsNothing);
    expect(push.calls, isEmpty, reason: '没有再问');
  });

  testWidgets('设定：员工只看得到现在的通知方式，不能改', (tester) async {
    await startSeller(tester, role: 'staff');
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    expect(find.byKey(const Key('notify-read-only')), findsOneWidget);
    expect(find.text('自动（建议）'), findsOneWidget);
    expect(find.text('只有老板可以改。客服也可以帮你改。'), findsOneWidget);
    expect(find.byKey(const Key('notify-whatsapp')), findsNothing);
  });

  testWidgets('设定：通知还没打开 → 按一下打开', (tester) async {
    final push = FakePush();
    await startSeller(tester, push: push);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await scrollTo(tester, find.byKey(const Key('push-enable')));
    expect(find.text('通知还没打开'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('push-enable')));
    expect(push.calls, ['ask']);
    expect(find.byKey(const Key('push-on')), findsOneWidget);
    expect(find.text('已经打开，有新订单手机会响'), findsOneWidget);
  });

  testWidgets('设定：拒绝了通知 → 告诉老板去手机设定打开', (tester) async {
    final push = FakePush()
      ..status = PushPermission.denied
      ..answer = PushPermission.denied;
    await startSeller(tester, push: push);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await scrollTo(tester, find.byKey(const Key('push-enable')));
    await tapAndSettle(tester, find.byKey(const Key('push-enable')));
    expect(find.textContaining('「设定」→「通知」'), findsWidgets);
    expect(find.byKey(const Key('push-off')), findsOneWidget);
  });

  testWidgets('登出：Realtime 关掉，回到登录页', (tester) async {
    final api = await startSeller(tester);
    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await scrollTo(tester, find.byKey(const Key('logout')));
    await tapAndSettle(tester, find.byKey(const Key('logout')));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '登出'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('用手机号登录'), findsOneWidget);
    expect(api.orderWatcherCount, 0);
    expect(isSellerPath(routerOf(tester).state.uri.path), isFalse);
  });

  testWidgets('马来文 + 系统大字（1.3 倍）：每一页都不会撑爆', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await startSeller(tester, locale: 'ms', status: 'pending');
    expect(find.text('Pesanan baharu (2)'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('seller-new-orders')));
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-today')));
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-all')));
    await tapAndSettle(tester, find.byKey(const Key('seller-tab-pending')));
    await scrollTo(tester, find.byKey(const Key('seller-order-$amingPending')));
    await tapAndSettle(tester, find.byKey(const Key('seller-order-$amingPending')));
    expect(find.text('Sahkan'), findsOneWidget);
    expect(find.text('Habis stok'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('seller-confirm')));
    await tapAndSettle(tester, find.byKey(const Key('oos-item-$spoonItem')));
    expect(find.text('Sahkan (1 habis stok)'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('oos-checklist-done')));
    expect(find.text('Mula hantar'), findsOneWidget);
    await back(tester);
    await back(tester);

    await tapAndSettle(tester, find.byKey(const Key('seller-open-settings')));
    await scrollTo(tester, find.byKey(const Key('logout')));
    expect(find.text('Log keluar'), findsOneWidget);
  });
}
