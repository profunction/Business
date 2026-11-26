import 'package:flutter/widgets.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../l10n/app_localizations.dart';

extension L10nX on BuildContext {
  L10n get l10n => L10n.of(this);
}

/// 服务器的代码（状态、单位、错误……）→ 三语文字
extension L10nText on L10n {
  String get lang => localeName.split('_').first;

  String error(Object e) {
    final code = e is AppError ? e.code : 'UNKNOWN';
    return switch (code) {
      'NETWORK' => errNetwork,
      'AUTH' => errAuth,
      'NOT_ALLOWED' || 'NOT_LOGGED_IN' => errNotAllowed,
      'PRICE_CHANGED' => errPriceChanged,
      'CART_HAS_PROBLEMS' => errCartHasProblems,
      'CART_EMPTY' => errCartEmpty,
      'INVALID_TRANSITION' => errInvalidTransition,
      'INVALID_RATE' => errInvalidRate,
      'INVALID_DAYS' => errInvalidDays,
      'INVALID_MONTHS' => errInvalidMonths,
      'INVALID_AMOUNT' || 'INVALID_VALUE' || 'INVALID_QTY' => errInvalidAmount,
      'DUPLICATE_PAYMENT_REFERENCE' => errDuplicateReference,
      'INVALID_SUBSCRIPTION_STATE' => errSubscriptionState,
      'SUBSCRIPTION_ALREADY_OPEN' => errSubscriptionOpen,
      'INVALID_INVOICE_STATE' => errInvoiceState,
      'FOUNDING_QUOTA_FULL' => errFoundingFull,
      'FOUNDING_FULL' => errFoundingFull,
      'LISTING_FEE_ALREADY_PAID' || 'NOTHING_DUE' => errNothingDue,
      'PAYMENT_NOT_CONFIGURED' => errPaymentNotConfigured,
      'GATEWAY_UNAVAILABLE' || 'GATEWAY_AUTH_FAILED' || 'GATEWAY_REJECTED' || 'GATEWAY_BAD_RESPONSE' => errGateway,
      'TOO_MANY_PAYMENTS' => errTooManyPayments,
      'INVALID_PRODUCT' || 'INVALID_FIELD' => errInvalidProduct,
      'INVALID_NOTE' => errInvalidNote,
      'NO_PRICING_PLAN' => errNoPricingPlan,
      'COMPANY_NOT_FOUND' => errCompanyNotFound,
      // WhatsApp 订单（第六步）
      'DRAFT_NOT_PENDING' => waDone,
      'DRAFT_EMPTY' => waEmptyDraft,
      'DRAFT_NOT_FOUND' => waNotFound,
      _ => errUnknown(code),
    };
  }

  String status(OrderStatus s) => switch (s) {
    OrderStatus.pending => statusPending,
    OrderStatus.confirmed => statusConfirmed,
    OrderStatus.outOfStock => statusOutOfStock,
    OrderStatus.delivering => statusDelivering,
    OrderStatus.delivered => statusDelivered,
    OrderStatus.cancelled => statusCancelled,
  };

  String source(OrderSource s) => switch (s) {
    OrderSource.app => sourceApp,
    OrderSource.voice => sourceVoice,
    OrderSource.whatsapp => sourceWhatsapp,
    OrderSource.admin => sourceAdmin,
    OrderSource.reorder => sourceReorder,
  };

  String unit(SellUnit u) => switch (u) {
    SellUnit.carton => unitCarton,
    SellUnit.pack => unitPack,
    SellUnit.bag => unitBag,
    SellUnit.roll => unitRoll,
    SellUnit.bundle => unitBundle,
    SellUnit.box => unitBox,
    SellUnit.piece || SellUnit.unknown => unitPiece,
    SellUnit.dozen => unitDozen,
    SellUnit.kg => unitKg,
  };

  String stock(StockStatus s) => switch (s) {
    StockStatus.inStock => stockIn,
    StockStatus.lowStock => stockLow,
    StockStatus.outOfStock => stockOut,
  };

  String productState(ProductStatus s) => switch (s) {
    ProductStatus.active => productActive,
    ProductStatus.draft => productDraft,
    ProductStatus.archived => productArchived,
  };

  String subscription(SubscriptionState s) => switch (s) {
    SubscriptionState.trialing => subTrialing,
    SubscriptionState.active => subActive,
    SubscriptionState.pastDue => subPastDue,
    SubscriptionState.lapsed => subLapsed,
    SubscriptionState.none => subNone,
  };

  String wholesalerStatus(WholesalerStatus s) => switch (s) {
    WholesalerStatus.pending => wsStatusPending,
    WholesalerStatus.active => wsStatusActive,
    WholesalerStatus.suspended => wsStatusSuspended,
  };

  String rateSource(String s) => switch (s) {
    'override' => wsRateOverride,
    'founding' => wsRateFounding,
    _ => wsRateIndustry,
  };

  String invoiceStatus(String s) => switch (s) {
    'draft' => invoiceDraft,
    'issued' => invoiceIssued,
    'paid' => invoicePaid,
    'overdue' => invoiceOverdue,
    'void' => invoiceVoid,
    _ => s,
  };

  String method(PaymentMethod m) => switch (m) {
    PaymentMethod.fpx => methodFpx,
    PaymentMethod.duitnow => methodDuitnow,
    PaymentMethod.ewallet => methodEwallet,
    PaymentMethod.card => methodCard,
    PaymentMethod.other => methodOther,
  };

  String paymentPurpose(PaymentPurpose p) => switch (p) {
    PaymentPurpose.subscription => purposeSubscription,
    PaymentPurpose.listingFee => purposeListingFee,
    PaymentPurpose.commissionInvoice => purposeCommission,
    PaymentPurpose.companyPlan => purposeCompanyPlan,
  };

  String companyStatus(CompanyStatus s) => switch (s) {
    CompanyStatus.active => coStatusActive,
    CompanyStatus.suspended => coStatusSuspended,
  };

  String companyType(CompanyType t) => switch (t) {
    CompanyType.corporate => coTypeCorporate,
    CompanyType.factory => coTypeFactory,
    CompanyType.hotel => coTypeHotel,
    CompanyType.restaurantChain => coTypeRestaurantChain,
    CompanyType.glc => coTypeGlc,
    CompanyType.other => coTypeOther,
  };

  String companyRole(CompanyRole r) => switch (r) {
    CompanyRole.admin => coRoleAdmin,
    CompanyRole.approver => coRoleApprover,
    CompanyRole.finance => coRoleFinance,
    CompanyRole.requester => coRoleRequester,
  };

  String cycle(BillingCycle c) => switch (c) {
    BillingCycle.monthly => coCycleMonthly,
    BillingCycle.annual => coCycleAnnual,
  };

  String planName(String code) => switch (code) {
    'co_trial' => coPlanTrial,
    'co_starter' => coPlanStarter,
    'co_pro' => coPlanPro,
    'co_enterprise' => coPlanEnterprise,
    _ => code,
  };

  String paymentStatus(PaymentStatus s) => switch (s) {
    PaymentStatus.pending => payStatusPending,
    PaymentStatus.paid => payStatusPaid,
    PaymentStatus.failed => payStatusFailed,
    PaymentStatus.refunded => payStatusRefunded,
  };

  String? cartProblem(CartProblem? p, {int minQty = 1}) => switch (p) {
    null || CartProblem.belowMinOrder => null,
    CartProblem.productUnavailable || CartProblem.unknown => problemProductUnavailable,
    CartProblem.notDelivering => problemNotDelivering,
    CartProblem.wholesalerLocked => problemWholesalerLocked,
    CartProblem.outOfStock => problemOutOfStock,
    CartProblem.belowMinQty => problemBelowMinQty(minQty),
  };

  /// 操作记录的动作：客服函数（admin_*）或表的逐行记录（insert / update / delete）
  String auditAction(String action) => switch (action) {
    'admin_place_order' => auditActPlaceOrder,
    'admin_set_cart_item' => auditActSetCartItem,
    'admin_clear_cart' => auditActClearCart,
    'admin_set_order_status' => auditActSetOrderStatus,
    'admin_confirm_order' => auditActConfirmOrder,
    'admin_log_followup' => auditActLogFollowup,
    'admin_create_product' => auditActCreateProduct,
    'admin_update_product' => auditActUpdateProduct,
    'admin_set_wholesaler_status' => auditActWholesalerStatus,
    'admin_set_commission_rate' => auditActCommissionRate,
    'admin_set_wholesaler_founding' => auditActWholesalerFounding,
    'admin_set_whatsapp_opt_in' => auditActWhatsappOptIn,
    'admin_extend_trial' => auditActExtendTrial,
    'admin_mark_subscription_paid' => auditActMarkPaid,
    'admin_cancel_subscription' => auditActCancelSubscription,
    'admin_set_subscription_founding' => auditActSubscriptionFounding,
    'admin_generate_invoices' => auditActGenerateInvoices,
    'admin_issue_invoice' => auditActIssueInvoice,
    'admin_mark_invoice_paid' => auditActInvoicePaid,
    'admin_save_order_draft' => auditActSaveDraft,
    'admin_submit_order_draft' => auditActSubmitDraft,
    'admin_reject_order_draft' => auditActRejectDraft,
    'admin_set_company_status' => auditActCompanyStatus,
    'admin_set_company_plan' => auditActCompanyPlan,
    'admin_extend_company_trial' => auditActCompanyTrial,
    'admin_issue_company_invoice' => auditActCompanyInvoice,
    'admin_mark_company_invoice_paid' => auditActCompanyInvoicePaid,
    'register_company' ||
    'update_company' ||
    'add_company_site' ||
    'update_company_site' ||
    'archive_company_site' ||
    'invite_company_member' ||
    'set_company_member' ||
    'remove_company_member' ||
    'cancel_company_invite' ||
    'change_company_plan' => auditActCompanyEdit,
    'insert' => auditActInsert,
    'update' => auditActUpdate,
    'delete' => auditActDelete,
    _ => action,
  };
}

/// 服务器的时间是 UTC；画面一律显示马来西亚时间（UTC+8，没有夏令时）
DateTime myt(DateTime t) => t.toUtc().add(const Duration(hours: 8));

String _two(int n) => n.toString().padLeft(2, '0');

/// '2026-11-26'
String fmtDate(DateTime? d) => d == null ? '' : '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// '2026-11-26 14:05'（马来西亚时间）
String fmtDateTime(DateTime? t) {
  if (t == null) return '';
  final m = myt(t);
  return '${fmtDate(m)} ${_two(m.hour)}:${_two(m.minute)}';
}

/// 日期（服务器传的是马来西亚日期，不用转时区）
String fmtDay(DateTime? d) => fmtDate(d);

/// '2026-11'
String fmtMonth(DateTime m) => '${m.year}-${_two(m.month)}';
