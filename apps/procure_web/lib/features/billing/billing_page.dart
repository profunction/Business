import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/company_scope.dart';

/// 方案和付款（admin、finance）：现在的方案、换方案（admin，下一期生效、价钱照今天锁定）、账单（付款 → HitPay 新分页）、付款记录。
/// 公司方案只在这里（网页）付；手机 App 不卖（docs/08-procurement-spec.md 第 11 节）
class BillingPage extends ConsumerStatefulWidget {
  const BillingPage({super.key});

  @override
  ConsumerState<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends ConsumerState<BillingPage> {
  BillingCycle? _cycle;

  Future<void> _choose(CompanyContext c, CompanyPlan p, BillingCycle cycle) async {
    final l = context.l10n;
    final price = p.priceFor(cycle);
    if (price == null) return;
    final ok = await showConfirmDialog(
      context,
      title: l.billingChooseTitle(l.planName(p.code)),
      body: l.billingChooseBody(formatRm(price), l.perCycle(cycle)),
    );
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => ref.read(apiProvider).changePlan(c.company.id, p.code, cycle),
      success: l.billingPlanChanged,
    );
    if (done) refreshCompany(ref, c.company.id);
  }

  Future<void> _pay(CompanyContext c, CompanyInvoice i) async {
    final l = context.l10n;
    PaymentCheckout? checkout;
    final ok = await runAction(context, () async => checkout = await ref.read(apiProvider).payCompanyInvoice(i.id));
    if (!ok || checkout == null || !mounted) return;
    final url = checkout!.checkoutUrl;
    final opened = await ref.read(urlOpenerProvider).open(url);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.billingPayTitle(i.invoiceNo)),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.billingPayAmount(formatRm(checkout!.amountSen))),
              const SizedBox(height: 8),
              Text(opened ? l.billingPayOpened : l.billingPayOpenThis),
              const SizedBox(height: 8),
              SelectableText(url, key: const Key('pay-url')),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('pay-done'),
            onPressed: () {
              Navigator.pop(context);
              refreshCompany(ref, c.company.id);
            },
            child: Text(l.billingPaidRefresh),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return CompanyScope(
      builder: (context, c) {
        if (!c.canSeeBilling) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(l.errNotAllowed)),
          );
        }
        return AsyncBody(
          value: ref.watch(billingProvider(c.company.id)),
          onRetry: () => ref.invalidate(billingProvider(c.company.id)),
          builder: (b) {
            final sub = b.subscription;
            final cycle = _cycle ?? sub?.pendingCycle ?? sub?.cycle ?? BillingCycle.monthly;
            return ListView(
              children: [
                PageHeader(title: l.navBilling, subtitle: l.billingHint),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (sub != null) _CurrentPlan(sub: sub),
                      const SizedBox(height: 12),
                      Section(
                        title: l.billingPlans,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<BillingCycle>(
                              key: const Key('cycle-toggle'),
                              segments: [
                                for (final x in BillingCycle.values) ButtonSegment(value: x, label: Text(l.cycle(x))),
                              ],
                              selected: {cycle},
                              onSelectionChanged: (s) => setState(() => _cycle = s.first),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final p in b.plans)
                                  _PlanCard(
                                    plan: p,
                                    cycle: cycle,
                                    current:
                                        sub != null && sub.planCode == p.code && sub.cycle == cycle && !sub.isTrial,
                                    pending: sub?.pendingPlanCode == p.code && sub?.pendingCycle == cycle,
                                    onChoose: c.isAdmin && p.selfServe ? () => _choose(c, p, cycle) : null,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Section(
                        title: l.billingInvoices,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (b.invoices.isEmpty) Text(l.billingNoInvoices),
                            for (final i in b.invoices)
                              Padding(
                                key: Key('invoice-${i.invoiceNo}'),
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(i.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Tag(
                                      l.invoiceStatus(i.status),
                                      color: switch (i.status) {
                                        'paid' => const Color(0xFF2E7D32),
                                        'overdue' => const Color(0xFFC62828),
                                        'issued' => const Color(0xFFB26A00),
                                        _ => Colors.grey,
                                      },
                                    ),
                                    Text('${l.planName(i.planCode)} · ${l.cycle(i.cycle)}'),
                                    Text(formatRm(i.totalSen), style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (i.dueDate != null && i.canPay) Text(l.billingDue(fmtDay(i.dueDate))),
                                    if (i.paidAt != null) Text(l.billingPaidAt(fmtDateTime(i.paidAt))),
                                    if (i.canPay)
                                      FilledButton.icon(
                                        key: Key('pay-${i.invoiceNo}'),
                                        onPressed: () => _pay(c, i),
                                        icon: const Icon(Icons.payments_outlined),
                                        label: Text(l.billingPay),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(l.billingBankNote, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Section(
                        title: l.billingPayments,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (b.payments.isEmpty) Text(l.billingNoPayments),
                            for (final p in b.payments)
                              InfoLine(
                                fmtDateTime(p.paidAt ?? p.createdAt),
                                '${formatRm(p.amountSen)} · ${l.paymentStatus(p.status)}',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan({required this.sub});

  final CompanySubscription sub;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Section(
      title: l.billingCurrent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.planName(sub.planCode), style: Theme.of(context).textTheme.titleLarge),
              Tag(l.subscription(sub.state), color: ProcureTheme.subscriptionColor(sub.state)),
              if (sub.customPrice) Tag(l.billingCustomPrice, color: Theme.of(context).colorScheme.tertiary),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 24,
            children: [
              if (sub.accessUntil != null) InfoLine(l.billingUntil, fmtDateTime(sub.accessUntil)),
              if (sub.lockedPriceSen > 0)
                InfoLine(l.billingLocked, '${formatRm(sub.lockedPriceSen)} ${l.perCycle(sub.cycle)}'),
              InfoLine(l.billingLimits, l.billingLimitsValue('${sub.maxSites ?? '∞'}', '${sub.maxUsers ?? '∞'}')),
              if (sub.pendingPlanCode != null)
                InfoLine(
                  l.billingNext,
                  '${l.planName(sub.pendingPlanCode!)} · ${formatRm(sub.pendingPriceSen ?? 0)} '
                  '${l.perCycle(sub.pendingCycle ?? BillingCycle.monthly)}',
                ),
            ],
          ),
          if (!sub.hasAccess)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.billingNoAccess, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in CompanyFeature.all.where(sub.features.contains))
                Chip(label: Text(l.feature(f)), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.cycle,
    required this.current,
    required this.pending,
    this.onChoose,
  });

  final CompanyPlan plan;
  final BillingCycle cycle;
  final bool current;
  final bool pending;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final price = plan.priceFor(cycle);
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 260,
      child: Card(
        key: Key('plan-${plan.code}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.planName(plan.code), style: t.titleMedium),
              const SizedBox(height: 4),
              Text(price == null ? l.billingQuote : '${formatRm(price)} ${l.perCycle(cycle)}', style: t.headlineSmall),
              Text(l.billingLimitsValue('${plan.maxSites ?? '∞'}', '${plan.maxUsers ?? '∞'}'), style: t.bodySmall),
              const SizedBox(height: 8),
              for (final f in CompanyFeature.all.where(plan.features.contains))
                Row(
                  children: [
                    const Icon(Icons.check, size: 16),
                    const SizedBox(width: 4),
                    Expanded(child: Text(l.feature(f), style: t.bodySmall)),
                  ],
                ),
              const SizedBox(height: 8),
              if (current)
                Tag(l.billingCurrentTag, color: const Color(0xFF2E7D32))
              else if (pending)
                Tag(l.billingNextTag, color: const Color(0xFF1565C0))
              else if (!plan.selfServe)
                Text(l.billingContactUs, style: t.bodySmall)
              else if (onChoose != null)
                FilledButton.tonal(key: Key('choose-${plan.code}'), onPressed: onChoose, child: Text(l.billingChoose)),
            ],
          ),
        ),
      ),
    );
  }
}
