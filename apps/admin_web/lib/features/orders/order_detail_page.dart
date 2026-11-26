import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import 'followup_page.dart';

/// 订单详情：明细、进度；客服可以像批发商一样确认（可以标缺货）、缺货、送货中、已送达，也可以取消
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  final _oos = <String>{};
  bool _busy = false;

  Future<void> _do(Future<OrderDetail> Function() action) async {
    final l = context.l10n;
    setState(() => _busy = true);
    OrderDetail? result;
    await runAction(context, () async => result = await action());
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      _oos.clear();
      showSnack(context, l.statusUpdated(l.status(result!.status)));
      ref.invalidate(orderDetailProvider(widget.orderId));
      ref.invalidate(ordersPageProvider);
      ref.invalidate(ordersPageProvider(followupFilter));
      ref.invalidate(dashboardProvider);
    }
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    final reason = await showInputDialog(context, title: l.actCancel, label: l.cancelReasonLabel);
    if (reason == null) return;
    await _do(() => ref.read(apiProvider).setOrderStatusAsAdmin(widget.orderId, OrderStatus.cancelled, note: reason));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(orderDetailProvider(widget.orderId));
    return AsyncBody(
      value: value,
      onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
      builder: (o) {
        final api = ref.read(apiProvider);
        return ListView(
          children: [
            PageHeader(
              title: l.orderTitle(o.orderNo),
              subtitle: '${o.shopName}  →  ${o.wholesalerName}',
              actions: [StatusTag(o.status)],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 520,
                    child: Section(
                      title: l.itemsTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (o.actions.canConfirm)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(l.actConfirmHint, style: Theme.of(context).textTheme.bodySmall),
                            ),
                          for (final i in o.items)
                            Row(
                              children: [
                                if (o.actions.canConfirm)
                                  Checkbox(
                                    key: Key('oos-${i.id}'),
                                    value: _oos.contains(i.id),
                                    onChanged: (v) => setState(() => v == true ? _oos.add(i.id) : _oos.remove(i.id)),
                                  ),
                                Expanded(
                                  child: Text(
                                    '${i.name}  ${i.qty} ${l.unit(i.unit)} × ${formatRm(i.unitPriceSen)}',
                                    style: i.isOutOfStock
                                        ? const TextStyle(decoration: TextDecoration.lineThrough)
                                        : null,
                                  ),
                                ),
                                if (i.isOutOfStock)
                                  Tag(l.outOfStockTag, color: Theme.of(context).colorScheme.error)
                                else
                                  Text(formatRm(i.lineTotalSen)),
                              ],
                            ),
                          const Divider(),
                          InfoLine(l.goodsSubtotal, formatRm(o.goodsSubtotalSen)),
                          InfoLine(l.shippingFee, formatRm(o.shippingFeeSen)),
                          InfoLine(l.totalLabel, formatRm(o.totalSen)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: Section(
                      title: l.eventsTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InfoLine(l.colCreated, fmtDateTime(o.createdAt)),
                          if (o.source != null) InfoLine(l.colSource, l.source(orderSourceFrom(o.source))),
                          if (o.expectedDeliveryDate != null)
                            InfoLine(l.expectedDelivery, fmtDay(o.expectedDeliveryDate)),
                          if (o.note != null) InfoLine(l.noteLabel, o.note!),
                          if (o.cancelReason != null) InfoLine(l.cancelReasonLabel, o.cancelReason!),
                          PhoneText(o.wholesalerPhone, label: l.phoneOf(o.wholesalerName)),
                          PhoneText(o.shopPhone, label: l.phoneOf(o.shopName)),
                          const Divider(),
                          for (final e in o.events)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(width: 130, child: Text(fmtDateTime(e.createdAt))),
                                  Expanded(child: Text(l.status(e.toStatus))),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (o.actions.canConfirm) ...[
                    FilledButton.icon(
                      key: const Key('act-confirm'),
                      onPressed: _busy
                          ? null
                          : () => _do(() => api.confirmOrderAsAdmin(o.id, outOfStockItemIds: [..._oos])),
                      icon: const Icon(Icons.check),
                      label: Text(l.actConfirm),
                    ),
                    OutlinedButton.icon(
                      key: const Key('act-oos'),
                      onPressed: _busy
                          ? null
                          : () => _do(() => api.setOrderStatusAsAdmin(o.id, OrderStatus.outOfStock)),
                      icon: const Icon(Icons.remove_shopping_cart),
                      label: Text(l.actOutOfStock),
                    ),
                  ],
                  if (o.actions.canMarkDelivering)
                    FilledButton.tonalIcon(
                      key: const Key('act-delivering'),
                      onPressed: _busy
                          ? null
                          : () => _do(() => api.setOrderStatusAsAdmin(o.id, OrderStatus.delivering)),
                      icon: const Icon(Icons.local_shipping),
                      label: Text(l.actDelivering),
                    ),
                  if (o.actions.canMarkDelivered)
                    FilledButton.tonalIcon(
                      key: const Key('act-delivered'),
                      onPressed: _busy ? null : () => _do(() => api.setOrderStatusAsAdmin(o.id, OrderStatus.delivered)),
                      icon: const Icon(Icons.done_all),
                      label: Text(l.actDelivered),
                    ),
                  if (o.actions.canCancel)
                    TextButton.icon(
                      key: const Key('act-cancel'),
                      onPressed: _busy ? null : _cancel,
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(l.actCancel),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
