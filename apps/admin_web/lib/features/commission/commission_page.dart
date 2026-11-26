import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_link.dart';
import 'invoice_pdf.dart';

/// 这个月（马来西亚时间）的 1 号
DateTime currentMonth([DateTime? now]) {
  final m = myt(now ?? DateTime.now());
  return DateTime(m.year, m.month);
}

/// 每月佣金报表：每家批发商这个月已送达的货价（不含运费）和应付佣金。
/// 导出：全部一个 CSV；每家一份 PDF 账单。账单：生成草稿 → 发出 → 标记已付
class CommissionPage extends ConsumerStatefulWidget {
  const CommissionPage({super.key});

  @override
  ConsumerState<CommissionPage> createState() => _CommissionPageState();
}

class _CommissionPageState extends ConsumerState<CommissionPage> {
  DateTime _month = currentMonth();

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  void _refresh() {
    ref.invalidate(commissionReportProvider(_month));
    ref.invalidate(dashboardProvider);
  }

  Future<void> _save(String name, List<int> bytes, String mime) async {
    final l = context.l10n;
    final ok = await ref.read(fileSaverProvider).save(name, Uint8List.fromList(bytes), mime);
    if (mounted) showSnack(context, ok ? l.exported(name) : l.exportUnsupported);
  }

  Future<void> _csv(CommissionReport r) async {
    final l = context.l10n;
    final csv = commissionReportCsv(
      r,
      headers: [
        l.colPeriod,
        l.colWholesaler,
        l.colBillingName,
        l.colSsm,
        l.colEmail,
        l.colOrders,
        '${l.colGmv} (RM)',
        l.colRate,
        '${l.colCommission} (RM)',
        l.colInvoice,
        l.colInvoiceStatus,
      ],
      totalLabel: l.commissionTotal,
    );
    await _save(csvFileName(r), utf8.encode(csv), 'text/csv;charset=utf-8');
  }

  Future<void> _pdf(CommissionReport r, WholesalerCommission w) async {
    try {
      final bytes = await buildInvoicePdf(report: r, w: w, company: ref.read(invoiceCompanyProvider), l: context.l10n);
      await _save(invoiceFileName(r, w), bytes, 'application/pdf');
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.error(e));
    }
  }

  Future<void> _generate() async {
    final l = context.l10n;
    var count = 0;
    final ok = await runAction(context, () async => count = await ref.read(apiProvider).generateInvoices(_month));
    if (ok && mounted) {
      showSnack(context, l.invoicesGenerated(count));
      _refresh();
    }
  }

  Future<void> _invoice(Future<Object?> Function() action) async {
    final ok = await runAction(context, action, success: context.l10n.saved);
    if (ok) _refresh();
  }

  Future<void> _markPaid(CommissionInvoice inv) async {
    final l = context.l10n;
    final reference = await showInputDialog(
      context,
      title: '${l.markInvoicePaid} · ${inv.invoiceNo}',
      label: l.subReferenceLabel,
    );
    if (reference == null) return;
    await _invoice(
      () => ref
          .read(apiProvider)
          .markInvoicePaid(inv.id, method: PaymentMethod.other, reference: reference.trim().isEmpty ? null : reference),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(commissionReportProvider(_month));
    final report = value.value;
    return ListView(
      children: [
        PageHeader(
          title: l.navCommission,
          subtitle: l.commissionHint,
          actions: [
            FilledButton.icon(
              key: const Key('export-csv'),
              onPressed: report == null ? null : () => _csv(report),
              icon: const Icon(Icons.table_view),
              label: Text(l.exportCsv),
            ),
            OutlinedButton.icon(
              key: const Key('generate-invoices'),
              onPressed: _generate,
              icon: const Icon(Icons.receipt),
              label: Text(l.generateInvoices),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              IconButton(
                key: const Key('prev-month'),
                tooltip: l.prevMonth,
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(fmtMonth(_month), key: const Key('month-label'), style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                key: const Key('next-month'),
                tooltip: l.nextMonth,
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        AsyncBody(
          value: value,
          onRetry: _refresh,
          builder: (r) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: r.wholesalers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.commissionEmpty)),
                  )
                : Card(
                    child: Column(
                      children: [
                        for (final w in r.wholesalers) ...[
                          _Row(
                            w: w,
                            onPdf: () => _pdf(r, w),
                            onIssue: w.invoice?.status == 'draft'
                                ? () => _invoice(() => ref.read(apiProvider).issueInvoice(w.invoice!.id))
                                : null,
                            onPaid: w.invoice != null && const {'issued', 'overdue'}.contains(w.invoice!.status)
                                ? () => _markPaid(w.invoice!)
                                : null,
                            onPayLink: w.invoice != null && w.invoice!.isOutstanding && w.invoice!.commissionSen > 0
                                ? () => showPaymentLink(
                                    context,
                                    ref,
                                    PaymentPurpose.commissionInvoice,
                                    w.invoice!.id,
                                    title: '${w.name} ${w.invoice!.invoiceNo}',
                                  )
                                : null,
                          ),
                          const Divider(height: 1),
                        ],
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(l.commissionTotal, style: Theme.of(context).textTheme.titleMedium),
                              InfoLine(l.colOrders, '${r.orderCount}'),
                              InfoLine(l.colGmv, formatRm(r.gmvSen)),
                              Text(
                                formatRm(r.commissionSen),
                                key: const Key('commission-total'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.w, required this.onPdf, this.onIssue, this.onPaid, this.onPayLink});

  final WholesalerCommission w;
  final VoidCallback onPdf;
  final VoidCallback? onIssue;
  final VoidCallback? onPaid;
  final VoidCallback? onPayLink;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inv = w.invoice;
    return Padding(
      key: Key('commission-${w.wholesalerId}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  inv == null ? l.invoiceNone : '${inv.invoiceNo} · ${l.invoiceStatus(inv.status)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 16,
            children: [
              InfoLine(l.colOrders, '${w.orderCount}'),
              InfoLine(l.colGmv, formatRm(w.gmvSen)),
              InfoLine(l.colRate, w.rateText),
              InfoLine(l.colCommission, formatRm(w.commissionSen)),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: Key('pdf-${w.wholesalerId}'),
                onPressed: onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(l.exportPdf),
              ),
              if (onIssue != null)
                FilledButton.tonal(
                  key: Key('issue-${w.wholesalerId}'),
                  onPressed: onIssue,
                  child: Text(l.issueInvoice),
                ),
              if (onPaid != null)
                FilledButton.tonal(
                  key: Key('invpaid-${w.wholesalerId}'),
                  onPressed: onPaid,
                  child: Text(l.markInvoicePaid),
                ),
              if (onPayLink != null)
                OutlinedButton.icon(
                  key: Key('invlink-${w.wholesalerId}'),
                  onPressed: onPayLink,
                  icon: const Icon(Icons.link),
                  label: Text(l.payLink),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
