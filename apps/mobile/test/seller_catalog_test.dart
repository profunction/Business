// 批发商端的商品、送货单、价目表导入：用示范模式把整个流程点一遍（手机宽度 400，撑爆就失败）。
// 拍照、选文件、分享、打印都换成假的（FakeDevice），不会碰到 platform channel。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/app/l10n_x.dart';
import 'package:jb_wholesale/app/theme.dart';
import 'package:jb_wholesale/features/seller/import_page.dart';
import 'package:jb_wholesale/features/seller/products_page.dart';
import 'package:jb_wholesale/features/seller/seller_device.dart';
import 'package:jb_wholesale/features/seller/seller_widgets.dart';
import 'package:jb_wholesale/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionsHttpException;
import 'package:wholesale_core/wholesale_core.dart';

import 'seller_harness.dart';

// 示范批发 A 的商品（id 来自样本：订单明细、价目表对到的商品）
const cup16 = '820eff6d-5979-4fd3-aeff-5945edbd4894'; // 16安士 PP杯 95口径，RM85.00 / 箱
const lid95 = '163974ab-06dc-43e6-9a95-8c0036ba3ba1'; // 95 平盖
const amingConfirmed = '5c372e2f-2712-415e-bfdb-314c0d0985a3';
const sitiDelivering = '7880e5cf-34f0-4a69-a98e-82cece368564';
const vestBagRow = '224a77c9-473e-44bc-884e-0de9b16c0fe5'; // 价目表第 5 行「背心袋 (中)」：看不清价钱，跳过

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 7)]);
final heic = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits, 0, 0, 0, 0, ...List.filled(32, 1)]);

/// 一直 pump 到找得到（等的画面有转圈，pumpAndSettle 会一直等下去）
Future<void> pumpUntil(WidgetTester tester, Finder f, {int max = 50}) async {
  for (var i = 0; i < max && f.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(f, findsWidgets);
}

Future<void> openImport(WidgetTester tester) async {
  routerOf(tester).push('/seller/import');
  await tester.pumpAndSettle();
}

Future<void> scrollToKey(WidgetTester tester, String key) => scrollTo(tester, find.byKey(Key(key)));

Future<void> tapKey(WidgetTester tester, String key) async {
  await scrollToKey(tester, key);
  await tapAndSettle(tester, find.byKey(Key(key)));
}

/// 底下弹出来的那一页（改一行）里面滚动
Future<void> sheetScrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    150,
    scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('上传前检查（看内容，不信档名）', () {
    test('HEIC：认得出来，不上传，告诉老板用「选照片」', () async {
      final l = lookupL10n(const Locale('zh'));
      Object? error;
      try {
        await readPriceListFile(PickedFile.memory(heic, name: 'IMG_0002.jpg'));
      } catch (e) {
        error = e;
      }
      expect(error, isA<AppError>().having((e) => e.code, 'code', 'UNSUPPORTED_FILE'));
      expect((error! as AppError).detail, 'heic');
      expect(l.error(error), l.sellerErrHeic);
      expect(l.sellerErrHeic, contains('选照片'));
    });

    test('档名是 .HEIC、内容是 JPEG（image_picker 转过）→ 可以上传', () async {
      final r = await readPriceListFile(PickedFile.memory(jpeg, name: 'IMG_0001.HEIC'));
      expect(r.kind, FileKind.jpeg);
      expect(r.bytes, jpeg);
    });

    test('太大：知道大小就不读进来', () async {
      var read = false;
      final big = PickedFile(
        name: 'list.pdf',
        size: priceListMaxBytes + 1,
        read: () async {
          read = true;
          return Uint8List(0);
        },
      );
      await expectLater(
        readPriceListFile(big),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'FILE_TOO_LARGE')),
      );
      expect(read, isFalse);
    });

    test('Word（zip 但不是 xlsx）、看不懂的：不收', () async {
      final docx = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...'word/document.xml'.codeUnits]);
      for (final bad in [docx, Uint8List.fromList(List.filled(40, 0))]) {
        await expectLater(
          readPriceListFile(PickedFile.memory(bad, name: 'list.xlsx')),
          throwsA(isA<AppError>().having((e) => e.code, 'code', 'UNSUPPORTED_FILE')),
        );
      }
    });

    test('价目表 AI 的每一个错误代码（error_message、HTTP）：三语都有自己的说明，不是笼统的「出了点问题」', () {
      // 代码清单在 packages/core（supabase/functions/tests/error_codes_test.ts 扫 Edge 代码确认没漏）
      final codes = {...priceListImportErrorCodes, ...priceListHttpErrorCodes};
      expect(codes.length, greaterThanOrEqualTo(35));
      for (final lang in ['zh', 'en', 'ms']) {
        final l = lookupL10n(Locale(lang));
        // 笼统的说法：不认识的代码才用
        final generic = {
          l.errUnknown,
          l.sellerErrAiFailed,
          l.sellerImportErrService,
          l.errNotAllowed,
          l.sellerErrNotFound,
        };
        final seen = <String, String>{};
        for (final c in codes) {
          for (final type in [ImportFileType.image, ImportFileType.excel, ImportFileType.pdf, null]) {
            final text = l.priceListText(c, fileType: type);
            expect(text, isNotNull, reason: '$lang $c 没有说明');
            expect(generic, isNot(contains(text)), reason: '$lang $c：太笼统');
            expect(l.importFailure(c, fileType: type), text, reason: '$lang $c');
          }
          final text = l.priceListText(c, fileType: ImportFileType.image)!;
          // 每个代码自己的说明（UNAUTHORIZED 跟 AUTH 一样是登录过期）
          final other = seen[text];
          expect(
            other == null || {other, c}.containsAll(['AUTH', 'UNAUTHORIZED']),
            isTrue,
            reason: '$lang $c 跟 $other 的说明一样',
          );
          seen[text] = c;
          // 上传 / 叫 AI 时收到的 AppError 也一样（NETWORK、AUTH 在那里是一般的意思）
          if (c != 'NETWORK' && c != 'AUTH') {
            expect(l.priceListError(AppError(c)), isNot(l.errUnknown), reason: '$lang $c');
            expect(generic, isNot(contains(l.priceListError(AppError(c)))), reason: '$lang $c');
          }
        }
        // 照片太大（7 MB）跟文件太大（10 MB）、HEIC
        expect(l.importFailure('FILE_TOO_LARGE', fileType: ImportFileType.image), l.sellerErrPhotoTooLarge);
        expect(l.importFailure('FILE_TOO_LARGE', fileType: ImportFileType.pdf), l.sellerErrFileTooLarge);
        expect(l.priceListError(const AppError('UNSUPPORTED_FILE', detail: 'heic')), l.sellerErrHeic);
        // 找不到商品：照片叫老板拍清楚；Excel / PDF 拍清楚没用，请看是不是价目表
        expect(l.importFailure('NO_PRODUCTS_FOUND', fileType: ImportFileType.image), l.plErrNoProductsPhoto);
        expect(l.importFailure('NO_PRODUCTS_FOUND', fileType: ImportFileType.excel), l.sellerImportErrNoProductsFile);
        // App 自己写的：叫不到 AI 的原因
        expect(l.importFailure('NETWORK'), l.plErrNetwork);
        expect(l.importFailure('AUTH'), l.sellerErrLoginExpired);
        expect(l.priceListError(const AppError('NETWORK')), l.errNetwork, reason: '上传前没网络：一般的说法');
        // 不认识的代码（以后加的）：照片请拍清楚；文件请看是不是价目表
        expect(l.importFailure('SOMETHING_NEW', fileType: ImportFileType.image), l.sellerErrAiFailed);
        expect(l.importFailure('SOMETHING_NEW', fileType: ImportFileType.pdf), l.sellerImportErrNoProductsFile);
        expect(l.importFailure(null), l.sellerErrAiFailed);
        // HTTP 错误：函数回 {"error": "CODE"}
        final notProcessing = AppError.fromFunction(
          const FunctionsHttpException(status: 409, details: {'error': 'IMPORT_NOT_PROCESSING', 'status': 'review'}),
        );
        expect(l.priceListError(notProcessing), l.plErrImportNotProcessing);
        final config = AppError.fromFunction(
          const FunctionsHttpException(status: 500, details: {'error': 'CONFIG_MISSING'}),
        );
        expect(l.priceListError(config), l.plErrConfigMissing);
        final unauthorized = AppError.fromFunction(
          const FunctionsHttpException(status: 401, details: {'error': 'UNAUTHORIZED'}),
        );
        expect(l.priceListError(unauthorized), l.sellerErrLoginExpired);
      }
    });

    test('parse-price-list 不肯读（用量满了 / 停权 / 暂时叫不到）：三种语言都说清楚原因，不是「出了点问题」', () {
      for (final lang in ['zh', 'en', 'ms']) {
        final l = lookupL10n(Locale(lang));
        // 函数回 429 {"error":"TOO_MANY_IMPORTS","retry_after":420}：要等 7 分钟
        final quota = AppError.fromFunction(
          const FunctionsHttpException(status: 429, details: {'error': 'TOO_MANY_IMPORTS', 'retry_after': 420}),
        );
        expect(l.error(quota), l.sellerErrTooManyImports(7), reason: lang);
        expect(l.error(quota), contains('7'));
        expect(
          l.error(const AppError('TOO_MANY_IMPORTS', detail: '30')),
          l.sellerErrTooManyImports(1),
          reason: '不到 1 分钟也说 1 分钟',
        );
        final suspended = AppError.fromFunction(
          const FunctionsHttpException(status: 403, details: {'error': 'WHOLESALER_SUSPENDED'}),
        );
        expect(l.error(suspended), l.sellerErrSuspended);
        final busy = AppError.fromFunction(
          const FunctionsHttpException(status: 503, details: {'error': 'QUOTA_UNAVAILABLE'}),
        );
        expect(l.error(busy), l.sellerErrQuotaUnavailable);
        for (final e in [quota, suspended, busy]) {
          expect(l.error(e), isNot(l.errUnknown), reason: '$lang ${e.code}');
        }
        expect(l.sellerErrSuspended, isNot(l.sellerImportErrService), reason: '停权不是「AI 服务有问题、过几分钟再试」');
      }
      expect(lookupL10n(const Locale('en')).sellerErrTooManyImports(1), contains('1 minute '));
      expect(lookupL10n(const Locale('en')).sellerErrTooManyImports(8), contains('8 minutes'));
    });

    test('照片超过 7 MB（AI 收不了）：上传前就说，不用等上传完', () async {
      final l = lookupL10n(const Locale('zh'));
      final png = Uint8List(priceListMaxImageBytes + 1)..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      Object? error;
      try {
        await readPriceListFile(PickedFile.memory(png, name: 'Screenshot.png'));
      } catch (e) {
        error = e;
      }
      expect(error, isA<AppError>().having((e) => e.detail, 'detail', 'image'));
      expect(l.error(error!), l.sellerErrPhotoTooLarge);
      expect(l.sellerErrPhotoTooLarge, contains('7 MB'));
    });
  });

  group('送货单', () {
    testWidgets('拣货单加总、按区排的每张单；分享给送货员、打印 PDF', (tester) async {
      final device = FakeDevice();
      await startSeller(tester, device: device);
      await tapAndSettle(tester, find.byKey(const Key('seller-today')));
      await tapAndSettle(tester, find.byKey(const Key('seller-open-summary')));

      expect(find.text('送货单'), findsOneWidget);
      expect(find.text('11月25日周三'), findsOneWidget);
      expect(find.text('还有 2 张没确认'), findsOneWidget);
      expect(find.text('2 张单，总额 RM579.00'), findsOneWidget);
      // 拣货单：缺货的吸管不算
      expect(find.text('拣货单'), findsOneWidget);
      expect(find.text('3 箱'), findsNWidgets(2), reason: '16安士 PP杯 ×3、95 平盖 ×3');
      expect(find.text('2 箱'), findsOneWidget, reason: '650ml 饭盒');
      expect(find.text('5 包'), findsOneWidget, reason: '汤匙');
      expect(find.text('一箱 1000 个'), findsNWidgets(2));
      // 每张单：按区排
      await scrollTo(tester, find.byKey(const Key('summary-order-$sitiDelivering')));
      final aming = tester.getTopLeft(find.byKey(const Key('summary-order-$amingConfirmed'), skipOffstage: false));
      final siti = tester.getTopLeft(find.byKey(const Key('summary-order-$sitiDelivering')));
      expect(aming.dy, lessThan(siti.dy));
      expect(find.text('士古来'), findsOneWidget);
      expect(find.text('2. Kedai Runcit Siti'), findsOneWidget);
      expect(find.text('白色塑料汤匙  ×5 包'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('summary-share')));
      expect(device.calls, contains('share 送货单 11月25日周三'));
      expect(device.shared.single, contains('*拣货单*\n- 16安士 PP杯 95口径 ×3 箱 (一箱 1000 个)'));
      expect(device.shared.single, contains('2. Kedai Runcit Siti · JHB261125-00003'));

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('summary-print')));
        // 打印要读字体、做 PDF：等它做完
        for (var i = 0; i < 100 && device.printed.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect(device.calls, contains('print delivery-2026-11-25.pdf'));
      expect(String.fromCharCodes(device.printed.single.take(5)), '%PDF-');
    });

    testWidgets('换日子：后一天没有单（不能打印），再回前一天', (tester) async {
      await startSeller(tester);
      routerOf(tester).push('/seller/summary');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('summary-print')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('summary-next-day')));
      await settle(tester);
      expect(find.text('11月26日周四'), findsOneWidget);
      expect(find.text('这天没有要送的单'), findsOneWidget);
      expect(find.byKey(const Key('summary-print')), findsNothing);
      expect(find.byKey(const Key('summary-share')), findsNothing);

      await tapAndSettle(tester, find.byKey(const Key('summary-prev-day')));
      await settle(tester);
      expect(find.text('11月25日周三'), findsOneWidget);
      expect(find.text('2 张单，总额 RM579.00'), findsOneWidget);
    });

    testWidgets('从通知打开 ?date=：直接看那一天；还有没确认的 → 去确认', (tester) async {
      await startSeller(tester);
      routerOf(tester).push('/seller/summary?date=2026-11-25');
      await tester.pumpAndSettle();
      expect(find.text('11月25日周三'), findsOneWidget);
      await tapAndSettle(tester, find.text('去确认'));
      expect(routerOf(tester).state.uri.toString(), '/seller/orders?tab=pending');
    });

    testWidgets('确认了一张今天送的单：送货单跟着变', (tester) async {
      final api = await startSeller(tester);
      routerOf(tester).push('/seller/summary');
      await tester.pumpAndSettle();
      api.sellerData.confirm('1cf81f7b-9e34-42dd-9f8e-fe096bcf807c', const []); // WhatsApp 那边按了确认
      api.simulateOrderChange();
      await settle(tester);
      expect(find.text('3 张单，总额 RM770.00'), findsOneWidget);
      expect(find.text('还有 1 张没确认'), findsOneWidget);
    });
  });

  group('商品', () {
    testWidgets('列表：价钱 / 单位、包装、库存（颜色 + 文字）；搜索和筛选', (tester) async {
      await startSeller(tester);
      await tapAndSettle(tester, find.byKey(const Key('seller-products')));
      expect(find.text('商品和价钱'), findsOneWidget);
      expect(find.text('RM85.00 / 箱'), findsOneWidget);
      expect(find.text('一箱 1000 个'), findsWidgets);
      expect(find.widgetWithText(LabelChip, '快卖完'), findsOneWidget);
      await scrollTo(tester, find.text('黑色吸管 6mm 独立包'));
      expect(find.text('一包 250 个 · 最少买 2 包'), findsOneWidget, reason: '吸管：起订量 2');
      final oos = tester.widget<LabelChip>(find.widgetWithText(LabelChip, '缺货'));
      expect(oos.color, AppTheme.stockColor(StockStatus.outOfStock));

      await tapAndSettle(tester, find.byKey(const Key('products-filter-outOfStock')));
      expect(find.byType(ProductCard), findsOneWidget);
      expect(find.text('黑色吸管 6mm 独立包'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('products-filter-draft')));
      expect(find.text('找不到符合的商品'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('products-filter-all')));
      await tester.enterText(find.byKey(const Key('products-search')), '汤匙');
      await tester.pumpAndSettle();
      expect(find.byType(ProductCard), findsOneWidget);
      expect(find.text('白色塑料汤匙'), findsOneWidget);
    });

    testWidgets('「缺货」只算上架中的（跟首页一样）：下架了的缺货商品不算、不列出来', (tester) async {
      final api = await startSeller(tester);
      final straw = api.sellerData.products().firstWhere((p) => p.name == '黑色吸管 6mm 独立包').id;
      // 老板把缺货的吸管下架了（库存还是缺货）
      api.sellerData.updateProduct(straw, {'status': 'archived'});
      api.simulateOrderChange(); // 首页重新读
      await settle(tester);
      expect(find.text('上架 5 样 · 1 样快卖完'), findsOneWidget, reason: '首页：没有缺货的');
      await tapAndSettle(tester, find.byKey(const Key('seller-products')));
      expect(find.text('缺货（0）'), findsOneWidget, reason: '跟首页一样是 0');
      await tapAndSettle(tester, find.byKey(const Key('products-filter-outOfStock')));
      expect(find.byType(ProductCard), findsNothing);
      expect(find.text('找不到符合的商品'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('products-filter-all')));
      await scrollTo(tester, find.text('黑色吸管 6mm 独立包'));
      expect(find.widgetWithText(LabelChip, '已下架'), findsOneWidget, reason: '「全部」照样看得到');
    });

    testWidgets('改价钱 RM12.50（存成 1250 仙）、改成缺货', (tester) async {
      final api = await startSeller(tester);
      await tapAndSettle(tester, find.byKey(const Key('seller-products')));
      await tapAndSettle(tester, find.byKey(const Key('product-$cup16')));
      expect(find.text('改商品'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('product-price'))).controller!.text, '85.00');
      expect(find.text('一箱多少钱？'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('product-price')), '12.50');
      await tapKey(tester, 'stock-out_of_stock');
      await tapAndSettle(tester, find.byKey(const Key('product-save')));
      await settle(tester);

      expect(api.calls, contains('saveProduct 16安士 PP杯 95口径 1250'));
      final saved = api.sellerData.product(cup16);
      expect(saved.priceSen, 1250);
      expect(saved.stockStatus, StockStatus.outOfStock);
      expect(saved.packQty, 1000, reason: '没改的照旧');
      expect(find.text('保存好了'), findsOneWidget);
      // 回到列表
      expect(find.text('RM12.50 / 箱'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('product-$cup16')), matching: find.widgetWithText(LabelChip, '缺货')),
        findsOneWidget,
      );
    });

    testWidgets('价钱打 4.35、0.29（double 会算错的）：存进去一定是 435、29 仙', (tester) async {
      final api = await startSeller(tester);
      for (final (text, sen) in [('4.35', 435), ('0.29', 29)]) {
        routerOf(tester).push('/seller/products/$lid95');
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('product-price')), text);
        await tapAndSettle(tester, find.byKey(const Key('product-save')));
        await settle(tester);
        expect(api.sellerData.product(lid95).priceSen, sen);
      }
      // 不能打 3 位小数、字母
      routerOf(tester).push('/seller/products/$lid95');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('product-price')), '1.234');
      expect(tester.widget<TextField>(find.byKey(const Key('product-price'))).controller!.text, isNot('1.234'));
    });

    testWidgets('新增商品：没填好先说哪里不对，填好了才保存', (tester) async {
      final api = await startSeller(tester);
      await tapAndSettle(tester, find.byKey(const Key('seller-products')));
      await tapAndSettle(tester, find.byKey(const Key('products-add')));
      expect(find.text('新增商品'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('product-save')));
      expect(find.text('还有资料没填好，请看红色的地方'), findsOneWidget);
      expect(find.text('请写商品名字'), findsOneWidget);
      expect(find.text('请写价钱，例如 12.50'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('saveProduct')), isEmpty);

      await tester.enterText(find.byKey(const Key('product-name')), '1000ml 牛皮纸碗');
      await tapKey(tester, 'unit-pack');
      expect(find.text('一包多少钱？'), findsOneWidget, reason: '跟着选的单位');
      await tester.enterText(find.byKey(const Key('product-price')), '4.35');
      await scrollToKey(tester, 'product-pack');
      await tester.enterText(find.byKey(const Key('product-pack')), '50');
      await scrollToKey(tester, 'product-min-qty');
      await tapAndSettle(
        tester,
        find.descendant(of: find.byKey(const Key('product-min-qty')), matching: find.byIcon(Icons.add)),
      );
      await tapAndSettle(tester, find.byKey(const Key('product-save')));
      await settle(tester);

      expect(api.calls, contains('saveProduct 1000ml 牛皮纸碗 435'));
      final p = api.sellerData.products().firstWhere((p) => p.name == '1000ml 牛皮纸碗');
      expect((p.unit, p.packQty, p.minOrderQty, p.status), (SellUnit.pack, 50, 2, ProductStatus.active));
      expect(find.text('RM4.35 / 包'), findsOneWidget);
    });

    testWidgets('下架：列表标「已下架」，首页上架数字少一样', (tester) async {
      final api = await startSeller(tester);
      await tapAndSettle(tester, find.byKey(const Key('seller-products')));
      await tapAndSettle(tester, find.byKey(const Key('product-$lid95')));
      await tapKey(tester, 'status-archived');
      expect(find.text('下架了买家就看不到，以后可以再上架'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('product-save')));
      await settle(tester);
      expect(api.sellerData.product(lid95).status, ProductStatus.archived);
      await scrollTo(tester, find.byKey(const Key('product-$lid95')));
      expect(find.widgetWithText(LabelChip, '已下架'), findsOneWidget);
      await back(tester);
      expect(find.text('上架 5 样 · 1 样缺货 · 1 样快卖完'), findsOneWidget);
    });

    testWidgets('商品照片：选一张，保存时上传，路径存进 photo_paths', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg, name: 'photo.jpg');
      final api = await startSeller(tester, device: device);
      routerOf(tester).push('/seller/products/$lid95');
      await tester.pumpAndSettle();
      await tapKey(tester, 'photo-gallery');
      expect(device.calls, ['pickImage gallery productPhoto 1600 85']);
      expect(find.byKey(const Key('product-photo')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('product-save')));
      await settle(tester);
      expect(api.calls, containsAllInOrder(['uploadPhoto jpg', 'saveProduct 95 平盖 4500']));
      final paths = api.sellerData.product(lid95).photoPaths;
      expect(paths, hasLength(1));
      expect(paths.single, startsWith('${api.sellerData.wholesalerId}/'));
      expect(api.demoPhotos[paths.single], jpeg);

      // 不是照片（HEIC）：不收。先等「保存好了」消失（不然会挡住底下的按钮）
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      device.nextImage = PickedFile.memory(heic);
      routerOf(tester).push('/seller/products/$cup16');
      await tester.pumpAndSettle();
      await tapKey(tester, 'photo-camera');
      expect(find.text('照片只收 JPG、PNG、WebP，最多 5 MB'), findsOneWidget);
      expect(find.byKey(const Key('product-photo')), findsNothing);
    });
  });

  group('上传价目表', () {
    testWidgets('选照片 → 上传 → 等 AI → 一行一行确认 → 不完整的那一行跳过去 → 补好 → 确认上架', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg, name: 'IMG_0001.HEIC');
      final api = await startSeller(tester, device: device);
      await openImport(tester);
      expect(find.text('上传价目表'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('import-gallery')));

      expect(device.calls, ['pickImage gallery priceList 2576 85']);
      expect(api.calls, containsAllInOrder(['upload jpg image/jpeg', 'createImport image', 'startParse']));
      expect(routerOf(tester).state.uri.path, startsWith('/seller/import/'));
      expect(find.text('检查价目表'), findsOneWidget);
      expect(find.text('共 6 行：新增 2、更新 2、跳过 2'), findsOneWidget);
      expect(find.text('有 2 行 AI 不太肯定，请检查黄色的'), findsOneWidget);
      expect(find.text('会更新：16安士 PP杯 95口径 · 现在 RM85.00'), findsOneWidget);
      expect(find.text('确认上架（4 样）'), findsOneWidget);

      // 第 5 行（背心袋，看不清价钱）：改成新增 → 还缺包装数量、价钱
      await tapKey(tester, 'row-5-create');
      expect(api.calls, contains('updateRow $vestBagRow create'));
      await settle(tester);
      expect(find.text('还缺：包装数量、价钱'), findsOneWidget);
      expect(find.text('确认上架（5 样）'), findsOneWidget);

      // 上面写着还有几行没填好
      expect(find.byKey(const Key('review-incomplete')), findsOneWidget);
      // 先按确认上架：App 自己先检查，第 5 行没填好 → 说还有几行、跳到那一行，框红色（不用一次问一次服务器）
      await tapAndSettle(tester, find.byKey(const Key('review-apply')));
      expect(find.text('还有 1 行没填好（红色的）。请填好，或选「跳过」。'), findsNWidgets(2), reason: '上面的提示 + 底下的消息');
      expect(api.applyAttempts, 0, reason: '没填好的不用问服务器');
      expect(api.sellerData.currentImport.status, ImportStatus.review, reason: '什么都没上架');
      expect(api.sellerData.product(cup16).priceSen, 8500);
      final row5 = tester.widget<Container>(find.byKey(const Key('import-row-5')));
      expect(((row5.decoration! as BoxDecoration).border! as Border).top.color, AppTheme.problem);
      expect(tester.getRect(find.byKey(const Key('import-row-5'))).top, lessThan(860), reason: '跳到看得见');

      // 改第 5 行：价钱 15、一包 100 个
      await tapAndSettle(tester, find.byKey(const Key('row-5-edit')));
      expect(find.text('改第 5 行'), findsOneWidget);
      await sheetScrollTo(tester, find.byKey(const Key('row-edit-price')));
      await tester.enterText(find.byKey(const Key('row-edit-price')), '15');
      await sheetScrollTo(tester, find.byKey(const Key('row-edit-pack')));
      await tester.enterText(find.byKey(const Key('row-edit-pack')), '100');
      await tapAndSettle(tester, find.byKey(const Key('row-edit-save')));
      await settle(tester);
      expect(api.calls.where((c) => c == 'updateRow $vestBagRow create'), hasLength(2));
      expect(find.text('还缺：包装数量、价钱'), findsNothing);

      await tapAndSettle(tester, find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(api.calls, contains('applyImport 3 2 1'));
      expect(find.text('上架好了：新增 3 样，更新 2 样'), findsOneWidget);
      expect(routerOf(tester).state.uri.path, '/seller/products');
      await scrollTo(tester, find.text('背心袋 (中)'));
      expect(find.text('RM15.00 / 包'), findsOneWidget);
      expect(api.sellerData.product(cup16).priceSen, 8600, reason: '第 1 行更新了价钱');
    });

    testWidgets('跳过：不会上架；没对到商品的行按「更新」先选是哪一样（取消就不改）', (tester) async {
      final api = await startSeller(tester);
      // 首页：AI 读好了 → 直接到确认页
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      expect(find.text('检查价目表'), findsOneWidget);
      await tapKey(tester, 'row-3-update');
      expect(find.text('要更新哪一样商品？'), findsOneWidget, reason: '第 3 行没有对到商品：先选');
      await tapAndSettle(tester, find.byKey(const Key('choose-cancel')));
      expect(api.calls.where((c) => c.startsWith('updateRow')), isEmpty);
      await tapKey(tester, 'row-1-skip');
      await settle(tester);
      expect(find.text('确认上架（3 样）'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(api.calls, contains('applyImport 2 1 3'));
      expect(api.sellerData.product(cup16).priceSen, 8500, reason: '跳过的不改');
    });

    testWidgets('HEIC 文件、太大的文件：不上传，说清楚原因', (tester) async {
      final device = FakeDevice()..nextFile = PickedFile.memory(heic, name: 'IMG_0002.HEIC');
      final api = await startSeller(tester, device: device);
      await openImport(tester);
      await tapAndSettle(tester, find.byKey(const Key('import-file')));
      expect(device.calls, ['pickFile pdf,xlsx,xls,csv']);
      expect(find.textContaining('HEIC 照片，AI 看不懂'), findsOneWidget);

      device.nextFile = PickedFile(name: 'big.pdf', size: priceListMaxBytes + 1, read: () async => Uint8List(0));
      await tapAndSettle(tester, find.byKey(const Key('import-file')));
      expect(find.text('文件太大了（最多 10 MB）'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
      expect(find.byKey(const Key('import-camera')), findsOneWidget, reason: '还在选的画面');

      // 不准用相机
      device.pickError = const AppError('NO_PERMISSION');
      await tapAndSettle(tester, find.byKey(const Key('import-camera')));
      expect(find.text('请到手机的「设定」，允许这个 App 用相机和照片'), findsOneWidget);
    });

    testWidgets('AI 读不到：每个原因有自己的说明（太长 / 不肯读 / 文件打不开 / 服务出问题 / 其他），可以再上传一次', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg);
      final api = await startSeller(tester, device: device);
      await openImport(tester);
      for (final (code, text) in [
        ('AI_TRUNCATED', '价目表太长，AI 读不完。请分成几张照片或几个文件，一份一份上传。'),
        ('TOO_MANY_ROWS', '这个表格太长了（最多大约 1200 样商品）。请分成几个文件，一份一份上传。'),
        ('AI_REFUSED', 'AI 不肯读这份文件。请确认是价目表，再试一次。'),
        ('UNSUPPORTED_FILE', '这种文件看不懂。请拍照，或选 Excel、PDF、CSV 文件。'),
        ('SPREADSHEET_UNREADABLE', '这个 Excel 文件打不开（可能坏了或设了密码）。请在电脑上打开，另存成 .xlsx 再上传，或拍照上传。'),
        ('AI_BUSY', '现在很多人在用 AI，排不到。请等 5 分钟再上传一次。'),
        ('START_FAILED', '这份价目表没有开始读（叫不到 AI）。请再上传一次。'),
        ('FILE_TOO_LARGE', '照片太大了（最多 7 MB）。请用「拍照」重新拍，或选小一点的照片。'),
        ('SOMETHING_ELSE', 'AI 读不懂这份价目表。请拍清楚一点再试一次。'),
      ]) {
        api.sellerData.nextImportError = code;
        await tapAndSettle(tester, find.byKey(const Key('import-camera')));
        expect(find.byKey(const Key('import-failed')), findsOneWidget);
        expect(find.text('AI 读不到这份价目表'), findsOneWidget);
        expect(find.text(text), findsOneWidget, reason: code);
        await tapAndSettle(tester, find.byKey(const Key('import-retry')));
        expect(find.byKey(const Key('import-camera')), findsOneWidget);
      }
    });

    testWidgets('等的时候先回首页；首页显示「AI 在读」，读好了首页自己变成「去确认」（不用拉下来刷新）', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg);
      final api = await startSeller(tester, device: device);
      api.sellerData.pollsToFinish = 8; // 读久一点：回到首页的时候还在读
      await openImport(tester);
      await tester.tap(find.byKey(const Key('import-camera')));
      await pumpUntil(tester, find.byKey(const Key('import-leave')));
      expect(find.text('通常要 1 到 3 分钟。你可以先离开这一页，读好了首页会告诉你。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('import-leave')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('AI 正在读你的价目表…'), findsOneWidget, reason: '首页的「上传价目表」');

      // 老板就停在首页：AI 读好了，首页自己会说
      await pumpUntil(tester, find.text('AI 读好了，去确认上架'), max: 80);
      expect(find.text('AI 正在读你的价目表…'), findsNothing);
      await tester.tap(find.byKey(const Key('seller-import')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(routerOf(tester).state.uri.path, startsWith('/seller/import/'));
      expect(find.text('检查价目表'), findsOneWidget);
    });
  });

  testWidgets('马来文 + 系统大字（1.3 倍）：送货单、商品、价目表都不会撑爆', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final device = FakeDevice()..nextImage = PickedFile.memory(jpeg);
    await startSeller(tester, locale: 'ms', device: device);

    routerOf(tester).push('/seller/summary');
    await tester.pumpAndSettle();
    expect(find.text('Kongsi dengan pemandu'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('summary-order-$sitiDelivering')));
    await back(tester);

    await tapAndSettle(tester, find.byKey(const Key('seller-products')));
    expect(find.text('Tambah barang'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('products-filter-outOfStock')));
    await tapAndSettle(tester, find.byKey(const Key('products-filter-all')));
    await tapAndSettle(tester, find.byKey(const Key('products-add')));
    await tapAndSettle(tester, find.byKey(const Key('product-save')));
    await scrollToKey(tester, 'unit-kg');
    await scrollToKey(tester, 'stock-out_of_stock');
    await scrollToKey(tester, 'photo-gallery');
    await back(tester);
    await back(tester);

    await openImport(tester);
    await scrollTo(tester, find.text('Pilih fail (Excel, PDF)'));
    await tapAndSettle(tester, find.byKey(const Key('import-gallery')));
    expect(find.text('Semak senarai harga'), findsOneWidget);
    await scrollToKey(tester, 'row-6-edit');
    await tapAndSettle(tester, find.byKey(const Key('row-6-edit')));
    await sheetScrollTo(tester, find.byKey(const Key('row-edit-min-qty')));
    await tapAndSettle(tester, find.byKey(const Key('row-edit-cancel')));
    expect(find.text('Jual 4 barang'), findsOneWidget);
  });

  // 每一页都滚到底（看不到的部分也排版过），三种语言、系统大字 1.3 倍。撑爆的话 Flutter 会报错，测试失败
  for (final lang in ['zh', 'en', 'ms']) {
    testWidgets('$lang + 大字（1.3 倍）：订单、送货单、商品、价目表每一页滚到底都不会撑爆', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await startSeller(tester, locale: lang);
      for (final path in [
        '/seller/orders?tab=today',
        '/seller/orders?tab=all',
        '/seller/orders/$sitiDelivering',
        '/seller/summary',
        '/seller/summary?date=2026-11-26',
        '/seller/products',
        '/seller/products/new',
        '/seller/products/$cup16',
        '/seller/import',
        '/seller/import/00000000-0000-4000-d000-000000000001',
      ]) {
        routerOf(tester).push(path);
        await tester.pumpAndSettle();
        await settle(tester);
        for (var i = 0; i < 12; i++) {
          await tester.drag(pageScrollable, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        routerOf(tester).pop();
        await tester.pumpAndSettle();
      }
    });
  }
}
