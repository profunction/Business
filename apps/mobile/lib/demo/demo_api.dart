import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'demo_data.dart';

/// 示范模式 / 自动测试用：不连服务器，数据来自本机数据库导出的真实样本（demo_data.dart）。
/// 只有 main_demo.dart 和测试会用到，正式 App（main.dart）不会打包进去。
class DemoApi extends WholesaleApi {
  DemoApi({this.freeUser = false, this.newUser = false, this.failNextPlaceOrderWithPriceChange = false})
    : super(
        SupabaseClient('http://127.0.0.1:1', 'demo-key', authOptions: const AuthClientOptions(autoRefreshToken: false)),
      );

  /// 试用已用完的老板（只看得到 1 家的价钱）
  final bool freeUser;

  /// 刚注册、还没开店
  bool newUser;

  /// 测试「价钱刚好改了」
  bool failNextPlaceOrderWithPriceChange;

  bool loggedIn = true;

  /// 示范模式没有真的登录事件，登录成功时叫这个（DemoSession 会设定）
  void Function()? onLoggedIn;
  final calls = <String>[];
  final Set<String> _unlocked = {'00000000-0000-4000-a000-00000000000a'};

  Object? _j(String name) => jsonDecode(demoFixtures[name]!);

  Future<T> _later<T>(T Function() f) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return f();
  }

  @override
  Future<void> sendOtp(String phoneE164, {String? locale}) => _later(() => calls.add('sendOtp $phoneE164'));

  @override
  Future<void> verifyOtp(String phoneE164, String code) => _later(() {
    calls.add('verifyOtp $code');
    if (code != '123456') throw const AppError('AUTH');
    loggedIn = true;
    onLoggedIn?.call();
  });

  @override
  Future<void> signOut() => _later(() => loggedIn = false);

  @override
  Future<MyContext> getMyContext() => _later(() {
    final c = asJson(_j('my_context'));
    if (newUser) c['shops'] = <Object>[];
    return MyContext.fromJson(c);
  });

  @override
  Future<void> setMyLocale(String userId, String locale) async {}

  @override
  Future<List<Zone>> listZones() => _later(() => asJsonList(_j('zones')).map(Zone.fromJson).toList());

  @override
  Future<String> registerShop({
    required String name,
    required String zoneId,
    required ShopType shopType,
    String? address,
  }) => _later(() {
    calls.add('registerShop $name');
    newUser = false;
    return 'demo-shop';
  });

  Json get _subscription => freeUser
      ? {...asJson(_j('subscription_free')), 'unlocked_wholesaler_ids': _unlocked.toList()}
      : asJson(asJson(_j('buyer_home'))['subscription']);

  @override
  Future<BuyerHome> getBuyerHome(String shopId) => _later(() {
    final h = asJson(_j('buyer_home'));
    h['subscription'] = _subscription;
    return BuyerHome.fromJson(h);
  });

  @override
  Future<SubscriptionInfo> getSubscriptionStatus(String shopId) =>
      _later(() => SubscriptionInfo.fromJson(_subscription));

  @override
  Future<void> setUnlockedWholesalers(String shopId, List<String> wholesalerIds) => _later(() {
    calls.add('setUnlocked ${wholesalerIds.length}');
    _unlocked
      ..clear()
      ..addAll(wholesalerIds);
  });

  @override
  Future<List<CategorySummary>> getCategories(String shopId) =>
      _later(() => asJsonList(_j('categories')).map(CategorySummary.fromJson).toList());

  @override
  Future<List<CatalogItemSummary>> getCatalogOverview(String shopId, {String? categoryId, String? search}) =>
      _later(() {
        var items = asJsonList(_j('catalog_overview')).map(CatalogItemSummary.fromJson);
        if (categoryId != null) items = items.where((i) => i.categoryId == categoryId);
        if (search != null) {
          final s = search.toLowerCase();
          items = items.where((i) => [i.name.zh, i.name.en, i.name.ms].any((n) => n.toLowerCase().contains(s)));
        }
        return items.toList();
      });

  @override
  Future<List<Offer>> getOffers(
    String shopId, {
    String? catalogItemId,
    String? wholesalerId,
    String? categoryId,
    String? search,
  }) => _later(() {
    final rows = asJsonList(_j(freeUser ? 'offers_free_user' : 'offers'));
    if (freeUser) {
      // 未付费的样本里，锁住的批发商本来就没有价钱（服务器没发）。解锁后从试用老板的样本补上
      final full = {for (final r in asJsonList(_j('offers'))) r['product_id']: r};
      for (final r in rows) {
        final visible = _unlocked.contains(r['wholesaler_id']);
        r['price_visible'] = visible;
        final source = visible ? full[r['product_id']] : null;
        r['price_sen'] = source == null ? null : source['price_sen'];
        r['price_per_base_unit_sen'] = source == null ? null : source['price_per_base_unit_sen'];
      }
      // 服务器排序：看得到价钱的在前面
      rows.sort((a, b) => (b['price_visible'] == true ? 1 : 0) - (a['price_visible'] == true ? 1 : 0));
    }
    var offers = rows.map(Offer.fromJson);
    if (wholesalerId != null) offers = offers.where((o) => o.wholesalerId == wholesalerId);
    return offers.toList();
  });

  @override
  Future<List<WholesalerSummary>> listWholesalers(String shopId) => _later(() {
    final rows = asJsonList(_j('wholesalers'));
    for (final r in rows) {
      r['is_unlocked'] = _unlocked.contains(r['wholesaler_id']);
      r['price_visible'] = !freeUser || _unlocked.contains(r['wholesaler_id']);
    }
    return rows.map(WholesalerSummary.fromJson).toList();
  });

  CartQuote _quote = CartQuote.empty;
  bool _quoteLoaded = false;

  @override
  Future<CartQuote> quoteCart(String shopId) => _later(() {
    if (!_quoteLoaded) {
      _quote = CartQuote.fromJson(asJson(_j('quote_cart')));
      _quoteLoaded = true;
    }
    return _quote;
  });

  @override
  Future<void> setCartQty(String shopId, String productId, int qty) =>
      _later(() => calls.add('setCartQty $productId $qty'));

  @override
  Future<void> clearCart(String shopId) async {}

  @override
  Future<String> placeOrder(String shopId, {required int expectedTotalSen, String? note, bool isReorder = false}) =>
      _later(() {
        calls.add('placeOrder $expectedTotalSen${isReorder ? ' reorder' : ''}');
        if (failNextPlaceOrderWithPriceChange) {
          failNextPlaceOrderWithPriceChange = false;
          throw const AppError('PRICE_CHANGED');
        }
        if (!_quote.canPlace) throw const AppError('CART_HAS_PROBLEMS');
        _quote = CartQuote.empty;
        return 'demo-checkout';
      });

  @override
  Future<ReorderResult> reorderLast(String shopId) => _later(() {
    calls.add('reorderLast');
    final r = ReorderResult.fromJson(asJson(_j('reorder')));
    _quote = r.quote;
    _quoteLoaded = true;
    return r;
  });

  @override
  Future<List<OrderSummary>> listOrders(String shopId, {int limit = 30, DateTime? before}) =>
      _later(() => asJsonList(_j('orders')).map(OrderSummary.fromJson).toList());

  @override
  Future<OrderDetail> getOrder(String orderId) => _later(() {
    final confirmed = asJson(_j('order_detail_confirmed'));
    return OrderDetail.fromJson(confirmed['id'] == orderId ? confirmed : asJson(_j('order_detail')));
  });

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) => _later(() => calls.add('cancel $orderId'));

  @override
  Future<void> markReceived(String orderId) => _later(() => calls.add('received $orderId'));

  @override
  Future<void> submitReview(String orderId, {required int rating, List<ReviewTag> tags = const [], String? comment}) =>
      _later(() => calls.add('review $rating ${tags.length}'));

  @override
  RealtimeChannel watchShopOrders(String shopId, void Function() onChange) => client.channel('demo');

  @override
  Future<void> stopWatching(RealtimeChannel channel) async {}
}
