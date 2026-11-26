import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/config.dart';
import '../../app/l10n_x.dart';
import '../../l10n/app_localizations.dart';

pw.Font? _font;

/// 账单用的中文字体（assets/fonts/NotoSansSC-Regular.ttf，跟手机 App 的送货单一样）。PDF 只放用到的字
Future<pw.Font> loadInvoiceFont() async =>
    _font ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');

/// 'invoice-2026-11-INV2611-0007.pdf'（还没开账单：用批发商 id 的前 8 个字）
String invoiceFileName(CommissionReport r, WholesalerCommission w) =>
    'invoice-${r.periodLabel}-${_safe(w.invoice?.invoiceNo ?? w.wholesalerId.split('-').first)}.pdf';

String csvFileName(CommissionReport r) => 'commission-${r.periodLabel}.csv';

/// 一家批发商一个月的佣金账单（A4）。还没发出的印「草稿」；公司资料没设定就印「公司资料未设定」
Future<Uint8List> buildInvoicePdf({
  required CommissionReport report,
  required WholesalerCommission w,
  required InvoiceCompany company,
  required L10n l,
  pw.Font? font,
}) async {
  final f = font ?? await loadInvoiceFont();
  final doc = pw.Document(title: '${l.pdfInvoiceTitle} ${report.periodLabel} ${w.name}', author: company.name);
  final inv = w.invoice;
  final small = const pw.TextStyle(fontSize: 9);
  final grey = PdfColor.fromInt(0xFF666666);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(base: f, bold: f),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  company.isConfigured ? company.name : l.pdfCompanyNotConfigured,
                  style: const pw.TextStyle(fontSize: 14),
                ),
                if (company.ssmNo.isNotEmpty) pw.Text('SSM ${company.ssmNo}', style: small),
                if (company.address.isNotEmpty) pw.Text(company.address, style: small),
                if (company.email.isNotEmpty) pw.Text(company.email, style: small),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(l.pdfInvoiceTitle, style: const pw.TextStyle(fontSize: 20)),
                pw.Text('${l.pdfInvoiceNo}: ${inv?.invoiceNo ?? '-'}'),
                pw.Text('${l.colPeriod}: ${report.periodLabel}'),
                if (inv?.dueDate != null) pw.Text('${l.pdfDueDate}: ${fmtDay(inv!.dueDate)}'),
                if (inv == null || inv.status == 'draft')
                  pw.Text(l.pdfDraft, style: pw.TextStyle(color: PdfColors.red800)),
                if (inv != null && inv.status != 'draft') pw.Text(l.invoiceStatus(inv.status)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(l.pdfBillTo, style: pw.TextStyle(color: grey)),
        pw.Text(w.billingName, style: const pw.TextStyle(fontSize: 13)),
        if (w.billingAddress != null) pw.Text(w.billingAddress!, style: small),
        if (w.billingEmail != null) pw.Text(w.billingEmail!, style: small),
        if (w.ssmNo != null) pw.Text('SSM ${w.ssmNo}', style: small),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headerStyle: const pw.TextStyle(fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
          headers: [l.colOrderNo, l.colShop, l.pdfDelivered, l.colGmv, l.colRate, l.colCommission],
          data: [
            for (final o in w.orders)
              [
                o.orderNo,
                o.shopName,
                fmtDateTime(o.deliveredAt),
                formatRm(o.baseAmountSen),
                formatRate(o.rate),
                formatRm(o.commissionSen),
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('${l.colOrders}: ${w.orderCount}'),
              pw.Text('${l.colGmv}: ${formatRm(w.gmvSen)}'),
              pw.Text('${l.pdfTotalDue}: ${formatRm(w.commissionSen)}', style: const pw.TextStyle(fontSize: 14)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(l.pdfNote, style: pw.TextStyle(fontSize: 9, color: grey)),
        if (company.bankDetails.isNotEmpty) pw.Text(company.bankDetails, style: small),
      ],
    ),
  );
  return doc.save();
}
