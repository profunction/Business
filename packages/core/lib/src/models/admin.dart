// 客服后台（apps/admin_web）用的数据模型。对应 supabase/migrations/20261128000100_admin.sql 的 admin_* 函数。
import '../json.dart';
import '../money.dart';
import 'account.dart';
import 'common.dart';
import 'seller.dart';

enum WholesalerStatus { pending, active, suspended }

WholesalerStatus wholesalerStatusFrom(Object? v) => switch (v?.toString()) {
  'active' => WholesalerStatus.active,
  'suspended' => WholesalerStatus.suspended,
  _ => WholesalerStatus.pending,
};

/// 订单来源（跟数据库 order_source 一样）
enum OrderSource { app, voice, whatsapp, admin, reorder }

OrderSource orderSourceFrom(Object? v) =>
    OrderSource.values.firstWhere((e) => e.name == v?.toString(), orElse: () => OrderSource.app);

/// 付款方式（跟数据库 payment_method 一样）
enum PaymentMethod { fpx, duitnow, ewallet, card, other }

PaymentMethod paymentMethodFrom(Object? v) =>
    PaymentMethod.values.firstWhere((e) => e.name == v?.toString(), orElse: () => PaymentMethod.other);

String subscriptionStateCode(SubscriptionState s) => switch (s) {
  SubscriptionState.trialing => 'trialing',
  SubscriptionState.active => 'active',
  SubscriptionState.pastDue => 'past_due',
  SubscriptionState.lapsed => 'lapsed',
  SubscriptionState.none => 'none',
};

/// 佣金比例 → 百分比文字：0.015 → '1.5%'，0.02 → '2%'
String formatRate(double rate) => '${formatSen(rate * 100)}%';

/// admin_dashboard()
class AdminDashboard {
  const AdminDashboard({
    required this.today,
    required this.alertMinutes,
    required this.pendingWholesalers,
    required this.unconfirmedOrders,
    required this.pendingOrders,
    required this.todayOrderCount,
    required this.todayTotalSen,
    required this.trialing,
    required this.active,
    required this.pastDue,
    required this.lapsed,
    required this.foundingPrice,
    required this.month,
    required this.monthGmvSen,
    required this.monthCommissionSen,
  });

  factory AdminDashboard.fromJson(Json j) {
    final subs = asJson(j['subscriptions']);
    return AdminDashboard(
      today: asDateOrNull(j['today']),
      alertMinutes: asInt(j['alert_minutes'], 30),
      pendingWholesalers: asInt(j['pending_wholesalers']),
      unconfirmedOrders: asInt(j['unconfirmed_orders']),
      pendingOrders: asInt(j['pending_orders']),
      todayOrderCount: asInt(j['today_order_count']),
      todayTotalSen: asInt(j['today_total_sen']),
      trialing: asInt(subs['trialing']),
      active: asInt(subs['active']),
      pastDue: asInt(subs['past_due']),
      lapsed: asInt(subs['lapsed']),
      foundingPrice: asInt(subs['founding_price']),
      month: asDateOrNull(j['month']),
      monthGmvSen: asInt(j['month_gmv_sen']),
      monthCommissionSen: asInt(j['month_commission_sen']),
    );
  }

  final DateTime? today;
  final int alertMinutes;
  final int pendingWholesalers;
  final int unconfirmedOrders;
  final int pendingOrders;
  final int todayOrderCount;
  final int todayTotalSen;
  final int trialing;
  final int active;
  final int pastDue;
  final int lapsed;
  final int foundingPrice;
  final DateTime? month;
  final int monthGmvSen;
  final int monthCommissionSen;
}

/// admin_list_shops() 的一行
class AdminShop {
  const AdminShop({
    required this.id,
    required this.name,
    required this.zoneName,
    this.address,
    this.contactName,
    this.phone,
    this.whatsappPhone,
    this.whatsappOptInAt,
    this.isActive = true,
    this.memberCount = 0,
    this.cartCount = 0,
    this.hasFullAccess = false,
    this.subscriptionState = SubscriptionState.none,
  });

  factory AdminShop.fromJson(Json j) => AdminShop(
    id: j['id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    zoneName: LocalizedName.fromJson(j['zone_name']),
    address: asStringOrNull(j['address']),
    contactName: asStringOrNull(j['contact_name']),
    phone: asStringOrNull(j['phone']),
    whatsappPhone: asStringOrNull(j['whatsapp_phone']),
    whatsappOptInAt: asDateTimeOrNull(j['whatsapp_opt_in_at']),
    isActive: asBool(j['is_active'], true),
    memberCount: asInt(j['member_count']),
    cartCount: asInt(j['cart_count']),
    hasFullAccess: asBool(j['has_full_access']),
    subscriptionState: subscriptionStateFrom(j['subscription_status']),
  );

  final String id;
  final String name;
  final LocalizedName zoneName;
  final String? address;
  final String? contactName;
  final String? phone;
  final String? whatsappPhone;
  final DateTime? whatsappOptInAt;
  final bool isActive;

  /// 0 = 没装 App（客服替他操作）
  final int memberCount;
  final int cartCount;
  final bool hasFullAccess;
  final SubscriptionState subscriptionState;
}

/// admin_list_wholesalers() 的一行（审核、停权、改佣金比例之后也回传这个）
class AdminWholesaler {
  const AdminWholesaler({
    required this.id,
    required this.name,
    required this.status,
    this.isFounding = false,
    this.foundingNo,
    this.foundingFeePaidAt,
    this.contactName,
    this.phone,
    this.whatsappPhone,
    this.whatsappOptInAt,
    this.notifyChannel = NotifyChannel.auto,
    this.regionName,
    this.industryName,
    required this.commissionRate,
    required this.commissionRateSource,
    this.commissionRateOverride,
    this.industryDefaultRate,
    this.industryFoundingRate,
    this.activeProductCount = 0,
    this.pendingOrderCount = 0,
    this.memberCount = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.approvedAt,
    this.createdAt,
  });

  factory AdminWholesaler.fromJson(Json j) => AdminWholesaler(
    id: j['id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    status: wholesalerStatusFrom(j['status']),
    isFounding: asBool(j['is_founding']),
    foundingNo: asIntOrNull(j['founding_no']),
    foundingFeePaidAt: asDateTimeOrNull(j['founding_fee_paid_at']),
    contactName: asStringOrNull(j['contact_name']),
    phone: asStringOrNull(j['phone']),
    whatsappPhone: asStringOrNull(j['whatsapp_phone']),
    whatsappOptInAt: asDateTimeOrNull(j['whatsapp_opt_in_at']),
    notifyChannel: notifyChannelFrom(j['notify_channel']),
    regionName: j['region_name'] == null ? null : LocalizedName.fromJson(j['region_name']),
    industryName: j['industry_name'] == null ? null : LocalizedName.fromJson(j['industry_name']),
    commissionRate: asDoubleOrNull(j['commission_rate']) ?? 0,
    commissionRateSource: asStringOrNull(j['commission_rate_source']) ?? 'industry',
    commissionRateOverride: asDoubleOrNull(j['commission_rate_override']),
    industryDefaultRate: asDoubleOrNull(j['industry_default_rate']),
    industryFoundingRate: asDoubleOrNull(j['industry_founding_rate']),
    activeProductCount: asInt(j['active_product_count']),
    pendingOrderCount: asInt(j['pending_order_count']),
    memberCount: asInt(j['member_count']),
    ratingAvg: asDoubleOrNull(j['rating_avg']) ?? 0,
    ratingCount: asInt(j['rating_count']),
    approvedAt: asDateTimeOrNull(j['approved_at']),
    createdAt: asDateTimeOrNull(j['created_at']),
  );

  final String id;
  final String name;
  final WholesalerStatus status;
  final bool isFounding;
  final int? foundingNo;

  /// 创始上架费什么时候付的（没付 → null）
  final DateTime? foundingFeePaidAt;
  final String? contactName;
  final String? phone;
  final String? whatsappPhone;
  final DateTime? whatsappOptInAt;
  final NotifyChannel notifyChannel;
  final LocalizedName? regionName;
  final LocalizedName? industryName;

  /// 现在用的比例（单独调整 > 创始 > 行业默认）
  final double commissionRate;

  /// override / founding / industry
  final String commissionRateSource;
  final double? commissionRateOverride;
  final double? industryDefaultRate;
  final double? industryFoundingRate;
  final int activeProductCount;
  final int pendingOrderCount;
  final int memberCount;
  final double ratingAvg;
  final int ratingCount;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  String? get contactPhone => whatsappPhone ?? phone;
}

/// 全部订单的筛选条件（admin_list_orders）
class AdminOrderFilter {
  const AdminOrderFilter({
    this.from,
    this.to,
    this.wholesalerId,
    this.shopId,
    this.statuses = const {},
    this.sources = const {},
    this.unconfirmedOnly = false,
    this.limit = 100,
    this.offset = 0,
  });

  /// 马来西亚时间的下单日期（包括这一天）
  final DateTime? from;
  final DateTime? to;
  final String? wholesalerId;
  final String? shopId;
  final Set<OrderStatus> statuses;
  final Set<OrderSource> sources;

  /// 待确认超过 30 分钟（跟进名单）
  final bool unconfirmedOnly;
  final int limit;
  final int offset;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Json toParams() => {
    'p_from': from == null ? null : _date(from!),
    'p_to': to == null ? null : _date(to!),
    'p_wholesaler_id': wholesalerId,
    'p_shop_id': shopId,
    'p_statuses': statuses.isEmpty ? null : [for (final s in statuses) orderStatusCode(s)],
    'p_sources': sources.isEmpty ? null : [for (final s in sources) s.name],
    'p_unconfirmed_only': unconfirmedOnly,
    'p_limit': limit,
    'p_offset': offset,
  };

  AdminOrderFilter copyWith({
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? wholesalerId,
    String? Function()? shopId,
    Set<OrderStatus>? statuses,
    Set<OrderSource>? sources,
    bool? unconfirmedOnly,
    int? offset,
  }) => AdminOrderFilter(
    from: from == null ? this.from : from(),
    to: to == null ? this.to : to(),
    wholesalerId: wholesalerId == null ? this.wholesalerId : wholesalerId(),
    shopId: shopId == null ? this.shopId : shopId(),
    statuses: statuses ?? this.statuses,
    sources: sources ?? this.sources,
    unconfirmedOnly: unconfirmedOnly ?? this.unconfirmedOnly,
    limit: limit,
    offset: offset ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is AdminOrderFilter &&
      other.from == from &&
      other.to == to &&
      other.wholesalerId == wholesalerId &&
      other.shopId == shopId &&
      _setEq(other.statuses, statuses) &&
      _setEq(other.sources, sources) &&
      other.unconfirmedOnly == unconfirmedOnly &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(
    from,
    to,
    wholesalerId,
    shopId,
    Object.hashAllUnordered(statuses),
    Object.hashAllUnordered(sources),
    unconfirmedOnly,
    limit,
    offset,
  );

  static bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
}

/// admin_list_orders() 的一行
class AdminOrderRow {
  const AdminOrderRow({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.source,
    required this.shopId,
    required this.shopName,
    this.shopPhone,
    required this.wholesalerId,
    required this.wholesalerName,
    this.wholesalerPhone,
    required this.goodsSubtotalSen,
    required this.shippingFeeSen,
    required this.totalSen,
    this.itemCount = 0,
    this.outOfStockCount = 0,
    this.createdAt,
    this.expectedDeliveryDate,
    this.pendingMinutes,
    this.lastFollowupAt,
    this.lastFollowupNote,
  });

  factory AdminOrderRow.fromJson(Json j) {
    final f = asJsonOrNull(j['last_followup']);
    return AdminOrderRow(
      id: j['id'] as String,
      orderNo: asStringOrNull(j['order_no']) ?? '',
      status: orderStatusFrom(j['status']),
      source: orderSourceFrom(j['source']),
      shopId: asStringOrNull(j['shop_id']) ?? '',
      shopName: asStringOrNull(j['shop_name']) ?? '',
      shopPhone: asStringOrNull(j['shop_phone']),
      wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
      wholesalerName: asStringOrNull(j['wholesaler_name']) ?? '',
      wholesalerPhone: asStringOrNull(j['wholesaler_phone']),
      goodsSubtotalSen: asInt(j['goods_subtotal_sen']),
      shippingFeeSen: asInt(j['shipping_fee_sen']),
      totalSen: asInt(j['total_sen']),
      itemCount: asInt(j['item_count']),
      outOfStockCount: asInt(j['out_of_stock_count']),
      createdAt: asDateTimeOrNull(j['created_at']),
      expectedDeliveryDate: asDateOrNull(j['expected_delivery_date']),
      pendingMinutes: asIntOrNull(j['pending_minutes']),
      lastFollowupAt: asDateTimeOrNull(f?['at']),
      lastFollowupNote: asStringOrNull(f?['note']),
    );
  }

  final String id;
  final String orderNo;
  final OrderStatus status;
  final OrderSource source;
  final String shopId;
  final String shopName;
  final String? shopPhone;
  final String wholesalerId;
  final String wholesalerName;
  final String? wholesalerPhone;
  final int goodsSubtotalSen;
  final int shippingFeeSen;
  final int totalSen;
  final int itemCount;
  final int outOfStockCount;
  final DateTime? createdAt;
  final DateTime? expectedDeliveryDate;

  /// 待确认的单：等了几分钟（其他状态是 null）
  final int? pendingMinutes;
  final DateTime? lastFollowupAt;
  final String? lastFollowupNote;
}

class AdminOrderPage {
  const AdminOrderPage({required this.total, required this.orders});

  factory AdminOrderPage.fromJson(Json j) =>
      AdminOrderPage(total: asInt(j['total']), orders: asJsonList(j['orders']).map(AdminOrderRow.fromJson).toList());

  /// 符合条件的总数（不只这一页）
  final int total;
  final List<AdminOrderRow> orders;
}

/// admin_place_order() 的回传
class AdminPlacedOrder {
  const AdminPlacedOrder({required this.checkoutId, required this.orders});

  factory AdminPlacedOrder.fromJson(Json j) => AdminPlacedOrder(
    checkoutId: asStringOrNull(j['checkout_id']) ?? '',
    orders: [
      for (final o in asJsonList(j['orders']))
        (
          id: asStringOrNull(o['id']) ?? '',
          orderNo: asStringOrNull(o['order_no']) ?? '',
          wholesalerName: asStringOrNull(o['wholesaler_name']) ?? '',
          totalSen: asInt(o['total_sen']),
        ),
    ],
  );

  final String checkoutId;
  final List<({String id, String orderNo, String wholesalerName, int totalSen})> orders;
}

class AdminPayment {
  const AdminPayment({required this.id, required this.amountSen, required this.method, this.reference, this.paidAt});

  factory AdminPayment.fromJson(Json j) => AdminPayment(
    id: asStringOrNull(j['id']) ?? '',
    amountSen: asInt(j['amount_sen']),
    method: paymentMethodFrom(j['method']),
    reference: asStringOrNull(j['gateway_ref']),
    paidAt: asDateTimeOrNull(j['paid_at']),
  );

  final String id;
  final int amountSen;
  final PaymentMethod method;
  final String? reference;
  final DateTime? paidAt;
}

/// admin_list_subscriptions() 的一行（延长试用、标记已付……之后也回传这个）
class AdminSubscription {
  const AdminSubscription({
    required this.id,
    required this.shopId,
    required this.shopName,
    this.shopPhone,
    required this.state,
    this.startedAt,
    this.trialEndsAt,
    required this.lockedPriceSen,
    this.isFoundingPrice = false,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.graceUntil,
    this.lapsedAt,
    this.hasFullAccess = false,
    this.lastPayment,
    this.paymentId,
  });

  factory AdminSubscription.fromJson(Json j) => AdminSubscription(
    id: j['id'] as String,
    shopId: asStringOrNull(j['shop_id']) ?? '',
    shopName: asStringOrNull(j['shop_name']) ?? '',
    shopPhone: asStringOrNull(j['shop_phone']),
    state: subscriptionStateFrom(j['status']),
    startedAt: asDateTimeOrNull(j['started_at']),
    trialEndsAt: asDateTimeOrNull(j['trial_ends_at']),
    lockedPriceSen: asInt(j['locked_price_sen']),
    isFoundingPrice: asBool(j['is_founding_price']),
    currentPeriodStart: asDateTimeOrNull(j['current_period_start']),
    currentPeriodEnd: asDateTimeOrNull(j['current_period_end']),
    graceUntil: asDateTimeOrNull(j['grace_until']),
    lapsedAt: asDateTimeOrNull(j['lapsed_at']),
    hasFullAccess: asBool(j['has_full_access']),
    lastPayment: asJsonOrNull(j['last_payment']) == null ? null : AdminPayment.fromJson(asJson(j['last_payment'])),
    paymentId: asStringOrNull(j['payment_id']),
  );

  final String id;
  final String shopId;
  final String shopName;
  final String? shopPhone;
  final SubscriptionState state;
  final DateTime? startedAt;
  final DateTime? trialEndsAt;
  final int lockedPriceSen;
  final bool isFoundingPrice;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? graceUntil;
  final DateTime? lapsedAt;
  final bool hasFullAccess;
  final AdminPayment? lastPayment;

  /// 刚标记已付时：那一笔付款
  final String? paymentId;

  /// 试用过期、从来没付过 → 可以重新打开试用
  bool get canExtendTrial =>
      state == SubscriptionState.trialing || (state == SubscriptionState.lapsed && currentPeriodEnd == null);
  bool get canCancel => state != SubscriptionState.lapsed && state != SubscriptionState.none;
}

class CommissionInvoice {
  const CommissionInvoice({
    required this.id,
    required this.invoiceNo,
    required this.status,
    this.orderCount = 0,
    this.gmvSen = 0,
    this.commissionSen = 0,
    this.issuedAt,
    this.dueDate,
    this.paidAt,
    this.periodMonth,
  });

  factory CommissionInvoice.fromJson(Json j) => CommissionInvoice(
    id: j['id'] as String,
    invoiceNo: asStringOrNull(j['invoice_no']) ?? '',
    status: asStringOrNull(j['status']) ?? 'draft',
    orderCount: asInt(j['order_count']),
    gmvSen: asInt(j['gmv_sen']),
    commissionSen: asInt(j['commission_sen']),
    issuedAt: asDateTimeOrNull(j['issued_at']),
    dueDate: asDateOrNull(j['due_date']),
    paidAt: asDateTimeOrNull(j['paid_at']),
    periodMonth: asDateOrNull(j['period_month']),
  );

  final String id;
  final String invoiceNo;

  /// 哪个月的佣金（那个月的 1 号）
  final DateTime? periodMonth;

  /// draft / issued / paid / overdue / void
  final String status;
  final int orderCount;
  final int gmvSen;
  final int commissionSen;
  final DateTime? issuedAt;
  final DateTime? dueDate;
  final DateTime? paidAt;

  /// 已发出 / 逾期、还没付
  bool get isOutstanding => status == 'issued' || status == 'overdue';
}

class CommissionOrderLine {
  const CommissionOrderLine({
    required this.orderId,
    required this.orderNo,
    required this.shopName,
    this.deliveredAt,
    required this.baseAmountSen,
    required this.shippingFeeSen,
    required this.rate,
    required this.rateSource,
    required this.commissionSen,
  });

  factory CommissionOrderLine.fromJson(Json j) => CommissionOrderLine(
    orderId: asStringOrNull(j['order_id']) ?? '',
    orderNo: asStringOrNull(j['order_no']) ?? '',
    shopName: asStringOrNull(j['shop_name']) ?? '',
    deliveredAt: asDateTimeOrNull(j['delivered_at']),
    baseAmountSen: asInt(j['base_amount_sen']),
    shippingFeeSen: asInt(j['shipping_fee_sen']),
    rate: asDoubleOrNull(j['rate']) ?? 0,
    rateSource: asStringOrNull(j['rate_source']) ?? 'industry',
    commissionSen: asInt(j['commission_sen']),
  );

  final String orderId;
  final String orderNo;
  final String shopName;
  final DateTime? deliveredAt;

  /// 货价（不含运费）
  final int baseAmountSen;

  /// 只做参考：运费不算佣金
  final int shippingFeeSen;
  final double rate;
  final String rateSource;
  final int commissionSen;
}

/// 报表里一家批发商
class WholesalerCommission {
  const WholesalerCommission({
    required this.wholesalerId,
    required this.name,
    this.status = WholesalerStatus.active,
    this.isFounding = false,
    this.phone,
    required this.billingName,
    this.billingEmail,
    this.billingAddress,
    this.ssmNo,
    required this.orderCount,
    required this.gmvSen,
    required this.commissionSen,
    this.rates = const [],
    this.invoice,
    this.orders = const [],
  });

  factory WholesalerCommission.fromJson(Json j) {
    final billing = asJson(j['billing']);
    final name = asStringOrNull(j['name']) ?? '';
    return WholesalerCommission(
      wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
      name: name,
      status: wholesalerStatusFrom(j['status']),
      isFounding: asBool(j['is_founding']),
      phone: asStringOrNull(j['phone']),
      billingName: asStringOrNull(billing['name']) ?? name,
      billingEmail: asStringOrNull(billing['email']),
      billingAddress: asStringOrNull(billing['address']),
      ssmNo: asStringOrNull(billing['ssm_no']),
      orderCount: asInt(j['order_count']),
      gmvSen: asInt(j['gmv_sen']),
      commissionSen: asInt(j['commission_sen']),
      rates: [
        for (final r in asJsonList(j['rates']))
          (rate: asDoubleOrNull(r['rate']) ?? 0, source: asStringOrNull(r['rate_source']) ?? 'industry'),
      ]..sort((a, b) => a.rate.compareTo(b.rate)),
      invoice: asJsonOrNull(j['invoice']) == null ? null : CommissionInvoice.fromJson(asJson(j['invoice'])),
      orders: asJsonList(j['orders']).map(CommissionOrderLine.fromJson).toList(),
    );
  }

  final String wholesalerId;
  final String name;
  final WholesalerStatus status;
  final bool isFounding;
  final String? phone;
  final String billingName;
  final String? billingEmail;
  final String? billingAddress;
  final String? ssmNo;
  final int orderCount;
  final int gmvSen;
  final int commissionSen;
  final List<({double rate, String source})> rates;
  final CommissionInvoice? invoice;
  final List<CommissionOrderLine> orders;

  /// '1.5%'，几个比例时 '1.5% / 2%'
  String get rateText => rates.isEmpty ? '' : rates.map((r) => formatRate(r.rate)).toSet().join(' / ');
}

/// admin_commission_report()
class CommissionReport {
  const CommissionReport({
    required this.periodMonth,
    this.generatedAt,
    this.invoiceDueDays = 14,
    required this.orderCount,
    required this.gmvSen,
    required this.commissionSen,
    required this.wholesalers,
  });

  factory CommissionReport.fromJson(Json j) => CommissionReport(
    periodMonth: asDateOrNull(j['period_month']) ?? DateTime(2000),
    generatedAt: asDateTimeOrNull(j['generated_at']),
    invoiceDueDays: asInt(j['invoice_due_days'], 14),
    orderCount: asInt(j['order_count']),
    gmvSen: asInt(j['gmv_sen']),
    commissionSen: asInt(j['commission_sen']),
    wholesalers: asJsonList(j['wholesalers']).map(WholesalerCommission.fromJson).toList(),
  );

  /// 那个月的 1 号
  final DateTime periodMonth;
  final DateTime? generatedAt;
  final int invoiceDueDays;
  final int orderCount;
  final int gmvSen;
  final int commissionSen;
  final List<WholesalerCommission> wholesalers;

  /// '2026-11'
  String get periodLabel => '${periodMonth.year}-${periodMonth.month.toString().padLeft(2, '0')}';
}

/// admin_list_audit_logs() 的一行
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    this.actorId,
    this.actorName,
    this.actorPhone,
    required this.action,
    this.tableName,
    this.recordId,
    this.shopId,
    this.shopName,
    this.wholesalerId,
    this.wholesalerName,
    this.before,
    this.after,
  });

  factory AuditEntry.fromJson(Json j) => AuditEntry(
    id: asInt(j['id']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    actorId: asStringOrNull(j['actor_id']),
    actorName: asStringOrNull(j['actor_name']),
    actorPhone: asStringOrNull(j['actor_phone']),
    action: asStringOrNull(j['action']) ?? '',
    tableName: asStringOrNull(j['table_name']),
    recordId: asStringOrNull(j['record_id']),
    shopId: asStringOrNull(j['acting_for_shop_id']),
    shopName: asStringOrNull(j['acting_for_shop_name']),
    wholesalerId: asStringOrNull(j['acting_for_wholesaler_id']),
    wholesalerName: asStringOrNull(j['acting_for_wholesaler_name']),
    before: asJsonOrNull(j['before']),
    after: asJsonOrNull(j['after']),
  );

  final int id;
  final DateTime createdAt;
  final String? actorId;
  final String? actorName;
  final String? actorPhone;

  /// admin_place_order 等（客服函数），或 insert / update / delete（表的逐行记录）
  final String action;
  final String? tableName;
  final String? recordId;
  final String? shopId;
  final String? shopName;
  final String? wholesalerId;
  final String? wholesalerName;
  final Json? before;
  final Json? after;

  bool get isAdminAction => action.startsWith('admin_');

  /// 改了哪几栏（before / after 不一样的）
  List<String> get changedKeys {
    final b = before ?? const {};
    final a = after ?? const {};
    return {...b.keys, ...a.keys}.where((k) => '${b[k]}' != '${a[k]}').toList()..sort();
  }
}

/// 客服改商品时只送改了的栏（admin_save_product 的 p_fields）。新增时送全部
Json productChanges(SellerProduct? before, SellerProduct after) {
  final next = after.toWriteJson()..remove('photo_paths');
  if (before == null) return next;
  final prev = before.toWriteJson();
  return {
    for (final e in next.entries)
      if ('${prev[e.key]}' != '${e.value}') e.key: e.value,
  };
}
