import 'dart:convert';

import 'package:wholesale_core/wholesale_core.dart';

import 'demo_data.dart';

/// 示范模式的批发商端：示范批发 A 的订单、送货总结、商品、价目表导入。
/// 一开始的资料全部来自 packages/core/test/fixtures 的真实样本（seller_home、seller_orders、seller_order_detail、
/// delivery_summary、price_list_import、price_list_import_rows）；按了「确认」「缺货」「上架」之后，
/// 订单、送货总结、首页数字都照数据库函数的规则跟着变（不会真的连服务器）。
class DemoSeller {
  DemoSeller() {
    _buildProducts();
    _buildOrders();
    _resetImport(asJson(_j('price_list_import')));
  }

  static Object? _j(String name) => jsonDecode(demoFixtures[name]!);

  /// 示范批发商的成员（价目表样本的 created_by）
  static String get userId =>
      asStringOrNull(asJson(_j('price_list_import'))['created_by']) ?? '00000000-0000-4000-c000-000000000002';

  Json get _homeFixture => asJson(_j('seller_home'));
  Json get _wholesaler => asJson(_homeFixture['wholesaler']);
  String get wholesalerId => _wholesaler['id'] as String;
  String get wholesalerName => asStringOrNull(_wholesaler['name']) ?? '';

  /// 样本的「今天」（马来西亚时间）
  DateTime get today => asDateOrNull(_homeFixture['today']) ?? DateTime.now();

  /// 批发商的审核状态：示范 / 测试可以改成 'pending'（等客服审核）或 'suspended'
  late String wholesalerStatus = asStringOrNull(_wholesaler['status']) ?? 'active';

  /// 登录的人在这家批发商的角色：'owner'（老板）或 'staff'（员工不能改通知方式，跟数据库的 RLS 一样）
  String memberRole = 'owner';

  /// get_my_context()：示范批发商的老板（my_context 样本是买家，这里另外做一个）
  Json myContext() => {
    'profile': {'id': userId, 'role': 'seller', 'full_name': 'Demo', 'phone': '60120000002', 'locale': 'zh'},
    'shops': <Object>[],
    'wholesalers': [
      {'id': wholesalerId, 'name': wholesalerName, 'status': wholesalerStatus, 'member_role': memberRole},
    ],
  };

  // ---------------- 商品 ----------------

  final List<Json> _products = [];

  /// 示范批发 A 的商品（跟 supabase/seed.sql 一样）。id 尽量用样本里出现过的，订单和导入才对得上
  static const _seedProducts = [
    ('16安士 PP杯 95口径', 'carton', 1000, 8500, 1, 'in_stock'),
    ('22安士 PP杯 95口径', 'carton', 1000, 9800, 1, 'in_stock'),
    ('95 平盖', 'carton', 1000, 4500, 1, 'in_stock'),
    ('650ml 长方饭盒连盖', 'carton', 300, 7800, 1, 'low_stock'),
    ('黑色吸管 6mm 独立包', 'pack', 250, 950, 2, 'out_of_stock'),
    ('白色塑料汤匙', 'pack', 100, 420, 5, 'in_stock'),
  ];

  void _buildProducts() {
    final known = <String, String>{};
    for (final i in asJsonList(asJson(_j('seller_order_detail'))['items'])) {
      final id = asStringOrNull(i['product_id']);
      if (id != null) known[i['name'] as String] = id;
    }
    for (final r in asJsonList(_j('price_list_import_rows'))) {
      final id = asStringOrNull(r['matched_product_id']);
      if (id != null && r['name'] != null) known.putIfAbsent(r['name'] as String, () => id);
    }
    final created = asStringOrNull(asJson(_j('price_list_import'))['created_at']) ?? '2026-11-25T00:00:00+00:00';
    var n = 0;
    for (final (name, unit, pack, price, moq, stock) in _seedProducts) {
      n++;
      _products.add({
        'id': known[name] ?? '00000000-0000-4000-f000-${n.toString().padLeft(12, '0')}',
        'wholesaler_id': wholesalerId,
        'catalog_item_id': null,
        'category_id': null,
        'name': name,
        'description': null,
        'photo_paths': <String>[],
        'unit': unit,
        'pack_qty': pack,
        'price_sen': price,
        'min_order_qty': moq,
        'stock_status': stock,
        'lead_time_days_override': null,
        'status': 'active',
        'sort_order': 0,
        'price_updated_at': created,
        'created_by': null,
        'created_at': created,
        'updated_at': created,
      });
    }
  }

  List<SellerProduct> products() {
    final list = _products.map(SellerProduct.fromJson).toList()
      ..sort((a, b) {
        final s = a.sortOrder.compareTo(b.sortOrder);
        return s != 0 ? s : a.name.compareTo(b.name);
      });
    return list;
  }

  Json? _product(String id) {
    for (final p in _products) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  Json? _productByName(String name) {
    for (final p in _products) {
      if (p['name'] == name) return p;
    }
    return null;
  }

  SellerProduct product(String id) {
    final p = _product(id);
    if (p == null) throw const AppError('PRODUCT_NOT_FOUND');
    return SellerProduct.fromJson(p);
  }

  SellerProduct saveProduct(SellerProduct product) {
    if (!product.isValid) throw const AppError('UNKNOWN');
    final now = DateTime.now().toUtc().toIso8601String();
    final data = product.toWriteJson();
    if (product.isNew) {
      final row = {
        ...data,
        'id': newUuidV4(),
        'wholesaler_id': wholesalerId,
        'photo_paths': <String>[],
        'sort_order': 0,
        'price_updated_at': now,
        'created_by': userId,
        'created_at': now,
        'updated_at': now,
      };
      _products.add(row);
      return SellerProduct.fromJson(row);
    }
    return updateProduct(product.id, data);
  }

  SellerProduct updateProduct(String id, Json fields) {
    final p = _product(id);
    if (p == null) throw const AppError('PRODUCT_NOT_FOUND');
    final now = DateTime.now().toUtc().toIso8601String();
    if (fields.containsKey('price_sen') && fields['price_sen'] != p['price_sen']) p['price_updated_at'] = now;
    p
      ..addAll(fields)
      ..['updated_at'] = now;
    return SellerProduct.fromJson(p);
  }

  // ---------------- 订单 ----------------

  /// get_order() 格式的订单，按 seller_orders 样本的顺序
  final List<Json> _orders = [];

  void _buildOrders() {
    final detail = asJson(_j('seller_order_detail'));
    final delivery = asJson(_j('delivery_summary'));
    final byId = {for (final o in asJsonList(delivery['orders'])) o['id']: o};
    // 店的资料：从有完整资料的样本找（按店名）
    final shops = <String, Json>{asStringOrNull(asJson(detail['shop'])['name']) ?? '': asJson(detail['shop'])};
    for (final o in asJsonList(delivery['orders'])) {
      shops.putIfAbsent(asStringOrNull(asJson(o['shop'])['name']) ?? '', () => asJson(o['shop']));
    }
    final wholesaler = asJson(detail['wholesaler']);
    var itemNo = 0;
    String nextItemId() => '00000000-0000-4000-e000-${(++itemNo).toString().padLeft(12, '0')}';

    for (final s in asJsonList(_j('seller_orders'))) {
      final id = s['id'] as String;
      if (id == detail['id']) {
        _orders.add(detail);
        continue;
      }
      List<Json> items;
      final d = byId[id];
      if (d != null) {
        items = [
          for (final i in asJsonList(d['items']))
            {...i, 'id': nextItemId(), 'product_id': _productByName(i['name'] as String)?['id']},
        ];
      } else {
        items = _guessItems(
          asInt(s['goods_subtotal_sen']),
          asInt(s['item_count']),
          asInt(s['out_of_stock_count']),
        ).map((i) => {...i, 'id': nextItemId()}).toList();
      }
      final shopName = asStringOrNull(s['shop_name']) ?? '';
      final shop = shops[shopName] ?? {'name': shopName, 'zone_name': s['zone_name']};
      final goods = items
          .where((i) => i['is_out_of_stock'] != true)
          .fold<int>(0, (n, i) => n + asInt(i['line_total_sen']));
      final status = s['status'] as String;
      _orders.add({
        'id': id,
        'order_no': s['order_no'],
        'status': status,
        'source': 'app',
        'note': s['note'],
        'created_at': s['created_at'],
        'expected_delivery_date': s['expected_delivery_date'],
        // 拆不出跟样本一样的金额时，以明细为准（示范模式里前后对得上比较重要）
        'goods_subtotal_sen': status == 'out_of_stock' ? s['goods_subtotal_sen'] : goods,
        'shipping_fee_sen': s['shipping_fee_sen'],
        'total_sen': (status == 'out_of_stock' ? asInt(s['goods_subtotal_sen']) : goods) + asInt(s['shipping_fee_sen']),
        'shop': {...shop, 'name': shopName, 'zone_name': s['zone_name']},
        'wholesaler': wholesaler,
        'items': items,
        'events': [
          {'from_status': null, 'to_status': 'pending', 'created_at': s['created_at'], 'note': null, 'channel': 'app'},
          if (status != 'pending')
            {
              'from_status': 'pending',
              'to_status': status,
              'created_at': s['created_at'],
              'note': null,
              'channel': 'app',
            },
        ],
        'review': null,
      });
    }
  }

  /// 只有总额、没有明细的订单：用示范商品拼出一样的金额（找不到就用最接近的）
  List<Json> _guessItems(int goodsSen, int itemCount, int oosCount) {
    final active = _products.where((p) => p['status'] == 'active').toList();
    final inStockCount = (itemCount - oosCount).clamp(1, active.length);
    List<(Json, int)>? best;
    var bestDiff = 1 << 30;
    void search(int start, List<(Json, int)> picked, int sum) {
      if (bestDiff == 0) return;
      if (picked.length == inStockCount) {
        final diff = (goodsSen - sum).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = List.of(picked);
        }
        return;
      }
      for (var i = start; i < active.length; i++) {
        final price = asInt(active[i]['price_sen']);
        for (var q = 1; q <= 10 && sum + price * q <= goodsSen + price; q++) {
          picked.add((active[i], q));
          search(i + 1, picked, sum + price * q);
          picked.removeLast();
          if (bestDiff == 0) return;
        }
      }
    }

    search(0, [], 0);
    final lines = <Json>[for (final (p, q) in best ?? <(Json, int)>[]) _line(p, q, false)];
    // 缺货的几样（不算钱）
    final used = lines.map((l) => l['product_id']).toSet();
    for (final p in active.where((p) => !used.contains(p['id'])).take(oosCount)) {
      lines.add(_line(p, 1, true));
    }
    return lines;
  }

  Json _line(Json p, int qty, bool oos) => {
    'product_id': p['id'],
    'name': p['name'],
    'unit': p['unit'],
    'pack_qty': p['pack_qty'],
    'qty': qty,
    'unit_price_sen': p['price_sen'],
    'line_total_sen': asInt(p['price_sen']) * qty,
    'is_out_of_stock': oos,
  };

  Json _order(String id) {
    for (final o in _orders) {
      if (o['id'] == id) return o;
    }
    throw const AppError('ORDER_NOT_FOUND');
  }

  bool hasOrder(String id) => _orders.any((o) => o['id'] == id);

  OrderDetail order(String id) {
    final o = _order(id);
    final status = o['status'];
    return OrderDetail.fromJson({
      ...o,
      'actions': {
        'can_cancel': false,
        'can_mark_received': false,
        'can_review': false,
        'can_confirm': status == 'pending',
        'can_mark_delivering': status == 'confirmed',
        'can_mark_delivered': status == 'confirmed' || status == 'delivering',
      },
    });
  }

  Json _summaryJson(Json o) {
    final items = asJsonList(o['items']);
    return {
      'id': o['id'],
      'order_no': o['order_no'],
      'status': o['status'],
      'shop_name': asJson(o['shop'])['name'],
      'zone_name': asJson(o['shop'])['zone_name'],
      'item_count': items.length,
      'out_of_stock_count': items.where((i) => i['is_out_of_stock'] == true).length,
      'goods_subtotal_sen': o['goods_subtotal_sen'],
      'shipping_fee_sen': o['shipping_fee_sen'],
      'total_sen': o['total_sen'],
      'note': o['note'],
      'created_at': o['created_at'],
      'expected_delivery_date': o['expected_delivery_date'],
    };
  }

  /// list_seller_orders()：pending 最前面（旧到新），其他新到旧
  List<SellerOrderSummary> orders({List<OrderStatus>? statuses, DateTime? deliveryDate, int limit = 50}) {
    final codes = statuses == null || statuses.isEmpty ? null : statuses.map(orderStatusCode).toSet();
    final date = deliveryDate == null ? null : dateParam(deliveryDate);
    final list = _orders
        .where((o) => codes == null || codes.contains(o['status']))
        .where((o) => date == null || o['expected_delivery_date'] == date)
        .map((o) => SellerOrderSummary.fromJson(_summaryJson(o)))
        .toList();
    list.sort((a, b) {
      final ap = a.status == OrderStatus.pending, bp = b.status == OrderStatus.pending;
      if (ap != bp) return ap ? -1 : 1;
      final c = ap ? a.createdAt.compareTo(b.createdAt) : b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : (ap ? a.orderNo.compareTo(b.orderNo) : b.orderNo.compareTo(a.orderNo));
    });
    return list.take(limit.clamp(1, 200)).toList();
  }

  void _setStatus(Json o, String to) {
    final from = o['status'];
    o['status'] = to;
    (o['events'] as List).add({
      'from_status': from,
      'to_status': to,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'note': null,
      'channel': 'app',
    });
  }

  /// confirm_order()：勾了缺货的那几样不算钱；全部缺货 → out_of_stock
  OrderStatus confirm(String orderId, List<String> outOfStockItemIds) {
    final o = _order(orderId);
    if (o['status'] != 'pending') throw AppError('INVALID_TRANSITION', detail: '${o['status']} -> confirmed');
    final items = (o['items'] as List).cast<Map<String, dynamic>>();
    final ids = items.map((i) => i['id']).toSet();
    if (outOfStockItemIds.any((id) => !ids.contains(id))) throw const AppError('ITEM_NOT_IN_ORDER');
    for (final i in items) {
      i['is_out_of_stock'] = outOfStockItemIds.contains(i['id']);
    }
    if (items.every((i) => i['is_out_of_stock'] == true)) {
      _setStatus(o, 'out_of_stock');
      return OrderStatus.outOfStock;
    }
    final goods = items
        .where((i) => i['is_out_of_stock'] != true)
        .fold<int>(0, (n, i) => n + asInt(i['line_total_sen']));
    o['goods_subtotal_sen'] = goods;
    o['total_sen'] = goods + asInt(o['shipping_fee_sen']);
    _setStatus(o, 'confirmed');
    return OrderStatus.confirmed;
  }

  /// set_order_status()：批发商可以做的那几种
  void setStatus(String orderId, OrderStatus to) {
    final o = _order(orderId);
    final from = orderStatusFrom(o['status']);
    if (from == to) return;
    final ok = switch (to) {
      OrderStatus.outOfStock || OrderStatus.confirmed => from == OrderStatus.pending,
      OrderStatus.delivering => from == OrderStatus.confirmed,
      OrderStatus.delivered => from == OrderStatus.confirmed || from == OrderStatus.delivering,
      _ => false,
    };
    if (!ok) throw AppError('INVALID_TRANSITION', detail: '${orderStatusCode(from)} -> ${orderStatusCode(to)}');
    if (to == OrderStatus.outOfStock) {
      for (final i in (o['items'] as List).cast<Map<String, dynamic>>()) {
        i['is_out_of_stock'] = true;
      }
    }
    _setStatus(o, orderStatusCode(to));
  }

  // ---------------- 首页、送货总结 ----------------

  bool _isTodayDelivery(Json o, String date) =>
      o['expected_delivery_date'] == date && (o['status'] == 'confirmed' || o['status'] == 'delivering');

  SellerHome home() {
    final h = _homeFixture;
    final todayCode = dateParam(today);
    final pending = _orders.where((o) => o['status'] == 'pending').toList();
    final todays = _orders.where((o) => _isTodayDelivery(o, todayCode)).toList();
    final active = _products.where((p) => p['status'] == 'active');
    h['wholesaler'] = {
      ...asJson(h['wholesaler']),
      'status': wholesalerStatus,
      'notify_channel': _settings['notify_channel'],
    };
    h['pending_count'] = pending.length;
    h['oldest_pending_at'] = pending.isEmpty
        ? null
        : pending
              .map((o) => o['created_at'] as String)
              .reduce((a, b) => DateTime.parse(a).isBefore(DateTime.parse(b)) ? a : b);
    h['today_order_count'] = todays.length;
    h['today_total_sen'] = todays.fold<int>(0, (n, o) => n + asInt(o['total_sen']));
    h['product_counts'] = {
      'active': active.length,
      'draft': _products.where((p) => p['status'] == 'draft').length,
      'out_of_stock': active.where((p) => p['stock_status'] == 'out_of_stock').length,
      'low_stock': active.where((p) => p['stock_status'] == 'low_stock').length,
    };
    h['latest_import'] = {'id': _import['id'], 'status': _import['status'], 'created_at': _import['created_at']};
    return SellerHome.fromJson(h);
  }

  /// get_delivery_summary()：按送货区、再按店名排；拣货单不含缺货
  DeliverySummary delivery(DateTime? date) {
    final fixture = asJson(_j('delivery_summary'));
    final code = dateParam(date ?? today);
    final zoneOrder = <String, int>{
      for (final z in asJsonList(_j('zones'))) LocalizedName.fromJson(z['name']).zh: asInt(z['sort_order']),
    };
    int zoneOf(Json o) => zoneOrder[LocalizedName.fromJson(asJson(o['shop'])['zone_name']).zh] ?? 999;
    final day = _orders.where((o) => _isTodayDelivery(o, code)).toList()
      ..sort((a, b) {
        final z = zoneOf(a).compareTo(zoneOf(b));
        if (z != 0) return z;
        final s = (asJson(a['shop'])['name'] as String).compareTo(asJson(b['shop'])['name'] as String);
        return s != 0 ? s : (a['order_no'] as String).compareTo(b['order_no'] as String);
      });
    final picking = <String, Json>{};
    for (final o in day) {
      for (final i in asJsonList(o['items']).where((i) => i['is_out_of_stock'] != true)) {
        final key = '${i['name']}|${i['unit']}|${i['pack_qty']}';
        final p = picking.putIfAbsent(
          key,
          () => {'name': i['name'], 'unit': i['unit'], 'pack_qty': i['pack_qty'], 'qty': 0},
        );
        p['qty'] = asInt(p['qty']) + asInt(i['qty']);
      }
    }
    final units = SellUnit.values.map((u) => u.name).toList();
    final pickingList = picking.values.toList()
      ..sort((a, b) {
        final n = (a['name'] as String).compareTo(b['name'] as String);
        if (n != 0) return n;
        final u = units.indexOf(a['unit'] as String).compareTo(units.indexOf(b['unit'] as String));
        return u != 0 ? u : asInt(a['pack_qty']).compareTo(asInt(b['pack_qty']));
      });
    final paymentTerms = asJson(_orders.first['wholesaler'])['payment_terms'];
    return DeliverySummary.fromJson({
      'date': code,
      'wholesaler': fixture['wholesaler'],
      'order_count': day.length,
      'pending_count': _orders.where((o) => o['expected_delivery_date'] == code && o['status'] == 'pending').length,
      'goods_total_sen': day.fold<int>(0, (n, o) => n + asInt(o['goods_subtotal_sen'])),
      'shipping_total_sen': day.fold<int>(0, (n, o) => n + asInt(o['shipping_fee_sen'])),
      'total_sen': day.fold<int>(0, (n, o) => n + asInt(o['total_sen'])),
      'picking': pickingList,
      'orders': [
        for (final o in day)
          {
            'id': o['id'],
            'order_no': o['order_no'],
            'status': o['status'],
            'shop': {
              for (final k in ['name', 'contact_name', 'phone', 'address', 'zone_name']) k: asJson(o['shop'])[k],
            },
            'items':
                (asJsonList(o['items'])..sort((a, b) {
                      final x = (a['is_out_of_stock'] == true ? 1 : 0) - (b['is_out_of_stock'] == true ? 1 : 0);
                      return x != 0 ? x : (a['name'] as String).compareTo(b['name'] as String);
                    }))
                    .map((i) => {for (final k in i.keys.where((k) => k != 'id' && k != 'product_id')) k: i[k]})
                    .toList(),
            'goods_subtotal_sen': o['goods_subtotal_sen'],
            'shipping_fee_sen': o['shipping_fee_sen'],
            'total_sen': o['total_sen'],
            'note': o['note'],
            'payment_terms': paymentTerms,
          },
      ],
    });
  }

  // ---------------- 价目表导入 ----------------

  late Json _import;
  final List<Json> _rows = [];
  int _pollsUntilDone = 0;

  /// 下一次导入 AI 读失败（测试失败画面）：例如 'AI_REFUSED'、'UNSUPPORTED_FILE'
  String? nextImportError;

  void _resetImport(Json import) {
    _import = import;
    _rows
      ..clear()
      ..addAll(asJsonList(_j('price_list_import_rows')).map((r) => {...r, 'import_id': import['id']}));
  }

  PriceListImport createImport(String filePath, ImportFileType type) {
    final now = DateTime.now().toUtc().toIso8601String();
    _resetImport({
      ...asJson(_j('price_list_import')),
      'id': newUuidV4(),
      'status': 'processing',
      'file_path': filePath,
      'file_type': type.name,
      'error_message': null,
      'ai_raw': null,
      'applied_at': null,
      'created_at': now,
      'updated_at': now,
    });
    _pollsUntilDone = -1; // 还没叫 AI
    return PriceListImport.fromJson(_import);
  }

  /// parse-price-list：示范模式查两次之后就读好了
  void startParse(String importId) {
    _checkImport(importId);
    if (_import['status'] != 'processing') throw const AppError('IMPORT_NOT_PROCESSING');
    _pollsUntilDone = 2;
  }

  void _checkImport(String importId) {
    if (_import['id'] != importId) throw const AppError('IMPORT_NOT_FOUND');
  }

  PriceListImport getImport(String importId) {
    _checkImport(importId);
    if (_import['status'] == 'processing' && _pollsUntilDone > 0 && --_pollsUntilDone == 0) {
      final error = nextImportError;
      nextImportError = null;
      _import
        ..['status'] = error == null ? 'review' : 'failed'
        ..['error_message'] = error
        ..['ai_raw'] = error == null ? asJson(_j('price_list_import'))['ai_raw'] : null
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
    return PriceListImport.fromJson(_import);
  }

  void markFailed(String importId, String code) {
    _checkImport(importId);
    if (_import['status'] == 'processing') {
      _import
        ..['status'] = 'failed'
        ..['error_message'] = code;
    }
  }

  List<PriceListImport> imports() => [PriceListImport.fromJson(_import)];

  List<PriceListImportRow> rows(String importId) {
    _checkImport(importId);
    if (_import['status'] == 'processing' || _import['status'] == 'failed') return const [];
    return (_rows.map(PriceListImportRow.fromJson).toList()..sort((a, b) => a.rowNo.compareTo(b.rowNo)));
  }

  PriceListImportRow updateRow(String rowId, Map<String, Object?> fields) {
    for (final r in _rows) {
      if (r['id'] == rowId) {
        r.addAll(fields);
        return PriceListImportRow.fromJson(r);
      }
    }
    throw const AppError('IMPORT_NOT_FOUND');
  }

  /// apply_price_list_import()：先全部检查（跟数据库一样的错误代码），都没问题才改商品
  ApplyImportResult apply(String importId) {
    _checkImport(importId);
    if (_import['status'] != 'review') throw AppError('IMPORT_NOT_IN_REVIEW', detail: _import['status'] as String?);
    final rows = _rows.map(PriceListImportRow.fromJson).toList()..sort((a, b) => a.rowNo.compareTo(b.rowNo));
    final seen = <String, int>{};
    int? dup;
    for (final r in rows.where((r) => r.action == ImportRowAction.update && r.matchedProductId != null)) {
      if (seen.containsKey(r.matchedProductId)) {
        final first = seen[r.matchedProductId]!;
        dup = dup == null || first < dup ? first : dup;
      } else {
        seen[r.matchedProductId!] = r.rowNo;
      }
    }
    if (dup != null) throw AppError('IMPORT_DUPLICATE_PRODUCT', detail: '$dup');
    for (final r in rows) {
      if (r.action == ImportRowAction.create && !r.canCreate) {
        throw AppError('IMPORT_ROW_INCOMPLETE', detail: '${r.rowNo}');
      }
      if (r.action == ImportRowAction.update) {
        if (!r.canUpdate) throw AppError('IMPORT_ROW_INCOMPLETE', detail: '${r.rowNo}');
        if (_product(r.matchedProductId!) == null) throw AppError('IMPORT_ROW_INVALID_PRODUCT', detail: '${r.rowNo}');
      }
    }
    var created = 0, updated = 0, skipped = 0;
    for (final r in rows) {
      switch (r.action) {
        case ImportRowAction.skip:
          skipped++;
        case ImportRowAction.create:
          saveProduct(
            SellerProduct.draft(wholesalerId: wholesalerId).copyWith(
              name: r.name!.trim(),
              unit: r.unit,
              packQty: r.packQty,
              priceSen: r.priceSen,
              minOrderQty: r.minOrderQty ?? 1,
              catalogItemId: r.suggestedCatalogItemId,
              status: ProductStatus.active,
            ),
          );
          created++;
        case ImportRowAction.update:
          final p = _product(r.matchedProductId!)!;
          updateProduct(r.matchedProductId!, {
            'price_sen': r.priceSen,
            'min_order_qty': r.minOrderQty ?? p['min_order_qty'],
            'unit': r.unit == null ? p['unit'] : sellUnitCode(r.unit!),
            'pack_qty': r.packQty ?? p['pack_qty'],
            'status': 'active',
          });
          updated++;
      }
    }
    _import
      ..['status'] = 'applied'
      ..['applied_at'] = DateTime.now().toUtc().toIso8601String();
    return ApplyImportResult(created: created, updated: updated, skipped: skipped);
  }

  // ---------------- 设定 ----------------

  late Json _settings = {
    'id': wholesalerId,
    'name': wholesalerName,
    'phone': asJson(asJson(_j('delivery_summary'))['wholesaler'])['phone'],
    'whatsapp_phone': asJson(asJson(_j('seller_order_detail'))['wholesaler'])['whatsapp_phone'],
    'notify_channel': _wholesaler['notify_channel'],
    'whatsapp_opt_in_at': null,
  };

  WholesalerSettings settings() => WholesalerSettings.fromJson(_settings);

  WholesalerSettings setNotifyChannel(NotifyChannel channel) {
    _checkOwner();
    _settings = {..._settings, 'notify_channel': channel.name};
    if (channel == NotifyChannel.whatsapp) setWhatsappOptIn(true);
    return settings();
  }

  void setWhatsappOptIn(bool optIn) {
    _checkOwner();
    if (optIn && _settings['whatsapp_opt_in_at'] != null) return;
    _settings = {..._settings, 'whatsapp_opt_in_at': optIn ? DateTime.now().toUtc().toIso8601String() : null};
  }

  /// 只有老板能改批发商的资料（数据库：wholesalers 的 update policy 只给老板，员工改了 0 行 → NOT_ALLOWED）
  void _checkOwner() {
    if (memberRole != 'owner') throw const AppError('NOT_ALLOWED');
  }
}
