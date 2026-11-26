// 第六步：客服后台的「WhatsApp 订单」：列表 → 一张 → 改草稿（数量、删掉、加商品）→ 代老板下单；
// AI 没做好的语音 → 不处理（WhatsApp 回原因）。样本是本机数据库导出的（tool/export_draft_fixtures.sh）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Finder _queueRow(String text) => find.ancestor(of: find.textContaining(text), matching: find.byType(ListTile));

void main() {
  for (final size in [desktop, tablet]) {
    testWidgets('WhatsApp 订单：改草稿、代老板下单、不处理（${size.width.toInt()} 宽）', (tester) async {
      final r = await pumpAdmin(tester, size: size);
      await goTo(tester, 'whatsapp-orders');
      expect(find.text('WhatsApp 订单'), findsWidgets);
      expect(find.textContaining('Kedai Runcit Siti'), findsOneWidget);
      expect(find.text('AI 没做好'), findsOneWidget, reason: '语音没转成文字');

      // Siti 的文字订单：3 盒饭盒
      await tester.tap(_queueRow('Kedai Runcit Siti').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wa-text')), findsOneWidget);
      expect(find.text('Salam boss, nak 3 kotak bekas 650ml esok pagi'), findsOneWidget);
      expect(find.text('24 小时内：可以用 WhatsApp 回'), findsOneWidget);
      expect(find.textContaining('650ml 长方饭盒连盖'), findsWidgets);
      await tapKey(tester, 'wa-plus-0');
      expect(r.api.calls, contains('saveOrderDraft'));
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('4 ')), findsOneWidget);

      // 搜商品、加一样
      await tester.enterText(find.byKey(const Key('wa-search')), '平盖');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final add = find.byWidgetPredicate((w) => w is ListTile && '${w.key}'.contains('wa-add-')).first;
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wa-item-1')), findsOneWidget);

      final submit = find.byKey(const Key('wa-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(r.api.calls.any((c) => c.startsWith('submitOrderDraft ')), isTrue);
      expect(find.text('已经下单：JHB261129-00041'), findsOneWidget);
      expect(find.textContaining('Kedai Runcit Siti'), findsNothing, reason: '处理完就不在列表里');

      // 阿明的语音（AI 没做好）：不处理，写原因
      await tester.tap(_queueRow('阿明茶餐室').first);
      await tester.pumpAndSettle();
      expect(find.text('（没有文字：语音没转成文字）'), findsWidgets);
      expect(tester.widget<FilledButton>(find.byKey(const Key('wa-submit'))).onPressed, isNull, reason: '没有商品');
      await tapKey(tester, 'wa-reject');
      await fillDialog(tester, '请打电话来订');
      expect(r.api.calls, contains('rejectOrderDraft 请打电话来订'));
      expect(find.text('现在没有要处理的 WhatsApp 订单'), findsOneWidget);

      // 操作记录
      await goTo(tester, 'audit');
      expect(find.textContaining('代老板送出 WhatsApp 订单'), findsWidgets);
    });
  }

  for (final locale in ['en', 'ms']) {
    testWidgets('WhatsApp 订单（$locale）', (tester) async {
      await pumpAdmin(tester, locale: locale);
      await goTo(tester, 'whatsapp-orders');
      expect(find.text(locale == 'en' ? 'WhatsApp orders' : 'Pesanan WhatsApp'), findsWidgets);
      await tester.tap(_queueRow('Kedai Runcit Siti').first);
      await tester.pumpAndSettle();
      expect(
        find.text(locale == 'en' ? 'Within 24 h: can reply on WhatsApp' : 'Dalam 24 jam: boleh balas di WhatsApp'),
        findsOneWidget,
      );
      expect(
        find.textContaining(locale == 'en' ? 'Place order for shop RM' : 'Buat pesanan untuk kedai RM'),
        findsOneWidget,
      );
    });
  }
}
