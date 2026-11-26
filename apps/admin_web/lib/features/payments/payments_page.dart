import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 付款记录：网关（HitPay）收到的、客服手动记的。「要处理」= 收到钱但不能照常处理（金额不对、账单已经付过、
/// 创始名额刚好满了……），要客服退款或补登
class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  PaymentPurpose? _purpose;
  bool _reviewOnly = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final q = (purpose: _purpose, reviewOnly: _reviewOnly);
    final value = ref.watch(paymentsProvider(q));
    return ListView(
      children: [
        PageHeader(title: l.navPayments),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<PaymentPurpose?>(
                key: const Key('pay-purpose-filter'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: null, label: Text(l.all)),
                  for (final p in PaymentPurpose.values)
                    ButtonSegment(
                      value: p,
                      label: Text(l.paymentPurpose(p), key: Key('pay-filter-${p.name}')),
                    ),
                ],
                selected: {_purpose},
                onSelectionChanged: (s) => setState(() => _purpose = s.first),
              ),
              FilterChip(
                key: const Key('pay-review-only'),
                label: Text(l.payReviewOnly),
                selected: _reviewOnly,
                onSelected: (v) => setState(() => _reviewOnly = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(paymentsProvider(q)),
          builder: (list) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.paymentsEmpty)),
                  )
                : Card(
                    child: Column(
                      children: [
                        for (final p in list) ...[_PaymentRow(p: p), const Divider(height: 1)],
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

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.p});

  final PaymentInfo p;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (p.status) {
      PaymentStatus.paid => const Color(0xFF2E7D32),
      PaymentStatus.pending => const Color(0xFFB26A00),
      _ => scheme.error,
    };
    return Padding(
      key: Key('payment-${p.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.payerName ?? '-', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  [
                    l.paymentPurpose(p.purpose),
                    if (p.invoiceNo != null) p.invoiceNo!,
                    if (p.months != null) l.monthsN(p.months!),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(formatRm(p.amountSen), style: Theme.of(context).textTheme.titleMedium),
          Tag(l.paymentStatus(p.status), color: color),
          if (p.reviewReason != null) Tag(l.payNeedsReview(p.reviewReason!), color: scheme.error),
          InfoLine(l.colMethod, [if (p.method != null) l.method(p.method!), p.gateway ?? ''].join(' · ')),
          if (p.gatewayRef != null) InfoLine(l.colReference, p.gatewayRef!),
          InfoLine(l.colTime, fmtDateTime(p.paidAt ?? p.createdAt)),
          if (p.failureReason != null) Text(p.failureReason!, style: TextStyle(color: scheme.error)),
        ],
      ),
    );
  }
}
