// 第八步第 1 期：公司账号（本机数据库真实返回的 JSON：apps/procure_web/tool/export_fixtures.sh）、送出去的请求
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

SupabaseClient mockClient(List<(String, Object?)> sent, Object? Function(String path) reply) => SupabaseClient(
  'http://sb.test',
  'test-key',
  httpClient: MockClient((req) async {
    sent.add((req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
    return http.Response(
      jsonEncode(reply(req.url.path)),
      200,
      headers: {'content-type': 'application/json'},
      request: req,
    );
  }),
);

void main() {
  test('get_my_context：公司（角色、能管的分店、方案状态）；公司分店不在 shops', () {
    final c = MyContext.fromJson(asJson(fixture('procure_my_context')));
    expect(c.shops, isEmpty);
    expect(c.companies, hasLength(1));
    final co = c.companies.single;
    expect(co.name, 'Grand Hotel Johor Bahru');
    expect(co.roles, {CompanyRole.admin, CompanyRole.approver, CompanyRole.finance, CompanyRole.requester});
    expect(co.sites.map((s) => s.name), ['Grand Hotel 中央厨房', 'Grand Hotel 宴会厅']);
    expect(co.planStatus, SubscriptionState.trialing);
    expect(co.hasAccess, isTrue);
    // 旧的 get_my_context（没有 companies）照样读得到
    expect(MyContext.fromJson(asJson(fixture('my_context'))).companies, isEmpty);
  });

  test('公司首页：资料、我的角色、分店、试用 = Pro 的功能', () {
    final c = CompanyContext.fromJson(asJson(fixture('procure_context')));
    expect(c.company.legalName, 'Grand Hotel JB Sdn Bhd');
    expect(c.company.type, CompanyType.hotel);
    expect(c.company.autoReceiveDays, 14);
    expect(c.company.regionName.zh, '新山');
    expect(c.isAdmin, isTrue);
    expect(c.canSeeBilling, isTrue);
    expect(c.sites.map((s) => s.siteCode), ['CK', 'BQ']);
    expect(c.sites.first.zoneName.en, startsWith('Tebrau'));
    final s = c.subscription!;
    expect(s.isTrial, isTrue);
    expect(s.planCode, 'co_trial');
    expect(s.pendingPlanCode, 'co_pro');
    expect(s.hasFeature(CompanyFeature.reverseAuction), isTrue);
    expect(s.maxSites, 3);
    expect(s.accessUntil, s.trialEndsAt);
    expect([c.siteCount, c.memberCount, c.openInvites, c.unreadInbox], [2, 3, 1, 1]);
  });

  test('requester：只看到自己的分店，看不到方案', () {
    final c = CompanyContext.fromJson(asJson(fixture('procure_context_requester')));
    expect(c.myRoles, {CompanyRole.requester});
    expect(c.allSites, isFalse);
    expect(c.sites.map((s) => s.siteCode), ['BQ']);
    expect(c.isAdmin, isFalse);
    expect(c.canSeeBilling, isFalse);
  });

  test('成员 + 邀请', () {
    final m = CompanyMembers.fromJson(asJson(fixture('procure_members')));
    expect(m.members.map((x) => x.fullName), ['林美玲', 'Rajesh Kumar', 'Aisyah']);
    final req = m.members.last;
    expect(req.roles, {CompanyRole.requester});
    expect(req.allSites, isFalse);
    expect(req.shopIds, hasLength(1));
    expect(m.invites.single.phone, '60123334444');
    expect(m.invites.single.expired, isFalse);
  });

  test('方案和账单：可以选的方案、第一期账单（Pro，选的那天锁定）', () {
    final b = CompanyBilling.fromJson(asJson(fixture('procure_billing')));
    expect(b.plans.map((p) => p.code), ['co_starter', 'co_pro', 'co_enterprise']);
    expect(b.plan('co_pro')!.priceFor(BillingCycle.annual), 790000);
    expect(b.plan('co_enterprise')!.selfServe, isFalse);
    expect(b.plan('co_starter')!.selfServe, isTrue);
    final i = b.openInvoices.single;
    expect(i.invoiceNo, startsWith('CI'));
    expect(i.planCode, 'co_pro');
    expect(i.totalSen, 79000);
    expect(i.canPay, isTrue);
    expect(i.dueDate, isNotNull);
    expect(b.payments, isEmpty);
  });

  test('收件箱', () {
    final p = InboxPage.fromJson(asJson(fixture('procure_inbox')));
    expect(p.unreadCount, 1);
    expect(p.items.map((x) => x.eventType), containsAll(['company_invoice_issued', 'company_trial_ending']));
    expect(p.items.where((x) => !x.isRead).single.eventType, 'company_invoice_issued');
    expect(p.items.first.companyId, isNotNull);
  });

  test('客服：公司列表、详情', () {
    final list = asJsonList(fixture('admin_companies')).map(AdminCompany.fromJson).toList();
    expect(list.single.siteCount, 2);
    expect(list.single.memberCount, 3);
    expect(list.single.openInvoiceSen, 79000);
    expect(list.single.subscription!.isTrial, isTrue);
    final d = AdminCompanyDetail.fromJson(asJson(fixture('admin_company_detail')));
    expect(d.company.tin, 'C2581234560');
    expect(d.sites, hasLength(2));
    expect(d.members.members, hasLength(3));
    expect(d.members.invites, hasLength(1));
    expect(d.invoices.single.status, 'issued');
  });

  test('付款：company_plan 的代码', () {
    expect(paymentPurposeFrom('company_plan'), PaymentPurpose.companyPlan);
    expect(paymentPurposeCode(PaymentPurpose.companyPlan), 'company_plan');
    expect(companyTypeCode(CompanyType.restaurantChain), 'restaurant_chain');
    expect(companyTypeFrom('restaurant_chain'), CompanyType.restaurantChain);
    expect(companyRoleCodes({CompanyRole.requester, CompanyRole.admin}), ['admin', 'requester']);
  });

  test('ProcureApi：送出去的参数', () async {
    final sent = <(String, Object?)>[];
    final api = ProcureApi(mockClient(sent, (path) => path.endsWith('register_company') ? 'co-1' : 'inv-1'));
    expect(
      await api.registerCompany(
        name: ' Grand Hotel ',
        type: CompanyType.restaurantChain,
        regionId: 'r1',
        ssmNo: ' ',
        firstSite: const NewSite(name: '厨房', zoneId: 'z1', phone: ' 0123 '),
      ),
      'co-1',
    );
    expect(sent.last.$1, '/rest/v1/rpc/register_company');
    expect(sent.last.$2, {
      'p_name': 'Grand Hotel',
      'p_company_type': 'restaurant_chain',
      'p_region_id': 'r1',
      'p_ssm_no': null,
      'p_billing_email': null,
      'p_first_site': {'name': '厨房', 'zone_id': 'z1', 'phone': '0123'},
    });
    await api.inviteMember('co-1', phone: '0123', roles: {CompanyRole.finance}, allSites: true, shopIds: ['s1']);
    expect(sent.last.$1, '/rest/v1/rpc/invite_company_member');
    expect(sent.last.$2, {
      'p_company_id': 'co-1',
      'p_phone': '0123',
      'p_roles': ['finance'],
      'p_all_sites': true,
      'p_shop_ids': <String>[],
    });
  });

  test('ProcureApi：方案、收件箱', () async {
    final sent = <(String, Object?)>[];
    final api = ProcureApi(
      mockClient(sent, (path) {
        if (path.endsWith('change_company_plan')) return fixture('procure_billing');
        if (path.endsWith('list_my_inbox')) return fixture('procure_inbox');
        return 2;
      }),
    );
    final b = await api.changePlan('co-1', 'co_pro', BillingCycle.annual);
    expect(b.plans, isNotEmpty);
    expect(sent.last.$2, {'p_company_id': 'co-1', 'p_plan_code': 'co_pro', 'p_billing_cycle': 'annual'});
    final before = DateTime.utc(2026, 12, 1, 8);
    expect((await api.listInbox(limit: 10, before: before)).unreadCount, 1);
    expect(sent.last.$2, {'p_limit': 10, 'p_before': '2026-12-01T08:00:00.000Z'});
    expect(await api.markInboxRead(['n1']), 2);
    expect(sent.last.$2, {
      'p_ids': ['n1'],
    });
  });
}
