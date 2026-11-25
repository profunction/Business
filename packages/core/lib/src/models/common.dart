import '../json.dart';

/// 三语名称：{"zh": "...", "en": "...", "ms": "..."}
class LocalizedName {
  const LocalizedName({required this.zh, required this.en, required this.ms});

  factory LocalizedName.fromJson(Object? json) {
    final m = asJson(json);
    final zh = asStringOrNull(m['zh']) ?? '';
    final en = asStringOrNull(m['en']) ?? zh;
    final ms = asStringOrNull(m['ms']) ?? en;
    return LocalizedName(zh: zh, en: en, ms: ms);
  }

  final String zh;
  final String en;
  final String ms;

  /// languageCode: 'zh' / 'en' / 'ms'
  String of(String languageCode) => switch (languageCode) {
    'zh' => zh,
    'ms' => ms,
    _ => en,
  };
}

/// 卖的单位（App 按代码显示三语）
enum SellUnit { carton, pack, bag, roll, bundle, box, piece, dozen, kg, unknown }

SellUnit sellUnitFrom(Object? v) =>
    SellUnit.values.firstWhere((e) => e.name == v?.toString(), orElse: () => SellUnit.unknown);

enum StockStatus { inStock, lowStock, outOfStock }

StockStatus stockStatusFrom(Object? v) => switch (v?.toString()) {
  'low_stock' => StockStatus.lowStock,
  'out_of_stock' => StockStatus.outOfStock,
  _ => StockStatus.inStock,
};

enum ShopType { restaurant, drinkStall, grocery, other }

ShopType shopTypeFrom(Object? v) => switch (v?.toString()) {
  'restaurant' => ShopType.restaurant,
  'drink_stall' => ShopType.drinkStall,
  'grocery' => ShopType.grocery,
  _ => ShopType.other,
};

String shopTypeCode(ShopType t) => switch (t) {
  ShopType.restaurant => 'restaurant',
  ShopType.drinkStall => 'drink_stall',
  ShopType.grocery => 'grocery',
  ShopType.other => 'other',
};

enum OrderStatus { pending, confirmed, outOfStock, delivering, delivered, cancelled }

OrderStatus orderStatusFrom(Object? v) => switch (v?.toString()) {
  'confirmed' => OrderStatus.confirmed,
  'out_of_stock' => OrderStatus.outOfStock,
  'delivering' => OrderStatus.delivering,
  'delivered' => OrderStatus.delivered,
  'cancelled' => OrderStatus.cancelled,
  _ => OrderStatus.pending,
};

String orderStatusCode(OrderStatus s) => switch (s) {
  OrderStatus.pending => 'pending',
  OrderStatus.confirmed => 'confirmed',
  OrderStatus.outOfStock => 'out_of_stock',
  OrderStatus.delivering => 'delivering',
  OrderStatus.delivered => 'delivered',
  OrderStatus.cancelled => 'cancelled',
};

extension OrderStatusX on OrderStatus {
  /// 还在进行中（老板要留意的）
  bool get isActive => this == OrderStatus.pending || this == OrderStatus.confirmed || this == OrderStatus.delivering;
}

/// 评价时一键点选的标签（跟数据库 reviews.tags 的检查一致）
enum ReviewTag { onTime, goodQuality, wellPacked, goodPrice, friendly, late, wrongItems, damaged, missingItems }

const reviewTagCodes = {
  ReviewTag.onTime: 'on_time',
  ReviewTag.goodQuality: 'good_quality',
  ReviewTag.wellPacked: 'well_packed',
  ReviewTag.goodPrice: 'good_price',
  ReviewTag.friendly: 'friendly',
  ReviewTag.late: 'late',
  ReviewTag.wrongItems: 'wrong_items',
  ReviewTag.damaged: 'damaged',
  ReviewTag.missingItems: 'missing_items',
};

ReviewTag? reviewTagFrom(Object? v) {
  for (final e in reviewTagCodes.entries) {
    if (e.value == v?.toString()) return e.key;
  }
  return null;
}

/// 购物车每一行、每一组可能的问题（跟数据库 _quote_cart 一致）
enum CartProblem {
  productUnavailable,
  notDelivering,
  wholesalerLocked,
  outOfStock,
  belowMinQty,
  belowMinOrder,
  unknown,
}

CartProblem? cartProblemFrom(Object? v) => switch (v?.toString()) {
  null => null,
  'PRODUCT_UNAVAILABLE' => CartProblem.productUnavailable,
  'NOT_DELIVERING' => CartProblem.notDelivering,
  'WHOLESALER_LOCKED' => CartProblem.wholesalerLocked,
  'OUT_OF_STOCK' => CartProblem.outOfStock,
  'BELOW_MIN_QTY' => CartProblem.belowMinQty,
  'BELOW_MIN_ORDER' => CartProblem.belowMinOrder,
  _ => CartProblem.unknown,
};

class Zone {
  const Zone({required this.id, required this.code, required this.name});

  factory Zone.fromJson(Json j) =>
      Zone(id: j['id'] as String, code: asStringOrNull(j['code']) ?? '', name: LocalizedName.fromJson(j['name']));

  final String id;
  final String code;
  final LocalizedName name;
}
