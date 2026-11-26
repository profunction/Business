import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import 'file_type.dart';
import 'ids.dart';
import 'json.dart';
import 'models/account.dart';
import 'models/admin.dart';
import 'models/catalog.dart';
import 'models/common.dart';
import 'models/orders.dart';
import 'models/seller.dart';

part 'admin_api.dart';

/// 服务器返回的错误。code 是数据库函数 raise 的英文代码（见 docs/02-database.md 第 4 节），
/// 另外还有 App 自己的：NETWORK（没网络）、AUTH（验证码错 / 登录过期）、UNKNOWN。
class AppError implements Exception {
  const AppError(this.code, {this.detail, this.message});

  factory AppError.fromPostgrest(PostgrestException e) {
    final code = RegExp(r'^[A-Z_]+$').hasMatch(e.message) ? e.message : 'UNKNOWN';
    return AppError(code, detail: e.details?.toString(), message: e.message);
  }

  /// Storage 上传失败（档案太大、格式不收、没权限……）
  factory AppError.fromStorage(StorageException e) {
    final status = e.statusCode ?? '';
    final text = '${e.error ?? ''} ${e.message}'.toLowerCase();
    final code = switch (status) {
      '413' => 'FILE_TOO_LARGE',
      '415' => 'UNSUPPORTED_FILE',
      '401' || '403' => 'NOT_ALLOWED',
      _ when text.contains('too large') || text.contains('maximum allowed size') => 'FILE_TOO_LARGE',
      _ when text.contains('mime') => 'UNSUPPORTED_FILE',
      _ when text.contains('row-level security') => 'NOT_ALLOWED',
      _ => 'UNKNOWN',
    };
    return AppError(code, detail: status.isEmpty ? null : status, message: e.message);
  }

  /// Edge Function 调用失败。函数回传 {"error": "CODE"} 时用那个代码；否则按 HTTP 状态猜
  factory AppError.fromFunction(FunctionException e, {Map<int, String> byStatus = const {}}) {
    if (e is FunctionsFetchException) {
      // 登录过期（refresh 失败）也会被包成 FunctionsFetchException
      return e.details is AuthException
          ? AppError('AUTH', detail: sessionExpired, message: e.details?.toString())
          : AppError('NETWORK', message: e.details?.toString());
    }
    if (e is FunctionsRelayException) return AppError('UNKNOWN', detail: '${e.status}', message: e.reasonPhrase);
    var details = e.details;
    if (details is String && details.trimLeft().startsWith('{')) {
      try {
        details = jsonDecode(details);
      } catch (_) {}
    }
    final fromBody = details is Map ? (details['error'] ?? details['code'])?.toString() : null;
    final code = fromBody != null && RegExp(r'^[A-Z_]+$').hasMatch(fromBody)
        ? fromBody
        : byStatus[e.status] ??
              switch (e.status) {
                401 => 'AUTH',
                403 => 'NOT_ALLOWED',
                404 => 'NOT_FOUND',
                413 => 'FILE_TOO_LARGE',
                _ => 'UNKNOWN',
              };
    // 函数自己验 JWT：{"error":"UNAUTHORIZED"}（401）= 登录过期 / 被登出，跟没有代码的 401 一样当 AUTH
    if (code == 'UNAUTHORIZED' || code == 'AUTH') {
      return AppError('AUTH', detail: sessionExpired, message: e.reasonPhrase);
    }
    // parse-price-list 用量满了（429）：detail 是要等几秒（body 的 retry_after），老板才知道要等多久
    if (code == 'TOO_MANY_IMPORTS') {
      final after = details is Map ? details['retry_after'] : null;
      final sec = after is num ? after.ceil() : int.tryParse('${after ?? ''}');
      return AppError(code, detail: sec != null && sec > 0 ? '$sec' : null, message: e.reasonPhrase);
    }
    return AppError(code, detail: '${e.status}', message: e.reasonPhrase);
  }

  /// AUTH 的 detail：登录过期（不是验证码打错）
  static const sessionExpired = 'session';

  final String code;
  final String? detail;
  final String? message;

  /// 价目表导入的错误（IMPORT_ROW_INCOMPLETE 等），detail 是第几行
  int? get rowNo => int.tryParse(detail ?? '');

  /// TOO_MANY_IMPORTS（价目表上传太多次）：要等多久才可以再上传。不知道 → null
  Duration? get retryAfter {
    if (code != 'TOO_MANY_IMPORTS') return null;
    final sec = int.tryParse(detail ?? '');
    return sec == null || sec <= 0 ? null : Duration(seconds: sec);
  }

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
    } on StorageException catch (e) {
      throw AppError.fromStorage(e);
    } on FunctionException catch (e) {
      throw AppError.fromFunction(e);
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

  /// 老板换了 App 的语言：自己的批发商 / 店铺收到的通知（推送、WhatsApp 模板）也换成这个语言。
  /// 发给批发商、店铺的通知看的是 wholesalers.locale / shops.locale，不是个人的 profiles.locale。
  /// RLS：只有老板改得到（员工改了 0 行，不算错）；已经是这个语言的不会再写
  Future<void> setBusinessLocale(
    String locale, {
    Iterable<String> wholesalerIds = const [],
    Iterable<String> shopIds = const [],
  }) => _call(() async {
    for (final id in wholesalerIds) {
      await client.from('wholesalers').update({'locale': locale}).eq('id', id).neq('locale', locale);
    }
    for (final id in shopIds) {
      await client.from('shops').update({'locale': locale}).eq('id', id).neq('locale', locale);
    }
  });

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

  // ---------------- 推送通知 ----------------

  /// 登记这部手机的推送目标（FCM 的 Firebase Installation ID 或旧的 registration token）。
  /// platform：'android' / 'ios' / 'web'；kind：'fid'（2026 年起的新做法）或 'token'。
  /// 同一个值再登记只会更新 last_seen_at；换人登录会转给新的人。
  Future<void> registerDeviceToken(String token, {required String platform, String kind = 'fid'}) => _call(
    () => client.rpc<dynamic>(
      'register_device_token',
      params: {'p_token': token, 'p_platform': platform, 'p_kind': kind},
    ),
  );

  /// 登出前删掉这部手机的推送目标（RLS：只能删自己的）
  Future<void> unregisterDeviceToken(String token) =>
      _call(() => client.from('device_tokens').delete().eq('fcm_token', token));

  // ---------------- 批发商：首页、订单、送货总结 ----------------

  Future<SellerHome> getSellerHome(String wholesalerId) async =>
      SellerHome.fromJson(await _rpcJson('get_seller_home', {'p_wholesaler_id': wholesalerId}));

  /// statuses 空 = 全部；pending 排最前面（先来先做），其他新到旧。limit 1..200
  Future<List<SellerOrderSummary>> listSellerOrders(
    String wholesalerId, {
    List<OrderStatus>? statuses,
    DateTime? deliveryDate,
    int limit = 50,
  }) async => (await _rpcList('list_seller_orders', {
    'p_wholesaler_id': wholesalerId,
    'p_statuses': statuses == null || statuses.isEmpty ? null : statuses.map(orderStatusCode).toList(),
    'p_delivery_date': deliveryDate == null ? null : dateParam(deliveryDate),
    'p_limit': limit,
  })).map(SellerOrderSummary.fromJson).toList();

  /// date 空 = 马来西亚的今天
  Future<DeliverySummary> getDeliverySummary(String wholesalerId, {DateTime? date}) async => DeliverySummary.fromJson(
    await _rpcJson('get_delivery_summary', {
      'p_wholesaler_id': wholesalerId,
      'p_date': date == null ? null : dateParam(date),
    }),
  );

  /// 确认订单；outOfStockItemIds 是缺货的那几样（order_items.id），不算钱。
  /// 全部都缺货时服务器会改成 out_of_stock。回传订单的新状态
  Future<OrderStatus> confirmOrder(String orderId, {List<String> outOfStockItemIds = const []}) => _call(
    () async => orderStatusFrom(
      await client.rpc<dynamic>(
        'confirm_order',
        params: {'p_order_id': orderId, 'p_out_of_stock_item_ids': outOfStockItemIds},
      ),
    ),
  );

  /// 整张单缺货（全部都没有）
  Future<void> markOutOfStock(String orderId, {String? note}) => _setStatus(orderId, OrderStatus.outOfStock, note);

  /// 出发送货
  Future<void> markDelivering(String orderId) => _setStatus(orderId, OrderStatus.delivering);

  /// 批发商按「已送达」
  Future<void> markDelivered(String orderId) => _setStatus(orderId, OrderStatus.delivered);

  Future<void> _setStatus(String orderId, OrderStatus status, [String? note]) => _call(
    () => client.rpc<dynamic>(
      'set_order_status',
      params: {'p_order_id': orderId, 'p_status': orderStatusCode(status), 'p_note': note},
    ),
  );

  /// 批发商的订单一有变化就叫 onChange（新订单、买家取消……）。用完记得 stopWatching。
  /// 断线（App 到背景）再连上时，中间的变化 Realtime 不会补发：重新连上（第二次以后的 SUBSCRIBED）也叫 onChange
  RealtimeChannel watchWholesalerOrders(String wholesalerId, void Function() onChange) {
    return client
        .channel('wholesaler-orders-$wholesalerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'wholesaler_id', value: wholesalerId),
          callback: (_) => onChange(),
        )
        .subscribe(onRejoined(onChange));
  }

  // ---------------- 批发商：商品（直接读写 products 表，RLS 只给自己的） ----------------

  /// 全部商品，包括草稿和下架的
  Future<List<SellerProduct>> listMyProducts(String wholesalerId) => _call(() async {
    final rows = await client
        .from('products')
        .select()
        .eq('wholesaler_id', wholesalerId)
        .order('sort_order')
        .order('name');
    return asJsonList(rows).map(SellerProduct.fromJson).toList();
  });

  Future<SellerProduct> getProduct(String productId) => _call(() async {
    final row = await client.from('products').select().eq('id', productId).maybeSingle();
    if (row == null) throw const AppError('PRODUCT_NOT_FOUND');
    return SellerProduct.fromJson(asJson(row));
  });

  /// 新增（product.isNew）或修改一样商品，回传存好的那一行
  Future<SellerProduct> saveProduct(SellerProduct product) => _call(() async {
    final data = product.toWriteJson();
    final List<dynamic> rows;
    if (product.isNew) {
      rows = await client.from('products').insert({
        ...data,
        'wholesaler_id': product.wholesalerId,
        'created_by': client.auth.currentUser?.id,
      }).select();
    } else {
      rows = await client.from('products').update(data).eq('id', product.id).select();
    }
    if (rows.isEmpty) throw const AppError('PRODUCT_NOT_FOUND');
    return SellerProduct.fromJson(asJson(rows.first));
  });

  /// 库存三个大按钮：有货 / 快卖完 / 缺货
  Future<SellerProduct> setStockStatus(String productId, StockStatus status) =>
      _updateProduct(productId, {'stock_status': stockStatusCode(status)});

  /// 上架（active）/ 下架（archived）
  Future<SellerProduct> setProductStatus(String productId, ProductStatus status) =>
      _updateProduct(productId, {'status': status.name});

  Future<SellerProduct> _updateProduct(String productId, Json fields) => _call(() async {
    final rows = await client.from('products').update(fields).eq('id', productId).select();
    if (rows.isEmpty) throw const AppError('PRODUCT_NOT_FOUND');
    return SellerProduct.fromJson(asJson(rows.first));
  });

  // ---------------- 批发商：价目表导入 ----------------

  /// 查导入状态的间隔和上限（示范模式会改短）
  Duration get importPollInterval => const Duration(seconds: 3);
  Duration get importPollTimeout => const Duration(minutes: 5);

  /// 上传价目表档案到 Storage `price-lists/<wholesalerId>/<uuid>.<ext>`，回传 bucket 里的路径。
  /// ext、contentType 用 [sniffFileType] 从内容判断出来的（不要信档名）
  Future<String> uploadPriceList(String wholesalerId, Uint8List bytes, String ext, String contentType) =>
      _call(() async {
        if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)) throw ArgumentError.value(ext, 'ext');
        final path = '$wholesalerId/${newUuidV4()}.$ext';
        await client.storage
            .from('price-lists')
            .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType));
        return path;
      });

  /// 上传后建一行 price_list_imports（status = processing），回传那一行
  Future<PriceListImport> createImport({
    required String wholesalerId,
    required String filePath,
    required ImportFileType fileType,
  }) => _call(() async {
    final row = await client
        .from('price_list_imports')
        .insert({
          'wholesaler_id': wholesalerId,
          'file_path': filePath,
          'file_type': fileType.name,
          'status': 'processing',
          'created_by': client.auth.currentUser?.id,
        })
        .select()
        .single();
    return PriceListImport.fromJson(asJson(row));
  });

  /// 叫 Edge Function parse-price-list 在背景读价目表（马上回 202）。之后用 [watchImport] 等结果。
  /// 404 = 读不到这份导入；409 IMPORT_NOT_PROCESSING = 已经不是 processing；
  /// 409 IMPORT_ALREADY_RUNNING = 已经有人叫了、正在读（不算失败）
  Future<void> startParse(String importId) => _call(() async {
    try {
      await client.functions.invoke('parse-price-list', body: {'import_id': importId});
    } on FunctionException catch (e) {
      throw AppError.fromFunction(e, byStatus: const {404: 'IMPORT_NOT_FOUND', 409: 'IMPORT_NOT_PROCESSING'});
    }
  });

  /// 一次做完：判断格式 → 上传 → 建导入 → 叫 AI。回传的导入还是 processing。
  /// 不收的格式（HEIC、Word……）→ UNSUPPORTED_FILE；超过 10 MB → FILE_TOO_LARGE。
  /// parse-price-list 不肯读（[importStartRefused]：停权、用量满了、暂时叫不到）：这一次当作没传过——
  /// 删掉导入和档案（首页不会显示「上次的读不到」），错误照样丢出来。用量满了之后，
  /// 等 retry_after 之前再传会直接丢 TOO_MANY_IMPORTS（不上传，不会多一个档案、多一份导入）
  Future<PriceListImport> submitPriceList(String wholesalerId, Uint8List bytes, {String? fileName}) async {
    final kind = checkPriceListFile(bytes, fileName: fileName);
    _checkImportCooldown(wholesalerId);
    final path = await uploadPriceList(wholesalerId, bytes, kind.ext, kind.contentType);
    final import = await createImport(wholesalerId: wholesalerId, filePath: path, fileType: kind.importType!);
    try {
      await startParse(import.id);
    } on AppError catch (e) {
      // 已经有人叫了（另一部手机、等的页面再叫一次）：一样在读，不算失败
      if (e.code == 'IMPORT_ALREADY_RUNNING') return import;
      if (importStartRefused.contains(e.code)) {
        final wait = e.retryAfter;
        if (wait != null) _importCooldown[wholesalerId] = DateTime.now().add(wait);
        var gone = false;
        try {
          gone = await discardImport(import);
        } catch (_) {}
        // 删不掉（没网络……）：照样标成失败，首页才不会一直显示「AI 在读」
        if (!gone) await markImportFailed(import.id, 'START_FAILED').catchError((_) => false);
        rethrow;
      }
      // 叫不到 AI：标成失败（记下真正的原因：没网络 / 登录过期 / 其他），免得首页一直显示「AI 在读」。
      // 批发商重新上传就好。标不了（例如一样没网络）也没关系：之后等的时候 [watchImport] 会再叫一次 AI
      final reason = e.code == 'NETWORK' || e.code == 'AUTH' ? e.code : 'START_FAILED';
      bool? marked;
      try {
        marked = await markImportFailed(import.id, reason);
      } catch (_) {}
      if (marked == false) {
        // 没标到：parse-price-list 其实已经开始读了（202 在路上断了），或已经读完。不是失败，照常等
        try {
          final now = await getImport(import.id);
          if (now.claimedAt != null || now.isDone) return now;
        } catch (_) {}
      }
      rethrow;
    }
    return import;
  }

  /// parse-price-list 这几个回应是「没开始读、什么都没改」（见 supabase/functions/README.md）：
  /// 403 停权、429 用量满了、503 暂时叫不到。这一次的导入不会有人读
  static const importStartRefused = {'WHOLESALER_SUSPENDED', 'TOO_MANY_IMPORTS', 'QUOTA_UNAVAILABLE'};

  /// 批发商 id → 用量满了，等到这个时间才可以再上传（这部手机记着，不用每次都上传了才知道）
  final _importCooldown = <String, DateTime>{};

  void _checkImportCooldown(String wholesalerId) {
    final until = _importCooldown[wholesalerId];
    if (until == null) return;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) {
      _importCooldown.remove(wholesalerId);
      return;
    }
    throw AppError('TOO_MANY_IMPORTS', detail: '${(left.inMilliseconds / 1000).ceil()}');
  }

  /// 还在 processing、而且从来没人开始读（ai_raw 是空的）的导入标成失败（App 叫不到 parse-price-list 时）。
  /// 已经有人在读的不标（回应断了，其实在读）。回传有没有标到
  Future<bool> markImportFailed(String importId, String code) => _call(() async {
    final rows = await client
        .from('price_list_imports')
        .update({'status': 'failed', 'error_message': code})
        .eq('id', importId)
        .eq('status', 'processing')
        .isFilter('ai_raw', null)
        .select('id');
    return rows.isNotEmpty;
  });

  /// 删掉一份没人读过的导入（还是 processing、ai_raw 是空的）和它在 Storage 的档案：parse-price-list 不肯读的那一次。
  /// RLS：只删得到自己批发商的。回传有没有删到（删到了档案删不掉也算）
  Future<bool> discardImport(PriceListImport import) => _call(() async {
    final rows = await client
        .from('price_list_imports')
        .delete()
        .eq('id', import.id)
        .eq('status', 'processing')
        .isFilter('ai_raw', null)
        .select('id');
    if (rows.isEmpty) return false;
    if (import.filePath.isNotEmpty) {
      try {
        await client.storage.from('price-lists').remove([import.filePath]);
      } catch (_) {
        // 档案留着也不影响什么
      }
    }
    return true;
  });

  Future<PriceListImport> getImport(String importId) => _call(() async {
    final row = await client.from('price_list_imports').select().eq('id', importId).maybeSingle();
    if (row == null) throw const AppError('IMPORT_NOT_FOUND');
    return PriceListImport.fromJson(asJson(row));
  });

  /// 最近的几次导入（新到旧）
  Future<List<PriceListImport>> listImports(String wholesalerId, {int limit = 10}) => _call(() async {
    final rows = await client
        .from('price_list_imports')
        .select()
        .eq('wholesaler_id', wholesalerId)
        .order('created_at', ascending: false)
        .limit(limit);
    return asJsonList(rows).map(PriceListImport.fromJson).toList();
  });

  /// 每 [importPollInterval] 查一次导入，每次都回传；不是 processing（review / failed / applied）就结束。
  /// 超过 [importPollTimeout] → AppError('IMPORT_TIMEOUT')。中间没网络、服务器暂时出错（502……）不算失败，下一次再查；
  /// 只有读不到这份（IMPORT_NOT_FOUND）、没权限、登录过期才丢出来。
  ///
  /// 卡住的导入（[importNeedsRestart]：从来没开始读，或「在跑」太久、worker 死掉了）会再叫一次 parse-price-list
  /// （函数自己会判断能不能重跑，同时只会跑一份）；等到最后还是没人在读的，也再叫一次。
  /// 叫不动（登录过期、函数没设定好）而且从来没开始读的，标成失败，首页才会让老板重新上传。
  ///
  /// 不想等了就 cancel 这个 stream；暂停（pause）的时候不查
  Stream<PriceListImport> watchImport(String importId) {
    late final StreamController<PriceListImport> out;
    Timer? timer;
    // 期限用 Timer 算（不用 DateTime.now()）：测试的假时间也会到
    Timer? deadline;
    var timedOut = false;
    var polling = false;
    var cancelled = false;
    // 下一次可以再叫 AI 的时间（叫过之后至少等 importRestartInterval；用量满了等 retry_after）
    DateTime? nextKick;

    void stop([Object? error]) {
      timer?.cancel();
      timer = null;
      deadline?.cancel();
      if (out.isClosed) return;
      if (error != null) out.addError(error);
      out.close();
    }

    late final Future<void> Function() poll;

    void schedule({bool now = false}) {
      if (cancelled || out.isClosed || out.isPaused || polling || timer != null) return;
      timer = Timer(now ? Duration.zero : importPollInterval, () {
        timer = null;
        poll();
      });
    }

    poll = () async {
      if (cancelled || out.isClosed || polling) return;
      polling = true;
      var again = false;
      try {
        PriceListImport? current;
        try {
          current = await getImport(importId);
        } on AppError catch (e) {
          if (_importWatchFatal.contains(e.code)) {
            stop(e);
            return;
          }
          // 没网络、网关 502、暂时出错：下一次再查
        }
        if (cancelled || out.isClosed) return;
        final now = DateTime.now();
        if (current != null) {
          out.add(current);
          if (current.isDone) {
            stop();
            return;
          }
          final stuck = importNeedsRestart(current, now: now) || (timedOut && current.claimedAt == null);
          if (stuck && (nextKick == null || !now.isBefore(nextKick!))) {
            // 刚好读完了、或标成失败了：马上再查一次，把结果交出去
            final kick = await _restartParse(current);
            again = kick.again;
            nextKick = now.add(kick.wait > importRestartInterval ? kick.wait : importRestartInterval);
          }
        }
        if (cancelled || out.isClosed) return;
        if (!again && timedOut) stop(const AppError('IMPORT_TIMEOUT'));
      } finally {
        polling = false;
      }
      schedule(now: again);
    };

    out = StreamController<PriceListImport>(
      onListen: () {
        deadline = Timer(importPollTimeout, () => timedOut = true);
        poll();
      },
      onPause: () {
        timer?.cancel();
        timer = null;
      },
      onResume: schedule,
      onCancel: () {
        cancelled = true;
        timer?.cancel();
        timer = null;
        deadline?.cancel();
      },
    );
    return out.stream;
  }

  /// 等导入的时候遇到这些错误就不再等（其他的当成暂时的，下一次再查）
  static const _importWatchFatal = {'IMPORT_NOT_FOUND', 'NOT_ALLOWED', 'AUTH', 'NOT_LOGGED_IN'};

  /// 再叫 parse-price-list 都没用的错误：登录过期、函数没设定好、参数不对、批发商停权了
  static const _parseCannotStart = {
    'AUTH',
    'NOT_ALLOWED',
    'CONFIG_MISSING',
    'INVALID_IMPORT_ID',
    'WHOLESALER_SUSPENDED',
  };

  /// 卡住的导入再叫一次 parse-price-list。again = 状态可能变了（读完了 / 标成失败了），马上再查一次；
  /// wait = 至少等多久才再叫（用量满了：函数说的 retry_after）
  Future<({bool again, Duration wait})> _restartParse(PriceListImport imp) async {
    try {
      await startParse(imp.id);
      return (again: false, wait: Duration.zero);
    } on AppError catch (e) {
      switch (e.code) {
        case 'IMPORT_ALREADY_RUNNING':
          return (again: false, wait: Duration.zero); // 有人在读
        case 'IMPORT_NOT_PROCESSING' || 'IMPORT_NOT_FOUND':
          return (again: true, wait: Duration.zero);
        case 'TOO_MANY_IMPORTS':
          // 用量满了（不算失败，导入没动）：等到有位置再叫
          return (again: false, wait: e.retryAfter ?? Duration.zero);
      }
      // 从来没开始读、又叫不动：标成失败（首页会让老板重新上传）。没网络、函数暂时出错：等下一次
      if (imp.claimedAt != null || !_parseCannotStart.contains(e.code)) return (again: false, wait: Duration.zero);
      try {
        await markImportFailed(imp.id, e.code == 'AUTH' ? 'AUTH' : 'START_FAILED');
        return (again: true, wait: Duration.zero);
      } on AppError {
        return (again: false, wait: Duration.zero);
      }
    }
  }

  Future<List<PriceListImportRow>> listImportRows(String importId) => _call(() async {
    final rows = await client.from('price_list_import_rows').select().eq('import_id', importId).order('row_no');
    return asJsonList(rows).map(PriceListImportRow.fromJson).toList();
  });

  static const _importRowFields = {
    'name',
    'unit',
    'pack_qty',
    'price_sen',
    'min_order_qty',
    'matched_product_id',
    'action',
  };

  /// 批发商改一行（只能改 name、unit、pack_qty、price_sen、min_order_qty、matched_product_id、action）。
  /// 通常传 row.copyWith(...).toWriteJson()
  Future<PriceListImportRow> updateImportRow(String rowId, Map<String, Object?> fields) => _call(() async {
    final bad = fields.keys.where((k) => !_importRowFields.contains(k));
    if (bad.isNotEmpty) throw ArgumentError('not editable: ${bad.join(', ')}');
    final rows = await client.from('price_list_import_rows').update(fields).eq('id', rowId).select();
    if (rows.isEmpty) throw const AppError('IMPORT_NOT_FOUND');
    return PriceListImportRow.fromJson(asJson(rows.first));
  });

  /// 确认上架：create 行新增商品，update 行改对到的商品，skip 不动。
  /// 行不完整 → IMPORT_ROW_INCOMPLETE（error.rowNo 是第几行）
  Future<ApplyImportResult> applyImport(String importId) async =>
      ApplyImportResult.fromJson(await _rpcJson('apply_price_list_import', {'p_import_id': importId}));

  // ---------------- 批发商：商品照片 ----------------

  /// 上传一张商品照片到 Storage `product-photos/<wholesalerId>/<uuid>.<ext>`（公开读），回传路径。
  /// 存进商品的 photo_paths 才会显示。只收 JPEG / PNG / WebP、最多 5 MB（[checkProductPhoto]）
  Future<String> uploadProductPhoto(String wholesalerId, Uint8List bytes) => _call(() async {
    final kind = checkProductPhoto(bytes);
    final path = '$wholesalerId/${newUuidV4()}.${kind.ext}';
    await client.storage
        .from('product-photos')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: kind.contentType));
    return path;
  });

  /// 商品照片的网址（bucket 是公开读的）
  String productPhotoUrl(String path) => client.storage.from('product-photos').getPublicUrl(path);

  // ---------------- 批发商：设定 ----------------

  Future<WholesalerSettings> getWholesalerSettings(String wholesalerId) => _call(() async {
    final row = await client
        .from('wholesalers')
        .select('id, name, phone, whatsapp_phone, notify_channel, whatsapp_opt_in_at')
        .eq('id', wholesalerId)
        .maybeSingle();
    if (row == null) throw const AppError('WHOLESALER_NOT_FOUND');
    return WholesalerSettings.fromJson(asJson(row));
  });

  /// 通知方式（只有批发商老板能改，员工会得到 NOT_ALLOWED）。选 WhatsApp 等于同意用 WhatsApp 收订单。
  /// 先记同意、再改通知方式：第二步失败的话还是原本的通知方式（多了同意也没关系）。
  /// 反过来的话会留下「选了 WhatsApp、没有同意」：服务器什么通知都不发（不会改用推送）
  Future<WholesalerSettings> setNotifyChannel(String wholesalerId, NotifyChannel channel) => _call(() async {
    if (channel == NotifyChannel.whatsapp) await setWhatsappOptIn(wholesalerId, true);
    final rows = await client
        .from('wholesalers')
        .update({'notify_channel': channel.name})
        .eq('id', wholesalerId)
        .select('id');
    if (rows.isEmpty) throw const AppError('NOT_ALLOWED');
    return getWholesalerSettings(wholesalerId);
  });

  /// 同意 / 不再同意用 WhatsApp 收订单（Meta 规定要先有同意才能发）。已经同意过的不会改时间
  Future<void> setWhatsappOptIn(String wholesalerId, bool optIn) => _call(() async {
    if (optIn) {
      await client
          .from('wholesalers')
          .update({'whatsapp_opt_in_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', wholesalerId)
          .isFilter('whatsapp_opt_in_at', null);
    } else {
      final rows = await client
          .from('wholesalers')
          .update({'whatsapp_opt_in_at': null})
          .eq('id', wholesalerId)
          .select('id');
      if (rows.isEmpty) throw const AppError('NOT_ALLOWED');
    }
  });
}

/// 上传价目表之前检查（不用等上传完才知道）：超过 10 MB → FILE_TOO_LARGE；照片超过 7 MB（AI 收不了）→
/// FILE_TOO_LARGE（detail 'image'）；HEIC、Word、看不懂的 → UNSUPPORTED_FILE（detail 是认出来的格式，例如 'heic'）。
/// 回传真正的格式
FileKind checkPriceListFile(Uint8List bytes, {String? fileName}) {
  if (bytes.length > priceListMaxBytes) throw const AppError('FILE_TOO_LARGE');
  final kind = sniffFileType(bytes, fileName: fileName);
  if (!kind.isPriceList) throw AppError('UNSUPPORTED_FILE', detail: kind.type.name);
  if (kind.importType == ImportFileType.image && bytes.length > priceListMaxImageBytes) {
    throw const AppError('FILE_TOO_LARGE', detail: 'image');
  }
  return kind;
}

/// 「从来没开始读」等多久才算卡住（建好导入到叫 AI 之间只有一下子）
const importStartGrace = Duration(seconds: 30);

/// parse-price-list「在跑」超过 10 分钟就当成死掉、可以重跑（函数的 STALE_CLAIM_MS）。多等一点，手机的时间可能不准
const importStaleClaim = Duration(minutes: 10, seconds: 15);

/// 同一次等待里，再叫 AI 的间隔
const importRestartInterval = Duration(seconds: 30);

/// 还在 processing 的导入是不是卡住了、要再叫一次 parse-price-list（跟函数的规则一样）：
/// 从来没人开始读（ai_raw 是空的：App 叫 AI 的时候断线、被关掉），或「在跑」太久（读的 worker 死掉了）
bool importNeedsRestart(PriceListImport imp, {DateTime? now}) {
  if (imp.status != ImportStatus.processing) return false;
  final t = now ?? DateTime.now();
  final claimed = imp.claimedAt;
  if (claimed == null) return t.difference(imp.createdAt) >= importStartGrace;
  return t.difference(claimed) >= importStaleClaim;
}

/// 商品照片的大小上限（跟 Storage bucket product-photos 一样：5 MB）
const productPhotoMaxBytes = 5 * 1024 * 1024;

/// 商品照片只收 JPEG / PNG / WebP（bucket 的 allowed_mime_types），最多 5 MB
FileKind checkProductPhoto(Uint8List bytes) {
  if (bytes.length > productPhotoMaxBytes) throw const AppError('FILE_TOO_LARGE');
  final kind = sniffFileType(bytes);
  if (kind != FileKind.jpeg && kind != FileKind.png && kind != FileKind.webp) {
    throw AppError('UNSUPPORTED_FILE', detail: kind.type.name);
  }
  return kind;
}

/// Realtime channel.subscribe() 的 callback：第一次 SUBSCRIBED 不用做什么；之后每一次 SUBSCRIBED
/// （断线、App 回到前台重新连上）叫 [onRejoin]，把断线时漏掉的变化补回来
void Function(RealtimeSubscribeStatus status, Object? error) onRejoined(void Function() onRejoin) {
  var joined = false;
  return (status, _) {
    if (status != RealtimeSubscribeStatus.subscribed) return;
    if (joined) onRejoin();
    joined = true;
  };
}

/// 'YYYY-MM-DD'（日期参数；DateTime 的年月日照原样，不换时区）
String dateParam(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
