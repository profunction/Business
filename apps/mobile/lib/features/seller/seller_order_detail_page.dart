import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'seller_widgets.dart';

enum _Action { confirm, outOfStock, delivering, delivered }

/// 批发商看一张单：店的资料（可以打电话 / WhatsApp）、明细、金额。
/// 底下的按钮由服务器决定（get_order 的 actions）：待确认 → 「缺货」「确认」；已确认 → 「出发送货」/「已送达」
class SellerOrderDetailPage extends ConsumerStatefulWidget {
  const SellerOrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<SellerOrderDetailPage> createState() => _SellerOrderDetailPageState();
}

class _SellerOrderDetailPageState extends ConsumerState<SellerOrderDetailPage> {
  _Action? _busy;

  /// 做一件事，成功就显示 [task] 回传的那句话；失败（例如在 WhatsApp 已经按过了）显示原因，画面会刷新成现在的状态
  Future<void> _run(_Action action, Future<String> Function() task) async {
    final l = context.l10n;
    setState(() => _busy = action);
    try {
      final message = await task();
      if (mounted) showMessage(context, message);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 「确认」：先问哪几样缺货（可以不勾），再确认
  Future<void> _confirm(OrderDetail d) async {
    final l = context.l10n;
    final outOfStock = await showOutOfStockChecklist(context, d.items);
    if (outOfStock == null || !mounted) return;
    await _run(_Action.confirm, () async {
      final status = await ref.read(sellerActionsProvider).confirmOrder(d.id, outOfStock);
      // 全部都勾了缺货 = 整张单缺货
      return status == OrderStatus.outOfStock ? l.sellerOosMsg : l.sellerConfirmedMsg;
    });
  }

  /// 「缺货」：整张单都没有，先问一次
  Future<void> _outOfStock(OrderDetail d) async {
    final l = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l.sellerOosConfirmTitle,
      confirmLabel: l.sellerOosConfirmButton,
      destructive: true,
      content: Text(l.sellerOosConfirmBody, style: Theme.of(context).textTheme.bodyLarge),
    );
    if (!ok || !mounted) return;
    await _run(_Action.outOfStock, () async {
      await ref.read(sellerActionsProvider).markOutOfStock(d.id);
      return l.sellerOosMsg;
    });
  }

  Future<void> _startDelivery(OrderDetail d) async {
    final l = context.l10n;
    await _run(_Action.delivering, () async {
      await ref.read(sellerActionsProvider).markDelivering(d.id);
      return l.sellerDeliveringMsg;
    });
  }

  Future<void> _delivered(OrderDetail d) async {
    final l = context.l10n;
    if (!await confirmDialog(context, title: l.sellerDeliveredConfirm, confirmLabel: l.sellerMarkDelivered)) return;
    if (!mounted) return;
    await _run(_Action.delivered, () async {
      await ref.read(sellerActionsProvider).markDelivered(d.id);
      return l.sellerDeliveredMsg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // 买家取消、WhatsApp 那边按了确认……画面自己更新
    ref.watch(sellerRealtimeProvider);
    final detail = ref.watch(orderDetailProvider(widget.orderId));
    final d = detail.value;
    return Scaffold(
      appBar: AppBar(title: Text(d == null ? l.sellerOrdersTitle : d.shopName)),
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
              _ShopCard(d: d),
              const SizedBox(height: 12),
              _Items(d: d),
            ],
          ),
        ),
      ),
      bottomNavigationBar: d == null ? null : _bottomBar(d),
    );
  }

  Widget? _bottomBar(OrderDetail d) {
    final l = context.l10n;
    final a = d.actions;
    final busy = _busy != null;
    Widget spinner(Color color) =>
        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: color));

    if (a.canConfirm) {
      return BottomAction(
        // 两个按钮一样高（字换行的那个也一样）
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('seller-oos'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    foregroundColor: AppTheme.problem,
                    side: const BorderSide(color: AppTheme.problem, width: 2),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 22),
                  ),
                  onPressed: busy ? null : () => _outOfStock(d),
                  icon: _busy == _Action.outOfStock
                      ? spinner(AppTheme.problem)
                      : const Icon(Icons.remove_shopping_cart, size: 28),
                  label: Text(l.sellerOutOfStock, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('seller-confirm'),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.confirm),
                  onPressed: busy ? null : () => _confirm(d),
                  icon: _busy == _Action.confirm ? spinner(AppTheme.confirm) : const Icon(Icons.check, size: 28),
                  label: Text(l.sellerConfirm, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final deliveredButton = a.canMarkDelivered
        ? (a.canMarkDelivering
              // 已确认：主要是「出发送货」，也可以直接按「已送达」（例如自己顺路送了）
              ? OutlinedButton.icon(
                  key: const Key('seller-mark-delivered'),
                  onPressed: busy ? null : () => _delivered(d),
                  icon: _busy == _Action.delivered
                      ? spinner(Theme.of(context).colorScheme.primary)
                      : const Icon(Icons.check_circle),
                  label: Text(l.sellerMarkDelivered),
                )
              : BusyButton(
                  key: const Key('seller-mark-delivered'),
                  icon: Icons.check_circle,
                  label: l.sellerMarkDelivered,
                  busy: _busy == _Action.delivered,
                  onPressed: busy ? null : () => _delivered(d),
                ))
        : null;
    if (a.canMarkDelivering) {
      return BottomAction(
        above: deliveredButton == null
            ? null
            : Padding(padding: const EdgeInsets.only(bottom: 10), child: deliveredButton),
        child: BusyButton(
          key: const Key('seller-start-delivery'),
          icon: Icons.local_shipping,
          label: l.sellerStartDelivery,
          busy: _busy == _Action.delivering,
          onPressed: busy ? null : () => _startDelivery(d),
        ),
      );
    }
    if (deliveredButton != null) return BottomAction(child: deliveredButton);
    return null;
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
            // 放不下就把状态放到下一行（不要把订单号切断）
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l.orderTitle(d.orderNo), style: t.titleMedium),
                StatusChip(status: d.status),
              ],
            ),
            const SizedBox(height: 6),
            InfoLine(icon: Icons.schedule, text: l.orderedAt(l.dateTime(d.createdAt))),
            if (d.status == OrderStatus.pending)
              InfoLine(
                icon: Icons.hourglass_top,
                text: l.sellerWaiting(l.waited(d.createdAt)),
                color: AppTheme.statusColor(OrderStatus.pending),
              ),
            if (d.status.isActive && d.expectedDeliveryDate != null)
              InfoLine(icon: Icons.local_shipping, text: l.sellerDeliverOn(l.date(d.expectedDeliveryDate!))),
            if (d.paymentTerms.isNotEmpty)
              InfoLine(icon: Icons.payments, text: l.paymentTerms(d.paymentTerms.map(l.paymentTerm).join(' / '))),
            if (d.note != null) InfoLine(icon: Icons.notes, text: l.sellerBuyerNote(d.note!)),
            if (d.status == OrderStatus.cancelled && d.cancelReason != null)
              InfoLine(icon: Icons.info_outline, text: l.cancelledReason(d.cancelReason!)),
          ],
        ),
      ),
    );
  }
}

/// 店的资料 + 打电话 / WhatsApp
class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.d});

  final OrderDetail d;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final zone = d.shopZoneName?.of(l.lang) ?? '';
    final phone = phoneDigits(d.shopPhone);
    // WhatsApp 号码可以跟电话不一样（get_order 只给批发商、客服）；没有就用电话
    final whatsapp = phoneDigits(d.shopWhatsappPhone) ?? phone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(d.shopName, style: t.titleLarge),
            const SizedBox(height: 4),
            if (zone.isNotEmpty) InfoLine(icon: Icons.map, text: zone),
            if (d.shopAddress != null) InfoLine(icon: Icons.location_on, text: d.shopAddress!),
            if (d.shopContactName != null) InfoLine(icon: Icons.person, text: l.sellerContact(d.shopContactName!)),
            if (phone != null) InfoLine(icon: Icons.phone, text: formatMalaysianMobile(phone)),
            if (whatsapp != null && whatsapp != phone)
              InfoLine(
                key: const Key('seller-shop-whatsapp'),
                icon: Icons.chat,
                text: l.sellerShopWhatsapp(formatMalaysianMobile(whatsapp)),
              ),
            if (phone != null || whatsapp != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (phone != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('seller-call'),
                        icon: const Icon(Icons.phone),
                        onPressed: () => openExternal(context, telUri(phone)),
                        label: Text(l.sellerCall),
                      ),
                    ),
                  if (phone != null && whatsapp != null) const SizedBox(width: 10),
                  if (whatsapp != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('seller-whatsapp'),
                        icon: const Icon(Icons.chat),
                        // 按一下打开 WhatsApp（wa.me），先打好一句话
                        onPressed: () =>
                            openExternal(context, whatsappUri(whatsapp, text: l.sellerWhatsappHello(d.orderNo))),
                        label: Text(l.sellerWhatsapp),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 明细：缺货的那几样划掉、写「不算钱」
class _Items extends StatelessWidget {
  const _Items({required this.d});

  final OrderDetail d;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in d.items)
              Padding(
                key: Key('seller-item-${i.id}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _ItemLine(item: i, showOutOfStockLabel: i.isOutOfStock && d.status != OrderStatus.outOfStock),
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

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item, required this.showOutOfStockLabel});

  final OrderItem item;
  final bool showOutOfStockLabel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final i = item;
    final crossed = i.isOutOfStock ? TextDecoration.lineThrough : null;
    final unit = l.unit(i.unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                // 英文要复数：×3 cartons（跟送货单一样）
                '${i.name}  ×${l.qtyUnit(i.qty, i.unit)}',
                style: t.titleMedium?.copyWith(decoration: crossed, color: i.isOutOfStock ? Colors.black45 : null),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRm(i.lineTotalSen),
              style: t.bodyLarge?.copyWith(decoration: crossed, color: i.isOutOfStock ? Colors.black45 : null),
            ),
          ],
        ),
        Text(
          '${l.pricePerSellUnit(formatRm(i.unitPriceSen), unit)} · ${l.packQty(unit, i.packQty)}',
          style: t.bodyMedium?.copyWith(color: Colors.black54),
        ),
        if (showOutOfStockLabel) Text(l.itemOutOfStockLabel, style: t.bodyLarge?.copyWith(color: AppTheme.problem)),
      ],
    );
  }
}

/// 按「确认」之后：哪几样缺货？（可以不勾 = 全部有货）。回传勾了的 order_items.id；按取消回传 null
Future<List<String>?> showOutOfStockChecklist(BuildContext context, List<OrderItem> items) =>
    showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _OutOfStockChecklist(items: items),
    );

class _OutOfStockChecklist extends StatefulWidget {
  const _OutOfStockChecklist({required this.items});

  final List<OrderItem> items;

  @override
  State<_OutOfStockChecklist> createState() => _OutOfStockChecklistState();
}

class _OutOfStockChecklistState extends State<_OutOfStockChecklist> {
  final _ticked = <String>{};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final all = _ticked.length == widget.items.length;
    final label = _ticked.isEmpty
        ? l.sellerConfirmAllInStock
        : all
        ? l.sellerConfirmAllOos
        : l.sellerConfirmWithOos(_ticked.length);
    // 标题、说明和每一样一起滚（大字、东西多的时候），底下两个按钮固定
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (constraints.hasBoundedHeight ? constraints.maxHeight : MediaQuery.sizeOf(context).height) * 0.9,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Text(l.sellerChecklistTitle, style: t.headlineSmall),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(l.sellerChecklistHint, style: t.bodyLarge),
                    ),
                    for (final i in widget.items)
                      CheckboxListTile(
                        key: Key('oos-item-${i.id}'),
                        value: _ticked.contains(i.id),
                        onChanged: (v) => setState(() => v == true ? _ticked.add(i.id) : _ticked.remove(i.id)),
                        controlAffinity: ListTileControlAffinity.leading,
                        checkboxScaleFactor: 1.4,
                        activeColor: AppTheme.problem,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text(
                          i.name,
                          style: t.titleMedium?.copyWith(
                            decoration: _ticked.contains(i.id) ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          _ticked.contains(i.id)
                              ? l.itemOutOfStockLabel
                              : '×${l.qtyUnit(i.qty, i.unit)}  ${formatRm(i.lineTotalSen)}',
                          style: t.bodyLarge?.copyWith(color: _ticked.contains(i.id) ? AppTheme.problem : null),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: const Key('oos-checklist-done'),
                      style: FilledButton.styleFrom(backgroundColor: all ? AppTheme.problem : AppTheme.confirm),
                      onPressed: () => Navigator.pop(context, [
                        for (final i in widget.items)
                          if (_ticked.contains(i.id)) i.id,
                      ]),
                      child: Text(label, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('oos-checklist-cancel'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.cancel),
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
}
