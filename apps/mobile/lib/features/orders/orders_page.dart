import 'dart:ui' show FontFeature;

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
                    const Icon(Icons.receipt_long_outlined, size: 56, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(l.noOrders, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => Card(child: OrderSummaryTile(order: list[i], detailed: true)),
                ),
        ),
      ),
    );
  }
}

/// 一张订单一行：批发商 + 状态；订单号 · 日期；金额靠右。首页「最近的订单」和订单页都用
class OrderSummaryTile extends StatelessWidget {
  const OrderSummaryTile({super.key, required this.order, this.detailed = false});

  final OrderSummary order;

  /// 订单页：多显示缺货、预计送到、写评价
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = order;
    final money = t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return InkWell(
      key: Key('order-${o.id}'),
      onTap: () => context.push('/orders/${o.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(o.wholesalerName, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                StatusChip(status: o.status),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.orderNo, style: t.bodySmall),
                      Text('${l.dateTime(o.createdAt)} · ${l.itemCount(o.itemCount)}', style: t.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatRm(o.totalSen), style: money),
              ],
            ),
            if (detailed) ...[
              if (o.outOfStockCount > 0 && o.status != OrderStatus.outOfStock)
                InfoLine(
                  icon: Icons.warning_amber,
                  text: l.outOfStockCount(o.outOfStockCount),
                  color: AppTheme.problem,
                ),
              if (o.status.isActive && o.expectedDeliveryDate != null)
                InfoLine(
                  icon: Icons.local_shipping_outlined,
                  text: l.expectedDelivery(l.date(o.expectedDeliveryDate!)),
                ),
              if (o.status == OrderStatus.delivered && !o.hasReview)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.star_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(l.writeReview, style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
