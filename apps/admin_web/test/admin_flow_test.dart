// 用示范模式（真实样本，不连服务器）把客服后台每一页点一遍：登录、首页、全部订单（筛选）、跟进、订单详情（代确认 / 改状态）、
// 代下单、批发商（审核、佣金比例、创始会员、WhatsApp 同意）、代管商品、订阅、佣金报表（CSV、PDF、账单）、操作记录。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_admin/features/commission/invoice_pdf.dart';

import 'harness.dart';

const _a = '00000000-0000-4000-a000-00000000000a';
const _b = '00000000-0000-4000-a000-00000000000b';
const _c = '00000000-0000-4000-a000-00000000000c';
const _d = '00000000-0000-4000-a000-00000000000d';

void main() {
  testWidgets('手机号 + 验证码登录 → 首页', (tester) async {
    final r = await pumpAdmin(tester, loggedIn: false);
    expect(find.text('客服登录'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone-field')), '12345');
    await tester.tap(find.byKey(const Key('send-code')));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入马来西亚手机号'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phone-field')), '012-000 0003');
    await tester.tap(find.byKey(const Key('send-code')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('sendOtp +60120000003'));
    await tester.enterText(find.byKey(const Key('otp-field')), '111111');
    await tester.tap(find.byKey(const Key('verify-code')));
    await tester.pumpAndSettle();
    expect(find.textContaining('验证码不对'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.tap(find.byKey(const Key('verify-code')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tile-unconfirmed')), findsOneWidget);
    expect(find.text('示范模式：资料是样本，按了不会真的改服务器'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('客服登录'), findsOneWidget);
  });

  testWidgets('不是客服的账号进不来', (tester) async {
    await pumpAdmin(tester, notAdmin: true);
    expect(find.text('这个账号不是客服'), findsOneWidget);
    expect(find.byKey(const Key('nav-dashboard')), findsNothing);
    await tester.tap(find.byKey(const Key('denied-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('客服登录'), findsOneWidget);
  });

  testWidgets('首页 → 待跟进：记下跟进 → 订单详情：代确认、送货、送达', (tester) async {
    final r = await pumpAdmin(tester);
    expect(find.text('超过 30 分钟没确认'), findsOneWidget);
    await tapKey(tester, 'tile-unconfirmed');
    expect(find.textContaining('打电话给批发商跟进'), findsOneWidget);
    expect(find.textContaining('上次跟进'), findsOneWidget, reason: '样本里已经跟进过一次');

    await tapKey(tester, 'followup-JHB261126-00002');
    await fillDialog(tester, '陈老板说马上确认');
    expect(r.api.calls, contains('logFollowup 陈老板说马上确认'));
    expect(find.textContaining('陈老板说马上确认'), findsOneWidget);

    await tapKey(tester, 'order-JHB261126-00002');
    expect(find.text('订单 JHB261126-00002'), findsOneWidget);
    expect(find.text('650ml 长方饭盒连盖  1 箱 × RM78.00'), findsOneWidget);
    await tapKey(tester, 'act-confirm');
    expect(r.api.calls, contains('confirmOrder 0'));
    expect(find.text('状态已更新：已确认'), findsOneWidget);
    expect(find.byKey(const Key('act-confirm')), findsNothing);
    await tapKey(tester, 'act-delivering');
    await tapKey(tester, 'act-delivered');
    expect(r.api.calls, containsAllInOrder(['setOrderStatus delivering', 'setOrderStatus delivered']));
    expect(find.byKey(const Key('act-cancel')), findsNothing, reason: '送达了不能取消');

    await goTo(tester, 'followup');
    expect(find.text('没有要跟进的单'), findsOneWidget);
  });

  testWidgets('订单详情：部分缺货、整单缺货、取消（有原因）', (tester) async {
    final r = await pumpAdmin(tester);
    await goTo(tester, 'orders');
    await tapKey(tester, 'order-JHB261126-00002');
    await tapKey(tester, 'oos-ba01567e-bca7-4a01-930e-4fd4a0ecaa8c');
    await tapKey(tester, 'act-confirm');
    expect(r.api.calls, contains('confirmOrder 1'));
    expect(find.text('状态已更新：缺货'), findsOneWidget, reason: '全部都缺货 → 缺货');

    await goTo(tester, 'orders');
    await tapKey(tester, 'order-JHB261126-00005');
    await tapKey(tester, 'act-cancel');
    await fillDialog(tester, '老板改主意');
    expect(r.api.calls, contains('setOrderStatus cancelled'));
    expect(find.textContaining('老板改主意'), findsOneWidget);
  });

  testWidgets('全部订单：按状态、来源、批发商筛选，只看没确认的，清除', (tester) async {
    await pumpAdmin(tester);
    await goTo(tester, 'orders');
    expect(find.text('共 5 张'), findsOneWidget);
    await tapKey(tester, 'status-pending');
    expect(find.text('共 2 张'), findsOneWidget);
    await tapKey(tester, 'source-admin');
    expect(find.text('共 1 张'), findsOneWidget);
    await tapKey(tester, 'filter-clear');
    expect(find.text('共 5 张'), findsOneWidget);
    await tapKey(tester, 'filter-unconfirmed');
    expect(find.text('共 1 张'), findsOneWidget);
    await tapKey(tester, 'filter-clear');

    await tapKey(tester, 'filter-wholesaler');
    await tester.tap(find.text('Demo Wholesaler B: Tebrau Packaging').last);
    await tester.pumpAndSettle();
    expect(find.text('共 1 张'), findsOneWidget);
    await tapKey(tester, 'filter-clear');

    await tapKey(tester, 'filter-from');
    await tester.tap(find.text('OK').evaluate().isEmpty ? find.text('确定').last : find.text('OK').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('从 20'), findsOneWidget, reason: '选了日期');
  });

  testWidgets('代下单：选店 → 加货 → 下单（来源是客服）', (tester) async {
    final r = await pumpAdmin(tester);
    await goTo(tester, 'place-order');
    await tapKey(tester, 'shop-阿明茶餐室');
    expect(find.text('95 平盖'), findsWidgets, reason: '购物车里本来就有 3 箱');
    // 再加一样 A 的商品（满 RM150 免运费）
    final cup = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('add-') && w is IconButton,
    );
    expect(cup, findsWidgets);
    await tester.enterText(find.byKey(const Key('offer-search')), '22安士');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(cup.first);
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('setCartItem 1'));
    await tester.enterText(find.byKey(const Key('order-note')), '老板打电话来订');
    await tapKey(tester, 'place-order');
    expect(find.text('已下单'), findsOneWidget);
    expect(r.api.calls.where((c) => c.startsWith('placeOrder ')), hasLength(1));
    await tapKey(tester, 'placed-ok');
    expect(find.text('购物车是空的'), findsOneWidget);

    await goTo(tester, 'orders');
    await tapKey(tester, 'source-admin');
    expect(find.text('共 3 张'), findsOneWidget, reason: '多了一张客服下的单');
  });

  testWidgets('代下单：未付费的店只能向免费开放的批发商下单', (tester) async {
    await pumpAdmin(tester);
    await goTo(tester, 'place-order');
    await tapKey(tester, 'shop-Kedai Runcit Siti');
    expect(find.textContaining('未付费：只能向免费开放的批发商下单'), findsOneWidget);
    expect(find.text('看不到价钱'), findsWidgets);
    await tapKey(tester, 'change-shop');
    expect(find.byKey(const Key('shop-search')), findsOneWidget);
  });

  testWidgets('批发商：审核通过、改佣金比例、创始会员、WhatsApp 同意、停权', (tester) async {
    final r = await pumpAdmin(tester);
    await tapKey(tester, 'tile-pending-wholesalers');
    expect(find.text('示范批发 D：待审核'), findsOneWidget);
    expect(find.text('Demo Pemborong C: Skudai Plastik'), findsNothing, reason: '只看待审核的');
    await tapKey(tester, 'approve-$_d');
    expect(r.api.calls, contains('setWholesalerStatus active'));
    expect(find.text('示范批发 D：待审核'), findsNothing);

    await tapKey(tester, 'ws-filter-active');
    await tapKey(tester, 'rate-$_c');
    await fillDialog(tester, '25');
    expect(find.textContaining('0% 到 20%'), findsOneWidget);
    await fillDialog(tester, '1.75');
    expect(r.api.calls, contains('setCommissionRate 0.0175'));
    expect(find.textContaining('佣金 1.75%（单独调整）'), findsOneWidget);

    await tapKey(tester, 'founding-$_c');
    expect(r.api.calls, contains('setFounding true'));
    await tapKey(tester, 'optin-$_c');
    expect(r.api.calls, contains('setOptIn true'));

    await tapKey(tester, 'suspend-$_b');
    await fillDialog(tester, '投诉太多');
    expect(r.api.calls, contains('setWholesalerStatus suspended'));
    await tapKey(tester, 'ws-filter-suspended');
    await tapKey(tester, 'reactivate-$_b');
    expect(find.text('没有批发商'), findsOneWidget);
  });

  testWidgets('代批发商管商品：改价钱、库存、下架、新增', (tester) async {
    final r = await pumpAdmin(tester);
    await goTo(tester, 'wholesalers');
    await tapKey(tester, 'products-$_a');
    expect(find.text('示范批发 A：新山包装行 的商品'), findsOneWidget);
    final first = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('edit-'),
    );
    await tester.tap(first.first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pf-price')), '90.50');
    await tester.tap(find.byKey(const Key('pf-save')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('saveProduct price_sen'), reason: '只送改了的栏');
    expect(find.textContaining('RM90.50'), findsOneWidget);

    final stock = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.endsWith('-outOfStock'),
    );
    await tester.tap(stock.first);
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('saveProduct stock_status'));

    final onSale = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('onsale-'),
    );
    await tester.tap(onSale.first);
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('saveProduct status'));

    await tapKey(tester, 'product-new');
    await tester.tap(find.byKey(const Key('pf-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('商品资料不对'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pf-name')), '新的 32oz 杯');
    await tester.enterText(find.byKey(const Key('pf-price')), '120');
    await tester.enterText(find.byKey(const Key('pf-pack')), '500');
    await tester.tap(find.byKey(const Key('pf-save')));
    await tester.pumpAndSettle();
    expect(find.text('新的 32oz 杯'), findsOneWidget);
  });

  testWidgets('订阅：延长试用、标记已付、创始价、取消', (tester) async {
    final r = await pumpAdmin(tester);
    await goTo(tester, 'subscriptions');
    expect(find.text('Kedai Runcit Siti'), findsOneWidget);
    await tapKey(tester, 'extend-Kedai Runcit Siti');
    await fillDialog(tester, '100');
    expect(find.text('天数要在 1 到 90 之间'), findsOneWidget);
    await fillDialog(tester, '5');
    expect(r.api.calls, contains('extendTrial 5'));

    await tapKey(tester, 'paid-阿明茶餐室');
    await tester.enterText(find.byKey(const Key('paid-months')), '3');
    await tester.enterText(find.byKey(const Key('paid-ref')), 'DN-123');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('markPaid 3'));
    expect(find.textContaining('RM150.00'), findsOneWidget, reason: '锁定月费 RM50 x 3 个月');

    await tapKey(tester, 'founding-阿明茶餐室');
    await tester.tap(find.byKey(const Key('founding-switch')));
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('setSubscriptionFounding false'));

    await tapKey(tester, 'cancel-阿明茶餐室');
    await fillDialog(tester, '老板说不用了');
    expect(r.api.calls, contains('cancelSubscription'));
    expect(find.byKey(const Key('cancel-阿明茶餐室')), findsNothing);

    await tapKey(tester, 'sub-founding-only');
    expect(find.text('阿明茶餐室'), findsNothing);
  });

  testWidgets('佣金报表：CSV、PDF、生成 / 发出 / 标记已付，换月份', (tester) async {
    await tester.runAsync(loadInvoiceFont);
    final r = await pumpAdmin(tester);
    await goTo(tester, 'commission');
    expect(find.text('2026-11'), findsOneWidget);
    expect(find.byKey(const Key('commission-total')), findsOneWidget);
    expect(find.text('RM5.67'), findsOneWidget);

    await tapKey(tester, 'export-csv');
    final bytes = r.saver.files['commission-2026-11.csv']!;
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM：Excel 才认得中文');
    final csv = utf8.decode(bytes);
    expect(csv, contains('月份,批发商'));
    expect(csv, contains('Demo Wholesaler B: Tebrau Packaging'));
    expect(csv.trim().split('\r\n').last, contains('合计'));
    expect(find.text('已下载 commission-2026-11.csv'), findsOneWidget);

    // 字体在上面先读好了（rootBundle 要真的读档），做 PDF 本身不用等
    await tapKey(tester, 'pdf-$_b');
    final pdf = r.saver.files.entries.firstWhere((e) => e.key.endsWith('.pdf'));
    expect(pdf.key, 'invoice-2026-11-00000000.pdf');
    expect(String.fromCharCodes(pdf.value.take(5)), '%PDF-');

    await tapKey(tester, 'generate-invoices');
    expect(find.text('生成 / 更新了 2 张草稿账单'), findsOneWidget);
    await tapKey(tester, 'issue-$_b');
    await tapKey(tester, 'invpaid-$_b');
    await fillDialog(tester, 'FPX-77');
    expect(r.api.calls, containsAllInOrder(['generateInvoices', 'issueInvoice', 'markInvoicePaid']));
    expect(find.textContaining('已付'), findsOneWidget);

    await tapKey(tester, 'prev-month');
    expect(find.text('2026-10'), findsOneWidget);
    expect(find.text('这个月还没有送达的订单'), findsOneWidget);
  });

  testWidgets('操作记录：客服做的事都看得到', (tester) async {
    final r = await pumpAdmin(tester);
    await goTo(tester, 'wholesalers');
    await tapKey(tester, 'approve-$_d');
    await goTo(tester, 'audit');
    expect(find.text('审核 / 停权'), findsOneWidget, reason: '刚刚的审核');
    expect(find.text('代下单'), findsWidgets);
    await tester.tap(find.text('审核 / 停权'));
    await tester.pumpAndSettle();
    expect(find.textContaining('status: pending  →  active'), findsOneWidget);
    await tapKey(tester, 'audit-admin-only');
    expect(find.text('新增'), findsWidgets, reason: '也看到表的逐行记录');
    expect(r.api.calls.where((c) => c == 'listAuditLogs'), hasLength(2));
  });

  testWidgets('换语言：English / Bahasa Melayu', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('All orders'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bahasa Melayu').last);
    await tester.pumpAndSettle();
    expect(find.text('Semua pesanan'), findsOneWidget);
  });

  for (final (name, size) in [('平板', tablet), ('电脑', desktop)]) {
    for (final lang in ['zh', 'en', 'ms']) {
      testWidgets('$name 宽度（$lang）：每一页都不会超出画面', (tester) async {
        await pumpAdmin(tester, size: size, locale: lang);
        for (final page in [
          'dashboard',
          'orders',
          'followup',
          'place-order',
          'wholesalers',
          'subscriptions',
          'commission',
          'audit',
        ]) {
          await goTo(tester, page);
          expect(tester.takeException(), isNull, reason: page);
        }
        await goTo(tester, 'place-order');
        await tapKey(tester, 'shop-阿明茶餐室');
        expect(tester.takeException(), isNull, reason: '代下单（选了店）');
        await goTo(tester, 'orders');
        await tapKey(tester, 'order-JHB261126-00002');
        expect(tester.takeException(), isNull, reason: '订单详情');
        await goTo(tester, 'wholesalers');
        await tapKey(tester, 'products-$_a');
        expect(tester.takeException(), isNull, reason: '商品');
      });
    }
  }
}
