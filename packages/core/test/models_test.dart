// 用本机数据库真实返回的 JSON（test/fixtures）测试解析，确保 App 跟服务器对得上。
// 重新生成样本：见 docs/03-buyer-app.md「更新测试样本」。
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  test('get_my_context', () {
    final c = MyContext.fromJson(asJson(fixture('my_context')));
    expect(c.profile.role, UserRole.buyer);
    expect(c.shops.single.name, '阿明茶餐室');
    expect(c.shops.single.isOwner, isTrue);
    expect(c.wholesalers, isEmpty);
  });

  test('get_buyer_home', () {
    final h = BuyerHome.fromJson(asJson(fixture('buyer_home')));
    expect(h.shopName, '阿明茶餐室');
    expect(h.shopType, ShopType.restaurant);
    expect(h.zoneName.of('ms'), contains('Tebrau'));
    expect(h.subscription.isTrial, isTrue);
    expect(h.subscription.lockedPriceSen, 5000);
    expect(h.subscription.trialDaysLeft(h.subscription.trialEndsAt!.subtract(const Duration(hours: 30))), 2);
    expect(h.activeOrderCount, 3);
    expect(h.lastCheckout?.itemCount, 6);
    expect(h.lastCheckout?.wholesalerNames, hasLength(3), reason: '上一次结账拆成 3 家');
  });

  test('get_subscription_status（未付费）', () {
    final s = SubscriptionInfo.fromJson(asJson(fixture('subscription_free')));
    expect(s.hasFullAccess, isFalse);
    expect(s.state, SubscriptionState.lapsed);
    expect(s.isTrial, isFalse);
    expect(s.freeUnlockedLimit, 3);
    expect(s.unlockedWholesalerIds, hasLength(1));
    expect(s.canChangeUnlocks(DateTime.now()), isTrue);
  });

  test('get_categories / get_catalog_overview', () {
    final cats = asJsonList(fixture('categories')).map(CategorySummary.fromJson).toList();
    expect(cats.first.code, 'cups');
    expect(cats.first.name.of('zh'), '杯子');
    final items = asJsonList(fixture('catalog_overview')).map(CatalogItemSummary.fromJson).toList();
    final cup = items.firstWhere((i) => i.name.of('en').startsWith('16oz'));
    expect(cup.offerCount, 4);
    expect(cup.minPricePerBaseUnitSen, 8.2);
  });

  test('get_offers：试用中看得到价钱', () {
    final offers = asJsonList(fixture('offers')).map(Offer.fromJson).toList();
    expect(offers, hasLength(4), reason: 'A、C 各一种，B 有 50 个和 1000 个两种包装');
    expect(offers.every((o) => o.priceVisible && o.priceSen != null), isTrue);
    expect(offers.first.pricePerBaseUnitSen, 8.2);
    expect(offers.first.unit, SellUnit.carton);
  });

  test('get_offers：未付费用户，锁住的批发商没有价钱', () {
    final offers = asJsonList(fixture('offers_free_user')).map(Offer.fromJson).toList();
    final locked = offers.where((o) => !o.priceVisible).toList();
    expect(locked, isNotEmpty);
    expect(locked.every((o) => o.priceSen == null && o.pricePerBaseUnitSen == null), isTrue);
    expect(locked.every((o) => !o.canOrder), isTrue);
    expect(offers.first.priceVisible, isTrue, reason: '看得到价钱的排在前面');
  });

  test('list_wholesalers', () {
    final ws = asJsonList(fixture('wholesalers')).map(WholesalerSummary.fromJson).toList();
    final a = ws.firstWhere((w) => w.name.contains('A'));
    expect(a.priceVisible, isTrue);
    expect(a.deliveryWeekdays, [1, 3, 5]);
    expect(a.paymentTerms, contains('cod'));
  });

  test('quote_cart：按批发商分组，标出问题', () {
    final q = CartQuote.fromJson(asJson(fixture('quote_cart')));
    expect(q.groups, hasLength(3));
    expect(q.canPlace, isFalse, reason: 'B 未到最低消费');
    final b = q.groups.firstWhere((g) => g.problem != null);
    expect(b.problem, CartProblem.belowMinOrder);
    expect(b.shortBySen, greaterThan(0));
    expect(q.totalSen, q.goodsTotalSen + q.shippingTotalSen);
    final a = q.groups.firstWhere((g) => g.wholesalerName.contains('A'));
    expect(a.shortOfFreeShippingSen, 15000 - a.goodsSubtotalSen);
    expect(a.expectedDeliveryDate, isNotNull);
    expect(q.qtyOf(b.lines.first.productId), 5);
  });

  test('reorder_last', () {
    final r = ReorderResult.fromJson(asJson(fixture('reorder')));
    expect(r.addedCount, 3);
    expect(r.skipped, isEmpty);
    expect(r.quote.canPlace, isTrue);
    expect(r.quote.totalSen, 28100);
  });

  test('list_orders / get_order', () {
    final orders = asJsonList(fixture('orders')).map(OrderSummary.fromJson).toList();
    expect(orders.map((o) => o.status).toSet(), {
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.delivering,
      OrderStatus.delivered,
    });
    expect(orders.where((o) => o.status.isActive), hasLength(3));
    final confirmed = orders.firstWhere((o) => o.status == OrderStatus.confirmed);
    expect(confirmed.outOfStockCount, 1);
    expect(orders.last.status, OrderStatus.delivered, reason: '最新的在前面');

    final c = OrderDetail.fromJson(asJson(fixture('order_detail_confirmed')));
    expect(c.items.where((i) => i.isOutOfStock), hasLength(1));
    expect(
      c.goodsSubtotalSen,
      c.items.where((i) => !i.isOutOfStock).fold<int>(0, (s, i) => s + i.lineTotalSen),
      reason: '缺货的不算钱',
    );
    expect(c.actions.canCancel && c.actions.canMarkReceived, isTrue);

    final d = OrderDetail.fromJson(asJson(fixture('order_detail')));
    expect(d.items, hasLength(3));
    expect(d.items.fold<int>(0, (s, i) => s + i.lineTotalSen), d.goodsSubtotalSen);
    expect(d.events.map((e) => e.toStatus), [OrderStatus.pending, OrderStatus.confirmed, OrderStatus.delivered]);
    expect(d.reachedAt(OrderStatus.delivered), isNotNull);
    expect(d.reachedAt(OrderStatus.delivering), isNull);
    expect(d.actions.canReview, isTrue);
    expect(d.actions.canCancel, isFalse);
    expect(d.wholesalerPhone, '60120000002');
  });
}
