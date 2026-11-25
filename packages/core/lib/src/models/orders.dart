import '../json.dart';
import 'common.dart';

/// quote_cart() 的一行
class CartLine {
  const CartLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.packQty,
    required this.qty,
    required this.minOrderQty,
    this.unitPriceSen,
    this.lineTotalSen,
    this.problem,
  });

  factory CartLine.fromJson(Json j) => CartLine(
    productId: j['product_id'] as String,
    productName: asStringOrNull(j['product_name']) ?? '',
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    qty: asInt(j['qty']),
    minOrderQty: asInt(j['min_order_qty'], 1),
    unitPriceSen: asIntOrNull(j['unit_price_sen']),
    lineTotalSen: asIntOrNull(j['line_total_sen']),
    problem: cartProblemFrom(j['problem']),
  );

  final String productId;
  final String productName;
  final SellUnit unit;
  final int packQty;
  final int qty;
  final int minOrderQty;

  /// 锁住的批发商：null
  final int? unitPriceSen;
  final int? lineTotalSen;
  final CartProblem? problem;
}

/// quote_cart() 的一组（一家批发商）
class CartGroup {
  const CartGroup({
    required this.wholesalerId,
    required this.wholesalerName,
    required this.goodsSubtotalSen,
    this.shippingFeeSen,
    this.freeShippingMinSen,
    this.minOrderSen,
    required this.shortBySen,
    this.expectedDeliveryDate,
    this.problem,
    required this.lines,
  });

  factory CartGroup.fromJson(Json j) => CartGroup(
    wholesalerId: j['wholesaler_id'] as String,
    wholesalerName: asStringOrNull(j['wholesaler_name']) ?? '',
    goodsSubtotalSen: asInt(j['goods_subtotal_sen']),
    shippingFeeSen: asIntOrNull(j['shipping_fee_sen']),
    freeShippingMinSen: asIntOrNull(j['free_shipping_min_sen']),
    minOrderSen: asIntOrNull(j['min_order_sen']),
    shortBySen: asInt(j['short_by_sen']),
    expectedDeliveryDate: asDateOrNull(j['expected_delivery_date']),
    problem: cartProblemFrom(j['problem']),
    lines: asJsonList(j['lines']).map(CartLine.fromJson).toList(),
  );

  final String wholesalerId;
  final String wholesalerName;
  final int goodsSubtotalSen;

  /// 不送这区时是 null
  final int? shippingFeeSen;
  final int? freeShippingMinSen;
  final int? minOrderSen;

  /// 还差多少才到最低消费
  final int shortBySen;
  final DateTime? expectedDeliveryDate;
  final CartProblem? problem;
  final List<CartLine> lines;

  int get totalSen => goodsSubtotalSen + (shippingFeeSen ?? 0);

  bool get hasProblem => problem != null || lines.any((l) => l.problem != null);

  /// 还差多少就免运费（已经免运费或没有免运费门槛时是 null）
  int? get shortOfFreeShippingSen {
    final min = freeShippingMinSen;
    if (min == null || shippingFeeSen == null || shippingFeeSen == 0) return null;
    final short = min - goodsSubtotalSen;
    return short > 0 ? short : null;
  }
}

/// quote_cart()
class CartQuote {
  const CartQuote({
    required this.canPlace,
    required this.goodsTotalSen,
    required this.shippingTotalSen,
    required this.totalSen,
    required this.groups,
  });

  factory CartQuote.fromJson(Json j) => CartQuote(
    canPlace: asBool(j['can_place']),
    goodsTotalSen: asInt(j['goods_total_sen']),
    shippingTotalSen: asInt(j['shipping_total_sen']),
    totalSen: asInt(j['total_sen']),
    groups: asJsonList(j['groups']).map(CartGroup.fromJson).toList(),
  );

  static const empty = CartQuote(canPlace: false, goodsTotalSen: 0, shippingTotalSen: 0, totalSen: 0, groups: []);

  final bool canPlace;
  final int goodsTotalSen;
  final int shippingTotalSen;
  final int totalSen;
  final List<CartGroup> groups;

  bool get isEmpty => groups.isEmpty;

  int get lineCount => groups.fold(0, (n, g) => n + g.lines.length);

  int qtyOf(String productId) {
    for (final g in groups) {
      for (final l in g.lines) {
        if (l.productId == productId) return l.qty;
      }
    }
    return 0;
  }
}

class PriceChange {
  const PriceChange({
    required this.productId,
    required this.productName,
    required this.oldPriceSen,
    required this.newPriceSen,
  });

  factory PriceChange.fromJson(Json j) => PriceChange(
    productId: j['product_id'] as String,
    productName: asStringOrNull(j['product_name']) ?? '',
    oldPriceSen: asInt(j['old_price_sen']),
    newPriceSen: asInt(j['new_price_sen']),
  );

  final String productId;
  final String productName;
  final int oldPriceSen;
  final int newPriceSen;
}

class SkippedItem {
  const SkippedItem({required this.productName, required this.reason});

  factory SkippedItem.fromJson(Json j) =>
      SkippedItem(productName: asStringOrNull(j['product_name']) ?? '', reason: asStringOrNull(j['reason']) ?? '');

  final String productName;

  /// PRODUCT_REMOVED / PRODUCT_UNAVAILABLE
  final String reason;
}

/// reorder_last()
class ReorderResult {
  const ReorderResult({
    required this.addedCount,
    required this.skipped,
    required this.priceChanges,
    required this.quote,
  });

  factory ReorderResult.fromJson(Json j) => ReorderResult(
    addedCount: asInt(j['added_count']),
    skipped: asJsonList(j['skipped']).map(SkippedItem.fromJson).toList(),
    priceChanges: asJsonList(j['price_changes']).map(PriceChange.fromJson).toList(),
    quote: CartQuote.fromJson(asJson(j['quote'])),
  );

  final int addedCount;
  final List<SkippedItem> skipped;
  final List<PriceChange> priceChanges;
  final CartQuote quote;
}

/// list_orders() 的一张
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.wholesalerId,
    required this.wholesalerName,
    required this.totalSen,
    required this.itemCount,
    required this.outOfStockCount,
    required this.createdAt,
    this.expectedDeliveryDate,
    this.deliveredAt,
    required this.hasReview,
  });

  factory OrderSummary.fromJson(Json j) => OrderSummary(
    id: j['id'] as String,
    orderNo: asStringOrNull(j['order_no']) ?? '',
    status: orderStatusFrom(j['status']),
    wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
    wholesalerName: asStringOrNull(j['wholesaler_name']) ?? '',
    totalSen: asInt(j['total_sen']),
    itemCount: asInt(j['item_count']),
    outOfStockCount: asInt(j['out_of_stock_count']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
    expectedDeliveryDate: asDateOrNull(j['expected_delivery_date']),
    deliveredAt: asDateTimeOrNull(j['delivered_at']),
    hasReview: asBool(j['has_review']),
  );

  final String id;
  final String orderNo;
  final OrderStatus status;
  final String wholesalerId;
  final String wholesalerName;
  final int totalSen;
  final int itemCount;
  final int outOfStockCount;
  final DateTime createdAt;
  final DateTime? expectedDeliveryDate;
  final DateTime? deliveredAt;
  final bool hasReview;
}

class OrderItem {
  const OrderItem({
    required this.id,
    this.productId,
    required this.name,
    required this.unit,
    required this.packQty,
    required this.unitPriceSen,
    required this.qty,
    required this.lineTotalSen,
    required this.isOutOfStock,
  });

  factory OrderItem.fromJson(Json j) => OrderItem(
    id: j['id'] as String,
    productId: asStringOrNull(j['product_id']),
    name: asStringOrNull(j['name']) ?? '',
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    unitPriceSen: asInt(j['unit_price_sen']),
    qty: asInt(j['qty']),
    lineTotalSen: asInt(j['line_total_sen']),
    isOutOfStock: asBool(j['is_out_of_stock']),
  );

  final String id;

  /// 商品可能已经删掉了（订单里的名字、价钱是下单时的快照）
  final String? productId;
  final String name;
  final SellUnit unit;
  final int packQty;
  final int unitPriceSen;
  final int qty;
  final int lineTotalSen;
  final bool isOutOfStock;
}

class OrderEvent {
  const OrderEvent({this.fromStatus, required this.toStatus, required this.createdAt, this.note});

  factory OrderEvent.fromJson(Json j) => OrderEvent(
    fromStatus: j['from_status'] == null ? null : orderStatusFrom(j['from_status']),
    toStatus: orderStatusFrom(j['to_status']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
    note: asStringOrNull(j['note']),
  );

  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final DateTime createdAt;
  final String? note;
}

class OrderReview {
  const OrderReview({required this.rating, required this.tags, this.comment});

  factory OrderReview.fromJson(Json j) => OrderReview(
    rating: asInt(j['rating']),
    tags: asStringList(j['tags']).map(reviewTagFrom).whereType<ReviewTag>().toList(),
    comment: asStringOrNull(j['comment']),
  );

  final int rating;
  final List<ReviewTag> tags;
  final String? comment;
}

/// 服务器算好的「现在可以按哪些按钮」（规则跟 set_order_status 一致）
class OrderActions {
  const OrderActions({
    required this.canCancel,
    required this.canMarkReceived,
    required this.canReview,
    required this.canConfirm,
    required this.canMarkDelivering,
    required this.canMarkDelivered,
  });

  factory OrderActions.fromJson(Json j) => OrderActions(
    canCancel: asBool(j['can_cancel']),
    canMarkReceived: asBool(j['can_mark_received']),
    canReview: asBool(j['can_review']),
    canConfirm: asBool(j['can_confirm']),
    canMarkDelivering: asBool(j['can_mark_delivering']),
    canMarkDelivered: asBool(j['can_mark_delivered']),
  );

  final bool canCancel;
  final bool canMarkReceived;
  final bool canReview;
  final bool canConfirm;
  final bool canMarkDelivering;
  final bool canMarkDelivered;
}

/// get_order()
class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.goodsSubtotalSen,
    required this.shippingFeeSen,
    required this.totalSen,
    this.note,
    this.expectedDeliveryDate,
    required this.createdAt,
    this.cancelReason,
    required this.wholesalerId,
    required this.wholesalerName,
    this.wholesalerPhone,
    required this.paymentTerms,
    required this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.shopContactName,
    this.shopZoneName,
    this.source,
    required this.items,
    required this.events,
    this.review,
    required this.actions,
  });

  factory OrderDetail.fromJson(Json j) {
    final w = asJson(j['wholesaler']);
    final s = asJson(j['shop']);
    final r = asJsonOrNull(j['review']);
    return OrderDetail(
      id: j['id'] as String,
      orderNo: asStringOrNull(j['order_no']) ?? '',
      status: orderStatusFrom(j['status']),
      goodsSubtotalSen: asInt(j['goods_subtotal_sen']),
      shippingFeeSen: asInt(j['shipping_fee_sen']),
      totalSen: asInt(j['total_sen']),
      note: asStringOrNull(j['note']),
      expectedDeliveryDate: asDateOrNull(j['expected_delivery_date']),
      createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
      cancelReason: asStringOrNull(j['cancel_reason']),
      wholesalerId: asStringOrNull(w['id']) ?? '',
      wholesalerName: asStringOrNull(w['name']) ?? '',
      wholesalerPhone: asStringOrNull(w['phone']) ?? asStringOrNull(w['whatsapp_phone']),
      paymentTerms: asStringList(w['payment_terms']),
      shopName: asStringOrNull(s['name']) ?? '',
      shopAddress: asStringOrNull(s['address']),
      // get_order 的 shop 现在只回传 phone（没有 whatsapp_phone，也没有像 get_delivery_summary 那样
      // coalesce(phone, whatsapp_phone)）：只有 WhatsApp 号码的店这里会是 null。要后端改 get_order，这一行先留着
      shopPhone: asStringOrNull(s['phone']) ?? asStringOrNull(s['whatsapp_phone']),
      shopContactName: asStringOrNull(s['contact_name']),
      shopZoneName: s['zone_name'] is Map ? LocalizedName.fromJson(s['zone_name']) : null,
      source: asStringOrNull(j['source']),
      items: asJsonList(j['items']).map(OrderItem.fromJson).toList(),
      events: asJsonList(j['events']).map(OrderEvent.fromJson).toList(),
      review: r == null ? null : OrderReview.fromJson(r),
      actions: OrderActions.fromJson(asJson(j['actions'])),
    );
  }

  final String id;
  final String orderNo;
  final OrderStatus status;
  final int goodsSubtotalSen;
  final int shippingFeeSen;
  final int totalSen;
  final String? note;
  final DateTime? expectedDeliveryDate;
  final DateTime createdAt;
  final String? cancelReason;
  final String wholesalerId;
  final String wholesalerName;
  final String? wholesalerPhone;
  final List<String> paymentTerms;
  final String shopName;
  final String? shopAddress;

  /// 批发商打电话 / WhatsApp 给店用（国际格式数字）
  final String? shopPhone;
  final String? shopContactName;
  final LocalizedName? shopZoneName;

  /// app / voice / whatsapp / admin / reorder
  final String? source;
  final List<OrderItem> items;
  final List<OrderEvent> events;
  final OrderReview? review;
  final OrderActions actions;

  /// 某个状态是什么时候到的（进度条用）
  DateTime? reachedAt(OrderStatus s) {
    for (final e in events) {
      if (e.toStatus == s) return e.createdAt;
    }
    return null;
  }
}
