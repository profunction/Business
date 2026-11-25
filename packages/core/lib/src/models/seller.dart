// 批发商端用的数据模型（第四步）。字段名跟数据库函数回传的 JSON 一致，
// 见 supabase/migrations/20261127000100_seller.sql 和 docs/04-seller-spec.md 第 2 节。
import '../json.dart';
import 'common.dart';

/// 批发商想怎么收新订单通知（wholesalers.notify_channel）
enum NotifyChannel { auto, push, whatsapp }

NotifyChannel notifyChannelFrom(Object? v) => switch (v?.toString()) {
  'push' => NotifyChannel.push,
  'whatsapp' => NotifyChannel.whatsapp,
  _ => NotifyChannel.auto,
};

/// 商品上架状态（products.status）：draft 草稿 / active 上架 / archived 下架
enum ProductStatus { draft, active, archived }

ProductStatus productStatusFrom(Object? v) => switch (v?.toString()) {
  'active' => ProductStatus.active,
  'archived' => ProductStatus.archived,
  _ => ProductStatus.draft,
};

/// 价目表导入的状态（price_list_imports.status）
enum ImportStatus { processing, review, applied, failed }

ImportStatus importStatusFrom(Object? v) => switch (v?.toString()) {
  'review' => ImportStatus.review,
  'applied' => ImportStatus.applied,
  'failed' => ImportStatus.failed,
  _ => ImportStatus.processing,
};

/// 上传的档案种类（price_list_imports.file_type）。CSV 也算 excel
enum ImportFileType { image, pdf, excel }

ImportFileType importFileTypeFrom(Object? v) => switch (v?.toString()) {
  'pdf' => ImportFileType.pdf,
  'excel' => ImportFileType.excel,
  _ => ImportFileType.image,
};

/// 导入的每一行要做什么：新增商品 / 更新对到的商品 / 跳过
enum ImportRowAction { create, update, skip }

ImportRowAction importRowActionFrom(Object? v) => switch (v?.toString()) {
  'update' => ImportRowAction.update,
  'skip' => ImportRowAction.skip,
  _ => ImportRowAction.create,
};

/// 数据库 enum 的值：SellUnit、StockStatus 等的英文代码
String sellUnitCode(SellUnit u) => u == SellUnit.unknown ? 'piece' : u.name;

/// null / 不认识的单位 → null（导入的行可能还没有单位）
SellUnit? sellUnitOrNull(Object? v) {
  final u = sellUnitFrom(v);
  return u == SellUnit.unknown ? null : u;
}

String stockStatusCode(StockStatus s) => switch (s) {
  StockStatus.inStock => 'in_stock',
  StockStatus.lowStock => 'low_stock',
  StockStatus.outOfStock => 'out_of_stock',
};

// ---------------- get_seller_home ----------------

class SellerWholesaler {
  const SellerWholesaler({
    required this.id,
    required this.name,
    required this.status,
    required this.isFounding,
    required this.notifyChannel,
  });

  factory SellerWholesaler.fromJson(Json j) => SellerWholesaler(
    id: j['id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    status: asStringOrNull(j['status']) ?? 'pending',
    isFounding: asBool(j['is_founding']),
    notifyChannel: notifyChannelFrom(j['notify_channel']),
  );

  final String id;
  final String name;

  /// pending（等客服审核）/ active / suspended
  final String status;
  final bool isFounding;
  final NotifyChannel notifyChannel;

  bool get isActive => status == 'active';
}

/// 商品数量；缺货 / 快卖完只算上架中的
class ProductCounts {
  const ProductCounts({required this.active, required this.draft, required this.outOfStock, required this.lowStock});

  factory ProductCounts.fromJson(Json j) => ProductCounts(
    active: asInt(j['active']),
    draft: asInt(j['draft']),
    outOfStock: asInt(j['out_of_stock']),
    lowStock: asInt(j['low_stock']),
  );

  final int active;
  final int draft;
  final int outOfStock;
  final int lowStock;
}

/// 最近一次上传的价目表（首页提示「AI 读好了，去确认」）
class ImportRef {
  const ImportRef({required this.id, required this.status, required this.createdAt});

  factory ImportRef.fromJson(Json j) => ImportRef(
    id: j['id'] as String,
    status: importStatusFrom(j['status']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
  );

  final String id;
  final ImportStatus status;
  final DateTime createdAt;
}

/// get_seller_home()
class SellerHome {
  const SellerHome({
    required this.today,
    required this.wholesaler,
    required this.pendingCount,
    this.oldestPendingAt,
    required this.todayOrderCount,
    required this.todayTotalSen,
    required this.productCounts,
    this.latestImport,
  });

  factory SellerHome.fromJson(Json j) {
    final latest = asJsonOrNull(j['latest_import']);
    return SellerHome(
      today: asDateOrNull(j['today']) ?? DateTime.now(),
      wholesaler: SellerWholesaler.fromJson(asJson(j['wholesaler'])),
      pendingCount: asInt(j['pending_count']),
      oldestPendingAt: asDateTimeOrNull(j['oldest_pending_at']),
      todayOrderCount: asInt(j['today_order_count']),
      todayTotalSen: asInt(j['today_total_sen']),
      productCounts: ProductCounts.fromJson(asJson(j['product_counts'])),
      latestImport: latest == null ? null : ImportRef.fromJson(latest),
    );
  }

  /// 马来西亚时间的今天（服务器算的）
  final DateTime today;
  final SellerWholesaler wholesaler;

  /// 等确认的新订单
  final int pendingCount;
  final DateTime? oldestPendingAt;

  /// 今天要送：confirmed / delivering 且 expected_delivery_date = 今天
  final int todayOrderCount;
  final int todayTotalSen;
  final ProductCounts productCounts;
  final ImportRef? latestImport;
}

// ---------------- list_seller_orders ----------------

/// list_seller_orders() 的一张
class SellerOrderSummary {
  const SellerOrderSummary({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.shopName,
    required this.zoneName,
    required this.itemCount,
    required this.outOfStockCount,
    required this.goodsSubtotalSen,
    required this.shippingFeeSen,
    required this.totalSen,
    this.note,
    required this.createdAt,
    this.expectedDeliveryDate,
  });

  factory SellerOrderSummary.fromJson(Json j) => SellerOrderSummary(
    id: j['id'] as String,
    orderNo: asStringOrNull(j['order_no']) ?? '',
    status: orderStatusFrom(j['status']),
    shopName: asStringOrNull(j['shop_name']) ?? '',
    zoneName: LocalizedName.fromJson(j['zone_name']),
    itemCount: asInt(j['item_count']),
    outOfStockCount: asInt(j['out_of_stock_count']),
    goodsSubtotalSen: asInt(j['goods_subtotal_sen']),
    shippingFeeSen: asInt(j['shipping_fee_sen']),
    totalSen: asInt(j['total_sen']),
    note: asStringOrNull(j['note']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
    expectedDeliveryDate: asDateOrNull(j['expected_delivery_date']),
  );

  final String id;
  final String orderNo;
  final OrderStatus status;
  final String shopName;
  final LocalizedName zoneName;
  final int itemCount;
  final int outOfStockCount;
  final int goodsSubtotalSen;
  final int shippingFeeSen;
  final int totalSen;
  final String? note;
  final DateTime createdAt;
  final DateTime? expectedDeliveryDate;
}

// ---------------- get_delivery_summary ----------------

/// 拣货单的一行：所有订单里没缺货的明细，按（名字、单位、包装数量）加总
class PickingLine {
  const PickingLine({required this.name, required this.unit, required this.packQty, required this.qty});

  factory PickingLine.fromJson(Json j) => PickingLine(
    name: asStringOrNull(j['name']) ?? '',
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    qty: asInt(j['qty']),
  );

  final String name;
  final SellUnit unit;
  final int packQty;
  final int qty;
}

/// 送货单上店铺的资料（电话没有时服务器已经用 WhatsApp 号码补上）
class DeliveryShop {
  const DeliveryShop({required this.name, this.contactName, this.phone, this.address, required this.zoneName});

  factory DeliveryShop.fromJson(Json j) => DeliveryShop(
    name: asStringOrNull(j['name']) ?? '',
    contactName: asStringOrNull(j['contact_name']),
    phone: asStringOrNull(j['phone']),
    address: asStringOrNull(j['address']),
    zoneName: LocalizedName.fromJson(j['zone_name']),
  );

  final String name;
  final String? contactName;

  /// 国际格式数字：'60123456789'
  final String? phone;
  final String? address;
  final LocalizedName zoneName;
}

/// 送货单上的一样东西。缺货的也列出来（排在后面），不算钱
class DeliveryItem {
  const DeliveryItem({
    required this.name,
    required this.unit,
    required this.packQty,
    required this.qty,
    required this.unitPriceSen,
    required this.lineTotalSen,
    required this.isOutOfStock,
  });

  factory DeliveryItem.fromJson(Json j) => DeliveryItem(
    name: asStringOrNull(j['name']) ?? '',
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    qty: asInt(j['qty']),
    unitPriceSen: asInt(j['unit_price_sen']),
    lineTotalSen: asInt(j['line_total_sen']),
    isOutOfStock: asBool(j['is_out_of_stock']),
  );

  final String name;
  final SellUnit unit;
  final int packQty;
  final int qty;
  final int unitPriceSen;
  final int lineTotalSen;
  final bool isOutOfStock;
}

/// 送货总结里的一张单（按送货区、再按店名排好）
class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.shop,
    required this.items,
    required this.goodsSubtotalSen,
    required this.shippingFeeSen,
    required this.totalSen,
    this.note,
    required this.paymentTerms,
  });

  factory DeliveryOrder.fromJson(Json j) => DeliveryOrder(
    id: j['id'] as String,
    orderNo: asStringOrNull(j['order_no']) ?? '',
    status: orderStatusFrom(j['status']),
    shop: DeliveryShop.fromJson(asJson(j['shop'])),
    items: asJsonList(j['items']).map(DeliveryItem.fromJson).toList(),
    goodsSubtotalSen: asInt(j['goods_subtotal_sen']),
    shippingFeeSen: asInt(j['shipping_fee_sen']),
    totalSen: asInt(j['total_sen']),
    note: asStringOrNull(j['note']),
    paymentTerms: asStringList(j['payment_terms']),
  );

  final String id;
  final String orderNo;
  final OrderStatus status;
  final DeliveryShop shop;
  final List<DeliveryItem> items;
  final int goodsSubtotalSen;
  final int shippingFeeSen;
  final int totalSen;
  final String? note;

  /// cod / transfer / credit
  final List<String> paymentTerms;
}

/// get_delivery_summary()：某一天要送的单（confirmed / delivering）
class DeliverySummary {
  const DeliverySummary({
    required this.date,
    required this.wholesalerId,
    required this.wholesalerName,
    this.wholesalerPhone,
    required this.orderCount,
    required this.pendingCount,
    required this.goodsTotalSen,
    required this.shippingTotalSen,
    required this.totalSen,
    required this.picking,
    required this.orders,
  });

  factory DeliverySummary.fromJson(Json j) {
    final w = asJson(j['wholesaler']);
    return DeliverySummary(
      date: asDateOrNull(j['date']) ?? DateTime.now(),
      wholesalerId: asStringOrNull(w['id']) ?? '',
      wholesalerName: asStringOrNull(w['name']) ?? '',
      wholesalerPhone: asStringOrNull(w['phone']),
      orderCount: asInt(j['order_count']),
      pendingCount: asInt(j['pending_count']),
      goodsTotalSen: asInt(j['goods_total_sen']),
      shippingTotalSen: asInt(j['shipping_total_sen']),
      totalSen: asInt(j['total_sen']),
      picking: asJsonList(j['picking']).map(PickingLine.fromJson).toList(),
      orders: asJsonList(j['orders']).map(DeliveryOrder.fromJson).toList(),
    );
  }

  final DateTime date;
  final String wholesalerId;
  final String wholesalerName;
  final String? wholesalerPhone;
  final int orderCount;

  /// 同一天还没确认的单（提醒「还有 N 张没确认」）
  final int pendingCount;
  final int goodsTotalSen;
  final int shippingTotalSen;
  final int totalSen;
  final List<PickingLine> picking;
  final List<DeliveryOrder> orders;

  bool get isEmpty => orders.isEmpty;
}

// ---------------- 商品（products 表，PostgREST select *） ----------------

/// 批发商自己的一样商品：products 表的一行。改价钱、库存、上架 / 下架用 [copyWith] 再 [WholesaleApi.saveProduct]
class SellerProduct {
  const SellerProduct({
    required this.id,
    required this.wholesalerId,
    this.catalogItemId,
    this.categoryId,
    required this.name,
    this.description,
    this.photoPaths = const [],
    required this.unit,
    required this.packQty,
    required this.priceSen,
    this.minOrderQty = 1,
    this.stockStatus = StockStatus.inStock,
    this.leadTimeDaysOverride,
    this.status = ProductStatus.active,
    this.sortOrder = 0,
    this.priceUpdatedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// 新增商品用（还没有 id）
  factory SellerProduct.draft({required String wholesalerId}) =>
      SellerProduct(id: '', wholesalerId: wholesalerId, name: '', unit: SellUnit.carton, packQty: 1, priceSen: 0);

  factory SellerProduct.fromJson(Json j) => SellerProduct(
    id: j['id'] as String,
    wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
    catalogItemId: asStringOrNull(j['catalog_item_id']),
    categoryId: asStringOrNull(j['category_id']),
    name: asStringOrNull(j['name']) ?? '',
    description: asStringOrNull(j['description']),
    photoPaths: asStringList(j['photo_paths']),
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    priceSen: asInt(j['price_sen']),
    minOrderQty: asInt(j['min_order_qty'], 1),
    stockStatus: stockStatusFrom(j['stock_status']),
    leadTimeDaysOverride: asIntOrNull(j['lead_time_days_override']),
    status: productStatusFrom(j['status']),
    sortOrder: asInt(j['sort_order']),
    priceUpdatedAt: asDateTimeOrNull(j['price_updated_at']),
    createdAt: asDateTimeOrNull(j['created_at']),
    updatedAt: asDateTimeOrNull(j['updated_at']),
  );

  /// 空的 = 还没存过（新增）
  final String id;
  final String wholesalerId;
  final String? catalogItemId;
  final String? categoryId;
  final String name;
  final String? description;
  final List<String> photoPaths;
  final SellUnit unit;
  final int packQty;
  final int priceSen;
  final int minOrderQty;
  final StockStatus stockStatus;
  final int? leadTimeDaysOverride;
  final ProductStatus status;
  final int sortOrder;
  final DateTime? priceUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isNew => id.isEmpty;

  /// 存之前检查：名字、价钱、包装数量、起订量（数据库也有一样的检查）
  bool get isValid => name.trim().isNotEmpty && priceSen > 0 && packQty > 0 && minOrderQty > 0;

  /// 批发商可以改的字段（id、wholesaler_id、created_by 受保护，不放进来）
  Json toWriteJson() => {
    'name': name.trim(),
    'description': description == null || description!.trim().isEmpty ? null : description!.trim(),
    'photo_paths': photoPaths,
    'catalog_item_id': catalogItemId,
    'category_id': categoryId,
    'unit': sellUnitCode(unit),
    'pack_qty': packQty,
    'price_sen': priceSen,
    'min_order_qty': minOrderQty,
    'stock_status': stockStatusCode(stockStatus),
    'lead_time_days_override': leadTimeDaysOverride,
    'status': status.name,
  };

  SellerProduct copyWith({
    String? name,
    String? description,
    String? catalogItemId,
    String? categoryId,
    SellUnit? unit,
    int? packQty,
    int? priceSen,
    int? minOrderQty,
    StockStatus? stockStatus,
    ProductStatus? status,
    List<String>? photoPaths,
  }) => SellerProduct(
    id: id,
    wholesalerId: wholesalerId,
    catalogItemId: catalogItemId ?? this.catalogItemId,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    description: description ?? this.description,
    photoPaths: photoPaths ?? this.photoPaths,
    unit: unit ?? this.unit,
    packQty: packQty ?? this.packQty,
    priceSen: priceSen ?? this.priceSen,
    minOrderQty: minOrderQty ?? this.minOrderQty,
    stockStatus: stockStatus ?? this.stockStatus,
    leadTimeDaysOverride: leadTimeDaysOverride,
    status: status ?? this.status,
    sortOrder: sortOrder,
    priceUpdatedAt: priceUpdatedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------- 价目表导入 ----------------

/// price_list_imports 的一行
class PriceListImport {
  const PriceListImport({
    required this.id,
    required this.wholesalerId,
    required this.filePath,
    required this.fileType,
    required this.status,
    this.errorMessage,
    this.aiRaw,
    this.createdBy,
    this.appliedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory PriceListImport.fromJson(Json j) => PriceListImport(
    id: j['id'] as String,
    wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
    filePath: asStringOrNull(j['file_path']) ?? '',
    fileType: importFileTypeFrom(j['file_type']),
    status: importStatusFrom(j['status']),
    errorMessage: asStringOrNull(j['error_message']),
    aiRaw: asJsonOrNull(j['ai_raw']),
    createdBy: asStringOrNull(j['created_by']),
    appliedAt: asDateTimeOrNull(j['applied_at']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
    updatedAt: asDateTimeOrNull(j['updated_at']),
  );

  final String id;
  final String wholesalerId;

  /// Storage bucket 'price-lists' 里的路径：`<wholesaler_id>/<uuid>.<ext>`
  final String filePath;
  final ImportFileType fileType;
  final ImportStatus status;

  /// 失败时的英文代码（UNSUPPORTED_FILE、AI_REFUSED、AI_TRUNCATED……）
  final String? errorMessage;
  final Json? aiRaw;
  final String? createdBy;
  final DateTime? appliedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isDone => status != ImportStatus.processing;

  /// parse-price-list 开始读的时间（ai_raw.claimed_at，函数占位时写的）。null = 还没有人开始读
  DateTime? get claimedAt => asDateTimeOrNull(aiRaw?['claimed_at']);
}

/// price_list_import_rows 的一行：AI 读到的一样商品，批发商可以改
class PriceListImportRow {
  const PriceListImportRow({
    required this.id,
    required this.importId,
    required this.rowNo,
    this.rawText,
    this.name,
    this.unit,
    this.packQty,
    this.priceSen,
    this.minOrderQty,
    this.matchedProductId,
    this.suggestedCatalogItemId,
    required this.action,
    this.confidence,
    this.createdAt,
  });

  factory PriceListImportRow.fromJson(Json j) => PriceListImportRow(
    id: j['id'] as String,
    importId: asStringOrNull(j['import_id']) ?? '',
    rowNo: asInt(j['row_no']),
    rawText: asStringOrNull(j['raw_text']),
    name: asStringOrNull(j['name']),
    unit: sellUnitOrNull(j['unit']),
    packQty: asIntOrNull(j['pack_qty']),
    priceSen: asIntOrNull(j['price_sen']),
    minOrderQty: asIntOrNull(j['min_order_qty']),
    matchedProductId: asStringOrNull(j['matched_product_id']),
    suggestedCatalogItemId: asStringOrNull(j['suggested_catalog_item_id']),
    action: importRowActionFrom(j['action']),
    confidence: asDoubleOrNull(j['confidence']),
    createdAt: asDateTimeOrNull(j['created_at']),
  );

  final String id;
  final String importId;

  /// 从 1 开始
  final int rowNo;

  /// 价目表上的原文（给批发商对照）
  final String? rawText;
  final String? name;
  final SellUnit? unit;
  final int? packQty;
  final int? priceSen;
  final int? minOrderQty;

  /// action = update 时改这样商品
  final String? matchedProductId;
  final String? suggestedCatalogItemId;
  final ImportRowAction action;

  /// AI 有多肯定（0..1）
  final double? confidence;
  final DateTime? createdAt;

  bool get hasName => name != null && name!.trim().isNotEmpty;

  /// 可以新增成商品（跟 apply_price_list_import 的检查一致）
  bool get canCreate => hasName && unit != null && packQty != null && priceSen != null;

  /// 可以更新对到的商品
  bool get canUpdate => matchedProductId != null && priceSen != null;

  /// 照现在的 action 能不能上架（skip 永远可以）
  bool get isReady => switch (action) {
    ImportRowAction.skip => true,
    ImportRowAction.create => canCreate,
    ImportRowAction.update => canUpdate,
  };

  /// AI 不太肯定的行（< 0.6）要特别提醒批发商看一下
  bool get isUnsure => (confidence ?? 1) < 0.6;

  /// 批发商可以改的字段（WholesaleApi.updateImportRow 用）
  Json toWriteJson() => {
    'name': hasName ? name!.trim() : null,
    'unit': unit == null ? null : sellUnitCode(unit!),
    'pack_qty': packQty,
    'price_sen': priceSen,
    'min_order_qty': minOrderQty,
    'matched_product_id': matchedProductId,
    'action': action.name,
  };

  /// 要清空某个字段（例如不对到任何商品）用 clearXxx: true
  PriceListImportRow copyWith({
    String? name,
    SellUnit? unit,
    int? packQty,
    int? priceSen,
    int? minOrderQty,
    String? matchedProductId,
    ImportRowAction? action,
    bool clearMatchedProduct = false,
    bool clearMinOrderQty = false,
  }) => PriceListImportRow(
    id: id,
    importId: importId,
    rowNo: rowNo,
    rawText: rawText,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    packQty: packQty ?? this.packQty,
    priceSen: priceSen ?? this.priceSen,
    minOrderQty: clearMinOrderQty ? null : (minOrderQty ?? this.minOrderQty),
    matchedProductId: clearMatchedProduct ? null : (matchedProductId ?? this.matchedProductId),
    suggestedCatalogItemId: suggestedCatalogItemId,
    action: action ?? this.action,
    confidence: confidence,
    createdAt: createdAt,
  );
}

/// apply_price_list_import()
class ApplyImportResult {
  const ApplyImportResult({required this.created, required this.updated, required this.skipped});

  factory ApplyImportResult.fromJson(Json j) =>
      ApplyImportResult(created: asInt(j['created']), updated: asInt(j['updated']), skipped: asInt(j['skipped']));

  final int created;
  final int updated;
  final int skipped;

  /// 上架了几样（新增 + 更新）
  int get listed => created + updated;
}

// ---------------- 批发商设定 ----------------

/// wholesalers 表里设定页要用的几个字段
class WholesalerSettings {
  const WholesalerSettings({
    required this.id,
    required this.name,
    this.phone,
    this.whatsappPhone,
    required this.notifyChannel,
    this.whatsappOptInAt,
  });

  factory WholesalerSettings.fromJson(Json j) => WholesalerSettings(
    id: j['id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    phone: asStringOrNull(j['phone']),
    whatsappPhone: asStringOrNull(j['whatsapp_phone']),
    notifyChannel: notifyChannelFrom(j['notify_channel']),
    whatsappOptInAt: asDateTimeOrNull(j['whatsapp_opt_in_at']),
  );

  final String id;
  final String name;
  final String? phone;
  final String? whatsappPhone;
  final NotifyChannel notifyChannel;

  /// 同意用 WhatsApp 收订单的时间；空的就不会发 WhatsApp（Meta 规定）
  final DateTime? whatsappOptInAt;

  /// 发 WhatsApp 用的号码（没有 WhatsApp 号码就用电话）
  String? get whatsappNumber => whatsappPhone ?? phone;

  bool get whatsappOptedIn => whatsappOptInAt != null;
}
