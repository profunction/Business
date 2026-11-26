import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/billing_config.dart';
import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common.dart';
import 'payment_flow.dart';

/// 买家「我的订阅」：现在的状态、试用 / 这期还剩几天、锁定的月费、付过的。
/// 付款按钮只在 [BillingPolicy.buyerCanPay] 时出现（商店版本默认没有，见 billing_config.dart）
class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> with PaymentFlow {
  int _months = 1;

  @override
  void onPaid() {
    ref.invalidate(buyerBillingProvider);
    ref.invalidate(subscriptionProvider);
    ref.invalidate(buyerHomeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final billing = ref.watch(buyerBillingProvider);
    final canPay = ref.watch(billingPolicyProvider).buyerCanPay;
    return Scaffold(
      appBar: AppBar(title: Text(l.subscription)),
      body: AsyncView<BuyerBilling>(
        value: billing,
        onRetry: () => ref.invalidate(buyerBillingProvider),
        builder: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(buyerBillingProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(b: b),
              if (!b.status.hasFullAccess) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => context.push('/free-wholesalers'), child: Text(l.chooseWholesalers)),
              ],
              if (canPay) ...[const SizedBox(height: 16), _payCard(l, b)],
              if (b.payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(l.payHistory, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final p in b.payments)
                        ListTile(
                          leading: const Icon(Icons.receipt_long, size: 30),
                          title: Text(formatRm(p.amountSen)),
                          subtitle: Text(
                            [
                              if (p.paidAt != null) l.dateOnly(p.paidAt!),
                              l.paymentMethod(p.method),
                              if (p.months != null) l.payMonths(p.months!),
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _payCard(L10n l, BuyerBilling b) {
    final t = Theme.of(context).textTheme;
    final total = b.renewPriceSen * _months;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.payChooseMonths, style: t.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in b.monthOptions)
                  ChoiceChip(
                    key: Key('months-$m'),
                    label: Text(l.payMonths(m), style: t.titleMedium),
                    selected: _months == m,
                    onSelected: (_) => setState(() => _months = m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AmountRow(label: l.payTotal, value: formatRm(total), bold: true),
            const SizedBox(height: 4),
            Text(l.payMethodsNote, style: t.bodyMedium?.copyWith(color: Colors.black54)),
            const SizedBox(height: 12),
            BusyButton(
              key: const Key('pay-subscription'),
              label: l.payButton(formatRm(total)),
              icon: Icons.payment,
              busy: paying,
              onPressed: () => startPayment(PaymentPurpose.subscription, ref.read(shopIdProvider), months: _months),
            ),
            if (pendingPaymentId != null) ...[
              const SizedBox(height: 8),
              TextButton(key: const Key('pay-check'), onPressed: checkPendingPayment, child: Text(l.payCheck)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.b});

  final BuyerBilling b;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final s = b.status;
    final (title, color) = switch (s.state) {
      SubscriptionState.trialing when s.hasFullAccess => (l.billTrial(b.daysLeft ?? 0), AppTheme.successBg),
      SubscriptionState.active => (l.billActive, AppTheme.successBg),
      SubscriptionState.pastDue => (l.billPastDue, AppTheme.warningBg),
      _ => (l.subFree, AppTheme.warningBg),
    };
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, key: const Key('sub-title'), style: t.headlineSmall),
            const SizedBox(height: 8),
            if (b.accessUntil != null)
              InfoLine(
                icon: Icons.event,
                text: s.state == SubscriptionState.pastDue
                    ? l.billGraceUntil(l.dateOnly(b.accessUntil!))
                    : l.billUntil(l.dateOnly(b.accessUntil!), b.daysLeft ?? 0),
              ),
            if (b.priceLocked)
              InfoLine(icon: Icons.lock, text: l.lockedPrice(formatRm(b.renewPriceSen)))
            else
              InfoLine(icon: Icons.sell, text: l.billCurrentPrice(formatRm(b.renewPriceSen))),
            if (!s.hasFullAccess) InfoLine(icon: Icons.lock_open, text: l.freeBanner(s.freeUnlockedLimit)),
          ],
        ),
      ),
    );
  }
}
