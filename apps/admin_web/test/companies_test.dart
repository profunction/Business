// 第八步：客服后台的「公司」：列表、搜索、详情（资料、方案、分店、成员和邀请、账单）、设方案 / 自订价、延长试用、
// 开账单、标记已付、停权 / 恢复。样本是本机数据库导出的（apps/procure_web/tool/export_fixtures.sh）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _co = 'Grand Hotel Johor Bahru';

void main() {
  for (final size in [desktop, tablet]) {
    testWidgets('公司列表 → 详情（${size.width.toInt()} 宽）', (tester) async {
      final r = await pumpAdmin(tester, size: size);
      await goTo(tester, 'companies');
      expect(find.text(_co), findsOneWidget);
      expect(find.text('试用 · 试用中'), findsOneWidget);
      expect(find.textContaining('RM790.00'), findsOneWidget, reason: '没付的第一期账单');
      await tester.enterText(find.byKey(const Key('co-search')), 'nothing here');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('没有公司'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('co-search')), '1234567x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tapKey(tester, 'co-$_co');
      expect(r.api.calls, contains('getCompany'));
      expect(find.textContaining('Grand Hotel JB Sdn Bhd'), findsOneWidget);
      expect(find.text('Grand Hotel 中央厨房 (CK)'), findsOneWidget);
      expect(find.text('Rajesh Kumar'), findsOneWidget);
      expect(find.text('还没接受的邀请'), findsOneWidget);
      expect(find.textContaining('012-333 4444'), findsOneWidget);
      expect(find.textContaining('下一期换成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('设方案（企业版要自订价）、标记已付、停权要写原因', (tester) async {
    final r = await pumpAdmin(tester);
    await goTo(tester, 'companies');
    await tapKey(tester, 'co-$_co');

    await tapKey(tester, 'co-set-plan');
    await tester.tap(find.byKey(const Key('co-plan-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('企业版').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('金额不对'), findsOneWidget, reason: '企业方案一定要给价钱');
    await tester.enterText(find.byKey(const Key('co-price-field')), '2,500');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('setCompanyPlan co_enterprise monthly 250000'));
    expect(find.text('自订价'), findsOneWidget);
    expect(find.textContaining('RM2,500.00'), findsWidgets, reason: '没付的账单照新价钱重开');

    final paid = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('co-paid-'),
    );
    await tester.ensureVisible(paid.first);
    await tester.tap(paid.first);
    await tester.pumpAndSettle();
    await fillDialog(tester, 'BANK-2026-001');
    expect(r.api.calls, contains('markCompanyInvoicePaid'));
    expect(find.text('有效'), findsOneWidget);
    expect(find.textContaining('现金 / 其他'), findsOneWidget, reason: '付款记录');

    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tapKey(tester, 'co-status');
    await fillDialog(tester, '');
    expect(find.text('请写跟进内容'), findsOneWidget, reason: '停权要写原因（INVALID_NOTE）');
    await tapKey(tester, 'co-status');
    await fillDialog(tester, '账单争议');
    expect(find.text('已停权：账单争议'), findsOneWidget);
    await tapKey(tester, 'co-status');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('恢复'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('延长试用、开账单（已经有没付的就拿回那一张）、英文', (tester) async {
    final r = await pumpAdmin(tester, locale: 'en');
    await goTo(tester, 'companies');
    expect(find.text('Trial · Trial'), findsOneWidget);
    await tapKey(tester, 'co-$_co');
    await tapKey(tester, 'co-extend-trial');
    await fillDialog(tester, '200');
    expect(find.text('Days must be 1–90'), findsOneWidget);
    await fillDialog(tester, '10');
    expect(r.api.calls, contains('extendCompanyTrial 10'));
    await tapKey(tester, 'co-issue-invoice');
    expect(r.api.calls, contains('issueCompanyInvoice'));
    expect(find.text('Invoice issued'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
