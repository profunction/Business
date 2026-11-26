// 第七步：收费。示范模式（资料是本机数据库导出的 buyer_billing*.json、seller_billing.json、commission_invoice.json），
// 假的「打开付款页」（不会真的开浏览器）。买家的付款按钮照 App Store / Google Play 的规定默认不出现。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/app/billing_config.dart';
import 'package:jb_wholesale/app/providers.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/demo/demo_session.dart';
import 'package:jb_wholesale/features/seller/seller_device.dart';
import 'package:jb_wholesale/main.dart';
import 'package:jb_wholesale/push/push_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seller_harness.dart';

class FakeLauncher implements PaymentLauncher {
  final opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return result;
  }
}

Future<(DemoApi, FakeLauncher)> startBuyer(
  WidgetTester tester, {
  String locale = 'zh',
  bool canPay = true,
  bool free = false,
  FakeDevice? device,
  bool seller = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'locale': locale, 'push_permission_asked': true});
  final prefs = await SharedPreferences.getInstance();
  final api = DemoApi(freeUser: free, seller: seller);
  final launcher = FakeLauncher();
  final session = DemoSession(api: api, prefs: prefs);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => session),
        paymentLauncherProvider.overrideWithValue(launcher),
        billingPolicyProvider.overrideWithValue(BillingPolicy(buyerCanPay: canPay, sellerCanPay: canPay)),
        sellerDeviceProvider.overrideWithValue(device ?? FakeDevice()),
      ],
      child: WholesaleApp(session: session),
    ),
  );
  await tester.pumpAndSettle();
  return (api, launcher);
}

void main() {
  test('付款按钮的规定：商店版本（iOS / Android）买家没有；网页版有；批发商默认有', () {
    final store = BillingPolicy.fromEnvironment(isWeb: false);
    expect(store.buyerCanPay, isFalse);
    expect(store.sellerCanPay, isTrue);
    expect(BillingPolicy.fromEnvironment(isWeb: true).buyerCanPay, isTrue);
  });

  test('点通知：账单 → 那张账单；收到付款 / 快到期 → 订阅页', () {
    const inv = '5cb717be-701e-4a69-9bd2-4be25d7bb553';
    expect(pushRoute({'type': 'invoice_issued', 'invoice_id': inv}, isSeller: true), '/seller/billing/invoices/$inv');
    expect(pushRoute({'type': 'invoice_overdue', 'invoice_id': 'x'}, isSeller: true), '/seller/billing');
    expect(pushRoute({'type': 'invoice_due_soon'}, isSeller: false), isNull);
    expect(pushRoute({'type': 'payment_received'}, isSeller: false), '/subscription');
    expect(pushRoute({'type': 'payment_received', 'invoice_id': inv}, isSeller: true), '/seller/billing/invoices/$inv');
    expect(pushRoute({'type': 'subscription_ending'}, isSeller: false), '/subscription');
  });

  testWidgets('买家：首页 → 订阅（试用还有 14 天、锁定 RM50）→ 选 3 个月 → 付款页 → 我付好了 → 已订阅', (tester) async {
    final (api, launcher) = await startBuyer(tester);
    await tapAndSettle(tester, find.byKey(const Key('banner-subscription')));
    expect(find.text('免费试用中，还有 14 天'), findsOneWidget);
    expect(find.textContaining('锁定 RM50.00'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('months-3')));
    expect(find.text('付款 RM150.00'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('pay-subscription')));
    expect(api.calls, contains('createPayment subscription 3'));
    expect(launcher.opened.single.host, 'securecheckout.sandbox.hit-pay.com');

    await tapAndSettle(tester, find.byKey(const Key('pay-check')));
    expect(find.text('收到付款 RM150.00，谢谢！'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('已订阅，全部价钱都看得到'), findsOneWidget);
    await scrollTo(tester, find.text('付过的'));
    expect(find.textContaining('FPX 网银 · 3 个月'), findsOneWidget);
  });

  testWidgets('买家（商店版本）：看得到状态，没有付款按钮、没有叫他去别的地方付的文字', (tester) async {
    await startBuyer(tester, canPay: false);
    await tapAndSettle(tester, find.byKey(const Key('banner-subscription')));
    expect(find.text('免费试用中，还有 14 天'), findsOneWidget);
    expect(find.byKey(const Key('pay-subscription')), findsNothing);
    expect(find.textContaining('FPX'), findsNothing);
    expect(find.textContaining('付款'), findsNothing);
  });

  testWidgets('买家（已停）：显示现在的价钱、选批发商；网关没开通 → 说清楚', (tester) async {
    final (api, launcher) = await startBuyer(tester, free: true, locale: 'en');
    await tapAndSettle(tester, find.byIcon(Icons.settings));
    await tapAndSettle(tester, find.byKey(const Key('open-subscription')));
    expect(find.text('Free plan'), findsWidgets);
    expect(find.textContaining('Current monthly fee RM50.00'), findsOneWidget);
    expect(find.text('Choose wholesalers'), findsOneWidget);
    api.paymentError = 'PAYMENT_NOT_CONFIGURED';
    await tapAndSettle(tester, find.byKey(const Key('pay-subscription')));
    expect(find.text('Online payment is not available yet. Please contact us.'), findsOneWidget);
    expect(launcher.opened, isEmpty);
  });

  for (final locale in ['zh', 'en', 'ms']) {
    testWidgets('订阅页三种语言都排得下（$locale）', (tester) async {
      await startBuyer(tester, locale: locale);
      await tapAndSettle(tester, find.byKey(const Key('banner-subscription')));
      expect(find.byKey(const Key('pay-subscription')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('批发商：设定 → 收费：付创始上架费、看账单明细、付佣金、印 PDF', (tester) async {
    final device = FakeDevice();
    final (api, launcher) = await startBuyer(tester, seller: true, device: device);
    await tapAndSettle(tester, find.byIcon(Icons.settings));
    await tapAndSettle(tester, find.byKey(const Key('seller-billing')));
    expect(find.text('还有 RM2.81 佣金没付'), findsOneWidget);
    expect(find.text('你是创始会员第 1 号，上架费 RM100.00（一次）'), findsOneWidget);
    expect(find.text('你的佣金：每张单 1%'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('pay-listing-fee')));
    expect(api.calls, contains('createPayment listing_fee 1'));
    expect(launcher.opened, hasLength(1));
    await tapAndSettle(tester, find.byKey(const Key('pay-check')));
    expect(find.text('收到付款 RM100.00，谢谢！'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('创始会员第 1 号，上架费已付'), findsOneWidget);
    expect(find.byKey(const Key('pay-listing-fee')), findsNothing);

    final invoice = find.byWidgetPredicate((w) => w is ListTile && '${w.key}'.contains('invoice-'));
    await scrollTo(tester, invoice);
    await tapAndSettle(tester, invoice);
    expect(find.textContaining('INV2610-0001'), findsWidgets);
    expect(find.textContaining('阿明茶餐室'), findsOneWidget);
    expect(find.textContaining('货价 RM281.00 x 1%'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('invoice-print')));
    expect(device.printed, hasLength(1));
    expect(String.fromCharCodes(device.printed.single.take(5)), '%PDF-');

    await tapAndSettle(tester, find.byKey(const Key('pay-invoice')));
    expect(api.calls, contains('createPayment commission_invoice 1'));
    await tapAndSettle(tester, find.byKey(const Key('pay-check')));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.byKey(const Key('pay-invoice')), findsNothing);
    expect(find.textContaining('已付'), findsWidgets);
  });

  testWidgets('批发商：关掉付款（SELLER_IN_APP_PAY=false）→ 只看账单，没有付款按钮', (tester) async {
    await startBuyer(tester, seller: true, canPay: false);
    await tapAndSettle(tester, find.byIcon(Icons.settings));
    await tapAndSettle(tester, find.byKey(const Key('seller-billing')));
    expect(find.byKey(const Key('pay-listing-fee')), findsNothing);
    expect(find.text('每月账单'), findsOneWidget);
  });
}
