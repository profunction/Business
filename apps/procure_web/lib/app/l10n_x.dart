import 'package:flutter/widgets.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../l10n/app_localizations.dart';

extension L10nX on BuildContext {
  L10n get l10n => L10n.of(this);
}

/// 服务器的代码（角色、方案、状态、错误……）→ 三语文字
extension L10nText on L10n {
  String get lang => localeName.split('_').first;

  String error(Object e) {
    final code = e is AppError ? e.code : 'UNKNOWN';
    return switch (code) {
      'NETWORK' => errNetwork,
      'AUTH' => errAuth,
      'NOT_ALLOWED' || 'NOT_LOGGED_IN' => errNotAllowed,
      'ROLE_MISMATCH' => errRoleMismatch,
      'COMPANY_NOT_FOUND' => errCompanyNotFound,
      'COMPANY_SUSPENDED' => errCompanySuspended,
      'COMPANY_PLAN_INACTIVE' => errPlanInactive,
      'PLAN_FEATURE_REQUIRED' => errPlanFeature,
      'PLAN_LIMIT_SITES' => errPlanLimitSites(e is AppError ? e.detail ?? '' : ''),
      'PLAN_LIMIT_USERS' => errPlanLimitUsers(e is AppError ? e.detail ?? '' : ''),
      'LAST_COMPANY_ADMIN' => errLastAdmin,
      'SITE_HAS_OPEN_DOCUMENTS' => errSiteOpenDocuments,
      'INVITE_NOT_FOUND' || 'MEMBER_NOT_FOUND' => errNotFound,
      'ALREADY_MEMBER' => errAlreadyMember,
      'INVALID_PHONE' => phoneInvalid,
      'SSM_ALREADY_REGISTERED' => errSsmRegistered,
      'INVALID_ZONE' => errInvalidZone,
      'INVALID_FIELD' || 'INVALID_VALUE' => errInvalidValue,
      'SHOP_NOT_FOUND' => errNotFound,
      'NOTHING_DUE' => errNothingDue,
      'PAYMENT_NOT_CONFIGURED' => errPaymentNotConfigured,
      'GATEWAY_UNAVAILABLE' || 'GATEWAY_AUTH_FAILED' || 'GATEWAY_REJECTED' || 'GATEWAY_BAD_RESPONSE' => errGateway,
      'TOO_MANY_PAYMENTS' => errTooManyPayments,
      'USE_REQUISITION' => errUseRequisition,
      _ => errUnknown(code),
    };
  }

  String role(CompanyRole r) => switch (r) {
    CompanyRole.admin => roleAdmin,
    CompanyRole.approver => roleApprover,
    CompanyRole.finance => roleFinance,
    CompanyRole.requester => roleRequester,
  };

  String roleHelp(CompanyRole r) => switch (r) {
    CompanyRole.admin => roleAdminHelp,
    CompanyRole.approver => roleApproverHelp,
    CompanyRole.finance => roleFinanceHelp,
    CompanyRole.requester => roleRequesterHelp,
  };

  /// 角色按固定顺序、用顿号接起来
  String roles(Iterable<CompanyRole> rs) =>
      CompanyRole.values.where(rs.contains).map(role).join(lang == 'zh' ? '、' : ', ');

  String companyType(CompanyType t) => switch (t) {
    CompanyType.corporate => typeCorporate,
    CompanyType.factory => typeFactory,
    CompanyType.hotel => typeHotel,
    CompanyType.restaurantChain => typeRestaurantChain,
    CompanyType.glc => typeGlc,
    CompanyType.other => typeOther,
  };

  String subscription(SubscriptionState s) => switch (s) {
    SubscriptionState.trialing => subTrialing,
    SubscriptionState.active => subActive,
    SubscriptionState.pastDue => subPastDue,
    SubscriptionState.lapsed => subLapsed,
    SubscriptionState.none => subNone,
  };

  String cycle(BillingCycle c) => switch (c) {
    BillingCycle.monthly => cycleMonthly,
    BillingCycle.annual => cycleAnnual,
  };

  /// 一期：「/ 月」「/ 年」
  String perCycle(BillingCycle c) => switch (c) {
    BillingCycle.monthly => perMonth,
    BillingCycle.annual => perYear,
  };

  String planName(String code) => switch (code) {
    'co_trial' => planTrial,
    'co_starter' => planStarter,
    'co_pro' => planPro,
    'co_enterprise' => planEnterprise,
    _ => code,
  };

  String feature(String code) => switch (code) {
    CompanyFeature.requisitions => featRequisitions,
    CompanyFeature.multiTier => featMultiTier,
    CompanyFeature.budgets => featBudgets,
    CompanyFeature.rfq => featRfq,
    CompanyFeature.reverseAuction => featReverseAuction,
    CompanyFeature.aiInsights => featAiInsights,
    CompanyFeature.aiSpend => featAiSpend,
    CompanyFeature.statements => featStatements,
    _ => code,
  };

  String invoiceStatus(String s) => switch (s) {
    'issued' => invIssued,
    'overdue' => invOverdue,
    'paid' => invPaid,
    'void' => invVoid,
    _ => s,
  };

  String paymentStatus(PaymentStatus s) => switch (s) {
    PaymentStatus.pending => payPending,
    PaymentStatus.paid => payPaid,
    PaymentStatus.failed => payFailed,
    PaymentStatus.refunded => payRefunded,
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

  /// 收件箱一条的标题和内容（payload 是服务器排通知时放的）
  ({String title, String body}) inboxText(InboxItem i) {
    final p = i.payload;
    String s(String k) => asStringOrNull(p[k]) ?? '';
    String money(String k) => formatRm(asInt(p[k]));
    return switch (i.eventType) {
      'company_invoice_issued' => (
        title: inboxInvoiceIssued(s('invoice_no')),
        body: inboxInvoiceIssuedBody(money('amount_sen'), fmtDay(asDateOrNull(p['due_date']))),
      ),
      'company_invoice_overdue' => (
        title: inboxInvoiceOverdue(s('invoice_no')),
        body: inboxInvoiceOverdueBody(money('amount_sen'), fmtDateTime(asDateTimeOrNull(p['grace_until']))),
      ),
      'company_trial_ending' => (
        title: inboxTrialEnding,
        body: asBool(p['plan_chosen'])
            ? inboxTrialEndingChosen(fmtDateTime(asDateTimeOrNull(p['trial_ends_at'])))
            : inboxTrialEndingBody(fmtDateTime(asDateTimeOrNull(p['trial_ends_at']))),
      ),
      'payment_received' => (title: inboxPaid(money('amount_sen')), body: inboxPaidBody(s('invoice_no'))),
      _ => (title: inboxGeneric, body: s('message')),
    };
  }
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
