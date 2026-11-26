// 第七步：客服后台的收费：付款记录、代开付款链接（月费 / 上架费 / 佣金账单）、手动标记创始上架费已付。
// 样本是本机数据库导出的（tool/export_billing_fixtures.sh）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _a = '00000000-0000-4000-a000-00000000000a';
const _c = '00000000-0000-4000-a000-00000000000c';

void main() {
  for (final size in [desktop, tablet]) {
    testWidgets('付款记录：网关收到的、筛选（${size.width.toInt()} 宽）', (tester) async {
      await pumpAdmin(tester, size: size);
      await goTo(tester, 'payments');
      expect(find.text('付款记录'), findsWidgets);
      expect(find.textContaining('HP-DEMO-1'), findsOneWidget);
      expect(find.text('RM150.00'), findsOneWidget);
      expect(find.text('已付'), findsWidgets);
      await tester.tap(find.byKey(const Key('pay-filter-listingFee')));
      await tester.pumpAndSettle();
      expect(find.text('没有付款记录'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pay-filter-subscription')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay-review-only')));
      await tester.pumpAndSettle();
      expect(find.text('没有付款记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('订阅：代开付款链接（服务器算金额）→ 复制；网关没设定 → 说清楚', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final r = await pumpAdmin(tester);
    await goTo(tester, 'subscriptions');
    await tapKey(tester, 'paylink-阿明茶餐室');
    expect(r.api.calls, contains('createPayment subscription'));
    expect(find.text('金额 RM50.00（服务器算的）'), findsOneWidget);
    final url = tester.widget<SelectableText>(find.byKey(const Key('pay-link-url'))).data!;
    expect(url, startsWith('https://'));
    await tapKey(tester, 'pay-link-copy');
    expect(copied, url);
    expect(find.text('复制好了'), findsOneWidget);

    await goTo(tester, 'payments');
    expect(find.text('等付款'), findsOneWidget, reason: '开了链接：一张等付款的');

    r.api.paymentError = 'PAYMENT_NOT_CONFIGURED';
    await goTo(tester, 'subscriptions');
    await tapKey(tester, 'paylink-阿明茶餐室');
    expect(find.text('付款网关还没设定（HITPAY_API_KEY）'), findsOneWidget);
    expect(find.byKey(const Key('pay-link-url')), findsNothing);
  });

  testWidgets('批发商：创始上架费未付 → 标记已付（写操作记录）；还不是创始会员的 → 变创始会员', (tester) async {
    final r = await pumpAdmin(tester, locale: 'en');
    await goTo(tester, 'wholesalers');
    expect(find.text('Listing fee unpaid'), findsNWidgets(2), reason: 'A、B 是创始会员，还没付');
    await tapKey(tester, 'listingfee-$_a');
    await fillDialog(tester, 'DN-LF-1');
    expect(r.api.calls, contains('markListingFeePaid'));
    expect(find.text('Listing fee paid'), findsOneWidget);
    expect(find.byKey(const Key('listingfee-$_a')), findsNothing);

    await tapKey(tester, 'listingfee-$_c');
    await fillDialog(tester, '');
    expect(find.text('Listing fee paid'), findsNWidgets(2));

    await tapKey(tester, 'listinglink-00000000-0000-4000-a000-00000000000b');
    expect(r.api.calls, contains('createPayment listing_fee'));
    expect(find.text('Amount RM100.00 (calculated by the server)'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await goTo(tester, 'audit');
    expect(find.textContaining('admin_mark_listing_fee_paid'), findsWidgets);
  });
}
