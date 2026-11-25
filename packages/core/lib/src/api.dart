import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'json.dart';
import 'models/account.dart';
import 'models/catalog.dart';
import 'models/common.dart';
import 'models/orders.dart';

/// 服务器返回的错误。code 是数据库函数 raise 的英文代码（见 docs/02-database.md 第 4 节），
/// 另外还有 App 自己的：NETWORK（没网络）、AUTH（验证码错 / 登录过期）、UNKNOWN。
class AppError implements Exception {
  const AppError(this.code, {this.detail, this.message});

  factory AppError.fromPostgrest(PostgrestException e) {
    final code = RegExp(r'^[A-Z_]+$').hasMatch(e.message) ? e.message : 'UNKNOWN';
    return AppError(code, detail: e.details?.toString(), message: e.message);
  }

  final String code;
  final String? detail;
  final String? message;

  /// PRICE_CHANGED / CART_HAS_PROBLEMS 时，detail 是服务器最新的报价
  CartQuote? get quote {
    final d = detail;
    if (d == null || !d.startsWith('{')) return null;
    try {
      return CartQuote.fromJson(asJson(jsonDecode(d)));
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'AppError($code${message != null && message != code ? ': $message' : ''})';
}

/// 所有跟服务器打交道的地方。手机 App 和客服后台都用这个。
class WholesaleApi {
  WholesaleApi(this.client);

  final SupabaseClient client;

  Future<T> _call<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw AppError.fromPostgrest(e);
    } on AuthException catch (e) {
      throw AppError('AUTH', message: e.message);
    } on AppError {
      rethrow;
    } catch (e) {
      final text = e.toString();
      final isNetwork =
          text.contains('SocketException') ||
          text.contains('ClientException') ||
          text.contains('XMLHttpRequest') ||
          text.contains('Failed host lookup') ||
          e is TimeoutException;
      throw AppError(isNetwork ? 'NETWORK' : 'UNKNOWN', message: text);
    }
  }

  Future<Json> _rpcJson(String fn, [Map<String, dynamic>? params]) =>
      _call(() async => asJson(await client.rpc<dynamic>(fn, params: params)));

  Future<List<Json>> _rpcList(String fn, [Map<String, dynamic>? params]) =>
      _call(() async => asJsonList(await client.rpc<dynamic>(fn, params: params)));

  // ---------------- 登录 ----------------

  /// phoneE164：'+60123456789'
  Future<void> sendOtp(String phoneE164, {String? locale}) =>
      _call(() => client.auth.signInWithOtp(phone: phoneE164, data: locale == null ? null : {'locale': locale}));

  Future<void> verifyOtp(String phoneE164, String code) =>
      _call(() => client.auth.verifyOTP(type: OtpType.sms, phone: phoneE164, token: code.trim()));

  Future<void> signOut() => _call(() => client.auth.signOut());

  Future<MyContext> getMyContext() async => MyContext.fromJson(await _rpcJson('get_my_context'));

  Future<void> setMyLocale(String userId, String locale) =>
      _call(() => client.from('profiles').update({'locale': locale}).eq('id', userId));

  // ---------------- 店铺 ----------------

  Future<List<Zone>> listZones() => _call(() async {
    final rows = await client.from('delivery_zones').select('id, code, name').eq('is_active', true).order('sort_order');
    return asJsonList(rows).map(Zone.fromJson).toList();
  });

  Future<String> registerShop({
    required String name,
    required String zoneId,
    required ShopType shopType,
    String? address,
  }) => _call(
    () async => (await client.rpc<dynamic>(
      'register_shop',
      params: {'p_name': name, 'p_zone_id': zoneId, 'p_shop_type': shopTypeCode(shopType), 'p_address': address},
    )).toString(),
  );

  Future<BuyerHome> getBuyerHome(String shopId) async =>
      BuyerHome.fromJson(await _rpcJson('get_buyer_home', {'p_shop_id': shopId}));

  Future<SubscriptionInfo> getSubscriptionStatus(String shopId) async =>
      SubscriptionInfo.fromJson(await _rpcJson('get_subscription_status', {'p_shop_id': shopId}));

  Future<void> setUnlockedWholesalers(String shopId, List<String> wholesalerIds) => _call(
    () => client.rpc<dynamic>(
      'set_unlocked_wholesalers',
      params: {'p_shop_id': shopId, 'p_wholesaler_ids': wholesalerIds},
    ),
  );

  // ---------------- 看商品 ----------------

  Future<List<CategorySummary>> getCategories(String shopId) async =>
      (await _rpcList('get_categories', {'p_shop_id': shopId})).map(CategorySummary.fromJson).toList();

  Future<List<CatalogItemSummary>> getCatalogOverview(String shopId, {String? categoryId, String? search}) async =>
      (await _rpcList('get_catalog_overview', {
        'p_shop_id': shopId,
        'p_category_id': categoryId,
        'p_search': search,
      })).map(CatalogItemSummary.fromJson).toList();

  Future<List<Offer>> getOffers(
    String shopId, {
    String? catalogItemId,
    String? wholesalerId,
    String? categoryId,
    String? search,
  }) async => (await _rpcList('get_offers', {
    'p_shop_id': shopId,
    'p_catalog_item_id': catalogItemId,
    'p_wholesaler_id': wholesalerId,
    'p_category_id': categoryId,
    'p_search': search,
  })).map(Offer.fromJson).toList();

  Future<List<WholesalerSummary>> listWholesalers(String shopId) async =>
      (await _rpcList('list_wholesalers', {'p_shop_id': shopId})).map(WholesalerSummary.fromJson).toList();

  // ---------------- 购物车和下单 ----------------

  Future<CartQuote> quoteCart(String shopId) async =>
      CartQuote.fromJson(await _rpcJson('quote_cart', {'p_shop_id': shopId}));

  /// qty <= 0 就从购物车拿掉
  Future<void> setCartQty(String shopId, String productId, int qty) => _call(() async {
    if (qty <= 0) {
      await client.from('cart_items').delete().eq('shop_id', shopId).eq('product_id', productId);
    } else {
      await client.from('cart_items').upsert({'shop_id': shopId, 'product_id': productId, 'qty': qty});
    }
  });

  Future<void> clearCart(String shopId) => _call(() => client.from('cart_items').delete().eq('shop_id', shopId));

  /// 返回 checkout id。总额跟服务器算的不一样会抛 AppError('PRICE_CHANGED')，error.quote 是新报价
  Future<String> placeOrder(String shopId, {required int expectedTotalSen, String? note, bool isReorder = false}) =>
      _call(
        () async => (await client.rpc<dynamic>(
          'place_order',
          params: {
            'p_shop_id': shopId,
            'p_expected_total_sen': expectedTotalSen,
            'p_note': note,
            'p_source': isReorder ? 'reorder' : 'app',
          },
        )).toString(),
      );

  Future<ReorderResult> reorderLast(String shopId) async =>
      ReorderResult.fromJson(await _rpcJson('reorder_last', {'p_shop_id': shopId}));

  // ---------------- 订单 ----------------

  Future<List<OrderSummary>> listOrders(String shopId, {int limit = 30, DateTime? before}) => _call(() async {
    final rows = await client.rpc<dynamic>(
      'list_orders',
      params: {'p_shop_id': shopId, 'p_limit': limit, 'p_before': before?.toUtc().toIso8601String()},
    );
    return asJsonList(rows).map(OrderSummary.fromJson).toList();
  });

  Future<OrderDetail> getOrder(String orderId) async =>
      OrderDetail.fromJson(await _rpcJson('get_order', {'p_order_id': orderId}));

  Future<void> cancelOrder(String orderId, {String? reason}) => _call(
    () => client.rpc<dynamic>(
      'set_order_status',
      params: {'p_order_id': orderId, 'p_status': 'cancelled', 'p_note': reason},
    ),
  );

  /// 老板按「收到了」
  Future<void> markReceived(String orderId) =>
      _call(() => client.rpc<dynamic>('set_order_status', params: {'p_order_id': orderId, 'p_status': 'delivered'}));

  Future<void> submitReview(String orderId, {required int rating, List<ReviewTag> tags = const [], String? comment}) =>
      _call(
        () => client.rpc<dynamic>(
          'submit_review',
          params: {
            'p_order_id': orderId,
            'p_rating': rating,
            'p_tags': tags.map((t) => reviewTagCodes[t]).toList(),
            'p_comment': comment,
          },
        ),
      );

  /// 这家店的订单一有变化就叫 onChange（Realtime，RLS 照样生效）。用完记得 removeChannel
  RealtimeChannel watchShopOrders(String shopId, void Function() onChange) {
    return client
        .channel('shop-orders-$shopId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'shop_id', value: shopId),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> stopWatching(RealtimeChannel channel) => client.removeChannel(channel);
}
