import '../json.dart';
import 'common.dart';

/// get_categories()
class CategorySummary {
  const CategorySummary({required this.id, required this.code, required this.name, required this.itemCount});

  factory CategorySummary.fromJson(Json j) => CategorySummary(
    id: j['category_id'] as String,
    code: asStringOrNull(j['code']) ?? '',
    name: LocalizedName.fromJson(j['name']),
    itemCount: asInt(j['item_count']),
  );

  final String id;
  final String code;
  final LocalizedName name;
  final int itemCount;
}

/// get_catalog_overview()：一样标准商品，几家有卖、最便宜每个多少钱
class CatalogItemSummary {
  const CatalogItemSummary({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.baseUnit,
    this.imagePath,
    required this.offerCount,
    required this.visibleOfferCount,
    this.minPricePerBaseUnitSen,
    this.fastestLeadTimeDays,
  });

  factory CatalogItemSummary.fromJson(Json j) => CatalogItemSummary(
    id: j['catalog_item_id'] as String,
    categoryId: asStringOrNull(j['category_id']) ?? '',
    name: LocalizedName.fromJson(j['name']),
    baseUnit: asStringOrNull(j['base_unit']) ?? 'pcs',
    imagePath: asStringOrNull(j['image_path']),
    offerCount: asInt(j['offer_count']),
    visibleOfferCount: asInt(j['visible_offer_count']),
    minPricePerBaseUnitSen: asDoubleOrNull(j['min_price_per_base_unit_sen']),
    fastestLeadTimeDays: asIntOrNull(j['fastest_lead_time_days']),
  );

  final String id;
  final String categoryId;
  final LocalizedName name;
  final String baseUnit;
  final String? imagePath;
  final int offerCount;
  final int visibleOfferCount;

  /// 只从看得到价钱的批发商里算；全部看不到时是 null
  final double? minPricePerBaseUnitSen;
  final int? fastestLeadTimeDays;
}

/// get_offers()：一家批发商的一样商品
class Offer {
  const Offer({
    required this.productId,
    required this.productName,
    this.description,
    required this.photoPaths,
    required this.unit,
    required this.packQty,
    required this.minOrderQty,
    required this.stockStatus,
    this.catalogItemId,
    required this.wholesalerId,
    required this.wholesalerName,
    required this.ratingAvg,
    required this.ratingCount,
    required this.isFounding,
    required this.priceVisible,
    this.priceSen,
    this.pricePerBaseUnitSen,
    required this.shippingFeeSen,
    this.freeShippingMinSen,
    this.minOrderSen,
    required this.leadTimeDays,
  });

  factory Offer.fromJson(Json j) => Offer(
    productId: j['product_id'] as String,
    productName: asStringOrNull(j['product_name']) ?? '',
    description: asStringOrNull(j['description']),
    photoPaths: asStringList(j['photo_paths']),
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    minOrderQty: asInt(j['min_order_qty'], 1),
    stockStatus: stockStatusFrom(j['stock_status']),
    catalogItemId: asStringOrNull(j['catalog_item_id']),
    wholesalerId: j['wholesaler_id'] as String,
    wholesalerName: asStringOrNull(j['wholesaler_name']) ?? '',
    ratingAvg: asDoubleOrNull(j['rating_avg']) ?? 0,
    ratingCount: asInt(j['rating_count']),
    isFounding: asBool(j['is_founding']),
    priceVisible: asBool(j['price_visible']),
    priceSen: asIntOrNull(j['price_sen']),
    pricePerBaseUnitSen: asDoubleOrNull(j['price_per_base_unit_sen']),
    shippingFeeSen: asInt(j['shipping_fee_sen']),
    freeShippingMinSen: asIntOrNull(j['free_shipping_min_sen']),
    minOrderSen: asIntOrNull(j['min_order_sen']),
    leadTimeDays: asInt(j['lead_time_days'], 1),
  );

  final String productId;
  final String productName;
  final String? description;
  final List<String> photoPaths;
  final SellUnit unit;
  final int packQty;
  final int minOrderQty;
  final StockStatus stockStatus;
  final String? catalogItemId;
  final String wholesalerId;
  final String wholesalerName;
  final double ratingAvg;
  final int ratingCount;
  final bool isFounding;

  /// false：未付费用户、这家不在免费名单。服务器不会传价钱过来，App 显示模糊方块
  final bool priceVisible;
  final int? priceSen;
  final double? pricePerBaseUnitSen;
  final int shippingFeeSen;
  final int? freeShippingMinSen;
  final int? minOrderSen;
  final int leadTimeDays;

  bool get canOrder => priceVisible && stockStatus != StockStatus.outOfStock;
}

/// list_wholesalers()
class WholesalerSummary {
  const WholesalerSummary({
    required this.id,
    required this.name,
    this.description,
    this.logoPath,
    required this.ratingAvg,
    required this.ratingCount,
    required this.isFounding,
    required this.paymentTerms,
    required this.shippingFeeSen,
    this.freeShippingMinSen,
    this.minOrderSen,
    required this.leadTimeDays,
    required this.deliveryWeekdays,
    required this.productCount,
    required this.priceVisible,
    required this.isUnlocked,
  });

  factory WholesalerSummary.fromJson(Json j) => WholesalerSummary(
    id: j['wholesaler_id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    description: asStringOrNull(j['description']),
    logoPath: asStringOrNull(j['logo_path']),
    ratingAvg: asDoubleOrNull(j['rating_avg']) ?? 0,
    ratingCount: asInt(j['rating_count']),
    isFounding: asBool(j['is_founding']),
    paymentTerms: asStringList(j['payment_terms']),
    shippingFeeSen: asInt(j['shipping_fee_sen']),
    freeShippingMinSen: asIntOrNull(j['free_shipping_min_sen']),
    minOrderSen: asIntOrNull(j['min_order_sen']),
    leadTimeDays: asInt(j['lead_time_days'], 1),
    deliveryWeekdays: (j['delivery_weekdays'] as List? ?? const []).map((e) => asInt(e)).toList(),
    productCount: asInt(j['product_count']),
    priceVisible: asBool(j['price_visible']),
    isUnlocked: asBool(j['is_unlocked']),
  );

  final String id;
  final String name;
  final String? description;
  final String? logoPath;
  final double ratingAvg;
  final int ratingCount;
  final bool isFounding;

  /// cod / transfer / credit
  final List<String> paymentTerms;
  final int shippingFeeSen;
  final int? freeShippingMinSen;
  final int? minOrderSen;
  final int leadTimeDays;

  /// 1 = 星期一 ... 7 = 星期日
  final List<int> deliveryWeekdays;
  final int productCount;
  final bool priceVisible;
  final bool isUnlocked;
}
