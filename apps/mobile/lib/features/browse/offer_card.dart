import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 一家批发商的一样商品。比价页（标题是批发商）和批发商页（标题是商品）都用这个。
/// 看不到价钱时：模糊方块 + 「把这家加进免费名单」（不是付款按钮）。
class OfferCard extends ConsumerWidget {
  const OfferCard({super.key, required this.offer, this.titleIsWholesaler = true, this.highlight = false});

  final Offer offer;
  final bool titleIsWholesaler;

  /// 比价页的第一名（最便宜）
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = offer;
    final unitName = l.unit(o.unit);
    final inCart = ref.watch(cartQuoteProvider).value?.qtyOf(o.productId) ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.primary, width: 3),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleIsWholesaler ? o.wholesalerName : o.productName, style: t.titleLarge),
            if (titleIsWholesaler) Text(o.productName, style: t.bodyMedium?.copyWith(color: Colors.black54)),
            if (titleIsWholesaler && o.isFounding)
              Text('★ ${l.founding}', style: t.bodyMedium?.copyWith(color: const Color(0xFFB26A00))),
            const SizedBox(height: 10),
            // ---- 价钱 ----
            if (o.priceVisible) ...[
              Text(
                l.perUnit(formatSen(o.pricePerBaseUnitSen ?? 0)),
                style: t.headlineSmall?.copyWith(color: scheme.primary),
              ),
              Text(
                '${l.pricePerSellUnit(formatRm(o.priceSen ?? 0), unitName)} · ${l.packQty(unitName, o.packQty)}',
                style: t.bodyLarge,
              ),
            ] else ...[
              const LockedPrice(large: true),
              Text(l.packQty(unitName, o.packQty), style: t.bodyLarge),
            ],
            const SizedBox(height: 8),
            if (titleIsWholesaler) RatingLine(avg: o.ratingAvg, count: o.ratingCount),
            InfoLine(icon: Icons.local_shipping, text: l.leadTime(o.leadTimeDays)),
            InfoLine(icon: Icons.production_quantity_limits, text: l.minOrderQty(o.minOrderQty, unitName)),
            InfoLine(
              icon: Icons.payments,
              text: [
                l.shippingFee(o.shippingFeeSen == 0 ? l.freeShipping : formatRm(o.shippingFeeSen)),
                if (o.freeShippingMinSen != null) l.freeShippingOver(formatRm(o.freeShippingMinSen!)),
              ].join(' · '),
            ),
            if (o.minOrderSen != null)
              InfoLine(icon: Icons.shopping_cart_checkout, text: l.minOrderAmount(formatRm(o.minOrderSen!))),
            if (o.stockStatus == StockStatus.lowStock)
              InfoLine(icon: Icons.warning_amber, text: l.lowStock, color: const Color(0xFFB26A00)),
            const SizedBox(height: 12),
            // ---- 动作 ----
            if (!o.priceVisible)
              _UnlockAction(wholesalerId: o.wholesalerId)
            else if (o.stockStatus == StockStatus.outOfStock)
              FilledButton(onPressed: null, child: Text(l.outOfStock))
            else if (inCart > 0)
              OutlinedButton.icon(
                key: Key('offer-${o.productId}'),
                icon: const Icon(Icons.shopping_cart),
                onPressed: () => showAddToCart(context, o, inCart),
                label: Text(l.inCart(inCart)),
              )
            else
              FilledButton.icon(
                key: Key('offer-${o.productId}'),
                icon: const Icon(Icons.add_shopping_cart),
                onPressed: () => showAddToCart(context, o, 0),
                label: Text(l.addToCart),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnlockAction extends ConsumerStatefulWidget {
  const _UnlockAction({required this.wholesalerId});

  final String wholesalerId;

  @override
  ConsumerState<_UnlockAction> createState() => _UnlockActionState();
}

class _UnlockActionState extends ConsumerState<_UnlockAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sub = ref.watch(subscriptionProvider).value;
    final hasSlot = sub != null && sub.unlockedWholesalerIds.length < sub.freeUnlockedLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.lockedHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
        const SizedBox(height: 8),
        if (hasSlot)
          OutlinedButton.icon(
            key: Key('unlock-${widget.wholesalerId}'),
            icon: const Icon(Icons.lock_open),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await ref.read(buyerActionsProvider).setUnlockedWholesalers([
                        ...sub.unlockedWholesalerIds,
                        widget.wholesalerId,
                      ]);
                    } catch (e) {
                      if (context.mounted) showMessage(context, l.error(e), error: true);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            label: Text(l.chooseThisWholesaler),
          )
        else if (sub != null)
          Text(l.freeSlotsFull, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

/// 选数量、放进购物车（或改数量、拿掉）
Future<void> showAddToCart(BuildContext context, Offer offer, int currentQty) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddToCartSheet(offer: offer, currentQty: currentQty),
  );
}

class _AddToCartSheet extends ConsumerStatefulWidget {
  const _AddToCartSheet({required this.offer, required this.currentQty});

  final Offer offer;
  final int currentQty;

  @override
  ConsumerState<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends ConsumerState<_AddToCartSheet> {
  late int _qty = widget.currentQty > 0 ? widget.currentQty : widget.offer.minOrderQty;
  bool _busy = false;

  Future<void> _save(int qty) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(buyerActionsProvider).setCartQty(widget.offer.productId, qty);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (qty > 0 && widget.currentQty == 0) showMessage(context, l.addedToCart);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = widget.offer;
    final unitName = l.unit(o.unit);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(o.productName, style: t.titleLarge),
            Text(o.wholesalerName, style: t.bodyLarge?.copyWith(color: Colors.black54)),
            const SizedBox(height: 8),
            Text(
              '${l.pricePerSellUnit(formatRm(o.priceSen ?? 0), unitName)} · ${l.packQty(unitName, o.packQty)}',
              style: t.bodyLarge,
            ),
            const SizedBox(height: 20),
            Center(
              child: QtyStepper(
                key: const Key('qty-stepper'),
                value: _qty,
                min: o.minOrderQty,
                unitLabel: unitName,
                onChanged: _busy ? null : (v) => setState(() => _qty = v),
              ),
            ),
            const SizedBox(height: 12),
            Text(formatRm((o.priceSen ?? 0) * _qty), textAlign: TextAlign.center, style: t.headlineSmall),
            const SizedBox(height: 16),
            BusyButton(
              key: const Key('confirm-add'),
              label: widget.currentQty > 0 ? l.updateCart : l.addToCart,
              busy: _busy,
              onPressed: () => _save(_qty),
            ),
            if (widget.currentQty > 0) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : () => _save(0),
                icon: const Icon(Icons.delete_outline),
                label: Text(l.removeFromCart),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
