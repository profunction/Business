// 批发商端：用本机数据库真实返回的 JSON（test/fixtures/seller_*、delivery_summary、price_list_import*、
// apply_import_result）测试解析。样本由另一个流程从数据库导出，不要手改。
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  test('get_seller_home', () {
    final h = SellerHome.fromJson(asJson(fixture('seller_home')));
    expect(h.wholesaler.id, looksLikeUuid);
    expect(h.wholesaler.name, isNotEmpty);
    expect(h.wholesaler.status, anyOf('pending', 'active', 'suspended'));
    expect(h.wholesaler.notifyChannel, isA<NotifyChannel>());
    expect(h.pendingCount, greaterThanOrEqualTo(0));
    if (h.pendingCount > 0) expect(h.oldestPendingAt, isNotNull);
    expect(h.todayOrderCount, greaterThanOrEqualTo(0));
    expect(h.todayTotalSen, greaterThanOrEqualTo(0));
    final c = h.productCounts;
    expect(c.outOfStock + c.lowStock, lessThanOrEqualTo(c.active), reason: '缺货 / 快卖完只算上架中的');
    final raw = asJson(fixture('seller_home'));
    expect(h.today, asDateOrNull(raw['today']));
    if (raw['latest_import'] != null) {
      expect(h.latestImport!.id, asJson(raw['latest_import'])['id']);
      expect(h.latestImport!.status.name, asJson(raw['latest_import'])['status']);
    }
  });

  test('list_seller_orders：pending 排最前面，先来先做', () {
    final orders = asJsonList(fixture('seller_orders')).map(SellerOrderSummary.fromJson).toList();
    expect(orders, isNotEmpty);
    for (final o in orders) {
      expect(o.id, looksLikeUuid);
      expect(o.orderNo, isNotEmpty);
      expect(o.shopName, isNotEmpty);
      expect(o.zoneName.of('zh'), isNotEmpty);
      expect(o.totalSen, o.goodsSubtotalSen + o.shippingFeeSen);
      expect(o.outOfStockCount, lessThanOrEqualTo(o.itemCount));
    }
    final pending = orders.takeWhile((o) => o.status == OrderStatus.pending).toList();
    expect(orders.skip(pending.length).any((o) => o.status == OrderStatus.pending), isFalse);
    for (var i = 1; i < pending.length; i++) {
      expect(pending[i].createdAt.isBefore(pending[i - 1].createdAt), isFalse, reason: 'pending 旧到新');
    }
    final rest = orders.skip(pending.length).toList();
    for (var i = 1; i < rest.length; i++) {
      expect(rest[i].createdAt.isAfter(rest[i - 1].createdAt), isFalse, reason: '其他新到旧');
    }
  });

  test('get_delivery_summary：拣货单不含缺货，金额加得起来', () {
    final s = DeliverySummary.fromJson(asJson(fixture('delivery_summary')));
    expect(s.wholesalerId, looksLikeUuid);
    expect(s.orderCount, s.orders.length);
    expect(s.totalSen, s.goodsTotalSen + s.shippingTotalSen);
    expect(s.goodsTotalSen, s.orders.fold<int>(0, (n, o) => n + o.goodsSubtotalSen));
    expect(s.shippingTotalSen, s.orders.fold<int>(0, (n, o) => n + o.shippingFeeSen));
    for (final o in s.orders) {
      expect(o.status, anyOf(OrderStatus.confirmed, OrderStatus.delivering));
      expect(o.shop.name, isNotEmpty);
      expect(o.shop.zoneName.of('en'), isNotEmpty);
      expect(o.paymentTerms, isNotEmpty);
      expect(
        o.goodsSubtotalSen,
        o.items.where((i) => !i.isOutOfStock).fold<int>(0, (n, i) => n + i.lineTotalSen),
        reason: '缺货的不算钱',
      );
      // 缺货的排在后面
      final firstOos = o.items.indexWhere((i) => i.isOutOfStock);
      if (firstOos >= 0) expect(o.items.skip(firstOos).every((i) => i.isOutOfStock), isTrue);
      for (final i in o.items) {
        expect(i.unit, isNot(SellUnit.unknown));
        expect(i.lineTotalSen, i.unitPriceSen * i.qty);
      }
    }
    // 拣货单 = 没缺货的明细按（名字、单位、包装）加总
    final expected = <String, int>{};
    for (final o in s.orders) {
      for (final i in o.items.where((i) => !i.isOutOfStock)) {
        final k = '${i.name}|${i.unit.name}|${i.packQty}';
        expected[k] = (expected[k] ?? 0) + i.qty;
      }
    }
    expect({for (final p in s.picking) '${p.name}|${p.unit.name}|${p.packQty}': p.qty}, expected);
  });

  test('get_order（批发商看）：店的电话、联络人、送货区和每一样的 id', () {
    final d = OrderDetail.fromJson(asJson(fixture('seller_order_detail')));
    expect(d.status, OrderStatus.pending);
    expect(d.actions.canConfirm, isTrue);
    expect(d.actions.canCancel, isFalse, reason: '批发商不能取消');
    expect(d.shopPhone, isNotNull);
    expect(d.shopContactName, isNotNull);
    expect(d.shopZoneName?.of('zh'), isNotEmpty);
    expect(d.source, isNotNull);
    expect(d.items, isNotEmpty);
    expect(d.items.every((i) => isUuid(i.id) && isUuid(i.productId)), isTrue);
    expect(d.items.fold<int>(0, (n, i) => n + i.lineTotalSen), d.goodsSubtotalSen);
  });

  test('price_list_imports 一行', () {
    final i = PriceListImport.fromJson(asJson(fixture('price_list_import')));
    final raw = asJson(fixture('price_list_import'));
    expect(i.id, raw['id']);
    expect(i.status.name, raw['status']);
    expect(i.fileType.name, raw['file_type']);
    expect(i.filePath, startsWith('${i.wholesalerId}/'), reason: '第一层文件夹 = 批发商 id（Storage 规则）');
    expect(i.isDone, i.status != ImportStatus.processing);
    if (i.status == ImportStatus.failed) expect(i.errorMessage, isNotNull);
  });

  test('price_list_import_rows：create / update / skip', () {
    final rows = asJsonList(fixture('price_list_import_rows')).map(PriceListImportRow.fromJson).toList();
    expect(rows.map((r) => r.rowNo).toList(), List.generate(rows.length, (i) => i + 1), reason: 'row_no 从 1 开始');
    expect(rows.map((r) => r.action).toSet(), ImportRowAction.values.toSet());
    for (final r in rows) {
      switch (r.action) {
        case ImportRowAction.update:
          expect(r.matchedProductId, isNotNull);
          expect(r.canUpdate, isTrue);
        case ImportRowAction.create:
          expect(r.canCreate, isTrue);
        case ImportRowAction.skip:
          expect(r.isReady, isTrue);
      }
      if (r.confidence != null) expect(r.confidence, inInclusiveRange(0, 1));
    }
    // 没名字的行（例如价目表上的备注）也有原文
    final noName = rows.where((r) => !r.hasName);
    expect(noName.every((r) => r.action == ImportRowAction.skip && r.unit == null), isTrue);

    // 改一行：跳过的补上价钱改成新增
    final skipped = rows.firstWhere((r) => r.action == ImportRowAction.skip && r.hasName);
    final fixed = skipped.copyWith(priceSen: 1200, packQty: 100, unit: SellUnit.pack, action: ImportRowAction.create);
    expect(fixed.isReady, isTrue);
    expect(fixed.toWriteJson(), {
      'name': skipped.name!.trim(),
      'unit': 'pack',
      'pack_qty': 100,
      'price_sen': 1200,
      'min_order_qty': skipped.minOrderQty,
      'matched_product_id': skipped.matchedProductId,
      'action': 'create',
    });
    final updated = rows.firstWhere((r) => r.action == ImportRowAction.update);
    final unmatched = updated.copyWith(clearMatchedProduct: true);
    expect(unmatched.matchedProductId, isNull);
    expect(unmatched.isReady, isFalse, reason: 'update 一定要对到商品');
  });

  test('apply_price_list_import', () {
    final r = ApplyImportResult.fromJson(asJson(fixture('apply_import_result')));
    final rows = asJsonList(fixture('price_list_import_rows')).map(PriceListImportRow.fromJson).toList();
    expect(r.created, rows.where((x) => x.action == ImportRowAction.create).length);
    expect(r.updated, rows.where((x) => x.action == ImportRowAction.update).length);
    expect(r.skipped, rows.where((x) => x.action == ImportRowAction.skip).length);
    expect(r.listed, r.created + r.updated);
  });

  test('products 一行（PostgREST select *）', () {
    // products 表的全部字段（supabase/migrations/20261125000200_catalog.sql）
    final p = SellerProduct.fromJson({
      'id': '820eff6d-5979-4fd3-aeff-5945edbd4894',
      'wholesaler_id': '00000000-0000-4000-a000-00000000000a',
      'catalog_item_id': null,
      'category_id': null,
      'name': '16安士 PP杯 95口径',
      'description': null,
      'photo_paths': <String>[],
      'unit': 'carton',
      'pack_qty': 1000,
      'price_sen': 8500,
      'min_order_qty': 1,
      'stock_status': 'low_stock',
      'lead_time_days_override': null,
      'status': 'active',
      'sort_order': 0,
      'price_updated_at': '2026-11-25T01:56:02.972609+00:00',
      'created_by': null,
      'created_at': '2026-11-25T01:56:02.972609+00:00',
      'updated_at': '2026-11-25T01:56:02.972609+00:00',
    });
    expect(p.isNew, isFalse);
    expect(p.unit, SellUnit.carton);
    expect(p.stockStatus, StockStatus.lowStock);
    expect(p.status, ProductStatus.active);
    expect(p.isValid, isTrue);
    final changed = p.copyWith(priceSen: 8800, stockStatus: StockStatus.outOfStock, status: ProductStatus.archived);
    final w = changed.toWriteJson();
    expect(w['price_sen'], 8800);
    expect(w['stock_status'], 'out_of_stock');
    expect(w['status'], 'archived');
    expect(w['photo_paths'], isEmpty);
    expect(p.copyWith(photoPaths: ['w/a.jpg']).toWriteJson()['photo_paths'], ['w/a.jpg']);
    expect(w.containsKey('wholesaler_id'), isFalse, reason: 'wholesaler_id 受保护，不能改');
    expect(w.containsKey('id'), isFalse);

    final draft = SellerProduct.draft(wholesalerId: p.wholesalerId);
    expect(draft.isNew, isTrue);
    expect(draft.isValid, isFalse, reason: '还没有名字和价钱');
  });

  test('枚举的数据库代码', () {
    expect(SellUnit.values.where((u) => u != SellUnit.unknown).map(sellUnitCode), [
      'carton',
      'pack',
      'bag',
      'roll',
      'bundle',
      'box',
      'piece',
      'dozen',
      'kg',
    ]);
    for (final s in StockStatus.values) {
      expect(stockStatusFrom(stockStatusCode(s)), s);
    }
    expect(sellUnitOrNull(null), isNull);
    expect(sellUnitOrNull('bogus'), isNull);
    expect(notifyChannelFrom('whatsapp'), NotifyChannel.whatsapp);
    expect(notifyChannelFrom(null), NotifyChannel.auto);
    expect(dateParam(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('AppError：导入错误的行号', () {
    const e = AppError('IMPORT_ROW_INCOMPLETE', detail: '4');
    expect(e.rowNo, 4);
    expect(const AppError('X').rowNo, isNull);
  });

  test('newUuidV4', () {
    final ids = {for (var i = 0; i < 200; i++) newUuidV4()};
    expect(ids, hasLength(200));
    expect(ids.every(isUuid), isTrue);
    expect(ids.every((s) => s[14] == '4' && '89ab'.contains(s[19])), isTrue);
  });
}

final Matcher looksLikeUuid = predicate<Object?>((v) => v is String && isUuid(v), 'a UUID');
