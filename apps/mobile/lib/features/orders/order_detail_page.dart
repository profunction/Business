import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 订单详情：进度条、明细、金额。底下的按钮由服务器决定（actions），规则跟数据库一致。
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReceived() async {
    final l = context.l10n;
    if (!await confirmDialog(context, title: l.markReceivedConfirm, confirmLabel: l.markReceived)) return;
    await _run(() => ref.read(buyerActionsProvider).markReceived(widget.orderId));
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    final reason = TextEditingController();
    final ok = await confirmDialog(
      context,
      title: l.cancelOrderConfirm,
      confirmLabel: l.cancelOrder,
      content: TextField(
        controller: reason,
        decoration: InputDecoration(hintText: l.cancelReasonHint),
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (!ok) return;
    await _run(() => ref.read(buyerActionsProvider).cancelOrder(widget.orderId, reason: text.isEmpty ? null : text));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final detail = ref.watch(orderDetailProvider(widget.orderId));
    final d = detail.value;
    return Scaffold(
      appBar: AppBar(title: Text(d == null ? l.ordersTitle : d.wholesalerName)),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
        builder: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(orderDetailProvider(widget.orderId).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(d: d),
              const SizedBox(height: 12),
              _Progress(d: d),
              const SizedBox(height: 12),
              _Items(d: d),
              if (d.review != null) ...[const SizedBox(height: 12), _ReviewCard(review: d.review!)],
              const SizedBox(height: 12),
              if (d.wholesalerPhone != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.phone),
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'tel', path: '+${d.wholesalerPhone!.replaceAll(RegExp(r'\D'), '')}')),
                  label: Text(l.callWholesaler),
                ),
              if (d.actions.canCancel) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('cancel-order'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.problem),
                  onPressed: _busy ? null : _cancel,
                  child: Text(l.cancelOrder),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: switch (d) {
        final d? when d.actions.canMarkReceived => BottomAction(
          child: BusyButton(
            key: const Key('mark-received'),
            icon: Icons.inventory,
            label: l.markReceived,
            busy: _busy,
            onPressed: _markReceived,
          ),
        ),
        final d? when d.actions.canReview => BottomAction(
          child: FilledButton.icon(
            key: const Key('write-review'),
            icon: const Icon(Icons.star, size: 28),
            onPressed: () => context.push('/orders/${d.id}/review'),
            label: Text(d.review == null ? l.writeReview : l.editReview),
          ),
        ),
        _ => null,
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.d});

  final OrderDetail d;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.orderTitle(d.orderNo), style: t.titleMedium)),
                StatusChip(status: d.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.orderedAt(l.dateTime(d.createdAt)), style: t.bodyLarge),
            if (d.status.isActive && d.expectedDeliveryDate != null)
              InfoLine(icon: Icons.local_shipping, text: l.expectedDelivery(l.date(d.expectedDeliveryDate!))),
            if (d.paymentTerms.isNotEmpty)
              InfoLine(icon: Icons.payments, text: l.paymentTerms(d.paymentTerms.map(l.paymentTerm).join(' / '))),
            if (d.note != null) InfoLine(icon: Icons.notes, text: d.note!),
            if (d.status == OrderStatus.cancelled && d.cancelReason != null)
              InfoLine(icon: Icons.info_outline, text: l.cancelledReason(d.cancelReason!)),
          ],
        ),
      ),
    );
  }
}

/// 待确认 → 已确认 → 送货中 → 已送达。缺货 / 取消就显示一个大的提示
class _Progress extends StatelessWidget {
  const _Progress({required this.d});

  final OrderDetail d;

  static const steps = [OrderStatus.pending, OrderStatus.confirmed, OrderStatus.delivering, OrderStatus.delivered];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    if (d.status == OrderStatus.outOfStock || d.status == OrderStatus.cancelled) {
      final color = AppTheme.statusColor(d.status);
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(
              d.status == OrderStatus.outOfStock ? Icons.remove_shopping_cart : Icons.cancel,
              size: 40,
              color: color,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(l.status(d.status), style: t.headlineSmall?.copyWith(color: color)),
            ),
          ],
        ),
      );
    }
    final currentIndex = steps.indexOf(d.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              _Step(
                label: l.status(steps[i]),
                time: d.reachedAt(steps[i]),
                done: i <= currentIndex,
                current: i == currentIndex,
                isLast: i == steps.length - 1,
                color: AppTheme.statusColor(steps[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    this.time,
    required this.done,
    required this.current,
    required this.isLast,
    required this.color,
  });

  final String label;
  final DateTime? time;
  final bool done;
  final bool current;
  final bool isLast;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final c = done ? color : Colors.black26;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: current ? 36 : 30, color: c),
              if (!isLast)
                Expanded(child: Container(width: 4, color: done ? color.withValues(alpha: 0.4) : Colors.black12)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: (current ? t.titleLarge : t.titleMedium)?.copyWith(color: done ? null : Colors.black45),
                  ),
                  if (time != null) Text(l.dateTime(time!), style: t.bodyMedium?.copyWith(color: Colors.black54)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.d});

  final OrderDetail d;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in d.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i.name}  ×${i.qty} ${l.unit(i.unit)}',
                            style: t.bodyLarge?.copyWith(
                              decoration: i.isOutOfStock ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        Text(
                          formatRm(i.lineTotalSen),
                          style: t.bodyLarge?.copyWith(decoration: i.isOutOfStock ? TextDecoration.lineThrough : null),
                        ),
                      ],
                    ),
                    if (i.isOutOfStock && d.status != OrderStatus.outOfStock)
                      Text(l.itemOutOfStockLabel, style: t.bodyMedium?.copyWith(color: AppTheme.problem)),
                  ],
                ),
              ),
            const Divider(height: 20),
            AmountRow(label: l.goodsSubtotal, value: formatRm(d.goodsSubtotalSen)),
            AmountRow(label: l.shipping, value: d.shippingFeeSen == 0 ? l.freeShipping : formatRm(d.shippingFeeSen)),
            const Divider(height: 20),
            AmountRow(label: l.total, value: formatRm(d.totalSen), bold: true),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final OrderReview review;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.yourReview, style: t.titleMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF5A623),
                    size: 30,
                  ),
              ],
            ),
            if (review.tags.isNotEmpty) Text(review.tags.map(l.reviewTag).join(' · '), style: t.bodyLarge),
            if (review.comment != null) Text(review.comment!, style: t.bodyLarge),
          ],
        ),
      ),
    );
  }
}
