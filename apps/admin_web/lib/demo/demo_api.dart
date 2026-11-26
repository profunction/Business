import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'demo_data.dart';

/// 示范模式 / 自动测试用的客服后台：不连服务器，资料来自本机数据库导出的真实样本（demo_data.dart，
/// tool/export_fixtures.sh 产生）。按了按钮会跟着变（审核、改价、代下单……），规则照数据库函数简单做一份，
/// 只放在记忆体里，重新整理网页就回到原样。只有 main_demo.dart 和测试会用到。
class DemoAdminApi extends AdminApi {
  DemoAdminApi({this.notAdmin = false, this.delay = const Duration(milliseconds: 120)})
    : super(
        SupabaseClient('http://127.0.0.1:1', 'demo-key', authOptions: const AuthClientOptions(autoRefreshToken: false)),
      ) {
    _shops = _list('admin_shops');
    _wholesalers = _list('admin_wholesalers');
    _orders = _list('admin_orders_rows');
    _offers = _list('admin_offers');
    _subs = _list('admin_subscriptions');
    _report = _j('admin_commission_report') as Json;
    _audit = _list('admin_audit_logs');
    final detail = _j('admin_order_detail') as Json;
    _details[detail['id'] as String] = detail;
    _products['00000000-0000-4000-a000-00000000000a'] = _list('admin_products');
    final quote = CartQuote.fromJson(_j('admin_quote') as Json);
    _carts['00000000-0000-4000-b000-000000000001'] = {
      for (final g in quote.groups)
        for (final line in g.lines) line.productId: line.qty,
    };
  }

  /// 登录的是老板（不是客服）：看「不是客服」那一页
  final bool notAdmin;
  final Duration delay;

  bool loggedIn = true;

  /// 示范模式没有真的登录事件，登录成功时叫这个（DemoSession 会设定）
  void Function()? onLoggedIn;

  /// 叫过哪些（测试检查用）
  final calls = <String>[];

  late final List<Json> _shops;
  late final List<Json> _wholesalers;
  late final List<Json> _orders;
  late final List<Json> _offers;
  late final List<Json> _subs;
  late final Json _report;
  late final List<Json> _audit;
  final _details = <String, Json>{};
  final _products = <String, List<Json>>{};
  final _carts = <String, Map<String, int>>{};
  final _references = <String>{};
  int _seq = 0;

  Object? _j(String name) {
    if (name == 'admin_orders_rows') return (jsonDecode(demoFixtures['admin_orders']!) as Map)['orders'];
    return jsonDecode(demoFixtures[name]!);
  }

  List<Json> _list(String name) => asJsonList(_j(name));

  Future<T> _later<T>(String call, T Function() f) async {
    calls.add(call);
    await Future<void>.delayed(delay);
    return f();
  }

  String _id(String kind) =>
      '00000000-0000-4000-d000-${kind.padRight(4, '0').substring(0, 4)}${(++_seq).toString().padLeft(8, '0')}';

  String get _now => DateTime.now().toUtc().toIso8601String();

  Json _find(List<Json> list, String id, [String key = 'id']) =>
      list.firstWhere((e) => e[key] == id, orElse: () => throw const AppError('NOT_FOUND'));

  void _log(
    String action,
    String table,
    String? recordId, {
    String? shopId,
    String? wholesalerId,
    Json? before,
    Json? after,
  }) {
    final profile = asJson(asJson(_j('admin_my_context'))['profile']);
    final nextId = _audit.fold<int>(0, (m, e) => asInt(e['id']) > m ? asInt(e['id']) : m) + 1;
    _audit.insert(0, {
      'id': nextId,
      'created_at': _now,
      'actor_id': profile['id'],
      'actor_name': profile['full_name'],
      'actor_phone': profile['phone'],
      'action': action,
      'table_name': table,
      'record_id': recordId,
      'acting_for_shop_id': shopId,
      'acting_for_shop_name': shopId == null ? null : _shops.where((s) => s['id'] == shopId).firstOrNull?['name'],
      'acting_for_wholesaler_id': wholesalerId,
      'acting_for_wholesaler_name': wholesalerId == null
          ? null
          : _wholesalers.where((w) => w['id'] == wholesalerId).firstOrNull?['name'],
      'before': before,
      'after': after,
    });
  }

  // ---------------- 登录 ----------------

  @override
  Future<void> sendOtp(String phoneE164, {String? locale}) => _later('sendOtp $phoneE164', () {});

  @override
  Future<void> verifyOtp(String phoneE164, String code) => _later('verifyOtp $code', () {
    if (code != '123456') throw const AppError('AUTH');
    loggedIn = true;
    onLoggedIn?.call();
  });

  @override
  Future<void> signOut() => _later('signOut', () => loggedIn = false);

  @override
  Future<MyContext> getMyContext() => _later('getMyContext', () {
    final c = asJson(_j('admin_my_context'));
    if (notAdmin) c['profile'] = {...asJson(c['profile']), 'role': 'buyer'};
    return MyContext.fromJson(c);
  });

  @override
  Future<void> setMyLocale(String userId, String locale) async {}

  // ---------------- 首页、店铺、批发商 ----------------

  @override
  Future<AdminDashboard> getDashboard() => _later('getDashboard', () {
    final d = asJson(_j('admin_dashboard'));
    d['pending_wholesalers'] = _wholesalers.where((w) => w['status'] == 'pending').length;
    d['pending_orders'] = _orders.where((o) => o['status'] == 'pending').length;
    d['unconfirmed_orders'] = _orders.where(_isUnconfirmed).length;
    d['month_gmv_sen'] = _report['gmv_sen'];
    d['month_commission_sen'] = _report['commission_sen'];
    final latest = _subs.map((s) => s['status']).toList();
    d['subscriptions'] = {
      for (final k in ['trialing', 'active', 'past_due', 'lapsed']) k: latest.where((s) => s == k).length,
      'founding_price': _subs.where((s) => s['is_founding_price'] == true && s['status'] != 'lapsed').length,
    };
    return AdminDashboard.fromJson(d);
  });

  bool _isUnconfirmed(Json o) => o['status'] == 'pending' && asInt(o['pending_minutes']) >= 30;

  bool _matches(String? search, List<Object?> fields) {
    final q = search?.trim().toLowerCase() ?? '';
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^(60|0)+'), '');
    return fields.any((f) {
      final s = '${f ?? ''}'.toLowerCase();
      return s.contains(q) || (digits.length >= 3 && RegExp(r'^[0-9+\- ()]+$').hasMatch(q) && s.contains(digits));
    });
  }

  @override
  Future<List<AdminShop>> listShops({String? search, int limit = 50}) => _later(
    'listShops',
    () => [
      for (final s in _shops)
        if (_matches(search, [s['name'], s['contact_name'], s['phone'], s['whatsapp_phone']])) AdminShop.fromJson(s),
    ],
  );

  @override
  Future<List<AdminWholesaler>> listAllWholesalers({WholesalerStatus? status, String? search}) => _later(
    'listWholesalers',
    () => [
      for (final w in _wholesalers)
        if ((status == null || w['status'] == status.name) &&
            _matches(search, [w['name'], w['contact_name'], w['phone'], w['whatsapp_phone']]))
          AdminWholesaler.fromJson(w),
    ]..sort((a, b) => a.status.index.compareTo(b.status.index)),
  );

  // ---------------- 订单 ----------------

  @override
  Future<AdminOrderPage> listAllOrders(AdminOrderFilter filter) => _later('listAllOrders', () {
    DateTime day(Json o) {
      final t = DateTime.parse(o['created_at'] as String).toUtc().add(const Duration(hours: 8));
      return DateTime(t.year, t.month, t.day);
    }

    final hit = _orders.where((o) {
      final s = orderStatusFrom(o['status']);
      return (filter.from == null || !day(o).isBefore(filter.from!)) &&
          (filter.to == null || !day(o).isAfter(filter.to!)) &&
          (filter.wholesalerId == null || o['wholesaler_id'] == filter.wholesalerId) &&
          (filter.shopId == null || o['shop_id'] == filter.shopId) &&
          (filter.statuses.isEmpty || filter.statuses.contains(s)) &&
          (filter.sources.isEmpty || filter.sources.contains(orderSourceFrom(o['source']))) &&
          (!filter.unconfirmedOnly || _isUnconfirmed(o));
    }).toList();
    hit.sort((a, b) {
      final c = (a['created_at'] as String).compareTo(b['created_at'] as String);
      return filter.unconfirmedOnly ? c : -c;
    });
    return AdminOrderPage.fromJson({
      'total': hit.length,
      'orders': hit.skip(filter.offset).take(filter.limit).toList(),
    });
  });

  Json _actions(String status) => {
    'can_cancel': status == 'pending' || status == 'confirmed',
    'can_mark_received': status == 'confirmed' || status == 'delivering',
    'can_review': false,
    'can_confirm': status == 'pending',
    'can_mark_delivering': status == 'confirmed',
    'can_mark_delivered': status == 'confirmed' || status == 'delivering',
  };

  /// 样本里只有一张有完整明细；其他的照列表那一行补一份
  Json _detail(String id) => _details.putIfAbsent(id, () {
    final o = _find(_orders, id);
    final shop = _shops.where((s) => s['id'] == o['shop_id']).firstOrNull ?? const {};
    return {
      'id': id,
      'order_no': o['order_no'],
      'status': o['status'],
      'source': o['source'],
      'goods_subtotal_sen': o['goods_subtotal_sen'],
      'shipping_fee_sen': o['shipping_fee_sen'],
      'total_sen': o['total_sen'],
      'note': null,
      'created_at': o['created_at'],
      'expected_delivery_date': o['expected_delivery_date'],
      'shop': {
        'id': o['shop_id'],
        'name': o['shop_name'],
        'phone': o['shop_phone'],
        'address': shop['address'],
        'contact_name': shop['contact_name'],
        'zone_name': shop['zone_name'],
      },
      'wholesaler': {
        'id': o['wholesaler_id'],
        'name': o['wholesaler_name'],
        'phone': o['wholesaler_phone'],
        'payment_terms': ['cod'],
      },
      'items': [
        {
          'id': '$id-item-1',
          'product_id': null,
          'name': o['wholesaler_name'],
          'unit': 'carton',
          'pack_qty': 1,
          'unit_price_sen': o['goods_subtotal_sen'],
          'qty': 1,
          'line_total_sen': o['goods_subtotal_sen'],
          'is_out_of_stock': false,
        },
      ],
      'events': [
        {
          'from_status': null,
          'to_status': 'pending',
          'channel': o['source'] == 'admin' ? 'admin' : 'app',
          'created_at': o['created_at'],
        },
        if (o['status'] != 'pending')
          {'from_status': 'pending', 'to_status': o['status'], 'channel': 'app', 'created_at': o['created_at']},
      ],
      'review': null,
      'actions': _actions(o['status'] as String),
    };
  });

  @override
  Future<OrderDetail> getOrder(String orderId) => _later('getOrder', () => OrderDetail.fromJson(_detail(orderId)));

  @override
  Future<void> logFollowup(String orderId, String note) => _later('logFollowup $note', () {
    final o = _find(_orders, orderId);
    o['last_followup'] = {'at': _now, 'note': note};
    _log(
      'admin_log_followup',
      'orders',
      orderId,
      shopId: o['shop_id'] as String?,
      wholesalerId: o['wholesaler_id'] as String?,
      after: {'note': note},
    );
  });

  void _setStatus(String id, String to, {String? note, String action = 'admin_set_order_status', Json? extra}) {
    final o = _find(_orders, id);
    final d = _detail(id);
    final from = o['status'] as String;
    o['status'] = to;
    o['pending_minutes'] = to == 'pending' ? o['pending_minutes'] : null;
    d['status'] = to;
    d['actions'] = _actions(to);
    if (to == 'cancelled') d['cancel_reason'] = note;
    (d['events'] as List).add({
      'from_status': from,
      'to_status': to,
      'channel': 'admin',
      'note': note,
      'created_at': _now,
    });
    _log(
      action,
      'orders',
      id,
      shopId: o['shop_id'] as String?,
      wholesalerId: o['wholesaler_id'] as String?,
      before: {'status': from},
      after: {'status': to, ...?extra},
    );
  }

  static const _allowed = {
    'confirmed': {'pending'},
    'out_of_stock': {'pending'},
    'delivering': {'confirmed'},
    'delivered': {'confirmed', 'delivering'},
    'cancelled': {'pending', 'confirmed'},
  };

  @override
  Future<OrderDetail> setOrderStatusAsAdmin(String orderId, OrderStatus status, {String? note}) =>
      _later('setOrderStatus ${orderStatusCode(status)}', () {
        final from = _find(_orders, orderId)['status'];
        final to = orderStatusCode(status);
        if (!(_allowed[to] ?? const {}).contains(from)) throw AppError('INVALID_TRANSITION', detail: '$from -> $to');
        if (to == 'out_of_stock') {
          for (final i in (_detail(orderId)['items'] as List).cast<Map>()) {
            i['is_out_of_stock'] = true;
          }
        }
        _setStatus(orderId, to, note: note);
        return OrderDetail.fromJson(_detail(orderId));
      });

  @override
  Future<OrderDetail> confirmOrderAsAdmin(String orderId, {List<String> outOfStockItemIds = const []}) =>
      _later('confirmOrder ${outOfStockItemIds.length}', () {
        final o = _find(_orders, orderId);
        if (o['status'] != 'pending') throw AppError('INVALID_TRANSITION', detail: '${o['status']} -> confirmed');
        final d = _detail(orderId);
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        for (final i in items) {
          i['is_out_of_stock'] = outOfStockItemIds.contains(i['id']);
        }
        final left = items.where((i) => i['is_out_of_stock'] != true);
        if (left.isEmpty) {
          _setStatus(orderId, 'out_of_stock', action: 'admin_confirm_order');
        } else {
          final goods = left.fold<int>(0, (s, i) => s + asInt(i['line_total_sen']));
          for (final m in [o, d]) {
            m['goods_subtotal_sen'] = goods;
            m['total_sen'] = goods + asInt(m['shipping_fee_sen']);
          }
          _setStatus(
            orderId,
            'confirmed',
            action: 'admin_confirm_order',
            extra: {'out_of_stock_item_ids': outOfStockItemIds},
          );
        }
        return OrderDetail.fromJson(d);
      });

  // ---------------- 代买家下单 ----------------

  bool _fullAccess(String shopId) => _shops.where((s) => s['id'] == shopId).firstOrNull?['has_full_access'] == true;

  /// 未付费的店：只看得到免费开放的批发商 A 的价钱（跟样本里 Siti 一样）
  bool _visible(String shopId, Json offer) =>
      _fullAccess(shopId) || offer['wholesaler_id'] == '00000000-0000-4000-a000-00000000000a';

  @override
  Future<List<Offer>> getOffers(
    String shopId, {
    String? catalogItemId,
    String? wholesalerId,
    String? categoryId,
    String? search,
  }) => _later('getOffers', () {
    return [
      for (final o in _offers)
        if (_matches(search, [o['product_name']]) && (wholesalerId == null || o['wholesaler_id'] == wholesalerId))
          Offer.fromJson(
            _visible(shopId, o)
                ? o
                : {...o, 'price_visible': false, 'price_sen': null, 'price_per_base_unit_sen': null},
          ),
    ];
  });

  Json _quoteJson(String shopId) {
    final cart = _carts[shopId] ?? const {};
    final byWholesaler = <String, List<Json>>{};
    for (final e in cart.entries) {
      final o = _offers.where((x) => x['product_id'] == e.key).firstOrNull;
      if (o == null) continue;
      byWholesaler.putIfAbsent(o['wholesaler_id'] as String, () => []).add({...o, 'qty': e.value});
    }
    var canPlace = byWholesaler.isNotEmpty;
    var goodsTotal = 0;
    var shippingTotal = 0;
    final groups = <Json>[];
    for (final lines in byWholesaler.values) {
      final first = lines.first;
      var goods = 0;
      final out = <Json>[];
      for (final o in lines) {
        final visible = _visible(shopId, o);
        final qty = o['qty'] as int;
        final problem = !visible
            ? 'WHOLESALER_LOCKED'
            : o['stock_status'] == 'out_of_stock'
            ? 'OUT_OF_STOCK'
            : qty < asInt(o['min_order_qty'], 1)
            ? 'BELOW_MIN_QTY'
            : null;
        final line = asInt(o['price_sen']) * qty;
        if (problem == null) goods += line;
        if (problem != null) canPlace = false;
        out.add({
          'product_id': o['product_id'],
          'product_name': o['product_name'],
          'unit': o['unit'],
          'pack_qty': o['pack_qty'],
          'qty': qty,
          'min_order_qty': o['min_order_qty'],
          'unit_price_sen': visible ? o['price_sen'] : null,
          'line_total_sen': visible ? line : null,
          'problem': problem,
        });
      }
      final freeMin = asIntOrNull(first['free_shipping_min_sen']);
      final shipping = freeMin != null && goods >= freeMin ? 0 : asInt(first['shipping_fee_sen']);
      final shortBy = (asInt(first['min_order_sen']) - goods).clamp(0, 1 << 31);
      if (shortBy > 0) canPlace = false;
      goodsTotal += goods;
      shippingTotal += shipping;
      groups.add({
        'wholesaler_id': first['wholesaler_id'],
        'wholesaler_name': first['wholesaler_name'],
        'goods_subtotal_sen': goods,
        'shipping_fee_sen': shipping,
        'free_shipping_min_sen': freeMin,
        'min_order_sen': first['min_order_sen'],
        'short_by_sen': shortBy,
        'expected_delivery_date': null,
        'problem': shortBy > 0 ? 'BELOW_MIN_ORDER' : null,
        'lines': out,
      });
    }
    return {
      'shop_id': shopId,
      'can_place': canPlace,
      'goods_total_sen': goodsTotal,
      'shipping_total_sen': shippingTotal,
      'total_sen': goodsTotal + shippingTotal,
      'groups': groups,
    };
  }

  @override
  Future<CartQuote> quoteCart(String shopId) => _later('quoteCart', () => CartQuote.fromJson(_quoteJson(shopId)));

  void _syncCartCount(String shopId) {
    final s = _shops.where((x) => x['id'] == shopId).firstOrNull;
    if (s != null) s['cart_count'] = _carts[shopId]?.length ?? 0;
  }

  @override
  Future<CartQuote> setCartItemAsAdmin(String shopId, String productId, int qty) => _later('setCartItem $qty', () {
    final cart = _carts.putIfAbsent(shopId, () => {});
    final before = cart[productId];
    if (qty <= 0) {
      cart.remove(productId);
    } else {
      cart[productId] = qty;
    }
    _syncCartCount(shopId);
    final w = _offers.where((o) => o['product_id'] == productId).firstOrNull?['wholesaler_id'] as String?;
    _log(
      'admin_set_cart_item',
      'cart_items',
      productId,
      shopId: shopId,
      wholesalerId: w,
      before: {'qty': before},
      after: {'qty': qty <= 0 ? null : qty},
    );
    return CartQuote.fromJson(_quoteJson(shopId));
  });

  @override
  Future<void> clearCartAsAdmin(String shopId) => _later('clearCart', () {
    _carts.remove(shopId);
    _syncCartCount(shopId);
    _log('admin_clear_cart', 'cart_items', shopId, shopId: shopId);
  });

  @override
  Future<AdminPlacedOrder> placeOrderAsAdmin(String shopId, {required int expectedTotalSen, String? note}) =>
      _later('placeOrder $expectedTotalSen', () {
        final q = _quoteJson(shopId);
        if ((q['groups'] as List).isEmpty) throw const AppError('CART_EMPTY');
        if (q['can_place'] != true) throw AppError('CART_HAS_PROBLEMS', detail: jsonEncode(q));
        if (q['total_sen'] != expectedTotalSen) throw AppError('PRICE_CHANGED', detail: jsonEncode(q));
        final shop = _find(_shops, shopId);
        final checkout = _id('chk');
        final placed = <Json>[];
        for (final g in (q['groups'] as List).cast<Json>()) {
          final id = _id('ord');
          final no = 'JHB261126-${(900 + _seq).toString().padLeft(5, '0')}';
          final w = _wholesalers.where((x) => x['id'] == g['wholesaler_id']).firstOrNull ?? const {};
          final total = asInt(g['goods_subtotal_sen']) + asInt(g['shipping_fee_sen']);
          final lines = (g['lines'] as List).cast<Json>();
          _orders.insert(0, {
            'id': id,
            'order_no': no,
            'status': 'pending',
            'source': 'admin',
            'shop_id': shopId,
            'shop_name': shop['name'],
            'shop_phone': shop['whatsapp_phone'] ?? shop['phone'],
            'wholesaler_id': g['wholesaler_id'],
            'wholesaler_name': g['wholesaler_name'],
            'wholesaler_phone': w['whatsapp_phone'] ?? w['phone'],
            'goods_subtotal_sen': g['goods_subtotal_sen'],
            'shipping_fee_sen': g['shipping_fee_sen'],
            'total_sen': total,
            'item_count': lines.length,
            'out_of_stock_count': 0,
            'created_at': _now,
            'pending_minutes': 0,
          });
          _detail(id)
            ..['note'] = note
            ..['items'] = [
              for (final (i, line) in lines.indexed)
                {
                  'id': '$id-item-$i',
                  'product_id': line['product_id'],
                  'name': line['product_name'],
                  'unit': line['unit'],
                  'pack_qty': line['pack_qty'],
                  'unit_price_sen': line['unit_price_sen'],
                  'qty': line['qty'],
                  'line_total_sen': line['line_total_sen'],
                  'is_out_of_stock': false,
                },
            ];
          placed.add({
            'id': id,
            'order_no': no,
            'wholesaler_id': g['wholesaler_id'],
            'wholesaler_name': g['wholesaler_name'],
            'total_sen': total,
          });
        }
        _carts.remove(shopId);
        _syncCartCount(shopId);
        _log(
          'admin_place_order',
          'checkouts',
          checkout,
          shopId: shopId,
          after: {'checkout_id': checkout, 'total_sen': expectedTotalSen, 'note': note, 'orders': placed},
        );
        return AdminPlacedOrder.fromJson({'checkout_id': checkout, 'orders': placed});
      });

  // ---------------- 代批发商管商品 ----------------

  List<Json> _productsOf(String wholesalerId) => _products.putIfAbsent(
    wholesalerId,
    () => [
      for (final o in _offers)
        if (o['wholesaler_id'] == wholesalerId)
          {
            'id': o['product_id'],
            'wholesaler_id': wholesalerId,
            'catalog_item_id': o['catalog_item_id'],
            'category_id': o['category_id'],
            'name': o['product_name'],
            'description': o['description'],
            'photo_paths': o['photo_paths'],
            'unit': o['unit'],
            'pack_qty': o['pack_qty'],
            'price_sen': o['price_sen'],
            'min_order_qty': o['min_order_qty'],
            'stock_status': o['stock_status'],
            'status': 'active',
            'sort_order': 0,
          },
    ],
  );

  @override
  Future<List<SellerProduct>> listProductsAsAdmin(String wholesalerId) =>
      _later('listProducts', () => _productsOf(wholesalerId).map(SellerProduct.fromJson).toList());

  @override
  Future<SellerProduct> saveProductAsAdmin(String wholesalerId, String? productId, Json fields) =>
      _later('saveProduct ${fields.keys.join(',')}', () {
        final list = _productsOf(wholesalerId);
        final before = productId == null ? null : _find(list, productId);
        final next = <String, dynamic>{
          ...?before,
          if (before == null) ...{
            'id': _id('prd'),
            'wholesaler_id': wholesalerId,
            'status': 'active',
            'photo_paths': <String>[],
          },
          ...fields,
        };
        if ('${next['name'] ?? ''}'.trim().isEmpty || asInt(next['price_sen']) <= 0 || asInt(next['pack_qty']) <= 0) {
          throw const AppError('INVALID_PRODUCT');
        }
        if (before == null) {
          list.insert(0, next);
        } else {
          list[list.indexOf(before)] = next;
        }
        final w = _wholesalers.where((x) => x['id'] == wholesalerId).firstOrNull;
        if (w != null) w['active_product_count'] = list.where((p) => p['status'] == 'active').length;
        _log(
          before == null ? 'admin_create_product' : 'admin_update_product',
          'products',
          next['id'] as String,
          wholesalerId: wholesalerId,
          before: before == null ? null : {for (final k in fields.keys) k: before[k]},
          after: fields,
        );
        return SellerProduct.fromJson(next);
      });

  // ---------------- 批发商 ----------------

  void _recomputeRate(Json w) {
    final override = asDoubleOrNull(w['commission_rate_override']);
    final founding = w['is_founding'] == true;
    w['commission_rate'] = override ?? (founding ? w['industry_founding_rate'] : w['industry_default_rate']);
    w['commission_rate_source'] = override != null ? 'override' : (founding ? 'founding' : 'industry');
  }

  @override
  Future<AdminWholesaler> setWholesalerStatus(String wholesalerId, WholesalerStatus status, {String? note}) =>
      _later('setWholesalerStatus ${status.name}', () {
        final w = _find(_wholesalers, wholesalerId);
        final from = w['status'];
        if (from != status.name) {
          if (status == WholesalerStatus.pending) throw AppError('INVALID_TRANSITION', detail: '$from -> pending');
          w['status'] = status.name;
          if (status == WholesalerStatus.active) w['approved_at'] ??= _now;
          _log(
            'admin_set_wholesaler_status',
            'wholesalers',
            wholesalerId,
            wholesalerId: wholesalerId,
            before: {'status': from},
            after: {'status': status.name, 'note': note},
          );
        }
        return AdminWholesaler.fromJson(w);
      });

  @override
  Future<AdminWholesaler> setCommissionRate(String wholesalerId, double? rate) => _later('setCommissionRate $rate', () {
    if (rate != null && (rate < 0 || rate > 0.2)) throw const AppError('INVALID_RATE');
    final w = _find(_wholesalers, wholesalerId);
    final before = w['commission_rate_override'];
    w['commission_rate_override'] = rate;
    _recomputeRate(w);
    _log(
      'admin_set_commission_rate',
      'wholesaler_private',
      wholesalerId,
      wholesalerId: wholesalerId,
      before: {'commission_rate_override': before},
      after: {'commission_rate_override': rate},
    );
    return AdminWholesaler.fromJson(w);
  });

  @override
  Future<AdminWholesaler> setWholesalerFounding(String wholesalerId, bool isFounding) =>
      _later('setFounding $isFounding', () {
        final w = _find(_wholesalers, wholesalerId);
        if (w['is_founding'] != isFounding) {
          final before = {'is_founding': w['is_founding'], 'founding_no': w['founding_no']};
          w['is_founding'] = isFounding;
          w['founding_no'] = isFounding
              ? _wholesalers.fold<int>(0, (m, x) => asInt(x['founding_no']) > m ? asInt(x['founding_no']) : m) + 1
              : null;
          _recomputeRate(w);
          _log(
            'admin_set_wholesaler_founding',
            'wholesalers',
            wholesalerId,
            wholesalerId: wholesalerId,
            before: before,
            after: {'is_founding': isFounding, 'founding_no': w['founding_no']},
          );
        }
        return AdminWholesaler.fromJson(w);
      });

  @override
  Future<DateTime?> setWhatsappOptInAsAdmin({String? shopId, String? wholesalerId, required bool optIn}) =>
      _later('setOptIn $optIn', () {
        final row = shopId != null ? _find(_shops, shopId) : _find(_wholesalers, wholesalerId!);
        final before = row['whatsapp_opt_in_at'];
        row['whatsapp_opt_in_at'] = optIn ? (before ?? _now) : null;
        _log(
          'admin_set_whatsapp_opt_in',
          shopId != null ? 'shops' : 'wholesalers',
          shopId ?? wholesalerId,
          shopId: shopId,
          wholesalerId: wholesalerId,
          before: {'whatsapp_opt_in_at': before},
          after: {'whatsapp_opt_in_at': row['whatsapp_opt_in_at']},
        );
        return asDateTimeOrNull(row['whatsapp_opt_in_at']);
      });

  // ---------------- 订阅 ----------------

  @override
  Future<List<AdminSubscription>> listSubscriptions({
    SubscriptionState? state,
    bool foundingOnly = false,
    String? search,
  }) => _later(
    'listSubscriptions',
    () => [
      for (final s in _subs)
        if ((state == null || s['status'] == subscriptionStateCode(state)) &&
            (!foundingOnly || s['is_founding_price'] == true) &&
            _matches(search, [s['shop_name'], s['shop_phone']]))
          AdminSubscription.fromJson(s),
    ],
  );

  void _syncShop(Json sub) {
    final shop = _shops.where((s) => s['id'] == sub['shop_id']).firstOrNull;
    final open = sub['status'] != 'lapsed';
    sub['has_full_access'] = open;
    if (shop != null) {
      shop['subscription_status'] = sub['status'];
      shop['has_full_access'] = open;
    }
  }

  @override
  Future<AdminSubscription> extendTrial(String subscriptionId, int days) => _later('extendTrial $days', () {
    if (days < 1 || days > 90) throw const AppError('INVALID_DAYS');
    final s = _find(_subs, subscriptionId);
    final before = {'status': s['status'], 'trial_ends_at': s['trial_ends_at']};
    final now = DateTime.now().toUtc();
    if (s['status'] == 'trialing') {
      final end = asDateTimeOrNull(s['trial_ends_at']) ?? now;
      s['trial_ends_at'] = (end.isAfter(now) ? end : now).add(Duration(days: days)).toIso8601String();
    } else if (s['status'] == 'lapsed' && s['current_period_end'] == null) {
      s['status'] = 'trialing';
      s['lapsed_at'] = null;
      s['trial_ends_at'] = now.add(Duration(days: days)).toIso8601String();
    } else {
      throw AppError('INVALID_SUBSCRIPTION_STATE', detail: '${s['status']}');
    }
    _syncShop(s);
    _log(
      'admin_extend_trial',
      'subscriptions',
      subscriptionId,
      shopId: s['shop_id'] as String?,
      before: before,
      after: {'status': s['status'], 'trial_ends_at': s['trial_ends_at'], 'days': days},
    );
    return AdminSubscription.fromJson(s);
  });

  @override
  Future<AdminSubscription> markSubscriptionPaid(
    String subscriptionId, {
    int months = 1,
    int? amountSen,
    PaymentMethod method = PaymentMethod.other,
    String? reference,
  }) => _later('markPaid $months', () {
    if (months < 1 || months > 24) throw const AppError('INVALID_MONTHS');
    if (reference != null && !_references.add(reference)) {
      throw AppError('DUPLICATE_PAYMENT_REFERENCE', detail: reference);
    }
    var s = _find(_subs, subscriptionId);
    final before = {'status': s['status'], 'current_period_end': s['current_period_end']};
    final now = DateTime.now().toUtc();
    DateTime start;
    if (s['status'] == 'lapsed') {
      // 停了之后回来：新的一条，按今天的价钱锁定（示范：RM50）
      s = {
        ...s,
        'id': _id('sub'),
        'status': 'active',
        'started_at': now.toIso8601String(),
        'trial_ends_at': null,
        'locked_price_sen': 5000,
        'lapsed_at': null,
      };
      _subs[_subs.indexWhere((x) => x['id'] == subscriptionId)] = s;
      start = now;
    } else if (s['status'] == 'trialing') {
      final end = asDateTimeOrNull(s['trial_ends_at']) ?? now;
      start = end.isAfter(now) ? end : now;
    } else {
      start = asDateTimeOrNull(s['current_period_end']) ?? now;
    }
    final amount = amountSen ?? asInt(s['locked_price_sen']) * months;
    final paymentId = _id('pay');
    s['status'] = 'active';
    s['current_period_start'] = start.toIso8601String();
    s['current_period_end'] = DateTime.utc(
      start.year,
      start.month + months,
      start.day,
      start.hour,
      start.minute,
    ).toIso8601String();
    s['grace_until'] = null;
    s['last_payment'] = {
      'id': paymentId,
      'amount_sen': amount,
      'method': method.name,
      'gateway': 'manual',
      'gateway_ref': reference,
      'paid_at': now.toIso8601String(),
    };
    _syncShop(s);
    _log(
      'admin_mark_subscription_paid',
      'subscriptions',
      s['id'] as String,
      shopId: s['shop_id'] as String?,
      before: before,
      after: {
        'status': 'active',
        'current_period_end': s['current_period_end'],
        'amount_sen': amount,
        'months': months,
        'method': method.name,
        'reference': reference,
      },
    );
    return AdminSubscription.fromJson({...s, 'payment_id': paymentId});
  });

  @override
  Future<AdminSubscription> cancelSubscription(String subscriptionId, {String? reason}) =>
      _later('cancelSubscription', () {
        final s = _find(_subs, subscriptionId);
        if (s['status'] == 'lapsed') throw const AppError('INVALID_SUBSCRIPTION_STATE', detail: 'lapsed');
        final before = {'status': s['status']};
        s['status'] = 'lapsed';
        s['lapsed_at'] = _now;
        _syncShop(s);
        _log(
          'admin_cancel_subscription',
          'subscriptions',
          subscriptionId,
          shopId: s['shop_id'] as String?,
          before: before,
          after: {'status': 'lapsed', 'reason': reason},
        );
        return AdminSubscription.fromJson(s);
      });

  @override
  Future<AdminSubscription> setSubscriptionFounding(String subscriptionId, bool isFounding, {int? lockedPriceSen}) =>
      _later('setSubscriptionFounding $isFounding', () {
        final s = _find(_subs, subscriptionId);
        final before = {'is_founding_price': s['is_founding_price'], 'locked_price_sen': s['locked_price_sen']};
        s['is_founding_price'] = isFounding;
        if (lockedPriceSen != null) s['locked_price_sen'] = lockedPriceSen;
        _log(
          'admin_set_subscription_founding',
          'subscriptions',
          subscriptionId,
          shopId: s['shop_id'] as String?,
          before: before,
          after: {'is_founding_price': isFounding, 'locked_price_sen': s['locked_price_sen']},
        );
        return AdminSubscription.fromJson(s);
      });

  // ---------------- 佣金报表和账单 ----------------

  bool _sameMonth(DateTime? m) {
    if (m == null) return true;
    final p = DateTime.parse(_report['period_month'] as String);
    return p.year == m.year && p.month == m.month;
  }

  @override
  Future<CommissionReport> getCommissionReport({DateTime? month}) => _later('getCommissionReport', () {
    if (_sameMonth(month)) return CommissionReport.fromJson(_report);
    final m = month!;
    return CommissionReport.fromJson({
      'period_month': '${m.year}-${m.month.toString().padLeft(2, '0')}-01',
      'order_count': 0,
      'gmv_sen': 0,
      'commission_sen': 0,
      'wholesalers': <Object>[],
    });
  });

  Iterable<Json> get _rows => (_report['wholesalers'] as List).cast<Json>();

  @override
  Future<int> generateInvoices(DateTime month) => _later('generateInvoices', () {
    if (!_sameMonth(month)) return 0;
    var n = 0;
    for (final w in _rows) {
      final inv = asJsonOrNull(w['invoice']);
      if (inv != null && inv['status'] != 'draft') continue;
      w['invoice'] = {
        'id': inv?['id'] ?? _id('inv'),
        'invoice_no': inv?['invoice_no'] ?? 'INV2611-${(++_seq).toString().padLeft(4, '0')}',
        'status': 'draft',
        'order_count': w['order_count'],
        'gmv_sen': w['gmv_sen'],
        'commission_sen': w['commission_sen'],
      };
      n++;
    }
    _log(
      'admin_generate_invoices',
      'commission_invoices',
      null,
      after: {'period_month': _report['period_month'], 'invoices': n},
    );
    return n;
  });

  Json _invoice(String id) {
    for (final w in _rows) {
      final inv = asJsonOrNull(w['invoice']);
      if (inv != null && inv['id'] == id) return w;
    }
    throw const AppError('INVOICE_NOT_FOUND');
  }

  @override
  Future<CommissionInvoice> issueInvoice(String invoiceId) => _later('issueInvoice', () {
    final w = _invoice(invoiceId);
    final inv = w['invoice'] as Json;
    if (inv['status'] != 'draft') throw AppError('INVALID_INVOICE_STATE', detail: '${inv['status']}');
    final due = DateTime.now().add(Duration(days: asInt(_report['invoice_due_days'], 14)));
    inv
      ..['status'] = 'issued'
      ..['issued_at'] = _now
      ..['due_date'] = '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
    _log(
      'admin_issue_invoice',
      'commission_invoices',
      invoiceId,
      wholesalerId: w['wholesaler_id'] as String?,
      before: {'status': 'draft'},
      after: {'status': 'issued'},
    );
    return CommissionInvoice.fromJson(inv);
  });

  @override
  Future<CommissionInvoice> markInvoicePaid(
    String invoiceId, {
    PaymentMethod method = PaymentMethod.other,
    String? reference,
  }) => _later('markInvoicePaid', () {
    final w = _invoice(invoiceId);
    final inv = w['invoice'] as Json;
    if (inv['status'] != 'issued' && inv['status'] != 'overdue') {
      throw AppError('INVALID_INVOICE_STATE', detail: '${inv['status']}');
    }
    final before = inv['status'];
    inv
      ..['status'] = 'paid'
      ..['paid_at'] = _now;
    _log(
      'admin_mark_invoice_paid',
      'commission_invoices',
      invoiceId,
      wholesalerId: w['wholesaler_id'] as String?,
      before: {'status': before},
      after: {'status': 'paid', 'reference': reference},
    );
    return CommissionInvoice.fromJson(inv);
  });

  // ---------------- 操作记录 ----------------

  @override
  Future<List<AuditEntry>> listAuditLogs({
    String? action,
    String? tableName,
    String? shopId,
    String? wholesalerId,
    bool adminOnly = false,
    int limit = 100,
    int? beforeId,
  }) => _later(
    'listAuditLogs',
    () => _audit
        .where(
          (e) =>
              (action == null || e['action'] == action) &&
              (tableName == null || e['table_name'] == tableName) &&
              (shopId == null || e['acting_for_shop_id'] == shopId) &&
              (wholesalerId == null || e['acting_for_wholesaler_id'] == wholesalerId) &&
              (!adminOnly || '${e['action']}'.startsWith('admin_')) &&
              (beforeId == null || asInt(e['id']) < beforeId),
        )
        .take(limit)
        .map(AuditEntry.fromJson)
        .toList(),
  );
}
