// 第七步：收费。对应 supabase/migrations/20261130000100_billing.sql 的 get_buyer_billing、get_seller_billing、
// get_commission_invoice、get_payment、admin_list_payments，和 Edge Function create-payment 的回传。
import '../json.dart';
import 'account.dart';
import 'admin.dart';

/// 付什么（跟数据库 payment_purpose 一样）
enum PaymentPurpose { subscription, listingFee, commissionInvoice }

PaymentPurpose paymentPurposeFrom(Object? v) => switch (v?.toString()) {
  'listing_fee' => PaymentPurpose.listingFee,
  'commission_invoice' => PaymentPurpose.commissionInvoice,
  _ => PaymentPurpose.subscription,
};

String paymentPurposeCode(PaymentPurpose p) => switch (p) {
  PaymentPurpose.subscription => 'subscription',
  PaymentPurpose.listingFee => 'listing_fee',
  PaymentPurpose.commissionInvoice => 'commission_invoice',
};

enum PaymentStatus { pending, paid, failed, refunded }

PaymentStatus paymentStatusFrom(Object? v) =>
    PaymentStatus.values.firstWhere((e) => e.name == v?.toString(), orElse: () => PaymentStatus.pending);

/// 一张付款单（get_payment、付款记录）
class PaymentInfo {
  const PaymentInfo({
    required this.id,
    required this.purpose,
    required this.status,
    required this.amountSen,
    this.months,
    this.method,
    this.gateway,
    this.description,
    this.checkoutUrl,
    this.paidAt,
    this.periodEnd,
    this.createdAt,
    this.failureReason,
    this.reviewReason,
    this.payerName,
    this.gatewayRef,
    this.invoiceNo,
  });

  factory PaymentInfo.fromJson(Json j) => PaymentInfo(
    id: asStringOrNull(j['id']) ?? '',
    purpose: paymentPurposeFrom(j['purpose']),
    status: paymentStatusFrom(j['status']),
    amountSen: asInt(j['amount_sen']),
    months: asIntOrNull(j['months']),
    method: j['method'] == null ? null : paymentMethodFrom(j['method']),
    gateway: asStringOrNull(j['gateway']),
    description: asStringOrNull(j['description']),
    checkoutUrl: asStringOrNull(j['checkout_url']),
    paidAt: asDateTimeOrNull(j['paid_at']),
    periodEnd: asDateTimeOrNull(j['period_end']),
    createdAt: asDateTimeOrNull(j['created_at']),
    failureReason: asStringOrNull(j['failure_reason']),
    reviewReason: asStringOrNull(j['review_reason']),
    payerName: asStringOrNull(j['payer_name']),
    gatewayRef: asStringOrNull(j['gateway_ref']),
    invoiceNo: asStringOrNull(j['invoice_no']),
  );

  final String id;
  final PaymentPurpose purpose;
  final PaymentStatus status;
  final int amountSen;
  final int? months;
  final PaymentMethod? method;

  /// hitpay / manual（客服手动记的）
  final String? gateway;
  final String? description;

  /// 还在等付款、付款页还有效时才有
  final String? checkoutUrl;
  final DateTime? paidAt;

  /// 月费：付了之后订阅到什么时候
  final DateTime? periodEnd;
  final DateTime? createdAt;
  final String? failureReason;

  /// 收到钱但要客服处理：AMOUNT_MISMATCH、INVOICE_PAID、FOUNDING_QUOTA_FULL……
  final String? reviewReason;

  // 客服后台的付款列表才有
  final String? payerName;
  final String? gatewayRef;
  final String? invoiceNo;

  bool get isPaid => status == PaymentStatus.paid;
}

/// create-payment 回传：用浏览器打开 checkoutUrl
class PaymentCheckout {
  const PaymentCheckout({
    required this.paymentId,
    required this.checkoutUrl,
    required this.amountSen,
    this.expiresAt,
    this.reuse = false,
  });

  factory PaymentCheckout.fromJson(Json j) => PaymentCheckout(
    paymentId: asStringOrNull(j['payment_id']) ?? '',
    checkoutUrl: asStringOrNull(j['checkout_url']) ?? '',
    amountSen: asInt(j['amount_sen']),
    expiresAt: asDateTimeOrNull(j['expires_at']),
    reuse: asBool(j['reuse']),
  );

  final String paymentId;
  final String checkoutUrl;
  final int amountSen;
  final DateTime? expiresAt;

  /// 拿回之前开的同一张（还没付）
  final bool reuse;
}

/// 买家「我的订阅」（get_buyer_billing）：get_subscription_status 加上续费资料
class BuyerBilling {
  const BuyerBilling({
    required this.status,
    this.accessUntil,
    this.daysLeft,
    required this.renewPriceSen,
    required this.priceLocked,
    this.monthOptions = const [1, 3, 6, 12],
    this.graceDays = 7,
    this.payments = const [],
  });

  factory BuyerBilling.fromJson(Json j) => BuyerBilling(
    status: SubscriptionInfo.fromJson(j),
    accessUntil: asDateTimeOrNull(j['access_until']),
    daysLeft: asIntOrNull(j['days_left']),
    renewPriceSen: asInt(j['renew_price_sen']),
    priceLocked: asBool(j['price_locked']),
    monthOptions: j['month_options'] is List
        ? (j['month_options'] as List).map((e) => asInt(e)).where((m) => m > 0).toList()
        : const [1, 3, 6, 12],
    graceDays: asInt(j['grace_days'], 7),
    payments: asJsonList(j['payments']).map(PaymentInfo.fromJson).toList(),
  );

  final SubscriptionInfo status;

  /// 试用结束 / 这期结束 / 宽限期最后一天（看状态）；没有订阅或已停 → null
  final DateTime? accessUntil;
  final int? daysLeft;

  /// 续费一个月多少：没停 = 锁定的价钱；已停 / 从来没订 = 现在的价钱
  final int renewPriceSen;

  /// 价钱是锁定的（一直续费就永远是这个价）
  final bool priceLocked;
  final List<int> monthOptions;
  final int graceDays;

  /// 付过的（新到旧，最多 12 笔）
  final List<PaymentInfo> payments;

  SubscriptionState get state => status.state;
}

/// 创始会员上架费
class ListingFeeInfo {
  const ListingFeeInfo({
    required this.isFounding,
    this.foundingNo,
    required this.feeSen,
    this.paidAt,
    required this.seatsLeft,
    required this.canPay,
  });

  factory ListingFeeInfo.fromJson(Json j) => ListingFeeInfo(
    isFounding: asBool(j['is_founding']),
    foundingNo: asIntOrNull(j['founding_no']),
    feeSen: asInt(j['fee_sen']),
    paidAt: asDateTimeOrNull(j['paid_at']),
    seatsLeft: asInt(j['seats_left']),
    canPay: asBool(j['can_pay']),
  );

  final bool isFounding;
  final int? foundingNo;
  final int feeSen;
  final DateTime? paidAt;

  /// 创始名额还剩几个
  final int seatsLeft;

  /// 现在可以付（还没付；已经是创始会员或者还有名额）
  final bool canPay;

  bool get isPaid => paidAt != null;
}

/// 批发商的「收费」页（get_seller_billing）
class SellerBilling {
  const SellerBilling({
    required this.wholesalerId,
    required this.listingFee,
    required this.commissionRate,
    required this.rateSource,
    required this.monthOrderCount,
    required this.monthGmvSen,
    required this.monthCommissionSen,
    this.periodMonth,
    required this.outstandingSen,
    this.invoices = const [],
  });

  factory SellerBilling.fromJson(Json j) {
    final c = asJson(j['commission']);
    final m = asJson(j['this_month']);
    return SellerBilling(
      wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
      listingFee: ListingFeeInfo.fromJson(asJson(j['listing_fee'])),
      commissionRate: asDoubleOrNull(c['rate']) ?? 0,
      rateSource: asStringOrNull(c['rate_source']) ?? 'industry',
      monthOrderCount: asInt(m['order_count']),
      monthGmvSen: asInt(m['gmv_sen']),
      monthCommissionSen: asInt(m['commission_sen']),
      periodMonth: asDateOrNull(m['period_month']),
      outstandingSen: asInt(j['outstanding_sen']),
      invoices: asJsonList(j['invoices']).map(CommissionInvoice.fromJson).toList(),
    );
  }

  final String wholesalerId;
  final ListingFeeInfo listingFee;
  final double commissionRate;

  /// override / founding / industry
  final String rateSource;

  /// 这个月到现在（已送达的）
  final int monthOrderCount;
  final int monthGmvSen;
  final int monthCommissionSen;
  final DateTime? periodMonth;

  /// 已发出 / 逾期还没付的总数
  final int outstandingSen;

  /// 不含草稿，新到旧
  final List<CommissionInvoice> invoices;
}

/// 一张佣金账单的明细（get_commission_invoice）：印 PDF 用
class InvoiceDetail {
  const InvoiceDetail({
    required this.invoice,
    required this.wholesalerName,
    required this.billingName,
    this.billingEmail,
    this.billingAddress,
    this.ssmNo,
    this.lines = const [],
    this.payments = const [],
  });

  factory InvoiceDetail.fromJson(Json j) {
    final b = asJson(j['billing']);
    return InvoiceDetail(
      invoice: CommissionInvoice.fromJson(j),
      wholesalerName: asStringOrNull(j['wholesaler_name']) ?? '',
      billingName: asStringOrNull(b['name']) ?? asStringOrNull(j['wholesaler_name']) ?? '',
      billingEmail: asStringOrNull(b['email']),
      billingAddress: asStringOrNull(b['address']),
      ssmNo: asStringOrNull(b['ssm_no']),
      lines: asJsonList(j['lines']).map(CommissionOrderLine.fromJson).toList(),
      payments: asJsonList(j['payments']).map(PaymentInfo.fromJson).toList(),
    );
  }

  final CommissionInvoice invoice;
  final String wholesalerName;
  final String billingName;
  final String? billingEmail;
  final String? billingAddress;
  final String? ssmNo;
  final List<CommissionOrderLine> lines;
  final List<PaymentInfo> payments;

  /// 可以付：已发出 / 逾期、金额 > 0
  bool get canPay => (invoice.status == 'issued' || invoice.status == 'overdue') && invoice.commissionSen > 0;
}
