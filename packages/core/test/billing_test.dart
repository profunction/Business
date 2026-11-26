// 第七步：收费（本机数据库真实返回的 JSON）、送出去的请求、create-payment 的错误
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

(AdminApi, List<(String, Object?)>) mockApi(Object? Function(String path, Object? body) reply, {int status = 200}) {
  final sent = <(String, Object?)>[];
  final api = AdminApi(
    SupabaseClient(
      'http://sb.test',
      'test-key',
      httpClient: MockClient((req) async {
        final body = req.body.isEmpty ? null : jsonDecode(req.body);
        sent.add((req.url.path, body));
        return http.Response(
          jsonEncode(reply(req.url.path, body)),
          status,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      }),
    ),
  );
  return (api, sent);
}

void main() {
  test('买家订阅（试用中）：还剩几天、锁定价、续费价', () {
    final b = BuyerBilling.fromJson(asJson(fixture('buyer_billing')));
    expect(b.state, SubscriptionState.trialing);
    expect(b.status.hasFullAccess, isTrue);
    expect(b.daysLeft, 14);
    expect(b.accessUntil, isNotNull);
    expect(b.priceLocked, isTrue);
    expect(b.renewPriceSen, 5000);
    expect(b.monthOptions, [1, 3, 6, 12]);
    expect(b.payments, isEmpty);
  });

  test('买家订阅（已停）：续费按现在的价钱，没有锁定', () {
    final b = BuyerBilling.fromJson(asJson(fixture('buyer_billing_lapsed')));
    expect(b.state, SubscriptionState.lapsed);
    expect(b.status.hasFullAccess, isFalse);
    expect(b.priceLocked, isFalse);
    expect(b.accessUntil, isNull);
    expect(b.renewPriceSen, b.status.currentPriceSen);
  });

  test('付了 3 个月：active，付款记录有到哪天', () {
    final b = BuyerBilling.fromJson(asJson(fixture('buyer_billing_active')));
    expect(b.state, SubscriptionState.active);
    expect(b.payments, hasLength(1));
    final p = b.payments.single;
    expect(p.isPaid, isTrue);
    expect(p.amountSen, 15000);
    expect(p.months, 3);
    expect(p.method, PaymentMethod.fpx);
    expect(p.periodEnd, b.status.currentPeriodEnd);
    final paid = PaymentInfo.fromJson(asJson(fixture('payment_paid')));
    expect(paid.id, p.id);
    expect(paid.checkoutUrl, isNull, reason: '付了就不再给付款页');
  });

  test('批发商收费页：上架费、佣金比例、账单', () {
    final s = SellerBilling.fromJson(asJson(fixture('seller_billing')));
    expect(s.listingFee.isFounding, isTrue);
    expect(s.listingFee.canPay, isTrue);
    expect(s.listingFee.isPaid, isFalse);
    expect(s.listingFee.feeSen, 10000);
    expect(s.commissionRate, 0.01);
    expect(s.rateSource, 'founding');
    expect(s.invoices, hasLength(1));
    expect(s.invoices.single.isOutstanding, isTrue);
    expect(s.invoices.single.periodMonth, isNotNull);
    expect(s.outstandingSen, s.invoices.single.commissionSen);
  });

  test('账单明细：每张单一行，货价不含运费', () {
    final d = InvoiceDetail.fromJson(asJson(fixture('commission_invoice')));
    expect(d.canPay, isTrue);
    expect(d.lines, hasLength(d.invoice.orderCount));
    expect(d.lines.fold<int>(0, (a, l) => a + l.commissionSen), d.invoice.commissionSen);
    expect(d.billingName, isNotEmpty);
  });

  test('客服的付款列表', () {
    final list = asJsonList(fixture('admin_payments')).map(PaymentInfo.fromJson).toList();
    expect(list, isNotEmpty);
    expect(list.first.payerName, isNotNull);
    expect(list.first.gatewayRef, 'HP-DEMO-1');
  });

  test('create-payment：送出去的东西、回传网址；错误代码', () async {
    final (api, sent) = mockApi(
      (path, body) => {
        'payment_id': 'p1',
        'checkout_url': 'https://securecheckout.hit-pay.com/x',
        'amount_sen': 15000,
        'reuse': false,
      },
    );
    final c = await api.createPayment(PaymentPurpose.subscription, 'shop-1', months: 3);
    expect(c.checkoutUrl, 'https://securecheckout.hit-pay.com/x');
    expect(sent.single.$1, '/functions/v1/create-payment');
    expect(sent.single.$2, {'purpose': 'subscription', 'target_id': 'shop-1', 'months': 3});
    await api.createPayment(PaymentPurpose.commissionInvoice, 'inv-1');
    expect(sent.last.$2, {'purpose': 'commission_invoice', 'target_id': 'inv-1'}, reason: '账单不送月数');

    for (final (status, code) in [(503, 'PAYMENT_NOT_CONFIGURED'), (409, 'NOTHING_DUE'), (429, 'TOO_MANY_PAYMENTS')]) {
      final (bad, _) = mockApi((path, body) => {'error': code}, status: status);
      await expectLater(
        bad.createPayment(PaymentPurpose.listingFee, 'w1'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', code)),
      );
    }
    final (noUrl, _) = mockApi((path, body) => {'payment_id': 'p1', 'checkout_url': 'http://x', 'amount_sen': 1});
    await expectLater(noUrl.createPayment(PaymentPurpose.listingFee, 'w1'), throwsA(isA<AppError>()));
  });

  test('收费的 RPC：参数名', () async {
    final (api, sent) = mockApi((path, body) => path.endsWith('admin_list_payments') ? [] : fixture('seller_billing'));
    await api.getSellerBilling('w1');
    expect(sent.last.$1, '/rest/v1/rpc/get_seller_billing');
    expect(sent.last.$2, {'p_wholesaler_id': 'w1'});
    await api.listPayments(purpose: PaymentPurpose.listingFee, reviewOnly: true);
    expect(sent.last.$2, {'p_status': null, 'p_purpose': 'listing_fee', 'p_review_only': true});
  });
}
