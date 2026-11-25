import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'session.dart';

/// main.dart 里用真正的值覆盖
final apiProvider = Provider<WholesaleApi>((ref) => throw UnimplementedError('apiProvider'));
final sessionProvider = ChangeNotifierProvider<SessionController>((ref) => throw UnimplementedError('sessionProvider'));

/// 现在用的店。只有买家页面会用到，那时一定有店
final shopIdProvider = Provider<String>((ref) {
  final id = ref.watch(sessionProvider.select((s) => s.shopId));
  if (id == null) throw StateError('no shop selected');
  return id;
});

final zonesProvider = FutureProvider.autoDispose<List<Zone>>((ref) => ref.watch(apiProvider).listZones());

final buyerHomeProvider = FutureProvider.autoDispose<BuyerHome>(
  (ref) => ref.watch(apiProvider).getBuyerHome(ref.watch(shopIdProvider)),
);

final subscriptionProvider = FutureProvider.autoDispose<SubscriptionInfo>(
  (ref) => ref.watch(apiProvider).getSubscriptionStatus(ref.watch(shopIdProvider)),
);

final categoriesProvider = FutureProvider.autoDispose<List<CategorySummary>>(
  (ref) => ref.watch(apiProvider).getCategories(ref.watch(shopIdProvider)),
);

typedef CatalogQuery = ({String? categoryId, String? search});

final catalogItemsProvider = FutureProvider.autoDispose.family<List<CatalogItemSummary>, CatalogQuery>(
  (ref, q) =>
      ref.watch(apiProvider).getCatalogOverview(ref.watch(shopIdProvider), categoryId: q.categoryId, search: q.search),
);

typedef OfferQuery = ({String? catalogItemId, String? wholesalerId});

final offersProvider = FutureProvider.autoDispose.family<List<Offer>, OfferQuery>(
  (ref, q) => ref
      .watch(apiProvider)
      .getOffers(ref.watch(shopIdProvider), catalogItemId: q.catalogItemId, wholesalerId: q.wholesalerId),
);

final wholesalersProvider = FutureProvider.autoDispose<List<WholesalerSummary>>(
  (ref) => ref.watch(apiProvider).listWholesalers(ref.watch(shopIdProvider)),
);

/// 购物车报价（货价 + 运费，按批发商分组）。改了购物车就 invalidate
final cartQuoteProvider = FutureProvider<CartQuote>(
  (ref) => ref.watch(apiProvider).quoteCart(ref.watch(shopIdProvider)),
);

final ordersProvider = FutureProvider.autoDispose<List<OrderSummary>>(
  (ref) => ref.watch(apiProvider).listOrders(ref.watch(shopIdProvider)),
);

final orderDetailProvider = FutureProvider.autoDispose.family<OrderDetail, String>(
  (ref, orderId) => ref.watch(apiProvider).getOrder(orderId),
);

/// 改购物车、改订单之后要刷新的东西，集中在这里
class BuyerActions {
  BuyerActions(this.ref);

  final Ref ref;

  WholesaleApi get _api => ref.read(apiProvider);
  String get _shopId => ref.read(shopIdProvider);

  Future<void> setCartQty(String productId, int qty) async {
    await _api.setCartQty(_shopId, productId, qty);
    _cartChanged();
  }

  Future<ReorderResult> reorderLast() async {
    final r = await _api.reorderLast(_shopId);
    _cartChanged();
    return r;
  }

  Future<String> placeOrder({required int expectedTotalSen, String? note, bool isReorder = false}) async {
    try {
      return await _api.placeOrder(_shopId, expectedTotalSen: expectedTotalSen, note: note, isReorder: isReorder);
    } finally {
      _cartChanged();
      ref.invalidate(ordersProvider);
    }
  }

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _api.cancelOrder(orderId, reason: reason);
    _orderChanged(orderId);
  }

  Future<void> markReceived(String orderId) async {
    await _api.markReceived(orderId);
    _orderChanged(orderId);
  }

  Future<void> submitReview(
    String orderId, {
    required int rating,
    List<ReviewTag> tags = const [],
    String? comment,
  }) async {
    await _api.submitReview(orderId, rating: rating, tags: tags, comment: comment);
    _orderChanged(orderId);
  }

  Future<void> setUnlockedWholesalers(List<String> ids) async {
    await _api.setUnlockedWholesalers(_shopId, ids);
    ref.invalidate(subscriptionProvider);
    ref.invalidate(buyerHomeProvider);
    ref.invalidate(offersProvider);
    ref.invalidate(catalogItemsProvider);
    ref.invalidate(wholesalersProvider);
    ref.invalidate(cartQuoteProvider);
  }

  void _cartChanged() {
    ref.invalidate(cartQuoteProvider);
    ref.invalidate(buyerHomeProvider);
  }

  void _orderChanged(String orderId) {
    ref.invalidate(orderDetailProvider(orderId));
    ref.invalidate(ordersProvider);
    ref.invalidate(buyerHomeProvider);
  }
}

final buyerActionsProvider = Provider<BuyerActions>(BuyerActions.new);
