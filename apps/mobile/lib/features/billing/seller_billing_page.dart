import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/billing_config.dart';
import '../../app/l10n_x.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'payment_flow.dart';

/// 批发商的「收费」：创始会员上架费、佣金比例和这个月到现在的佣金、每月账单（点进去看明细 / 付款 / PDF）
class SellerBillingPage extends ConsumerStatefulWidget {
  const SellerBillingPage({super.key});

  @override
  ConsumerState<SellerBillingPage> createState() => _SellerBillingPageState();
}

class _SellerBillingPageState extends ConsumerState<SellerBillingPage> with PaymentFlow {
  @override
  void onPaid() => ref.invalidate(sellerBillingProvider);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final billing = ref.watch(sellerBillingProvider);
    final canPay = ref.watch(billingPolicyProvider).sellerCanPay;
    return Scaffold(
      appBar: AppBar(title: Text(l.sellerBillingTitle)),
      body: AsyncView<SellerBilling>(
        value: billing,
        onRetry: () => ref.invalidate(sellerBillingProvider),
        builder: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(sellerBillingProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (b.outstandingSen > 0)
                NoticeBanner(
                  color: AppTheme.warningBg,
                  icon: Icons.receipt_long,
                  text: l.sellerBillingOutstanding(formatRm(b.outstandingSen)),
                  textStyle: t.titleMedium,
                ),
              const SizedBox(height: 8),
              _listingFee(b.listingFee, canPay),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.sellerCommissionRate(formatRate(b.commissionRate)), style: t.titleMedium),
                      const SizedBox(height: 6),
                      Text(l.sellerCommissionRule, style: t.bodyMedium?.copyWith(color: Colors.black54)),
                      const Divider(height: 24),
                      AmountRow(label: l.sellerThisMonthOrders, value: '${b.monthOrderCount}'),
                      AmountRow(label: l.sellerThisMonthGoods, value: formatRm(b.monthGmvSen)),
                      AmountRow(label: l.sellerThisMonthCommission, value: formatRm(b.monthCommissionSen), bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(l.sellerInvoices, style: t.titleMedium),
              const SizedBox(height: 8),
              if (b.invoices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l.sellerNoInvoices, style: t.bodyLarge),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final i in b.invoices)
                        ListTile(
                          key: Key('invoice-${i.id}'),
                          leading: Icon(
                            i.status == 'paid' ? Icons.check_circle : Icons.receipt_long,
                            size: 30,
                            color: i.status == 'overdue' ? Colors.red.shade700 : null,
                          ),
                          title: Text(
                            '${i.periodMonth == null ? '' : l.month(i.periodMonth!)}  ${formatRm(i.commissionSen)}',
                          ),
                          subtitle: Text(
                            [
                              i.invoiceNo,
                              l.invoiceStatus(i.status),
                              if (i.isOutstanding && i.dueDate != null) l.invoiceDue(l.date(i.dueDate!)),
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/seller/billing/invoices/${i.id}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listingFee(ListingFeeInfo f, bool canPay) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final String text;
    if (f.isPaid) {
      text = f.foundingNo != null ? l.listingFeePaidNo(f.foundingNo!) : l.listingFeePaid;
    } else if (f.isFounding) {
      text = l.listingFeeDue(formatRm(f.feeSen), f.foundingNo ?? 0);
    } else if (f.canPay) {
      text = l.listingFeeJoin(formatRm(f.feeSen), f.seatsLeft);
    } else {
      text = l.listingFeeFull;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.listingFeeTitle, style: t.titleMedium),
            const SizedBox(height: 6),
            Text(text, key: const Key('listing-fee-text'), style: t.bodyLarge),
            if (f.canPay && canPay) ...[
              const SizedBox(height: 12),
              BusyButton(
                key: const Key('pay-listing-fee'),
                label: l.payButton(formatRm(f.feeSen)),
                icon: Icons.payment,
                busy: paying,
                onPressed: () =>
                    startPayment(PaymentPurpose.listingFee, ref.read(sellerBillingProvider).value!.wholesalerId),
              ),
              const SizedBox(height: 4),
              Text(l.payMethodsNote, style: t.bodyMedium?.copyWith(color: Colors.black54)),
              if (pendingPaymentId != null)
                TextButton(key: const Key('pay-check'), onPressed: checkPendingPayment, child: Text(l.payCheck)),
            ],
          ],
        ),
      ),
    );
  }
}
