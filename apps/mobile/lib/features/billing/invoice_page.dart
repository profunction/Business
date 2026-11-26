import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/billing_config.dart';
import '../../app/l10n_x.dart';
import '../../app/seller_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common.dart';
import '../seller/seller_device.dart';
import 'payment_flow.dart';

/// 一张佣金账单：每张单一行（货价不含运费 x 比例）、付款、印 / 存 PDF
class InvoicePage extends ConsumerStatefulWidget {
  const InvoicePage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends ConsumerState<InvoicePage> with PaymentFlow {
  bool _printing = false;

  @override
  void onPaid() {
    ref.invalidate(invoiceDetailProvider(widget.invoiceId));
    ref.invalidate(sellerBillingProvider);
  }

  Future<void> _print(InvoiceDetail d) async {
    final l = context.l10n;
    setState(() => _printing = true);
    try {
      await ref
          .read(sellerDeviceProvider)
          .printPdf(
            name: 'invoice-${d.invoice.invoiceNo}.pdf',
            build: (format) async =>
                buildSellerInvoicePdf(d, l, font: await PdfGoogleFonts.notoSansSCRegular(), format: format),
          );
    } catch (_) {
      if (mounted) showMessage(context, l.sellerSummaryPrintFailed, error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final detail = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final canPay = ref.watch(billingPolicyProvider).sellerCanPay;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.invoiceTitle),
        actions: [
          if (detail.hasValue)
            IconButton(
              key: const Key('invoice-print'),
              tooltip: l.invoicePdf,
              icon: _printing ? const CircularProgressIndicator() : const Icon(Icons.picture_as_pdf, size: 30),
              onPressed: _printing ? null : () => _print(detail.requireValue),
            ),
        ],
      ),
      body: AsyncView<InvoiceDetail>(
        value: detail,
        onRetry: () => ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
        builder: (d) {
          final i = d.invoice;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${i.periodMonth == null ? '' : l.month(i.periodMonth!)}  ${i.invoiceNo}', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  l.invoiceStatus(i.status),
                  if (i.dueDate != null && i.isOutstanding) l.invoiceDue(l.date(i.dueDate!)),
                  if (i.paidAt != null) l.invoicePaidOn(l.dateOnly(i.paidAt!)),
                ].join(' · '),
                key: const Key('invoice-status'),
                style: t.titleMedium?.copyWith(color: i.status == 'overdue' ? Colors.red.shade700 : null),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AmountRow(label: l.sellerThisMonthOrders, value: '${i.orderCount}'),
                      AmountRow(label: l.sellerThisMonthGoods, value: formatRm(i.gmvSen)),
                      AmountRow(label: l.invoiceCommission, value: formatRm(i.commissionSen), bold: true),
                    ],
                  ),
                ),
              ),
              if (d.canPay && canPay) ...[
                const SizedBox(height: 12),
                BusyButton(
                  key: const Key('pay-invoice'),
                  label: l.payButton(formatRm(i.commissionSen)),
                  icon: Icons.payment,
                  busy: paying,
                  onPressed: () => startPayment(PaymentPurpose.commissionInvoice, i.id),
                ),
                const SizedBox(height: 4),
                Text(l.payMethodsNote, style: t.bodyMedium?.copyWith(color: Colors.black54)),
                if (pendingPaymentId != null)
                  TextButton(key: const Key('pay-check'), onPressed: checkPendingPayment, child: Text(l.payCheck)),
              ],
              const SizedBox(height: 16),
              Text(l.invoiceLines, style: t.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final line in d.lines)
                      ListTile(
                        title: Text('${line.orderNo}  ${line.shopName}'),
                        subtitle: Text(
                          l.invoiceLineText(formatRm(line.baseAmountSen), formatRate(line.rate)) +
                              (line.deliveredAt == null ? '' : ' · ${l.dateOnly(line.deliveredAt!)}'),
                        ),
                        trailing: Text(formatRm(line.commissionSen), style: t.titleMedium),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 账单的 PDF（A4）：批发商资料、月份、每张单一行、合计。字体要有中文（NotoSansSC）
Future<Uint8List> buildSellerInvoicePdf(
  InvoiceDetail d,
  L10n l, {
  required pw.Font font,
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final i = d.invoice;
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
    title: '${l.invoiceTitle} ${i.invoiceNo}',
    creator: l.appTitle,
  );
  const small = pw.TextStyle(fontSize: 9);
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text('${l.invoiceTitle}  ${i.invoiceNo}', style: const pw.TextStyle(fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text(
          [
            if (i.periodMonth != null) l.month(i.periodMonth!),
            l.invoiceStatus(i.status),
            if (i.dueDate != null) l.invoiceDue(l.date(i.dueDate!)),
          ].join('  ·  '),
        ),
        pw.SizedBox(height: 10),
        pw.Text(d.billingName),
        if (d.ssmNo != null) pw.Text('SSM ${d.ssmNo}', style: small),
        if (d.billingAddress != null) pw.Text(d.billingAddress!, style: small),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: [l.invoiceColOrder, l.invoiceColShop, l.invoiceColGoods, l.invoiceColRate, l.invoiceCommission],
          data: [
            for (final line in d.lines)
              [
                line.orderNo,
                line.shopName,
                formatRm(line.baseAmountSen),
                formatRate(line.rate),
                formatRm(line.commissionSen),
              ],
          ],
          cellStyle: small,
          headerStyle: small,
          cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('${l.sellerThisMonthGoods}: ${formatRm(i.gmvSen)}'),
              pw.Text('${l.invoiceCommission}: ${formatRm(i.commissionSen)}', style: const pw.TextStyle(fontSize: 13)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(l.sellerCommissionRule, style: small),
      ],
    ),
  );
  return doc.save();
}
