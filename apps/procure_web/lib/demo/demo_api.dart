import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'demo_data.dart';

/// 示范模式 / 自动测试用的公司采购网页：不连服务器，资料来自本机数据库导出的真实样本（demo_data.dart，
/// tool/export_fixtures.sh 产生）。按了按钮会跟着变（注册公司、加分店、邀请成员、换方案……），规则照数据库函数简单做一份，
/// 只放在记忆体里，重新整理网页就回到原样。只有 main_demo.dart 和测试会用到。
class DemoProcureApi extends ProcureApi {
  DemoProcureApi({
    this.role,
    this.noCompany = false,
    this.seller = false,
    this.delay = const Duration(milliseconds: 120),
  }) : super(
         SupabaseClient(
           'http://127.0.0.1:1',
           'demo-key',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       ) {
    _me = _j('procure_my_context') as Json;
    final ctx = _j(role == 'requester' ? 'procure_context_requester' : 'procure_context') as Json;
    final id = asJson(ctx['company'])['id'] as String;
    if (role == 'finance' || role == 'requester') {
      ctx['my_roles'] = [role];
      _me['companies'] = [
        for (final c in asJsonList(_me['companies']))
          {
            ...c,
            'roles': [role],
            if (role == 'requester') 'all_sites': false,
            if (role == 'requester')
              'sites': [
                for (final s in asJsonList(ctx['sites'])) {'id': s['id'], 'name': s['name']},
              ],
          },
      ];
    }
    if (seller) _me['profile'] = {...asJson(_me['profile']), 'role': 'seller'};
    if (noCompany) _me['companies'] = <Json>[];
    _contexts[id] = ctx;
    _members[id] = _j('procure_members') as Json;
    _billing[id] = _j('procure_billing') as Json;
    _inbox = asJsonList(asJson(_j('procure_inbox'))['items']);
    _offers = asJsonList(_j('procure_offers'));
    _zones = asJsonList(_j('procure_zones'));
    _regions = asJsonList(_j('procure_regions'));
  }

  /// null = admin（全部角色）；'finance' / 'requester' = 用这个角色看
  final String? role;

  /// 还没有公司（看注册页）
  final bool noCompany;

  /// 批发商账号（看「不能用」那一页）
  final bool seller;
  final Duration delay;

  bool loggedIn = true;

  /// 示范模式没有真的登录事件，登录成功时叫这个（DemoSession 会设定）
  void Function()? onLoggedIn;

  /// 测试用：create-payment 回传这个错误（例如 PAYMENT_NOT_CONFIGURED）
  String? paymentError;

  /// 叫过哪些（测试检查用）
  final calls = <String>[];

  late final Json _me;
  final _contexts = <String, Json>{};
  final _members = <String, Json>{};
  final _billing = <String, Json>{};
  late List<Json> _inbox;
  late final List<Json> _offers;
  late final List<Json> _zones;
  late final List<Json> _regions;
  final _payments = <String, Json>{};
  int _seq = 0;

  Object? _j(String name) => jsonDecode(demoFixtures[name]!);

  Future<T> _later<T>(String call, T Function() f) async {
    calls.add(call);
    await Future<void>.delayed(delay);
    return f();
  }

  String _id(String kind) =>
      '00000000-0000-4000-e000-${kind.padRight(4, '0').substring(0, 4)}${(++_seq).toString().padLeft(8, '0')}';

  String get _now => DateTime.now().toUtc().toIso8601String();

  Json _ctx(String companyId) => _contexts[companyId] ?? (throw const AppError('COMPANY_NOT_FOUND'));

  Set<String> _myRoles(String companyId) => asStringList(_ctx(companyId)['my_roles']).toSet();

  void _need(String companyId, Set<String> roles) {
    if (!_myRoles(companyId).any(roles.contains)) throw const AppError('NOT_ALLOWED');
  }

  Json _sub(String companyId) => asJson(_ctx(companyId)['subscription']);

  List<Json> _sites(String companyId) => asJsonList(_ctx(companyId)['sites']);

  /// 公司那一行改了 / 分店改了：get_my_context.companies 也跟着改
  void _syncMe(String companyId) {
    final ctx = _ctx(companyId);
    final company = asJson(ctx['company']);
    final mine = {
      'id': companyId,
      'name': company['name'],
      'status': company['status'],
      'roles': ctx['my_roles'],
      'all_sites': ctx['all_sites'],
      'sites': [
        for (final s in _sites(companyId))
          if (s['is_active'] == true) {'id': s['id'], 'name': s['name']},
      ],
      'plan_status': _sub(companyId)['status'],
      'has_access': _sub(companyId)['has_access'],
    };
    final list = asJsonList(_me['companies']);
    final i = list.indexWhere((c) => c['id'] == companyId);
    _me['companies'] = i < 0 ? [...list, mine] : [for (final c in list) c['id'] == companyId ? mine : c];
  }

  void _recount(String companyId) {
    final ctx = _ctx(companyId);
    final m = _members[companyId];
    ctx['counts'] = {
      'sites': _sites(companyId).where((s) => s['is_active'] == true).length,
      'members': m == null ? 0 : asJsonList(m['members']).where((x) => x['is_active'] == true).length,
      'open_invites': m == null ? 0 : asJsonList(m['invites']).where((x) => x['expired'] != true).length,
      'unread_inbox': _inbox
          .where((n) => n['read_at'] == null && asJson(n['payload'])['company_id'] == companyId)
          .length,
    };
  }

  Json _zone(String zoneId) =>
      _zones.firstWhere((z) => z['id'] == zoneId, orElse: () => throw const AppError('INVALID_ZONE'));

  // ---------------- 登录 ----------------

  @override
  Future<void> sendOtp(String phoneE164, {String? locale}) => _later('sendOtp $phoneE164', () {});

  @override
  Future<void> verifyOtp(String phoneE164, String code) => _later('verifyOtp $code', () {
    if (code != '123456') throw const AppError('AUTH');
    loggedIn = true;
    onLoggedIn?.call();
  });

  @override
  Future<void> signOut() => _later('signOut', () => loggedIn = false);

  @override
  Future<MyContext> getMyContext() =>
      _later('getMyContext', () => MyContext.fromJson(jsonDecode(jsonEncode(_me)) as Json));

  @override
  Future<void> setMyLocale(String userId, String locale) async {}

  @override
  Future<List<Zone>> listZones() => _later('listZones', () => _zones.map(Zone.fromJson).toList());

  @override
  Future<List<Region>> listRegions() => _later('listRegions', () => _regions.map(Region.fromJson).toList());

  // ---------------- 注册、公司资料 ----------------

  @override
  Future<String> registerCompany({
    required String name,
    required CompanyType type,
    required String regionId,
    String? ssmNo,
    String? billingEmail,
    NewSite? firstSite,
  }) => _later('registerCompany ${name.trim()}', () {
    if (name.trim().isEmpty) throw const AppError('INVALID_VALUE', detail: 'name');
    final ssm = ssmNo?.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (ssm != null && ssm.isNotEmpty && _contexts.values.any((c) => asJson(c['company'])['ssm_no'] == ssm)) {
      throw const AppError('SSM_ALREADY_REGISTERED');
    }
    final id = _id('comp');
    final region = _regions.firstWhere((r) => r['id'] == regionId, orElse: () => _regions.first);
    final profile = asJson(_me['profile']);
    // 已经有公司的号码拿过试用：再注册的没有试用（跟数据库一样要先付）
    final trial = asJsonList(_me['companies']).isEmpty;
    final plans = asJsonList(asJson(_billing.values.firstOrNull ?? _j('procure_billing'))['plans']);
    _contexts[id] = {
      'company': {
        'id': id,
        'name': name.trim(),
        'company_type': companyTypeCode(type),
        'status': 'active',
        'region_id': region['id'],
        'region_name': region['name'],
        'ssm_no': (ssm == null || ssm.isEmpty) ? null : ssm,
        'billing_email': billingEmail?.trim().isEmpty ?? true ? null : billingEmail!.trim(),
        'phone': profile['phone'],
        'locale': 'en',
        'auto_issue_po': true,
        'reissue_tolerance_bp': 0,
        'benchmark_tolerance_bp': 1000,
        'match_price_tolerance_bp': 0,
        'match_qty_tolerance_bp': 0,
        'auto_receive_days': 14,
        'created_at': _now,
      },
      'my_roles': ['admin', 'approver', 'finance', 'requester'],
      'all_sites': true,
      'acting_as_admin': false,
      'sites': <Json>[],
      'subscription': {
        'id': _id('csub'),
        'status': trial ? 'trialing' : 'lapsed',
        'plan_code': trial ? 'co_trial' : 'co_starter',
        'plan_name': trial
            ? {'zh': '试用', 'en': 'Trial', 'ms': 'Percubaan'}
            : {'zh': '入门版', 'en': 'Starter', 'ms': 'Permulaan'},
        'billing_cycle': 'monthly',
        'locked_price_sen': trial ? 0 : 29000,
        'custom_price': false,
        'trial_ends_at': trial ? DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String() : null,
        'has_access': trial,
        'features': trial
            ? CompanyFeature.all
            : asStringList(plans.firstWhere((p) => p['code'] == 'co_starter', orElse: () => {})['features']),
        'max_sites': 3,
        'max_users': trial ? 10 : 15,
      },
      'pending_approvals': 0,
    };
    _members[id] = {
      'members': [
        {
          'user_id': profile['id'],
          'full_name': profile['full_name'],
          'phone': profile['phone'],
          'roles': ['admin', 'approver', 'finance', 'requester'],
          'all_sites': true,
          'shop_ids': <String>[],
          'is_active': true,
        },
      ],
      'invites': <Json>[],
    };
    _billing[id] = {'company_id': id, 'plans': plans, 'invoices': <Json>[], 'payments': <Json>[]};
    if (!trial) _issueInvoice(id, 'co_starter', 'monthly', 29000);
    if (firstSite != null) _addSite(id, firstSite);
    _recount(id);
    _syncMe(id);
    return id;
  });

  @override
  Future<CompanyContext> getCompanyContext(String companyId) => _later('getCompanyContext', () {
    _recount(companyId);
    return CompanyContext.fromJson(jsonDecode(jsonEncode(_ctx(companyId))) as Json);
  });

  @override
  Future<Company> updateCompany(String companyId, Json fields) => _later('updateCompany', () {
    _need(companyId, {'admin'});
    const allowed = {
      'name',
      'legal_name',
      'ssm_no',
      'tin',
      'sst_no',
      'company_type',
      'region_id',
      'billing_email',
      'billing_address',
      'billing_contact',
      'phone',
      'locale',
      'auto_issue_po',
      'reissue_tolerance_bp',
      'benchmark_tolerance_bp',
      'match_price_tolerance_bp',
      'match_qty_tolerance_bp',
      'auto_receive_days',
    };
    for (final k in fields.keys) {
      if (!allowed.contains(k)) throw AppError('INVALID_FIELD', detail: k);
    }
    if (fields.containsKey('name') && '${fields['name']}'.trim().isEmpty) {
      throw const AppError('INVALID_VALUE', detail: 'name');
    }
    final ctx = _ctx(companyId);
    final c = asJson(ctx['company']);
    for (final e in fields.entries) {
      final v = e.value is String && (e.value as String).trim().isEmpty ? null : e.value;
      c[e.key] = e.key == 'ssm_no' && v is String ? v.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '') : v;
    }
    ctx['company'] = c;
    _syncMe(companyId);
    return Company.fromJson(c);
  });

  // ---------------- 分店 ----------------

  String _addSite(String companyId, NewSite s) {
    if (s.name.trim().isEmpty) throw const AppError('INVALID_VALUE', detail: 'name');
    final zone = _zone(s.zoneId);
    final max = asIntOrNull(_sub(companyId)['max_sites']);
    if (max != null && _sites(companyId).where((x) => x['is_active'] == true).length >= max) {
      throw AppError('PLAN_LIMIT_SITES', detail: '$max');
    }
    final id = _id('site');
    final json = s.toJson();
    _ctx(companyId)['sites'] = [
      ..._sites(companyId),
      {
        'id': id,
        'company_id': companyId,
        'name': s.name.trim(),
        'site_code': json['site_code'],
        'cost_center': json['cost_center'],
        'zone_id': zone['id'],
        'zone_name': zone['name'],
        'address': json['address'],
        'contact_name': json['contact_name'],
        'phone': json['phone'] == null ? null : normalizeMalaysianMobile('${json['phone']}')?.substring(1),
        'is_active': true,
        'created_at': _now,
      },
    ];
    return id;
  }

  String _companyOfSite(String shopId) => _contexts.entries
      .firstWhere(
        (e) => asJsonList(e.value['sites']).any((s) => s['id'] == shopId),
        orElse: () => throw const AppError('SHOP_NOT_FOUND'),
      )
      .key;

  @override
  Future<String> addSite(String companyId, NewSite site) => _later('addSite ${site.name.trim()}', () {
    _need(companyId, {'admin'});
    final id = _addSite(companyId, site);
    _syncMe(companyId);
    return id;
  });

  @override
  Future<CompanySite> updateSite(String shopId, Json fields) => _later('updateSite', () {
    final companyId = _companyOfSite(shopId);
    _need(companyId, {'admin'});
    const allowed = {'name', 'zone_id', 'address', 'contact_name', 'phone', 'site_code', 'cost_center'};
    for (final k in fields.keys) {
      if (!allowed.contains(k)) throw AppError('INVALID_FIELD', detail: k);
    }
    final sites = _sites(companyId);
    final s = sites.firstWhere((x) => x['id'] == shopId);
    for (final e in fields.entries) {
      final v = e.value is String && (e.value as String).trim().isEmpty ? null : e.value;
      s[e.key] = v is String ? v.trim() : v;
    }
    if ((s['name'] ?? '').toString().isEmpty) throw const AppError('INVALID_VALUE', detail: 'name');
    s['zone_name'] = _zone(s['zone_id'] as String)['name'];
    _ctx(companyId)['sites'] = sites;
    _syncMe(companyId);
    return CompanySite.fromJson(s);
  });

  @override
  Future<CompanySite> archiveSite(String shopId) => _later('archiveSite', () {
    final companyId = _companyOfSite(shopId);
    _need(companyId, {'admin'});
    final sites = _sites(companyId);
    final s = sites.firstWhere((x) => x['id'] == shopId)..['is_active'] = false;
    _ctx(companyId)['sites'] = sites;
    _syncMe(companyId);
    return CompanySite.fromJson(s);
  });

  // ---------------- 成员、邀请 ----------------

  Json _m(String companyId) => _members[companyId] ?? (throw const AppError('COMPANY_NOT_FOUND'));

  void _checkLastAdmin(String companyId, List<Json> members) {
    if (!members.any((m) => m['is_active'] == true && asStringList(m['roles']).contains('admin'))) {
      throw const AppError('LAST_COMPANY_ADMIN');
    }
  }

  int _userCount(String companyId, {String? exceptPhone}) {
    final m = _m(companyId);
    return asJsonList(m['members']).where((x) => x['is_active'] == true).length +
        asJsonList(m['invites']).where((x) => x['expired'] != true && x['phone'] != exceptPhone).length;
  }

  @override
  Future<CompanyMembers> listMembers(String companyId) => _later('listMembers', () {
    _need(companyId, {'admin', 'finance'});
    return CompanyMembers.fromJson(_m(companyId));
  });

  @override
  Future<String> inviteMember(
    String companyId, {
    required String phone,
    required Set<CompanyRole> roles,
    bool allSites = true,
    List<String> shopIds = const [],
  }) => _later('inviteMember $phone ${companyRoleCodes(roles).join(',')}', () {
    _need(companyId, {'admin'});
    final p = normalizeMalaysianMobile(phone)?.substring(1);
    if (p == null) throw const AppError('INVALID_PHONE');
    if (roles.isEmpty) throw const AppError('INVALID_VALUE', detail: 'roles');
    final m = _m(companyId);
    final members = asJsonList(m['members']);
    if (members.any((x) => x['phone'] == p && x['is_active'] == true)) throw const AppError('ALREADY_MEMBER');
    final max = asIntOrNull(_sub(companyId)['max_users']);
    if (max != null && _userCount(companyId, exceptPhone: p) + 1 > max) {
      throw AppError('PLAN_LIMIT_USERS', detail: '$max');
    }
    final id = _id('invt');
    final me = asJson(_me['profile']);
    m['invites'] = [
      {
        'id': id,
        'phone': p,
        'roles': companyRoleCodes(roles),
        'all_sites': allSites,
        'shop_ids': allSites ? <String>[] : shopIds,
        'expires_at': DateTime.now().toUtc().add(const Duration(days: 14)).toIso8601String(),
        'expired': false,
        'invited_by_name': me['full_name'],
        'created_at': _now,
      },
      ...asJsonList(m['invites']).where((x) => x['phone'] != p),
    ];
    return id;
  });

  @override
  Future<CompanyMembers> setMember(
    String companyId,
    String userId, {
    required Set<CompanyRole> roles,
    required bool allSites,
    List<String> shopIds = const [],
    bool isActive = true,
  }) => _later('setMember ${companyRoleCodes(roles).join(',')} $isActive', () {
    _need(companyId, {'admin'});
    if (roles.isEmpty) throw const AppError('INVALID_VALUE', detail: 'roles');
    final m = _m(companyId);
    final members = [
      for (final x in asJsonList(m['members']))
        x['user_id'] == userId
            ? {
                ...x,
                'roles': companyRoleCodes(roles),
                'all_sites': allSites,
                'shop_ids': allSites ? <String>[] : shopIds,
                'is_active': isActive,
              }
            : x,
    ];
    _checkLastAdmin(companyId, members);
    m['members'] = members;
    return CompanyMembers.fromJson(m);
  });

  @override
  Future<CompanyMembers> removeMember(String companyId, String userId) => _later('removeMember', () {
    _need(companyId, {'admin'});
    final m = _m(companyId);
    final members = asJsonList(m['members']).where((x) => x['user_id'] != userId).toList();
    _checkLastAdmin(companyId, members);
    m['members'] = members;
    return CompanyMembers.fromJson(m);
  });

  @override
  Future<CompanyMembers> cancelInvite(String inviteId) => _later('cancelInvite', () {
    final e = _members.entries.firstWhere(
      (e) => asJsonList(e.value['invites']).any((i) => i['id'] == inviteId),
      orElse: () => throw const AppError('INVITE_NOT_FOUND'),
    );
    _need(e.key, {'admin'});
    e.value['invites'] = asJsonList(e.value['invites']).where((i) => i['id'] != inviteId).toList();
    return CompanyMembers.fromJson(e.value);
  });

  // ---------------- 方案、账单、付款 ----------------

  Json _b(String companyId) => _billing[companyId] ?? (throw const AppError('COMPANY_NOT_FOUND'));

  Json _billingJson(String companyId) => {..._b(companyId), 'subscription': _sub(companyId)};

  void _issueInvoice(String companyId, String plan, String cycle, int amount) {
    final b = _b(companyId);
    final n = _billing.values.fold<int>(0, (a, x) => a + asJsonList(x['invoices']).length) + 1;
    final names = {for (final p in asJsonList(b['plans'])) p['code']: p['name']};
    b['invoices'] = [
      {
        'id': _id('cinv'),
        'invoice_no': 'CI2612-${n.toString().padLeft(4, '0')}',
        'company_id': companyId,
        'plan_code': plan,
        'plan_name': names[plan],
        'billing_cycle': cycle,
        'amount_sen': amount,
        'sst_sen': 0,
        'total_sen': amount,
        'status': 'issued',
        'due_date': DateTime.now().toIso8601String().substring(0, 10),
        'issued_at': _now,
        'created_at': _now,
      },
      ...asJsonList(b['invoices']),
    ];
  }

  @override
  Future<CompanyBilling> getCompanyBilling(String companyId) => _later('getCompanyBilling', () {
    _need(companyId, {'admin', 'finance'});
    return CompanyBilling.fromJson(_billingJson(companyId));
  });

  @override
  Future<CompanyBilling> changePlan(String companyId, String planCode, BillingCycle cycle) =>
      _later('changePlan $planCode ${cycle.name}', () {
        _need(companyId, {'admin'});
        final plan = asJsonList(_b(companyId)['plans'])
            .firstWhere((p) => p['code'] == planCode, orElse: () => throw AppError('INVALID_VALUE', detail: planCode));
        final price = asIntOrNull(cycle == BillingCycle.annual ? plan['annual_price_sen'] : plan['monthly_price_sen']);
        if (planCode == 'co_enterprise') throw const AppError('NOT_ALLOWED');
        if (price == null) throw AppError('INVALID_VALUE', detail: planCode);
        final sub = _sub(companyId);
        final same = sub['status'] != 'trialing' && sub['plan_code'] == planCode && sub['billing_cycle'] == cycle.name;
        _ctx(companyId)['subscription'] = {
          ...sub,
          'pending_plan_code': same ? null : planCode,
          'pending_billing_cycle': same ? null : cycle.name,
          'pending_price_sen': same ? null : price,
        };
        // 已经开了没付的账单：作废，照新方案重开；停了 → 马上开
        final b = _b(companyId);
        final open = asJsonList(b['invoices']).where((i) => i['status'] == 'issued' || i['status'] == 'overdue');
        final reissue = open.isNotEmpty || sub['status'] == 'lapsed';
        b['invoices'] = [
          for (final i in asJsonList(b['invoices']))
            i['status'] == 'issued' || i['status'] == 'overdue'
                ? {...i, 'status': 'void', 'void_reason': 'PLAN_CHANGED'}
                : i,
        ];
        if (reissue) {
          _issueInvoice(
            companyId,
            same ? sub['plan_code'] as String : planCode,
            cycle.name,
            same ? asInt(sub['locked_price_sen']) : price,
          );
        }
        return CompanyBilling.fromJson(_billingJson(companyId));
      });

  @override
  Future<PaymentCheckout> createPayment(PaymentPurpose purpose, String targetId, {int months = 1}) =>
      _later('createPayment ${paymentPurposeCode(purpose)}', () {
        if (paymentError != null) throw AppError(paymentError!);
        if (purpose != PaymentPurpose.companyPlan) throw const AppError('INVALID_REQUEST');
        final e = _billing.entries.firstWhere(
          (e) => asJsonList(e.value['invoices']).any((i) => i['id'] == targetId),
          orElse: () => throw const AppError('NOT_FOUND'),
        );
        _need(e.key, {'admin', 'finance'});
        final inv = asJsonList(e.value['invoices']).firstWhere((i) => i['id'] == targetId);
        if (inv['status'] != 'issued' && inv['status'] != 'overdue') throw const AppError('NOTHING_DUE');
        final id = _id('pay');
        _payments[id] = {
          'id': id,
          'purpose': 'company_plan',
          'status': 'pending',
          'amount_sen': inv['total_sen'],
          'company_id': e.key,
          'reference_id': targetId,
          'gateway': 'hitpay',
          'created_at': _now,
        };
        return PaymentCheckout(
          paymentId: id,
          checkoutUrl: 'https://securecheckout.sandbox.hit-pay.com/$id',
          amountSen: asInt(inv['total_sen']),
        );
      });

  @override
  Future<PaymentInfo> getPayment(String paymentId) => _later(
    'getPayment',
    () => PaymentInfo.fromJson(_payments[paymentId] ?? (throw const AppError('PAYMENT_NOT_FOUND'))),
  );

  // ---------------- 收件箱 ----------------

  @override
  Future<InboxPage> listInbox({int limit = 30, DateTime? before}) => _later(
    'listInbox',
    () => InboxPage.fromJson({
      'items': _inbox.take(limit).toList(),
      'unread_count': _inbox.where((n) => n['read_at'] == null).length,
    }),
  );

  @override
  Future<int> markInboxRead([List<String>? ids]) => _later('markInboxRead ${ids?.length ?? 'all'}', () {
    var n = 0;
    _inbox = [
      for (final i in _inbox)
        if (i['read_at'] == null && (ids == null || ids.contains(i['id'])))
          (() {
            n++;
            return {...i, 'read_at': _now};
          })()
        else
          i,
    ];
    return n;
  });

  // ---------------- 比价 ----------------

  @override
  Future<List<Offer>> getOffers(
    String shopId, {
    String? catalogItemId,
    String? wholesalerId,
    String? categoryId,
    String? search,
  }) => _later('getOffers', () {
    final companyId = _companyOfSite(shopId);
    final access = _sub(companyId)['has_access'] == true;
    final q = search?.trim().toLowerCase() ?? '';
    return [
      for (final o in _offers)
        if (q.isEmpty || '${o['product_name']} ${o['wholesaler_name']}'.toLowerCase().contains(q))
          Offer.fromJson(
            access ? o : {...o, 'price_visible': false, 'price_sen': null, 'price_per_base_unit_sen': null},
          ),
    ];
  });
}
