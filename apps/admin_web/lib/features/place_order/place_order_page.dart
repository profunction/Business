import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 代买家下单（老板打电话 / WhatsApp 来）：选店 → 加货（看到的价钱跟这家店在 App 看到的一样）→ 下单。
/// 订单来源记成「客服」，操作记录写下是哪个客服代哪家店下的
class PlaceOrderPage extends ConsumerStatefulWidget {
  const PlaceOrderPage({super.key, this.initialShopId});

  final String? initialShopId;

  @override
  ConsumerState<PlaceOrderPage> createState() => _PlaceOrderPageState();
}

class _PlaceOrderPageState extends ConsumerState<PlaceOrderPage> {
  AdminShop? _shop;
  String _shopSearch = '';
  String _offerSearch = '';
  CartQuote? _quote;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseShop(AdminShop s) async {
    setState(() {
      _shop = s;
      _quote = null;
    });
    try {
      final q = await ref.read(apiProvider).quoteCart(s.id);
      if (mounted && _shop?.id == s.id) setState(() => _quote = q);
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.error(e));
    }
  }

  Future<void> _setQty(String productId, int qty) async {
    final shop = _shop;
    if (shop == null || _busy) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final q = await ref.read(apiProvider).setCartItemAsAdmin(shop.id, productId, qty < 0 ? 0 : qty);
      if (mounted) setState(() => _quote = q);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clear() async {
    final shop = _shop;
    if (shop == null) return;
    await runAction(context, () async {
      await ref.read(apiProvider).clearCartAsAdmin(shop.id);
      final q = await ref.read(apiProvider).quoteCart(shop.id);
      if (mounted) setState(() => _quote = q);
    });
  }

  Future<void> _place() async {
    final shop = _shop;
    final quote = _quote;
    if (shop == null || quote == null || !quote.canPlace || _busy) return;
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final placed = await ref
          .read(apiProvider)
          .placeOrderAsAdmin(shop.id, expectedTotalSen: quote.totalSen, note: _note.text);
      _note.clear();
      ref.invalidate(ordersPageProvider);
      ref.invalidate(dashboardProvider);
      final q = await ref.read(apiProvider).quoteCart(shop.id);
      if (!mounted) return;
      setState(() => _quote = q);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.placedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.placedBody(placed.orders.length)),
              const SizedBox(height: 8),
              for (final o in placed.orders) Text('${o.orderNo}  ${o.wholesalerName}  ${formatRm(o.totalSen)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                this.context.go('/orders?shop=${shop.id}');
              },
              child: Text(l.navOrders),
            ),
            FilledButton(key: const Key('placed-ok'), onPressed: () => Navigator.pop(context), child: Text(l.close)),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showSnack(context, l.error(e));
      // 价钱改了 / 购物车有问题：服务器回传了最新的报价
      if (e is AppError && e.quote != null) setState(() => _quote = e.quote);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final shop = _shop;
    if (shop == null) return _shopPicker(context);
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    final offers = _OffersList(
      shopId: shop.id,
      search: _offerSearch,
      onSearch: (v) => setState(() => _offerSearch = v),
      quote: _quote,
      onAdd: (o, current) => _setQty(o.productId, current == 0 ? o.minOrderQty : current + 1),
    );
    final cart = _CartPanel(quote: _quote, note: _note, busy: _busy, onQty: _setQty, onClear: _clear, onPlace: _place);
    return ListView(
      children: [
        PageHeader(
          title: '${l.navPlaceOrder} · ${shop.name}',
          subtitle: [
            shop.zoneName.of(l.lang),
            if (shop.memberCount == 0) l.shopNoApp,
            if (!shop.hasFullAccess) l.shopLocked,
          ].join(' · '),
          actions: [
            OutlinedButton.icon(
              key: const Key('change-shop'),
              onPressed: () => setState(() => _shop = null),
              icon: const Icon(Icons.swap_horiz),
              label: Text(l.changeShop),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: offers),
                    const SizedBox(width: 16),
                    SizedBox(width: 420, child: cart),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cart, const SizedBox(height: 16), offers],
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _shopPicker(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(shopsProvider(_shopSearch));
    return ListView(
      children: [
        PageHeader(title: l.navPlaceOrder, subtitle: l.chooseShop),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            key: const Key('shop-search'),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.shopSearchHint),
            onSubmitted: (v) => setState(() => _shopSearch = v),
          ),
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(shopsProvider(_shopSearch)),
          builder: (shops) {
            final initial = widget.initialShopId;
            if (initial != null && _shop == null) {
              final match = shops.where((s) => s.id == initial);
              if (match.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _chooseShop(match.first));
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                child: Column(
                  children: [
                    for (final s in shops)
                      ListTile(
                        key: Key('shop-${s.name}'),
                        title: Text(s.name),
                        subtitle: Text(
                          [
                            s.zoneName.of(l.lang),
                            formatMalaysianMobile(s.whatsappPhone ?? s.phone),
                            l.subscription(s.subscriptionState),
                            if (s.memberCount == 0) l.shopNoApp,
                          ].where((e) => e.isNotEmpty).join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _chooseShop(s),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OffersList extends ConsumerWidget {
  const _OffersList({
    required this.shopId,
    required this.search,
    required this.onSearch,
    required this.quote,
    required this.onAdd,
  });

  final String shopId;
  final String search;
  final ValueChanged<String> onSearch;
  final CartQuote? quote;
  final void Function(Offer offer, int currentQty) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(offersProvider((shopId: shopId, search: search)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('offer-search'),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.offersSearchHint),
          onSubmitted: onSearch,
        ),
        const SizedBox(height: 8),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(offersProvider((shopId: shopId, search: search))),
          builder: (offers) => offers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(l.offersEmpty)),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final o in offers)
                        ListTile(
                          key: Key('offer-${o.productId}'),
                          title: Text(o.productName),
                          subtitle: Text(
                            [
                              o.wholesalerName,
                              '${o.packQty} / ${l.unit(o.unit)}',
                              if (o.minOrderQty > 1) l.minOrderQty(o.minOrderQty),
                              if (o.stockStatus != StockStatus.inStock) l.stock(o.stockStatus),
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                o.priceVisible && o.priceSen != null ? formatRm(o.priceSen!) : l.priceHidden,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(width: 8),
                              if ((quote?.qtyOf(o.productId) ?? 0) > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text('×${quote!.qtyOf(o.productId)}'),
                                ),
                              IconButton.filledTonal(
                                key: Key('add-${o.productId}'),
                                tooltip: l.add,
                                onPressed: o.canOrder ? () => onAdd(o, quote?.qtyOf(o.productId) ?? 0) : null,
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.quote,
    required this.note,
    required this.busy,
    required this.onQty,
    required this.onClear,
    required this.onPlace,
  });

  final CartQuote? quote;
  final TextEditingController note;
  final bool busy;
  final Future<void> Function(String productId, int qty) onQty;
  final VoidCallback onClear;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final q = quote;
    final t = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    return Section(
      title: l.cartTitle,
      child: q == null
          ? const Center(child: CircularProgressIndicator())
          : q.isEmpty
          ? Text(l.cartEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in q.groups) ...[
                  Text(g.wholesalerName, style: t.titleSmall),
                  for (final line in g.lines)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.productName),
                              if (l.cartProblem(line.problem, minQty: line.minOrderQty) != null)
                                Text(
                                  l.cartProblem(line.problem, minQty: line.minOrderQty)!,
                                  style: TextStyle(color: error),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('minus-${line.productId}'),
                          onPressed: busy ? null : () => onQty(line.productId, line.qty - 1),
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${line.qty} ${l.unit(line.unit)}'),
                        IconButton(
                          key: Key('plus-${line.productId}'),
                          onPressed: busy ? null : () => onQty(line.productId, line.qty + 1),
                          icon: const Icon(Icons.add),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            line.lineTotalSen == null ? '—' : formatRm(line.lineTotalSen!),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  InfoLine(l.goodsSubtotal, formatRm(g.goodsSubtotalSen)),
                  InfoLine(l.shippingFee, g.shippingFeeSen == null ? '—' : formatRm(g.shippingFeeSen!)),
                  if (g.problem == CartProblem.belowMinOrder)
                    Text(l.problemBelowMinOrder(formatRm(g.shortBySen)), style: TextStyle(color: error)),
                  if (g.problem == CartProblem.notDelivering)
                    Text(l.problemNotDelivering, style: TextStyle(color: error)),
                  const Divider(),
                ],
                Row(
                  children: [
                    Expanded(child: Text(l.totalLabel, style: t.titleMedium)),
                    Text(formatRm(q.totalSen), key: const Key('cart-total'), style: t.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('order-note'),
                  controller: note,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: l.orderNoteLabel),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(onPressed: busy ? null : onClear, child: Text(l.clearCart)),
                    FilledButton(
                      key: const Key('place-order'),
                      onPressed: busy || !q.canPlace ? null : onPlace,
                      child: Text(l.placeOrderButton(formatRm(q.totalSen))),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
