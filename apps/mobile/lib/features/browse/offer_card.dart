import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 一家批发商的一样商品。比价页（标题是批发商）和批发商页（标题是商品）都用这个。
/// 价钱靠右；看不到价钱时：模糊方块 + 「把这家加进免费名单」（不是付款按钮）。
class OfferCard extends ConsumerWidget {
  const OfferCard({
    super.key,
    required this.offer,
    this.titleIsWholesaler = true,
    this.highlight = false,
    this.showTerms = true,
  });

  final Offer offer;
  final bool titleIsWholesaler;

  /// 比价页的第一名（最便宜）
  final bool highlight;

  /// 送货天数、运费、最低消费（批发商页已经写在最上面，就不用每样都写）
  final bool showTerms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = offer;
    final unitName = l.unit(o.unit);
    final inCart = ref.watch(cartQuoteProvider).value?.qtyOf(o.productId) ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final tags = [
      if (highlight) TagChip(label: l.cheapestTag, color: scheme.primary, icon: Icons.trending_down),
      if (titleIsWholesaler && o.isFounding) TagChip(label: l.founding, color: AppTheme.caution, icon: Icons.star),
      if (o.stockStatus == StockStatus.lowStock)
        TagChip(label: l.lowStock, color: AppTheme.caution, icon: Icons.warning_amber),
    ];
    final smallButton = const Size(0, 40);

    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleIsWholesaler ? o.wholesalerName : o.productName, style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        titleIsWholesaler ? '${o.productName} · ${l.packQty(unitName, o.packQty)}' : l.packQty(unitName, o.packQty),
                        style: t.bodySmall,
                      ),
                      if (titleIsWholesaler) ...[
                        const SizedBox(height: 2),
                        RatingLine(avg: o.ratingAvg, count: o.ratingCount),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // ---- 价钱（靠右）----
                if (o.priceVisible)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l.pricePerSellUnit(formatRm(o.priceSen ?? 0), unitName),
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        l.perUnit(formatSen(o.pricePerBaseUnitSen ?? 0)),
                        style: t.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                else
                  const LockedPrice(),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: tags),
            ],
            const SizedBox(height: 8),
            if (showTerms)
              InfoLine(
                icon: Icons.local_shipping_outlined,
                text: [
                  l.leadTime(o.leadTimeDays),
                  l.shippingFee(o.shippingFeeSen == 0 ? l.freeShipping : formatRm(o.shippingFeeSen)),
                  if (o.freeShippingMinSen != null) l.freeShippingOver(formatRm(o.freeShippingMinSen!)),
                  if (o.minOrderSen != null) l.minOrderAmount(formatRm(o.minOrderSen!)),
                ].join(' · '),
              ),
            // ---- 动作 ----
            if (!o.priceVisible)
              Padding(padding: const EdgeInsets.only(top: 6), child: _UnlockAction(wholesalerId: o.wholesalerId))
            else
              Row(
                children: [
                  Expanded(
                    child: Text(l.minOrderQty(o.minOrderQty, unitName), style: t.bodySmall),
                  ),
                  const SizedBox(width: 8),
                  if (o.stockStatus == StockStatus.outOfStock)
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: smallButton),
                      onPressed: null,
                      child: Text(l.outOfStock),
                    )
                  else if (inCart > 0)
                    OutlinedButton.icon(
                      key: Key('offer-${o.productId}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: smallButton,
                        side: BorderSide(color: scheme.primary),
                      ),
                      icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                      onPressed: () => showAddToCart(context, o, inCart),
                      label: Text(l.inCart(inCart)),
                    )
                  else
                    FilledButton.icon(
                      key: Key('offer-${o.productId}'),
                      style: FilledButton.styleFrom(minimumSize: smallButton),
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      onPressed: () => showAddToCart(context, o, 0),
                      label: Text(l.addToCart),
                    ),
                ],
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
        Text(l.lockedHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (hasSlot)
          OutlinedButton.icon(
            key: Key('unlock-${widget.wholesalerId}'),
            icon: const Icon(Icons.lock_open, size: 18),
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
          Text(l.freeSlotsFull, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// 选数量、放进购物车（或改数量、拿掉）
Future<void> showAddToCart(BuildContext context, Offer offer, int currentQty) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(o.productName, style: t.titleLarge),
            const SizedBox(height: 2),
            Text(o.wholesalerName, style: t.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(
              '${l.pricePerSellUnit(formatRm(o.priceSen ?? 0), unitName)} · ${l.packQty(unitName, o.packQty)}',
              style: t.bodyMedium,
            ),
            const Divider(height: 28),
            Row(
              children: [
                QtyStepper(
                  key: const Key('qty-stepper'),
                  value: _qty,
                  min: o.minOrderQty,
                  unitLabel: unitName,
                  onChanged: _busy ? null : (v) => setState(() => _qty = v),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    formatRm((o.priceSen ?? 0) * _qty),
                    textAlign: TextAlign.right,
                    style: t.headlineSmall,
                  ),
                ),
              ],
            ),
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
