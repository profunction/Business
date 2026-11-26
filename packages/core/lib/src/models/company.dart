// 第八步第 1 期：公司账号、分店、成员、公司方案、收件箱。
// 对应 supabase/migrations/20261202000200_company_accounts.sql 的 get_company_context、list_company_members、
// get_company_billing、list_my_inbox、admin_list_companies、admin_get_company 和 get_my_context.companies。
import '../json.dart';
import 'account.dart';
import 'billing.dart';
import 'common.dart';

/// 公司角色（一个人可以有几个）
enum CompanyRole { admin, approver, finance, requester }

CompanyRole? companyRoleFrom(Object? v) {
  for (final r in CompanyRole.values) {
    if (r.name == v?.toString()) return r;
  }
  return null;
}

Set<CompanyRole> companyRolesFrom(Object? v) =>
    v is List ? v.map(companyRoleFrom).whereType<CompanyRole>().toSet() : const <CompanyRole>{};

/// 送给服务器的顺序固定（跟数据库的 enum 顺序一样）
List<String> companyRoleCodes(Iterable<CompanyRole> roles) =>
    CompanyRole.values.where(roles.contains).map((r) => r.name).toList();

enum CompanyType { corporate, factory, hotel, restaurantChain, glc, other }

CompanyType companyTypeFrom(Object? v) => switch (v?.toString()) {
  'corporate' => CompanyType.corporate,
  'factory' => CompanyType.factory,
  'hotel' => CompanyType.hotel,
  'restaurant_chain' => CompanyType.restaurantChain,
  'glc' => CompanyType.glc,
  _ => CompanyType.other,
};

String companyTypeCode(CompanyType t) => switch (t) {
  CompanyType.restaurantChain => 'restaurant_chain',
  _ => t.name,
};

enum CompanyStatus { active, suspended }

CompanyStatus companyStatusFrom(Object? v) =>
    v?.toString() == 'suspended' ? CompanyStatus.suspended : CompanyStatus.active;

enum BillingCycle { monthly, annual }

BillingCycle billingCycleFrom(Object? v) => v?.toString() == 'annual' ? BillingCycle.annual : BillingCycle.monthly;

/// 方案功能代码（company_plans.features）
abstract final class CompanyFeature {
  static const requisitions = 'requisitions';
  static const multiTier = 'multi_tier';
  static const budgets = 'budgets';
  static const rfq = 'rfq';
  static const reverseAuction = 'reverse_auction';
  static const aiInsights = 'ai_insights';
  static const aiSpend = 'ai_spend';
  static const statements = 'statements';
  static const all = [requisitions, multiTier, budgets, rfq, reverseAuction, aiInsights, aiSpend, statements];
}

/// get_my_context().companies 的一家
class MyCompany {
  const MyCompany({
    required this.id,
    required this.name,
    required this.status,
    required this.roles,
    required this.allSites,
    required this.sites,
    this.planStatus,
    required this.hasAccess,
  });

  factory MyCompany.fromJson(Json j) => MyCompany(
    id: asStringOrNull(j['id']) ?? '',
    name: asStringOrNull(j['name']) ?? '',
    status: companyStatusFrom(j['status']),
    roles: companyRolesFrom(j['roles']),
    allSites: asBool(j['all_sites'], true),
    sites: asJsonList(j['sites'])
        .map((s) => (id: asStringOrNull(s['id']) ?? '', name: asStringOrNull(s['name']) ?? ''))
        .toList(),
    planStatus: j['plan_status'] == null ? null : subscriptionStateFrom(j['plan_status']),
    hasAccess: asBool(j['has_access']),
  );

  final String id;
  final String name;
  final CompanyStatus status;
  final Set<CompanyRole> roles;
  final bool allSites;

  /// 我能管的分店（还开着的）
  final List<({String id, String name})> sites;
  final SubscriptionState? planStatus;
  final bool hasAccess;

  bool has(CompanyRole r) => roles.contains(r);
}

/// 一个分店 / 工地（shops 里 company_id 不是空的那一行）
class CompanySite {
  const CompanySite({
    required this.id,
    required this.name,
    this.siteCode,
    this.costCenter,
    required this.zoneId,
    required this.zoneName,
    this.address,
    this.contactName,
    this.phone,
    required this.isActive,
  });

  factory CompanySite.fromJson(Json j) => CompanySite(
    id: asStringOrNull(j['id']) ?? '',
    name: asStringOrNull(j['name']) ?? '',
    siteCode: asStringOrNull(j['site_code']),
    costCenter: asStringOrNull(j['cost_center']),
    zoneId: asStringOrNull(j['zone_id']) ?? '',
    zoneName: LocalizedName.fromJson(j['zone_name']),
    address: asStringOrNull(j['address']),
    contactName: asStringOrNull(j['contact_name']),
    phone: asStringOrNull(j['phone']),
    isActive: asBool(j['is_active'], true),
  );

  final String id;
  final String name;
  final String? siteCode;
  final String? costCenter;
  final String zoneId;
  final LocalizedName zoneName;
  final String? address;
  final String? contactName;
  final String? phone;
  final bool isActive;
}

/// 公司资料和设定（companies 那一行）
class Company {
  const Company({
    required this.id,
    required this.name,
    this.legalName,
    this.ssmNo,
    this.tin,
    this.sstNo,
    required this.type,
    required this.status,
    this.statusNote,
    required this.regionId,
    required this.regionName,
    this.billingEmail,
    this.billingAddress,
    this.billingContact,
    this.phone,
    required this.locale,
    required this.autoIssuePo,
    required this.reissueToleranceBp,
    required this.benchmarkToleranceBp,
    required this.matchPriceToleranceBp,
    required this.matchQtyToleranceBp,
    this.autoReceiveDays,
    this.createdAt,
  });

  factory Company.fromJson(Json j) => Company(
    id: asStringOrNull(j['id']) ?? '',
    name: asStringOrNull(j['name']) ?? '',
    legalName: asStringOrNull(j['legal_name']),
    ssmNo: asStringOrNull(j['ssm_no']),
    tin: asStringOrNull(j['tin']),
    sstNo: asStringOrNull(j['sst_no']),
    type: companyTypeFrom(j['company_type']),
    status: companyStatusFrom(j['status']),
    statusNote: asStringOrNull(j['status_note']),
    regionId: asStringOrNull(j['region_id']) ?? '',
    regionName: LocalizedName.fromJson(j['region_name']),
    billingEmail: asStringOrNull(j['billing_email']),
    billingAddress: asStringOrNull(j['billing_address']),
    billingContact: asStringOrNull(j['billing_contact']),
    phone: asStringOrNull(j['phone']),
    locale: asStringOrNull(j['locale']) ?? 'en',
    autoIssuePo: asBool(j['auto_issue_po'], true),
    reissueToleranceBp: asInt(j['reissue_tolerance_bp']),
    benchmarkToleranceBp: asInt(j['benchmark_tolerance_bp'], 1000),
    matchPriceToleranceBp: asInt(j['match_price_tolerance_bp']),
    matchQtyToleranceBp: asInt(j['match_qty_tolerance_bp']),
    autoReceiveDays: asIntOrNull(j['auto_receive_days']),
    createdAt: asDateTimeOrNull(j['created_at']),
  );

  final String id;
  final String name;
  final String? legalName;
  final String? ssmNo;
  final String? tin;
  final String? sstNo;
  final CompanyType type;
  final CompanyStatus status;
  final String? statusNote;
  final String regionId;
  final LocalizedName regionName;
  final String? billingEmail;
  final String? billingAddress;
  final String? billingContact;
  final String? phone;
  final String locale;
  final bool autoIssuePo;
  final int reissueToleranceBp;
  final int benchmarkToleranceBp;
  final int matchPriceToleranceBp;
  final int matchQtyToleranceBp;

  /// 送达后几天没开收货单当成全收；null = 不自动
  final int? autoReceiveDays;
  final DateTime? createdAt;
}

/// 公司的订阅（现在这一条）
class CompanySubscription {
  const CompanySubscription({
    required this.id,
    required this.state,
    required this.planCode,
    required this.planName,
    required this.cycle,
    required this.lockedPriceSen,
    required this.customPrice,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.graceUntil,
    this.lapsedAt,
    this.pendingPlanCode,
    this.pendingCycle,
    this.pendingPriceSen,
    required this.hasAccess,
    required this.features,
    this.maxSites,
    this.maxUsers,
  });

  factory CompanySubscription.fromJson(Json j) => CompanySubscription(
    id: asStringOrNull(j['id']) ?? '',
    state: subscriptionStateFrom(j['status']),
    planCode: asStringOrNull(j['plan_code']) ?? '',
    planName: LocalizedName.fromJson(j['plan_name']),
    cycle: billingCycleFrom(j['billing_cycle']),
    lockedPriceSen: asInt(j['locked_price_sen']),
    customPrice: asBool(j['custom_price']),
    trialEndsAt: asDateTimeOrNull(j['trial_ends_at']),
    currentPeriodEnd: asDateTimeOrNull(j['current_period_end']),
    graceUntil: asDateTimeOrNull(j['grace_until']),
    lapsedAt: asDateTimeOrNull(j['lapsed_at']),
    pendingPlanCode: asStringOrNull(j['pending_plan_code']),
    pendingCycle: j['pending_billing_cycle'] == null ? null : billingCycleFrom(j['pending_billing_cycle']),
    pendingPriceSen: asIntOrNull(j['pending_price_sen']),
    hasAccess: asBool(j['has_access']),
    features: asStringList(j['features']).toSet(),
    maxSites: asIntOrNull(j['max_sites']),
    maxUsers: asIntOrNull(j['max_users']),
  );

  final String id;
  final SubscriptionState state;

  /// co_trial / co_starter / co_pro / co_enterprise
  final String planCode;
  final LocalizedName planName;
  final BillingCycle cycle;

  /// 一期（月 / 年）的锁定价钱；试用中 0
  final int lockedPriceSen;
  final bool customPrice;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? graceUntil;
  final DateTime? lapsedAt;

  /// 公司自己换的方案（下一期生效）
  final String? pendingPlanCode;
  final BillingCycle? pendingCycle;
  final int? pendingPriceSen;

  /// 现在能不能用（试用中、有效、宽限期内，而且公司没停权）
  final bool hasAccess;
  final Set<String> features;
  final int? maxSites;
  final int? maxUsers;

  bool get isTrial => state == SubscriptionState.trialing;

  /// 试用结束 / 这期结束 / 宽限期最后一天
  DateTime? get accessUntil => switch (state) {
    SubscriptionState.trialing => trialEndsAt,
    SubscriptionState.active => currentPeriodEnd,
    SubscriptionState.pastDue => graceUntil,
    _ => null,
  };

  bool hasFeature(String code) => hasAccess && features.contains(code);
}

/// get_company_context：公司首页要的
class CompanyContext {
  const CompanyContext({
    required this.company,
    required this.myRoles,
    required this.allSites,
    required this.actingAsAdmin,
    required this.sites,
    this.subscription,
    required this.pendingApprovals,
    required this.siteCount,
    required this.memberCount,
    required this.openInvites,
    required this.unreadInbox,
  });

  factory CompanyContext.fromJson(Json j) {
    final c = asJson(j['counts']);
    final sub = asJsonOrNull(j['subscription']);
    return CompanyContext(
      company: Company.fromJson(asJson(j['company'])),
      myRoles: companyRolesFrom(j['my_roles']),
      allSites: asBool(j['all_sites']),
      actingAsAdmin: asBool(j['acting_as_admin']),
      sites: asJsonList(j['sites']).map(CompanySite.fromJson).toList(),
      subscription: sub == null ? null : CompanySubscription.fromJson(sub),
      pendingApprovals: asInt(j['pending_approvals']),
      siteCount: asInt(c['sites']),
      memberCount: asInt(c['members']),
      openInvites: asInt(c['open_invites']),
      unreadInbox: asInt(c['unread_inbox']),
    );
  }

  final Company company;
  final Set<CompanyRole> myRoles;
  final bool allSites;

  /// 客服在看（不是成员）：什么都可以做
  final bool actingAsAdmin;

  /// 我能管的分店（admin、finance：全部，包括封存的）
  final List<CompanySite> sites;
  final CompanySubscription? subscription;
  final int pendingApprovals;
  final int siteCount;
  final int memberCount;
  final int openInvites;
  final int unreadInbox;

  bool has(CompanyRole r) => actingAsAdmin || myRoles.contains(r);
  bool get isAdmin => has(CompanyRole.admin);

  /// 看得到方案和账单
  bool get canSeeBilling => has(CompanyRole.admin) || has(CompanyRole.finance);

  List<CompanySite> get activeSites => sites.where((s) => s.isActive).toList();
}

class CompanyMember {
  const CompanyMember({
    required this.userId,
    this.fullName,
    this.phone,
    required this.roles,
    required this.allSites,
    required this.shopIds,
    this.title,
    required this.isActive,
  });

  factory CompanyMember.fromJson(Json j) => CompanyMember(
    userId: asStringOrNull(j['user_id']) ?? '',
    fullName: asStringOrNull(j['full_name']),
    phone: asStringOrNull(j['phone']),
    roles: companyRolesFrom(j['roles']),
    allSites: asBool(j['all_sites'], true),
    shopIds: asStringList(j['shop_ids']),
    title: asStringOrNull(j['title']),
    isActive: asBool(j['is_active'], true),
  );

  final String userId;
  final String? fullName;
  final String? phone;
  final Set<CompanyRole> roles;
  final bool allSites;
  final List<String> shopIds;
  final String? title;
  final bool isActive;
}

class CompanyInvite {
  const CompanyInvite({
    required this.id,
    required this.phone,
    required this.roles,
    required this.allSites,
    required this.shopIds,
    this.expiresAt,
    required this.expired,
    this.invitedByName,
  });

  factory CompanyInvite.fromJson(Json j) => CompanyInvite(
    id: asStringOrNull(j['id']) ?? '',
    phone: asStringOrNull(j['phone']) ?? '',
    roles: companyRolesFrom(j['roles']),
    allSites: asBool(j['all_sites'], true),
    shopIds: asStringList(j['shop_ids']),
    expiresAt: asDateTimeOrNull(j['expires_at']),
    expired: asBool(j['expired']),
    invitedByName: asStringOrNull(j['invited_by_name']),
  );

  final String id;
  final String phone;
  final Set<CompanyRole> roles;
  final bool allSites;
  final List<String> shopIds;
  final DateTime? expiresAt;
  final bool expired;
  final String? invitedByName;
}

/// list_company_members：成员 + 没接受的邀请
class CompanyMembers {
  const CompanyMembers({required this.members, required this.invites});

  factory CompanyMembers.fromJson(Json j) => CompanyMembers(
    members: asJsonList(j['members']).map(CompanyMember.fromJson).toList(),
    invites: asJsonList(j['invites']).map(CompanyInvite.fromJson).toList(),
  );

  final List<CompanyMember> members;
  final List<CompanyInvite> invites;
}

class CompanyPlan {
  const CompanyPlan({
    required this.code,
    required this.name,
    this.monthlyPriceSen,
    this.annualPriceSen,
    this.maxSites,
    this.maxUsers,
    required this.features,
  });

  factory CompanyPlan.fromJson(Json j) => CompanyPlan(
    code: asStringOrNull(j['code']) ?? '',
    name: LocalizedName.fromJson(j['name']),
    monthlyPriceSen: asIntOrNull(j['monthly_price_sen']),
    annualPriceSen: asIntOrNull(j['annual_price_sen']),
    maxSites: asIntOrNull(j['max_sites']),
    maxUsers: asIntOrNull(j['max_users']),
    features: asStringList(j['features']).toSet(),
  );

  final String code;
  final LocalizedName name;

  /// 企业方案没有价钱（客服报价）
  final int? monthlyPriceSen;
  final int? annualPriceSen;
  final int? maxSites;
  final int? maxUsers;
  final Set<String> features;

  int? priceFor(BillingCycle c) => c == BillingCycle.annual ? annualPriceSen : monthlyPriceSen;

  /// 公司自己可以选（企业方案只能客服设）
  bool get selfServe => code != 'co_enterprise' && monthlyPriceSen != null;
}

class CompanyInvoice {
  const CompanyInvoice({
    required this.id,
    required this.invoiceNo,
    required this.planCode,
    required this.planName,
    required this.cycle,
    this.periodStart,
    this.periodEnd,
    required this.amountSen,
    required this.sstSen,
    required this.totalSen,
    required this.status,
    this.dueDate,
    this.issuedAt,
    this.paidAt,
    this.voidReason,
  });

  factory CompanyInvoice.fromJson(Json j) => CompanyInvoice(
    id: asStringOrNull(j['id']) ?? '',
    invoiceNo: asStringOrNull(j['invoice_no']) ?? '',
    planCode: asStringOrNull(j['plan_code']) ?? '',
    planName: LocalizedName.fromJson(j['plan_name']),
    cycle: billingCycleFrom(j['billing_cycle']),
    periodStart: asDateTimeOrNull(j['period_start']),
    periodEnd: asDateTimeOrNull(j['period_end']),
    amountSen: asInt(j['amount_sen']),
    sstSen: asInt(j['sst_sen']),
    totalSen: asInt(j['total_sen'], asInt(j['amount_sen']) + asInt(j['sst_sen'])),
    status: asStringOrNull(j['status']) ?? 'issued',
    dueDate: asDateOrNull(j['due_date']),
    issuedAt: asDateTimeOrNull(j['issued_at']),
    paidAt: asDateTimeOrNull(j['paid_at']),
    voidReason: asStringOrNull(j['void_reason']),
  );

  final String id;
  final String invoiceNo;
  final String planCode;
  final LocalizedName planName;
  final BillingCycle cycle;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int amountSen;
  final int sstSen;
  final int totalSen;

  /// issued / overdue / paid / void
  final String status;
  final DateTime? dueDate;
  final DateTime? issuedAt;
  final DateTime? paidAt;
  final String? voidReason;

  bool get canPay => status == 'issued' || status == 'overdue';
}

/// get_company_billing：订阅、可以选的方案、账单、付款
class CompanyBilling {
  const CompanyBilling({
    required this.companyId,
    this.subscription,
    required this.plans,
    required this.invoices,
    required this.payments,
  });

  factory CompanyBilling.fromJson(Json j) {
    final sub = asJsonOrNull(j['subscription']);
    return CompanyBilling(
      companyId: asStringOrNull(j['company_id']) ?? '',
      subscription: sub == null ? null : CompanySubscription.fromJson(sub),
      plans: asJsonList(j['plans']).map(CompanyPlan.fromJson).toList(),
      invoices: asJsonList(j['invoices']).map(CompanyInvoice.fromJson).toList(),
      payments: asJsonList(j['payments']).map(PaymentInfo.fromJson).toList(),
    );
  }

  final String companyId;
  final CompanySubscription? subscription;
  final List<CompanyPlan> plans;

  /// 新到旧
  final List<CompanyInvoice> invoices;
  final List<PaymentInfo> payments;

  List<CompanyInvoice> get openInvoices => invoices.where((i) => i.canPay).toList();

  CompanyPlan? plan(String code) => plans.where((p) => p.code == code).firstOrNull;
}

/// 收件箱的一条（notifications.user_id = 我）
class InboxItem {
  const InboxItem({
    required this.id,
    required this.eventType,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  factory InboxItem.fromJson(Json j) => InboxItem(
    id: asStringOrNull(j['id']) ?? '',
    eventType: asStringOrNull(j['event_type']) ?? '',
    payload: asJson(j['payload']),
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    readAt: asDateTimeOrNull(j['read_at']),
  );

  final String id;
  final String eventType;
  final Json payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
  String? get companyId => asStringOrNull(payload['company_id']);
}

class InboxPage {
  const InboxPage({required this.items, required this.unreadCount});

  factory InboxPage.fromJson(Json j) =>
      InboxPage(items: asJsonList(j['items']).map(InboxItem.fromJson).toList(), unreadCount: asInt(j['unread_count']));

  final List<InboxItem> items;
  final int unreadCount;
}

/// 客服后台的公司列表一行（admin_list_companies）
class AdminCompany {
  const AdminCompany({
    required this.id,
    required this.name,
    this.legalName,
    this.ssmNo,
    required this.type,
    required this.status,
    this.statusNote,
    this.phone,
    this.billingEmail,
    required this.siteCount,
    required this.memberCount,
    this.subscription,
    required this.openInvoiceSen,
    this.createdAt,
  });

  factory AdminCompany.fromJson(Json j) {
    final sub = asJsonOrNull(j['subscription']);
    return AdminCompany(
      id: asStringOrNull(j['id']) ?? '',
      name: asStringOrNull(j['name']) ?? '',
      legalName: asStringOrNull(j['legal_name']),
      ssmNo: asStringOrNull(j['ssm_no']),
      type: companyTypeFrom(j['company_type']),
      status: companyStatusFrom(j['status']),
      statusNote: asStringOrNull(j['status_note']),
      phone: asStringOrNull(j['phone']),
      billingEmail: asStringOrNull(j['billing_email']),
      siteCount: asInt(j['site_count']),
      memberCount: asInt(j['member_count']),
      subscription: sub == null ? null : CompanySubscription.fromJson(sub),
      openInvoiceSen: asInt(j['open_invoice_sen']),
      createdAt: asDateTimeOrNull(j['created_at']),
    );
  }

  final String id;
  final String name;
  final String? legalName;
  final String? ssmNo;
  final CompanyType type;
  final CompanyStatus status;
  final String? statusNote;
  final String? phone;
  final String? billingEmail;
  final int siteCount;
  final int memberCount;
  final CompanySubscription? subscription;

  /// 还没付的账单加起来
  final int openInvoiceSen;
  final DateTime? createdAt;
}

/// 客服看一家公司的全部（admin_get_company）
class AdminCompanyDetail {
  const AdminCompanyDetail({
    required this.summary,
    required this.company,
    required this.sites,
    required this.members,
    required this.invoices,
    required this.payments,
  });

  factory AdminCompanyDetail.fromJson(Json j) => AdminCompanyDetail(
    summary: AdminCompany.fromJson(j),
    company: Company.fromJson(asJson(j['company'])),
    sites: asJsonList(j['sites']).map(CompanySite.fromJson).toList(),
    members: CompanyMembers.fromJson(j),
    invoices: asJsonList(j['invoices']).map(CompanyInvoice.fromJson).toList(),
    payments: asJsonList(j['payments']).map(PaymentInfo.fromJson).toList(),
  );

  final AdminCompany summary;
  final Company company;
  final List<CompanySite> sites;
  final CompanyMembers members;
  final List<CompanyInvoice> invoices;
  final List<PaymentInfo> payments;
}

/// 注册公司时顺便建的第一个分店
class NewSite {
  const NewSite({
    required this.name,
    required this.zoneId,
    this.address,
    this.contactName,
    this.phone,
    this.siteCode,
    this.costCenter,
  });

  final String name;
  final String zoneId;
  final String? address;
  final String? contactName;
  final String? phone;
  final String? siteCode;
  final String? costCenter;

  Json toJson() => {
    'name': name.trim(),
    'zone_id': zoneId,
    if (_t(address) != null) 'address': _t(address),
    if (_t(contactName) != null) 'contact_name': _t(contactName),
    if (_t(phone) != null) 'phone': _t(phone),
    if (_t(siteCode) != null) 'site_code': _t(siteCode),
    if (_t(costCenter) != null) 'cost_center': _t(costCenter),
  };

  static String? _t(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}

class Region {
  const Region({required this.id, required this.code, required this.name});

  factory Region.fromJson(Json j) => Region(
    id: asStringOrNull(j['id']) ?? '',
    code: asStringOrNull(j['code']) ?? '',
    name: LocalizedName.fromJson(j['name']),
  );

  final String id;
  final String code;
  final LocalizedName name;
}
