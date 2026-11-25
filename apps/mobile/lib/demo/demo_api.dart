import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'demo_data.dart';
import 'demo_seller.dart';

/// 示范模式 / 自动测试用：不连服务器，数据来自本机数据库导出的真实样本（demo_data.dart）。
/// 只有 main_demo.dart 和测试会用到，正式 App（main.dart）不会打包进去。
class DemoApi extends WholesaleApi {
  DemoApi({
    this.freeUser = false,
    this.newUser = false,
    this.failNextPlaceOrderWithPriceChange = false,
    this.seller = false,
  }) : super(
         SupabaseClient(
           'http://127.0.0.1:1',
           'demo-key',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       );

  /// 试用已用完的老板（只看得到 1 家的价钱）
  final bool freeUser;

  /// 刚注册、还没开店
  bool newUser;

  /// 测试「价钱刚好改了」
  bool failNextPlaceOrderWithPriceChange;

  /// 用示范批发商 A 的账号登录（批发商端）
  final bool seller;

  /// 批发商端的示范资料（订单、商品、价目表导入……），按了按钮会跟着变
  late final DemoSeller sellerData = DemoSeller();

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
    if (seller) return MyContext.fromJson(sellerData.myContext());
    final c = asJson(_j('my_context'));
    if (newUser) c['shops'] = <Object>[];
    return MyContext.fromJson(c);
  });

  @override
  Future<void> setMyLocale(String userId, String locale) async {}

  @override
  Future<void> setBusinessLocale(
    String locale, {
    Iterable<String> wholesalerIds = const [],
    Iterable<String> shopIds = const [],
  }) async {
    for (final id in wholesalerIds) {
      calls.add('wholesalerLocale $id $locale');
    }
    for (final id in shopIds) {
      calls.add('shopLocale $id $locale');
    }
  }

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
    if (seller) return sellerData.order(orderId);
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
  Future<void> stopWatching(RealtimeChannel channel) async => _orderWatchers.remove(channel);

  // ---------------- 推送 ----------------

  @override
  Future<void> registerDeviceToken(String token, {required String platform, String kind = 'fid'}) =>
      _later(() => calls.add('registerDevice $platform $kind'));

  @override
  Future<void> unregisterDeviceToken(String token) => _later(() => calls.add('unregisterDevice'));

  // ---------------- 批发商端 ----------------

  /// 测试用：首页读不到（例如没网络），清掉就好了
  AppError? sellerHomeError;

  @override
  Future<SellerHome> getSellerHome(String wholesalerId) => _later(() {
    final e = sellerHomeError;
    if (e != null) throw e;
    return sellerData.home();
  });

  @override
  Future<List<SellerOrderSummary>> listSellerOrders(
    String wholesalerId, {
    List<OrderStatus>? statuses,
    DateTime? deliveryDate,
    int limit = 50,
  }) => _later(() => sellerData.orders(statuses: statuses, deliveryDate: deliveryDate, limit: limit));

  @override
  Future<DeliverySummary> getDeliverySummary(String wholesalerId, {DateTime? date}) =>
      _later(() => sellerData.delivery(date));

  @override
  Future<OrderStatus> confirmOrder(String orderId, {List<String> outOfStockItemIds = const []}) => _later(() {
    calls.add('confirm $orderId ${outOfStockItemIds.length}');
    return sellerData.confirm(orderId, outOfStockItemIds);
  });

  @override
  Future<void> markOutOfStock(String orderId, {String? note}) => _later(() {
    calls.add('outOfStock $orderId');
    sellerData.setStatus(orderId, OrderStatus.outOfStock);
  });

  @override
  Future<void> markDelivering(String orderId) => _later(() {
    calls.add('delivering $orderId');
    sellerData.setStatus(orderId, OrderStatus.delivering);
  });

  @override
  Future<void> markDelivered(String orderId) => _later(() {
    calls.add('delivered $orderId');
    sellerData.setStatus(orderId, OrderStatus.delivered);
  });

  /// 现在开着的「批发商订单」Realtime（示范模式不会真的连线）
  final _orderWatchers = <RealtimeChannel, void Function()>{};
  var _channelNo = 0;

  /// 有几个页面在听批发商的订单（应该最多一个 channel）
  int get orderWatcherCount => _orderWatchers.length;

  /// 测试用：假装 Realtime 说订单变了（例如批发商在 WhatsApp 按了确认、来了新订单）
  void simulateOrderChange() {
    for (final onChange in [..._orderWatchers.values]) {
      onChange();
    }
  }

  @override
  RealtimeChannel watchWholesalerOrders(String wholesalerId, void Function() onChange) {
    final channel = client.channel('demo-wholesaler-orders-${++_channelNo}');
    _orderWatchers[channel] = onChange;
    return channel;
  }

  /// 测试用：读商品失败（例如没网络），清掉就好了
  AppError? productsError;

  @override
  Future<List<SellerProduct>> listMyProducts(String wholesalerId) => _later(() {
    final e = productsError;
    if (e != null) throw e;
    return sellerData.products();
  });

  @override
  Future<SellerProduct> getProduct(String productId) => _later(() => sellerData.product(productId));

  @override
  Future<SellerProduct> saveProduct(SellerProduct product) => _later(() {
    calls.add('saveProduct ${product.name} ${product.priceSen}');
    return sellerData.saveProduct(product);
  });

  @override
  Future<SellerProduct> setStockStatus(String productId, StockStatus status) => _later(() {
    calls.add('stock $productId ${stockStatusCode(status)}');
    return sellerData.updateProduct(productId, {'stock_status': stockStatusCode(status)});
  });

  @override
  Future<SellerProduct> setProductStatus(String productId, ProductStatus status) => _later(() {
    calls.add('productStatus $productId ${status.name}');
    return sellerData.updateProduct(productId, {'status': status.name});
  });

  /// 示范模式上传的商品照片（不会真的上传）：路径 → 内容
  final demoPhotos = <String, Uint8List>{};

  @override
  Future<String> uploadProductPhoto(String wholesalerId, Uint8List bytes) => _later(() {
    final kind = checkProductPhoto(bytes);
    final path = '$wholesalerId/${newUuidV4()}.${kind.ext}';
    calls.add('uploadPhoto ${kind.ext}');
    demoPhotos[path] = bytes;
    return path;
  });

  /// 示范模式没有 Storage：照片网址指向不存在的地方，页面会显示占位图
  @override
  String productPhotoUrl(String path) => 'http://127.0.0.1:1/demo-photos/$path';

  /// 示范模式不用等 3 秒
  @override
  Duration get importPollInterval => const Duration(milliseconds: 200);

  /// 等 AI 最多等多久（测试「等太久」可以改短）
  Duration pollTimeout = const Duration(minutes: 5);

  @override
  Duration get importPollTimeout => pollTimeout;

  @override
  Future<String> uploadPriceList(String wholesalerId, Uint8List bytes, String ext, String contentType) => _later(() {
    calls.add('upload $ext $contentType');
    return '$wholesalerId/${newUuidV4()}.$ext';
  });

  @override
  Future<PriceListImport> createImport({
    required String wholesalerId,
    required String filePath,
    required ImportFileType fileType,
  }) => _later(() {
    calls.add('createImport ${fileType.name}');
    return sellerData.createImport(filePath, fileType);
  });

  @override
  Future<void> startParse(String importId) => _later(() {
    calls.add('startParse');
    sellerData.startParse(importId);
  });

  @override
  Future<bool> markImportFailed(String importId, String code) => _later(() => sellerData.markFailed(importId, code));

  @override
  Future<bool> discardImport(PriceListImport import) => _later(() {
    calls.add('discardImport ${import.fileType.name}');
    return sellerData.discard(import.id);
  });

  @override
  Future<PriceListImport> getImport(String importId) => _later(() => sellerData.getImport(importId));

  @override
  Future<List<PriceListImport>> listImports(String wholesalerId, {int limit = 10}) => _later(sellerData.imports);

  @override
  Future<List<PriceListImportRow>> listImportRows(String importId) => _later(() => sellerData.rows(importId));

  @override
  Future<PriceListImportRow> updateImportRow(String rowId, Map<String, Object?> fields) => _later(() {
    calls.add('updateRow $rowId ${fields['action']}');
    return sellerData.updateRow(rowId, fields);
  });

  /// 按了几次「确认上架」（包括服务器说不行的）
  int applyAttempts = 0;

  @override
  Future<ApplyImportResult> applyImport(String importId) => _later(() {
    applyAttempts++;
    final r = sellerData.apply(importId);
    calls.add('applyImport ${r.created} ${r.updated} ${r.skipped}');
    return r;
  });

  @override
  Future<WholesalerSettings> getWholesalerSettings(String wholesalerId) => _later(sellerData.settings);

  /// 测试用：下一次改通知方式，服务器改好了、但回应在路上断了（App 收到 NETWORK）
  bool loseNextSettingsReply = false;

  @override
  Future<WholesalerSettings> setNotifyChannel(String wholesalerId, NotifyChannel channel) => _later(() {
    calls.add('notifyChannel ${channel.name}');
    final s = sellerData.setNotifyChannel(channel);
    if (loseNextSettingsReply) {
      loseNextSettingsReply = false;
      throw const AppError('NETWORK');
    }
    return s;
  });

  @override
  Future<void> setWhatsappOptIn(String wholesalerId, bool optIn) => _later(() => sellerData.setWhatsappOptIn(optIn));
}
