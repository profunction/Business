// 示范模式的批发商端（DemoApi(seller: true)）：一开始跟真实样本一样，按了按钮之后照数据库函数的规则变。
// 第四步的批发商页面和测试都靠这些资料。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/demo/demo_data.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(demoFixtures[name]!);

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 7)]);

Future<(DemoApi, String)> seller() async {
  final api = DemoApi(seller: true);
  final ctx = await api.getMyContext();
  return (api, ctx.wholesalers.single.id);
}

Future<PriceListImport> uploadAndWait(DemoApi api, String wid) async {
  final imp = await api.submitPriceList(wid, jpeg, fileName: 'IMG_0001.HEIC');
  return api.watchImport(imp.id).last;
}

void main() {
  test('示范批发商的账号：角色是批发商（my_context 样本是买家）', () async {
    final api = DemoApi(seller: true);
    final ctx = await api.getMyContext();
    expect(ctx.profile.role, UserRole.seller);
    expect(ctx.shops, isEmpty);
    expect(ctx.wholesalers.single.id, asJson(asJson(fixture('seller_home'))['wholesaler'])['id']);
  });

  test('一开始：首页、订单列表、送货总结跟样本一样', () async {
    final (api, wid) = await seller();
    final home = await api.getSellerHome(wid);
    final h = SellerHome.fromJson(asJson(fixture('seller_home')));
    expect(home.pendingCount, h.pendingCount);
    expect(home.oldestPendingAt, h.oldestPendingAt);
    expect(home.todayOrderCount, h.todayOrderCount);
    expect(home.todayTotalSen, h.todayTotalSen);
    expect(home.latestImport?.status, h.latestImport?.status);

    final orders = await api.listSellerOrders(wid);
    expect(orders.map((o) => o.id), asJsonList(fixture('seller_orders')).map((o) => o['id']));
    for (final o in orders) {
      expect(o.totalSen, o.goodsSubtotalSen + o.shippingFeeSen);
    }

    final s = await api.getDeliverySummary(wid);
    final f = DeliverySummary.fromJson(asJson(fixture('delivery_summary')));
    expect(s.date, f.date);
    expect(s.orders.map((o) => o.id), f.orders.map((o) => o.id));
    expect(s.totalSen, f.totalSen);
    expect(s.pendingCount, f.pendingCount);
    expect(s.picking.map((p) => '${p.name} ${p.qty}'), f.picking.map((p) => '${p.name} ${p.qty}'));
    expect(s.orders.first.items.map((i) => i.isOutOfStock), f.orders.first.items.map((i) => i.isOutOfStock));
  });

  test('每张单都有明细，金额对得上（没有明细的样本用示范商品拼出来）', () async {
    final (api, wid) = await seller();
    for (final o in await api.listSellerOrders(wid)) {
      final d = await api.getOrder(o.id);
      expect(d.items, hasLength(o.itemCount), reason: o.orderNo);
      expect(d.items.where((i) => !i.isOutOfStock).fold<int>(0, (n, i) => n + i.lineTotalSen), d.goodsSubtotalSen);
      expect(d.shopName, o.shopName);
      expect(d.actions.canConfirm, o.status == OrderStatus.pending);
      expect(d.actions.canCancel, isFalse, reason: '批发商不能取消');
    }
  });

  test('确认（勾一样缺货）：那样不算钱，变成今天要送，拣货单不算缺货的', () async {
    final (api, wid) = await seller();
    final id = asJson(fixture('seller_order_detail'))['id'] as String;
    final before = await api.getSellerHome(wid);
    final d = await api.getOrder(id);
    expect(d.items.length, greaterThan(1));
    final oos = d.items.last;
    expect(await api.confirmOrder(id, outOfStockItemIds: [oos.id]), OrderStatus.confirmed);
    expect(api.calls, contains('confirm $id 1'));

    final after = await api.getOrder(id);
    expect(after.status, OrderStatus.confirmed);
    expect(after.items.last.isOutOfStock, isTrue);
    expect(after.goodsSubtotalSen, d.goodsSubtotalSen - oos.lineTotalSen);
    expect(after.actions.canMarkDelivering && after.actions.canMarkDelivered, isTrue);

    final home = await api.getSellerHome(wid);
    expect(home.pendingCount, before.pendingCount - 1);
    expect(home.todayOrderCount, before.todayOrderCount + 1, reason: '这张单今天送');
    expect(home.todayTotalSen, before.todayTotalSen + after.totalSen);

    final s = await api.getDeliverySummary(wid);
    final order = s.orders.firstWhere((o) => o.id == id);
    expect(order.items.last.isOutOfStock, isTrue, reason: '缺货的排后面');
    expect(s.orderCount, before.todayOrderCount + 1);
    final oosQtyInPicking = s.picking.where((p) => p.name == oos.name).fold<int>(0, (n, p) => n + p.qty);
    final oosQtyElsewhere = s.orders
        .where((o) => o.id != id)
        .expand((o) => o.items)
        .where((i) => i.name == oos.name && !i.isOutOfStock)
        .fold<int>(0, (n, i) => n + i.qty);
    expect(oosQtyInPicking, oosQtyElsewhere, reason: '缺货的不进拣货单');

    await expectLater(
      api.confirmOrder(id),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'INVALID_TRANSITION')),
    );
  });

  test('确认时全部缺货 → 整张单缺货；不在订单里的东西不行', () async {
    final (api, wid) = await seller();
    final pending = (await api.listSellerOrders(wid, statuses: [OrderStatus.pending])).last;
    final d = await api.getOrder(pending.id);
    await expectLater(
      api.confirmOrder(pending.id, outOfStockItemIds: ['00000000-0000-4000-9999-000000000000']),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'ITEM_NOT_IN_ORDER')),
    );
    expect(
      await api.confirmOrder(pending.id, outOfStockItemIds: d.items.map((i) => i.id).toList()),
      OrderStatus.outOfStock,
    );
  });

  test('整张单缺货、出发送货、已送达', () async {
    final (api, wid) = await seller();
    final pending = (await api.listSellerOrders(wid, statuses: [OrderStatus.pending])).first;
    await api.markOutOfStock(pending.id);
    final oos = await api.getOrder(pending.id);
    expect(oos.status, OrderStatus.outOfStock);
    expect(oos.items.every((i) => i.isOutOfStock), isTrue);

    final confirmed = (await api.listSellerOrders(wid, statuses: [OrderStatus.confirmed])).first;
    final before = await api.getSellerHome(wid);
    await api.markDelivering(confirmed.id);
    expect((await api.getOrder(confirmed.id)).status, OrderStatus.delivering);
    expect((await api.getSellerHome(wid)).todayOrderCount, before.todayOrderCount, reason: '送货中也算今天要送');
    await api.markDelivered(confirmed.id);
    expect((await api.getSellerHome(wid)).todayOrderCount, before.todayOrderCount - 1);
    await expectLater(
      api.markDelivering(confirmed.id),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'INVALID_TRANSITION')),
    );
  });

  test('订单列表：pending 先来先做；可以按状态和送货日筛', () async {
    final (api, wid) = await seller();
    final all = await api.listSellerOrders(wid);
    final pending = all.takeWhile((o) => o.status == OrderStatus.pending).toList();
    expect(pending, isNotEmpty);
    expect(all.skip(pending.length).every((o) => o.status != OrderStatus.pending), isTrue);
    final day = DateTime(2026, 11, 26);
    final onDay = await api.listSellerOrders(wid, deliveryDate: day);
    expect(onDay.every((o) => o.expectedDeliveryDate == day), isTrue);
    expect((await api.listSellerOrders(wid, limit: 2)), hasLength(2));
  });

  test('商品：改价钱、库存、下架，首页数字跟着变', () async {
    final (api, wid) = await seller();
    final products = await api.listMyProducts(wid);
    expect(products, isNotEmpty);
    final home = await api.getSellerHome(wid);
    expect(home.productCounts.active, products.where((p) => p.status == ProductStatus.active).length);

    final p = products.firstWhere((p) => p.stockStatus == StockStatus.inStock);
    final saved = await api.saveProduct(p.copyWith(priceSen: p.priceSen + 100, minOrderQty: 3));
    expect(saved.priceSen, p.priceSen + 100);
    expect(saved.minOrderQty, 3);
    expect((await api.setStockStatus(p.id, StockStatus.outOfStock)).stockStatus, StockStatus.outOfStock);
    expect((await api.getSellerHome(wid)).productCounts.outOfStock, home.productCounts.outOfStock + 1);
    await api.setProductStatus(p.id, ProductStatus.archived);
    final after = await api.getSellerHome(wid);
    expect(after.productCounts.active, home.productCounts.active - 1);
    expect(after.productCounts.outOfStock, home.productCounts.outOfStock, reason: '只算上架中的');

    final created = await api.saveProduct(
      SellerProduct.draft(wholesalerId: wid).copyWith(name: '新商品', unit: SellUnit.pack, packQty: 50, priceSen: 300),
    );
    expect(created.isNew, isFalse);
    expect((await api.listMyProducts(wid)).map((x) => x.id), contains(created.id));
  });

  test('价目表：拍照上传 → AI 读好 → 补一行 → 确认上架', () async {
    final (api, wid) = await seller();
    final productCount = (await api.listMyProducts(wid)).length;
    final imp = await api.submitPriceList(wid, jpeg, fileName: 'IMG_0001.HEIC');
    expect(api.calls, containsAllInOrder(['upload jpg image/jpeg', 'createImport image', 'startParse']));
    expect(imp.status, ImportStatus.processing);
    expect((await api.getSellerHome(wid)).latestImport?.status, ImportStatus.processing);
    final seen = await api.watchImport(imp.id).map((i) => i.status).toList();
    expect(seen.last, ImportStatus.review);

    final rows = await api.listImportRows(imp.id);
    expect(rows, hasLength(asJsonList(fixture('price_list_import_rows')).length));
    final skipped = rows.firstWhere((r) => r.action == ImportRowAction.skip && r.hasName);
    final fixed = skipped.copyWith(priceSen: 1500, packQty: 100, unit: SellUnit.pack, action: ImportRowAction.create);
    expect((await api.updateImportRow(skipped.id, fixed.toWriteJson())).action, ImportRowAction.create);

    final update = rows.firstWhere((r) => r.action == ImportRowAction.update);
    final result = await api.applyImport(imp.id);
    final base = ApplyImportResult.fromJson(asJson(fixture('apply_import_result')));
    expect(result.created, base.created + 1);
    expect(result.updated, base.updated);
    expect(result.skipped, base.skipped - 1);
    final products = await api.listMyProducts(wid);
    expect(products, hasLength(productCount + result.created));
    expect(products.firstWhere((p) => p.id == update.matchedProductId).priceSen, update.priceSen);
    expect(products.any((p) => p.name == skipped.name!.trim() && p.priceSen == 1500), isTrue);
    expect((await api.getSellerHome(wid)).latestImport?.status, ImportStatus.applied);

    await expectLater(
      api.applyImport(imp.id),
      throwsA(
        isA<AppError>()
            .having((e) => e.code, 'code', 'IMPORT_NOT_IN_REVIEW')
            .having((e) => e.detail, 'detail', 'applied'),
      ),
    );
  });

  test('价目表：不完整的行、两行改同一样商品，都不能上架（什么都不改）', () async {
    final (api, wid) = await seller();
    final imp = await uploadAndWait(api, wid);
    final rows = await api.listImportRows(imp.id);
    final create = rows.firstWhere((r) => r.action == ImportRowAction.create);
    await api.updateImportRow(create.id, {'price_sen': null});
    await expectLater(
      api.applyImport(imp.id),
      throwsA(
        isA<AppError>()
            .having((e) => e.code, 'code', 'IMPORT_ROW_INCOMPLETE')
            .having((e) => e.rowNo, 'rowNo', create.rowNo),
      ),
    );
    await api.updateImportRow(create.id, {'action': 'skip'});

    final updates = rows.where((r) => r.action == ImportRowAction.update).toList();
    expect(updates.length, greaterThanOrEqualTo(2));
    await api.updateImportRow(updates[1].id, {'matched_product_id': updates[0].matchedProductId});
    await expectLater(
      api.applyImport(imp.id),
      throwsA(
        isA<AppError>()
            .having((e) => e.code, 'code', 'IMPORT_DUPLICATE_PRODUCT')
            .having((e) => e.rowNo, 'rowNo', updates[0].rowNo),
      ),
    );
    expect((await api.getImport(imp.id)).status, ImportStatus.review, reason: '失败了还可以再改');
  });

  test('价目表：AI 读不到 → failed + 原因；不收的格式不上传', () async {
    final (api, wid) = await seller();
    api.sellerData.nextImportError = 'AI_REFUSED';
    final imp = await uploadAndWait(api, wid);
    expect(imp.status, ImportStatus.failed);
    expect(imp.errorMessage, 'AI_REFUSED');
    expect(await api.listImportRows(imp.id), isEmpty);

    api.calls.clear();
    final heic = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits, 0, 0, 0, 0]);
    await expectLater(
      api.submitPriceList(wid, heic),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'UNSUPPORTED_FILE')),
    );
    expect(api.calls, isEmpty);
  });

  test('设定：选 WhatsApp = 同意用 WhatsApp 收订单（时间只记第一次）', () async {
    final (api, wid) = await seller();
    expect((await api.getWholesalerSettings(wid)).whatsappOptedIn, isFalse);
    final s = await api.setNotifyChannel(wid, NotifyChannel.whatsapp);
    expect(s.notifyChannel, NotifyChannel.whatsapp);
    expect(s.whatsappOptedIn, isTrue);
    final again = await api.setNotifyChannel(wid, NotifyChannel.push);
    expect(again.notifyChannel, NotifyChannel.push);
    expect(again.whatsappOptInAt, s.whatsappOptInAt);
    await api.setWhatsappOptIn(wid, false);
    expect((await api.getWholesalerSettings(wid)).whatsappOptedIn, isFalse);
  });
}
