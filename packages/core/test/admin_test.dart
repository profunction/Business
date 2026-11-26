// 客服后台：用本机数据库真实返回的 JSON（test/fixtures/admin_*.json，apps/admin_web/tool/export_fixtures.sh 导出）
// 测试解析；送出去的 RPC 参数用 http 的 MockClient 看；佣金报表 CSV。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

/// 记下每一个 RPC（函数名 + 参数），回传 reply
({AdminApi api, List<(String, Map<String, dynamic>)> calls}) recordingApi(Object? Function(String fn) reply) {
  final calls = <(String, Map<String, dynamic>)>[];
  final api = AdminApi(
    SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((req) async {
        final fn = req.url.pathSegments.last;
        calls.add((
          fn,
          req.body.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(req.body) as Map),
        ));
        final r = reply(fn);
        if (r is http.Response) {
          return http.Response(r.body, r.statusCode, headers: {'content-type': 'application/json'}, request: req);
        }
        return http.Response(jsonEncode(r), 200, headers: {'content-type': 'application/json'}, request: req);
      }),
    ),
  );
  return (api: api, calls: calls);
}

void main() {
  group('解析（真实样本）', () {
    test('admin_dashboard', () {
      final d = AdminDashboard.fromJson(asJson(fixture('admin_dashboard')));
      expect(d.alertMinutes, 30);
      expect(d.unconfirmedOrders, 1);
      expect(d.pendingWholesalers, 1);
      expect(d.trialing, 1);
      expect(d.lapsed, 1);
      expect(d.monthCommissionSen, 567);
      expect(d.month, DateTime(2026, 11));
    });

    test('get_my_context：客服', () {
      final c = MyContext.fromJson(asJson(fixture('admin_my_context')));
      expect(c.profile.role, UserRole.admin);
    });

    test('admin_list_shops', () {
      final shops = asJsonList(fixture('admin_shops')).map(AdminShop.fromJson).toList();
      final siti = shops.firstWhere((s) => s.name == 'Kedai Runcit Siti');
      expect(siti.hasFullAccess, isFalse);
      expect(siti.subscriptionState, SubscriptionState.lapsed);
      expect(siti.zoneName.of('zh'), '士古来');
      expect(shops.firstWhere((s) => s.name == '阿明茶餐室').cartCount, 1);
    });

    test('admin_list_wholesalers：待审核排最前面，佣金比例', () {
      final list = asJsonList(fixture('admin_wholesalers')).map(AdminWholesaler.fromJson).toList();
      expect(list.first.status, WholesalerStatus.pending);
      final c = list.firstWhere((w) => w.name.contains('Skudai'));
      expect(c.commissionRate, 0.025);
      expect(c.commissionRateSource, 'override');
      expect(c.industryDefaultRate, 0.02);
      final a = list.firstWhere((w) => w.name.contains('A'));
      expect(a.isFounding, isTrue);
      expect(a.foundingNo, isNotNull);
      expect(a.commissionRateSource, 'founding');
      expect(formatRate(a.commissionRate), '1%');
    });

    test('admin_list_orders：来源、跟进', () {
      final page = AdminOrderPage.fromJson(asJson(fixture('admin_orders')));
      expect(page.total, page.orders.length);
      final waiting = page.orders.firstWhere((o) => o.shopName == 'Kedai Runcit Siti');
      expect(waiting.status, OrderStatus.pending);
      expect(waiting.pendingMinutes, greaterThanOrEqualTo(45));
      expect(waiting.lastFollowupNote, contains('3 点前'));
      expect(page.orders.where((o) => o.source == OrderSource.admin), isNotEmpty);
    });

    test('get_order（客服看）：可以按的按钮', () {
      final o = OrderDetail.fromJson(asJson(fixture('admin_order_detail')));
      expect(o.actions.canConfirm, isTrue);
      expect(o.actions.canCancel, isTrue);
    });

    test('get_offers、quote_cart（代下单）', () {
      final offers = asJsonList(fixture('admin_offers')).map(Offer.fromJson).toList();
      expect(offers, isNotEmpty);
      final q = CartQuote.fromJson(asJson(fixture('admin_quote')));
      expect(q.groups.single.lines.single.qty, 3);
    });

    test('admin_list_products', () {
      final products = asJsonList(fixture('admin_products')).map(SellerProduct.fromJson).toList();
      expect(products.firstWhere((p) => p.name == '16安士 PP杯 95口径').priceSen, 8300);
    });

    test('admin_list_subscriptions', () {
      final subs = asJsonList(fixture('admin_subscriptions')).map(AdminSubscription.fromJson).toList();
      final siti = subs.firstWhere((s) => s.shopName == 'Kedai Runcit Siti');
      expect(siti.state, SubscriptionState.lapsed);
      expect(siti.canExtendTrial, isTrue, reason: '试用过期、没付过：可以重新打开试用');
      expect(siti.canCancel, isFalse);
      final ming = subs.firstWhere((s) => s.shopName == '阿明茶餐室');
      expect(ming.state, SubscriptionState.trialing);
      expect(ming.lockedPriceSen, 5000);
      expect(ming.isFoundingPrice, isTrue);
    });

    test('admin_commission_report', () {
      final r = CommissionReport.fromJson(asJson(fixture('admin_commission_report')));
      expect(r.periodLabel, '2026-11');
      expect(r.commissionSen, r.wholesalers.fold<int>(0, (s, w) => s + w.commissionSen));
      final b = r.wholesalers.firstWhere((w) => w.name.contains('Tebrau'));
      expect(b.gmvSen, 28600);
      expect(b.rateText, '1%');
      expect(b.orders.single.shippingFeeSen, 0);
      expect(b.invoice, isNull);
    });

    test('admin_list_audit_logs', () {
      final logs = asJsonList(fixture('admin_audit_logs')).map(AuditEntry.fromJson).toList();
      final placed = logs.firstWhere((e) => e.action == 'admin_place_order');
      expect(placed.isAdminAction, isTrue);
      expect(placed.shopName, '阿明茶餐室');
      expect(placed.actorName, '客服 Mei');
      final price = logs.firstWhere((e) => e.action == 'admin_update_product');
      expect(price.changedKeys, contains('price_sen'));
      expect(price.wholesalerId, '00000000-0000-4000-a000-00000000000a');
      expect(logs.any((e) => !e.isAdminAction), isTrue, reason: '也有表的逐行记录');
    });
  });

  group('送出去的参数', () {
    test('admin_list_orders：筛选条件', () async {
      final r = recordingApi((_) => {'total': 0, 'orders': <Object>[]});
      await r.api.listAllOrders(
        AdminOrderFilter(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 11, 30),
          wholesalerId: 'w1',
          statuses: const {OrderStatus.outOfStock},
          sources: const {OrderSource.whatsapp},
          unconfirmedOnly: true,
        ),
      );
      final (fn, p) = r.calls.single;
      expect(fn, 'admin_list_orders');
      expect(p['p_from'], '2026-11-01');
      expect(p['p_to'], '2026-11-30');
      expect(p['p_wholesaler_id'], 'w1');
      expect(p['p_shop_id'], isNull);
      expect(p['p_statuses'], ['out_of_stock']);
      expect(p['p_sources'], ['whatsapp']);
      expect(p['p_unconfirmed_only'], isTrue);
    });

    test('筛选条件：空的集合送 null（不筛选），copyWith 回到第一页', () {
      const f = AdminOrderFilter(offset: 100);
      expect(f.toParams()['p_statuses'], isNull);
      expect(f.copyWith(unconfirmedOnly: true).offset, 0);
      expect(f.copyWith(wholesalerId: () => 'x').wholesalerId, 'x');
      expect(
        const AdminOrderFilter(statuses: {OrderStatus.pending}),
        const AdminOrderFilter(statuses: {OrderStatus.pending}),
      );
    });

    test('代下单、佣金比例、手动付款、月份', () async {
      final r = recordingApi(
        (fn) => switch (fn) {
          'admin_place_order' => {
            'checkout_id': 'c1',
            'orders': [
              {'id': 'o1', 'order_no': 'JHB1', 'wholesaler_name': 'A', 'total_sen': 100},
            ],
          },
          'admin_set_commission_rate' => (fixture('admin_wholesalers') as List).first,
          'admin_mark_subscription_paid' => (fixture('admin_subscriptions') as List).first,
          'admin_commission_report' => fixture('admin_commission_report'),
          _ => <String, dynamic>{},
        },
      );
      final placed = await r.api.placeOrderAsAdmin('s1', expectedTotalSen: 100, note: '  ');
      expect(placed.orders.single.orderNo, 'JHB1');
      expect(r.calls[0].$2, {'p_shop_id': 's1', 'p_expected_total_sen': 100, 'p_note': null});

      await r.api.setCommissionRate('w1', null);
      expect(r.calls[1].$2, {'p_wholesaler_id': 'w1', 'p_rate': null});

      await r.api.markSubscriptionPaid('sub', months: 3, method: PaymentMethod.duitnow, reference: 'DN1');
      expect(r.calls[2].$2, {
        'p_subscription_id': 'sub',
        'p_months': 3,
        'p_amount_sen': null,
        'p_method': 'duitnow',
        'p_reference': 'DN1',
      });

      await r.api.getCommissionReport(month: DateTime(2026, 10, 17));
      expect(r.calls[3].$2, {'p_period_month': '2026-10-01'});
    });

    test('服务器的错误代码', () async {
      final r = recordingApi(
        (_) =>
            http.Response(jsonEncode({'code': 'P0001', 'message': 'INVALID_RATE', 'details': null, 'hint': null}), 400),
      );
      await expectLater(
        r.api.setCommissionRate('w1', 0.5),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'INVALID_RATE')),
      );
    });
  });

  group('productChanges（只送改了的栏）', () {
    final p = SellerProduct.fromJson(asJsonList(fixture('admin_products')).first);
    test(
      '改价钱：只有 price_sen',
      () => expect(productChanges(p, p.copyWith(priceSen: p.priceSen + 100)), {'price_sen': p.priceSen + 100}),
    );
    test('没改：空的', () => expect(productChanges(p, p), isEmpty));
    test('新增：全部（不送照片）', () {
      final n = productChanges(null, SellerProduct.draft(wholesalerId: 'w').copyWith(name: 'x', priceSen: 100));
      expect(n['name'], 'x');
      expect(n.containsKey('photo_paths'), isFalse);
    });
  });

  group('佣金报表 CSV', () {
    final r = CommissionReport.fromJson(asJson(fixture('admin_commission_report')));
    test('每家一行 + 合计，金额两位小数', () {
      final csv = commissionReportCsv(r);
      expect(csv.startsWith('﻿'), isTrue, reason: 'Excel 要 BOM 才认得中文');
      final lines = csv.substring(1).trim().split('\r\n');
      expect(lines, hasLength(r.wholesalers.length + 2));
      expect(lines.first, startsWith('Period,Wholesaler'));
      expect(lines.firstWhere((l) => l.contains('Tebrau')), contains(',286.00,1%,2.86,'));
      expect(lines.last, contains('TOTAL'));
      expect(lines.last, endsWith(',567.00,,5.67,,'));
    });
    test('逗号、引号、公式', () {
      final w = WholesalerCommission.fromJson({
        'wholesaler_id': 'w',
        'name': '=HYPERLINK("x"),A',
        'billing': {'name': 'A, "B"'},
        'order_count': 1,
        'gmv_sen': 105,
        'commission_sen': 1,
      });
      final csv = commissionReportCsv(
        CommissionReport(
          periodMonth: DateTime(2026, 11),
          orderCount: 1,
          gmvSen: 105,
          commissionSen: 1,
          wholesalers: [w],
        ),
        withBom: false,
        totalLabel: '合计',
      );
      final row = csv.split('\r\n')[1];
      expect(row, '2026-11,"\'=HYPERLINK(""x""),A","A, ""B""",,,1,1.05,,0.01,,');
      expect(csv.split('\r\n')[2], startsWith('2026-11,合计,'));
    });
  });
}
