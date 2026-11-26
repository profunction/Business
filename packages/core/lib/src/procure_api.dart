part of 'api.dart';

/// 公司采购网页（apps/procure_web）用的服务器调用（第八步第 1 期：公司、分店、成员、方案和付款、收件箱）。
/// 函数在 supabase/migrations/20261202000200_company_accounts.sql，里面再检查角色（_require_company_role）。
/// 登录、送货区、比价（getOffers，分店的 id 当 shopId）、付款（createPayment / getPayment）跟手机 App 一样用 [WholesaleApi] 的。
class ProcureApi extends WholesaleApi {
  ProcureApi(super.client);

  static String? _t(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  // ---------------- 注册、公司资料 ----------------

  Future<List<Region>> listRegions() => _call(() async {
    final rows = await client.from('regions').select('id, code, name').eq('is_active', true).order('code');
    return asJsonList(rows).map(Region.fromJson).toList();
  });

  /// 回传新公司的 id。号码 / SSM 拿过试用 → 没有试用（要先付第一期）
  Future<String> registerCompany({
    required String name,
    required CompanyType type,
    required String regionId,
    String? ssmNo,
    String? billingEmail,
    NewSite? firstSite,
  }) => _call(
    () async => (await client.rpc<dynamic>(
      'register_company',
      params: {
        'p_name': name.trim(),
        'p_company_type': companyTypeCode(type),
        'p_region_id': regionId,
        'p_ssm_no': _t(ssmNo),
        'p_billing_email': _t(billingEmail),
        'p_first_site': firstSite?.toJson(),
      },
    )) as String,
  );

  Future<CompanyContext> getCompanyContext(String companyId) async =>
      CompanyContext.fromJson(await _rpcJson('get_company_context', {'p_company_id': companyId}));

  /// fields 只能有资料和设定栏位（name、legal_name、ssm_no、tin、sst_no、company_type、billing_*、phone、locale、
  /// auto_issue_po、*_tolerance_bp、auto_receive_days），其他 → INVALID_FIELD
  Future<Company> updateCompany(String companyId, Json fields) async =>
      Company.fromJson(await _rpcJson('update_company', {'p_company_id': companyId, 'p_fields': fields}));

  // ---------------- 分店 ----------------

  Future<String> addSite(String companyId, NewSite site) => _call(
    () async => (await client.rpc<dynamic>(
      'add_company_site',
      params: {
        'p_company_id': companyId,
        'p_name': site.name.trim(),
        'p_zone_id': site.zoneId,
        'p_address': _t(site.address),
        'p_contact_name': _t(site.contactName),
        'p_phone': _t(site.phone),
        'p_site_code': _t(site.siteCode),
        'p_cost_center': _t(site.costCenter),
      },
    )) as String,
  );

  /// fields：name、zone_id、address、contact_name、phone、site_code、cost_center
  Future<CompanySite> updateSite(String shopId, Json fields) async =>
      CompanySite.fromJson(await _rpcJson('update_company_site', {'p_shop_id': shopId, 'p_fields': fields}));

  /// 还有没完成的单 → SITE_HAS_OPEN_DOCUMENTS
  Future<CompanySite> archiveSite(String shopId) async =>
      CompanySite.fromJson(await _rpcJson('archive_company_site', {'p_shop_id': shopId}));

  // ---------------- 成员、邀请 ----------------

  Future<CompanyMembers> listMembers(String companyId) async =>
      CompanyMembers.fromJson(await _rpcJson('list_company_members', {'p_company_id': companyId}));

  /// 号码已经有账号就直接加；没有就留邀请（登录后自动接上）。回传邀请 id
  Future<String> inviteMember(
    String companyId, {
    required String phone,
    required Set<CompanyRole> roles,
    bool allSites = true,
    List<String> shopIds = const [],
  }) => _call(
    () async => (await client.rpc<dynamic>(
      'invite_company_member',
      params: {
        'p_company_id': companyId,
        'p_phone': phone,
        'p_roles': companyRoleCodes(roles),
        'p_all_sites': allSites,
        'p_shop_ids': allSites ? <String>[] : shopIds,
      },
    )) as String,
  );

  Future<CompanyMembers> setMember(
    String companyId,
    String userId, {
    required Set<CompanyRole> roles,
    required bool allSites,
    List<String> shopIds = const [],
    bool isActive = true,
  }) async => CompanyMembers.fromJson(
    await _rpcJson('set_company_member', {
      'p_company_id': companyId,
      'p_user_id': userId,
      'p_roles': companyRoleCodes(roles),
      'p_all_sites': allSites,
      'p_shop_ids': allSites ? <String>[] : shopIds,
      'p_is_active': isActive,
    }),
  );

  Future<CompanyMembers> removeMember(String companyId, String userId) async => CompanyMembers.fromJson(
    await _rpcJson('remove_company_member', {'p_company_id': companyId, 'p_user_id': userId}),
  );

  Future<CompanyMembers> cancelInvite(String inviteId) async =>
      CompanyMembers.fromJson(await _rpcJson('cancel_company_invite', {'p_invite_id': inviteId}));

  // ---------------- 方案、账单 ----------------

  Future<CompanyBilling> getCompanyBilling(String companyId) async =>
      CompanyBilling.fromJson(await _rpcJson('get_company_billing', {'p_company_id': companyId}));

  /// 下一期生效（价钱照今天锁定）；订阅停了 → 马上开账单
  Future<CompanyBilling> changePlan(String companyId, String planCode, BillingCycle cycle) async =>
      CompanyBilling.fromJson(
        await _rpcJson('change_company_plan', {
          'p_company_id': companyId,
          'p_plan_code': planCode,
          'p_billing_cycle': cycle.name,
        }),
      );

  /// 付一张公司方案账单：开 HitPay 付款页（只有网页有这个按钮；手机 App 不卖公司方案）
  Future<PaymentCheckout> payCompanyInvoice(String invoiceId) => createPayment(PaymentPurpose.companyPlan, invoiceId);

  // ---------------- 收件箱 ----------------

  /// 新到旧；before = 上一页最后一条的时间
  Future<InboxPage> listInbox({int limit = 30, DateTime? before}) async => InboxPage.fromJson(
    await _rpcJson('list_my_inbox', {'p_limit': limit, 'p_before': before?.toUtc().toIso8601String()}),
  );

  /// ids 空 = 全部标已读。回传改了几条
  Future<int> markInboxRead([List<String>? ids]) =>
      _call(() async => asInt(await client.rpc<dynamic>('mark_inbox_read', params: {'p_ids': ids})));
}
