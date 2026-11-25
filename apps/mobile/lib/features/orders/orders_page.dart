import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final orders = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.ordersTitle)),
      body: AsyncView(
        value: orders,
        onRetry: () => ref.invalidate(ordersProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(ordersProvider.future),
          child: list.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    const Icon(Icons.receipt_long, size: 80, color: Colors.black38),
                    const SizedBox(height: 12),
                    Text(l.noOrders, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _OrderCard(order: list[i]),
                ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = order;
    return Card(
      child: InkWell(
        key: Key('order-${o.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/orders/${o.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border(left: BorderSide(color: AppTheme.statusColor(o.status), width: 8)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(o.wholesalerName, style: t.titleLarge)),
                  StatusChip(status: o.status),
                ],
              ),
              const SizedBox(height: 6),
              Text('${l.dateTime(o.createdAt)} · ${l.itemCount(o.itemCount)}', style: t.bodyLarge),
              if (o.outOfStockCount > 0 && o.status != OrderStatus.outOfStock)
                InfoLine(
                  icon: Icons.warning_amber,
                  text: l.outOfStockCount(o.outOfStockCount),
                  color: AppTheme.problem,
                ),
              if (o.status.isActive && o.expectedDeliveryDate != null)
                InfoLine(icon: Icons.local_shipping, text: l.expectedDelivery(l.date(o.expectedDeliveryDate!))),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(o.orderNo, style: t.bodyMedium?.copyWith(color: Colors.black54)),
                  ),
                  Text(formatRm(o.totalSen), style: t.titleLarge),
                ],
              ),
              if (o.status == OrderStatus.delivered && !o.hasReview)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.star_outline, color: Color(0xFFF5A623)),
                      const SizedBox(width: 6),
                      Text(l.writeReview, style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
