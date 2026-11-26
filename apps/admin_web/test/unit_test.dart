import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_admin/app/config.dart';
import 'package:jb_admin/app/l10n_x.dart';
import 'package:jb_admin/features/commission/commission_page.dart';
import 'package:jb_admin/features/commission/invoice_pdf.dart';
import 'package:jb_admin/features/wholesalers/wholesalers_page.dart';
import 'package:jb_admin/l10n/app_localizations.dart';
import 'package:wholesale_core/wholesale_core.dart';

void main() {
  test('三个语言的 ARB 键一样', () {
    Set<String> keys(String lang) =>
        (jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>).keys
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(keys('en'), keys('zh'));
    expect(keys('ms'), keys('zh'));
  });

  test('佣金比例输入：% → 小数', () {
    expect(parsePercent('1.5'), 0.015);
    expect(parsePercent('1.15%'), 0.0115);
    expect(parsePercent('0'), 0);
    expect(parsePercent('20'), 0.2);
    expect(parsePercent('20.5'), isNull);
    expect(parsePercent('1.234'), isNull);
    expect(parsePercent('abc'), isNull);
  });

  test('马来西亚时间', () {
    expect(fmtDateTime(DateTime.utc(2026, 11, 30, 17, 5)), '2026-12-01 01:05');
    expect(currentMonth(DateTime.utc(2026, 11, 30, 17)), DateTime(2026, 12));
  });

  testWidgets('账单 PDF：公司资料没设定也做得出来；档名', (tester) async {
    final report = CommissionReport.fromJson(
      jsonDecode(File('../../packages/core/test/fixtures/admin_commission_report.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final l = await L10n.delegate.load(const Locale('zh'));
    final bytes = await tester.runAsync(
      () => buildInvoicePdf(report: report, w: report.wholesalers.first, company: const InvoiceCompany(), l: l),
    );
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes.length, lessThan(2000000), reason: '字体只放用到的字');
    expect(invoiceFileName(report, report.wholesalers.first), 'invoice-2026-11-00000000.pdf');
    expect(csvFileName(report), 'commission-2026-11.csv');
    expect(const InvoiceCompany().isConfigured, isFalse);
  });
}
