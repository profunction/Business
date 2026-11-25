// 价目表导入不会把老板困住：传错了、全部跳过、AI 一直没读（叫 AI 的时候断线）、等太久，都可以上传另一份；
// 卡住的会再叫一次 AI；首页自己知道 AI 读好了。确认页：存好一行之前不能上架、自己选要更新哪样商品、
// 讲清楚会重新上架 / 改包装。Android 把 App 关掉前选的价目表会拿回来上传。手机宽度 400，撑爆就失败。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/features/seller/seller_device.dart';
import 'package:jb_wholesale/widgets/common.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'seller_harness.dart';

const cup16 = '820eff6d-5979-4fd3-aeff-5945edbd4894'; // 16安士 PP杯 95口径（第 1 行对到）
const lid95 = '163974ab-06dc-43e6-9a95-8c0036ba3ba1'; // 95 平盖（第 2 行对到）

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 7)]);

Future<void> pumpUntil(WidgetTester tester, Finder f, {int max = 60}) async {
  for (var i = 0; i < max && f.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(f, findsWidgets);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await scrollTo(tester, find.byKey(Key(key)));
  await tapAndSettle(tester, find.byKey(Key(key)));
}

String productId(DemoApi api, String name) => api.sellerData.products().firstWhere((p) => p.name == name).id;

PriceListImportRow row(DemoApi api, int rowNo) =>
    api.sellerData.rows(api.sellerData.currentImport.id).firstWhere((r) => r.rowNo == rowNo);

/// 叫 AI 的时候断线了：服务器上有一份 processing、从来没人开始读（ai_raw 是空的）的导入，建好了 [age]
Future<void> stuckImport(WidgetTester tester, DemoApi api, {Duration age = const Duration(minutes: 2)}) async {
  api.sellerData
    ..createImport('${api.sellerData.wholesalerId}/x.jpg', ImportFileType.image)
    ..backdateImport(age);
  api.simulateOrderChange(); // 首页重新读
  await settle(tester);
}

void main() {
  group('不会被困住', () {
    testWidgets('传错了、全部都跳过：「确认上架（0 样）」按不了，但可以上传另一份；之后首页去新的那一份', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg);
      final api = await startSeller(tester, device: device);
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      for (final n in [1, 2, 3, 4]) {
        await tapKey(tester, 'row-$n-skip');
        await settle(tester);
      }
      expect(find.text('确认上架（0 样）'), findsOneWidget);
      expect(tester.widget<BusyButton>(find.byKey(const Key('review-apply'))).onPressed, isNull);

      await tapAndSettle(tester, find.byKey(const Key('review-upload-other')));
      expect(routerOf(tester).state.uri.toString(), '/seller/import');
      await tapAndSettle(tester, find.byKey(const Key('import-gallery')));
      await settle(tester);
      expect(routerOf(tester).state.uri.path, startsWith('/seller/import/'));
      expect(find.text('确认上架（4 样）'), findsOneWidget, reason: '新的那一份');
      await back(tester);
      expect(find.text('AI 读好了，去确认上架'), findsOneWidget);
      expect(api.sellerData.currentImport.status, ImportStatus.review);
    });

    testWidgets('叫 AI 的时候断线（一直显示「AI 在读」）：首页自己再叫一次 AI，读好了就说', (tester) async {
      final api = await startSeller(tester);
      api.sellerData.pollsToFinish = 3;
      await stuckImport(tester, api);
      expect(find.text('AI 正在读你的价目表…'), findsOneWidget);
      await pumpUntil(tester, find.text('AI 读好了，去确认上架'));
      expect(api.sellerData.startParseCount, 1, reason: '只叫一次（同一份只会有一个在读）');
    });

    testWidgets('卡住了、再叫 AI 也叫不动（例如函数没设定好）：标成读不到，首页让老板重新上传', (tester) async {
      final api = await startSeller(tester);
      api.sellerData.nextStartError = 'CONFIG_MISSING';
      await stuckImport(tester, api);
      await pumpUntil(tester, find.text('上次的读不到，请再上传一次'));
      expect(api.sellerData.currentImport.status, ImportStatus.failed);
      expect(api.sellerData.currentImport.errorMessage, 'START_FAILED');
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      expect(routerOf(tester).state.uri.toString(), '/seller/import');
      expect(find.byKey(const Key('import-camera')), findsOneWidget);
    });

    testWidgets('等的页面：AI 一直在读（等太久）也可以「上传另一份」，不会只剩「回首页」', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg);
      final api = await startSeller(tester, device: device);
      api
        ..pollTimeout = const Duration(seconds: 2)
        ..sellerData.pollsToFinish = 100000; // 一直读不完
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      await tapAndSettle(tester, find.byKey(const Key('review-upload-other')));
      await tester.tap(find.byKey(const Key('import-camera')));
      await pumpUntil(tester, find.byKey(const Key('import-upload-other')));
      expect(find.byKey(const Key('import-leave')), findsOneWidget);
      // 等到 2 秒（示范模式的上限）：还在读
      await pumpUntil(tester, find.byKey(const Key('import-timeout')));
      expect(find.text('AI 还没读完。请过几分钟再回来看。'), findsOneWidget);
      expect(find.byKey(const Key('import-upload-other')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('import-upload-other')));
      expect(find.byKey(const Key('import-camera')), findsOneWidget, reason: '回到三个大按钮');
      api.sellerData.pollsToFinish = 2;
      await tapAndSettle(tester, find.byKey(const Key('import-camera')));
      await settle(tester);
      expect(find.text('检查价目表'), findsOneWidget);
    });

    testWidgets('从首页回去等一份卡住的：等的时候就可以上传另一份；确认页的「AI 在读」也可以', (tester) async {
      final device = FakeDevice()..nextImage = PickedFile.memory(jpeg);
      final api = await startSeller(tester, device: device);
      api.sellerData.pollsToFinish = 100000;
      await stuckImport(tester, api);
      final stuckId = api.sellerData.currentImport.id;
      await tester.tap(find.byKey(const Key('seller-import')));
      await pumpUntil(tester, find.byKey(const Key('import-upload-other')));
      expect(routerOf(tester).state.uri.toString(), '/seller/import?id=$stuckId');
      // 等的画面一直在转：不能 pumpAndSettle
      await tester.tap(find.byKey(const Key('import-upload-other')));
      await pumpUntil(tester, find.byKey(const Key('import-camera')));
      await tester.pumpAndSettle();
      await back(tester);

      // 确认页（例如从旧的链接打开）：还在读的那一份
      routerOf(tester).push('/seller/import/$stuckId');
      await tester.pump(const Duration(milliseconds: 400));
      await pumpUntil(tester, find.byKey(const Key('review-upload-other')));
      expect(find.byKey(const Key('review-wait')), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-upload-other')));
      await pumpUntil(tester, find.byKey(const Key('import-camera')));
      expect(routerOf(tester).state.uri.toString(), '/seller/import');
      api.sellerData.pollsToFinish = 2;
      await tapAndSettle(tester, find.byKey(const Key('import-camera')));
      await settle(tester);
      expect(find.text('检查价目表'), findsOneWidget);
      expect(api.sellerData.currentImport.id, isNot(stuckId));
    });

    testWidgets('查进度时找不到那一份：不说「AI 读不到」，说查不到；可以再上传', (tester) async {
      await startSeller(tester);
      routerOf(tester).push('/seller/import?id=00000000-0000-4000-9000-000000000099');
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const Key('import-failed')), findsOneWidget);
      expect(find.text('查不到这份价目表读得怎样'), findsOneWidget);
      expect(find.text('AI 读不到这份价目表'), findsNothing);
      expect(find.text('找不到，可能已经被删掉了'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('import-retry')));
      expect(find.byKey(const Key('import-camera')), findsOneWidget);
    });
  });

  group('确认页', () {
    testWidgets('按了「跳过」还在存：「确认上架」按不了（不会上架刚跳过的那一行），存好了才可以', (tester) async {
      final api = await startSeller(tester);
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      await scrollTo(tester, find.byKey(const Key('row-1-skip')));
      await tester.tap(find.byKey(const Key('row-1-skip')));
      await tester.pump(const Duration(milliseconds: 50)); // 还没存好（示范资料要 150ms）
      expect(tester.widget<BusyButton>(find.byKey(const Key('review-apply'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('review-apply')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.applyAttempts, 0);

      await settle(tester);
      expect(find.text('确认上架（3 样）'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(api.calls, contains('applyImport 2 1 3'));
      expect(api.sellerData.product(cup16).priceSen, 8500, reason: '跳过的那一行没有上架');
    });

    testWidgets('自己选要更新哪样商品：没对到的可以选、对到的可以换或清掉；下架的会重新上架、包装会改，都写出来', (tester) async {
      final api = await startSeller(tester);
      final cup22 = productId(api, '22安士 PP杯 95口径'); // RM98.00，一箱 1000 个
      final box650 = productId(api, '650ml 长方饭盒连盖'); // 一箱 300 个
      api.sellerData.updateProduct(box650, {'status': 'archived'}); // 老板之前下架了
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));

      // 第 3 行（1000ml 牛皮纸碗，一箱 300 个）：AI 没对到 → 按「更新」选 22安士 PP杯
      await tapKey(tester, 'row-3-update');
      expect(find.text('要更新哪一样商品？'), findsOneWidget);
      expect(find.text('第 1 行已经对到这样'), findsOneWidget, reason: '16安士 PP杯');
      expect(find.byKey(const Key('choose-none')), findsNothing, reason: '本来就没对到');
      await tester.enterText(find.byKey(const Key('choose-search')), '22安士');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(Key('choose-product-$cup22')));
      await settle(tester);
      expect(api.calls, contains('updateRow ${row(api, 3).id} update'));
      expect(row(api, 3).matchedProductId, cup22);
      await scrollTo(tester, find.byKey(const Key('row-3-choose')));
      expect(find.text('会更新：22安士 PP杯 95口径 · 现在 RM98.00'), findsOneWidget);
      expect(find.text('包装会改：一箱 1000 个 → 一箱 300 个'), findsOneWidget);

      // 第 4 行（珍珠奶茶吸管，一包 100 支）：选下架了的饭盒 → 会重新上架、包装也会改
      await tapKey(tester, 'row-4-update');
      await scrollToSheet(tester, find.byKey(Key('choose-product-$box650')));
      await tapAndSettle(tester, find.byKey(Key('choose-product-$box650')));
      await settle(tester);
      await scrollTo(tester, find.byKey(const Key('row-4-choose')));
      expect(find.text('现在是「已下架」，确认后会上架给买家看'), findsOneWidget);
      expect(find.text('包装会改：一箱 300 个 → 一包 100 个'), findsOneWidget);

      // 第 1 行：AI 对错了 → 「都不是」→ 当新商品
      await tapKey(tester, 'row-1-choose');
      await tapAndSettle(tester, find.byKey(const Key('choose-none')));
      await settle(tester);
      expect(row(api, 1).matchedProductId, isNull);
      expect(row(api, 1).action, ImportRowAction.create);

      expect(find.text('确认上架（4 样）'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(api.calls, contains('applyImport 1 3 2'));
      final updated = api.sellerData.product(cup22);
      expect((updated.priceSen, updated.packQty), (12800, 300), reason: '第 3 行改了 22安士 PP杯');
      expect(api.sellerData.product(box650).status, ProductStatus.active, reason: '重新上架了');
      expect(api.sellerData.product(cup16).priceSen, 8500, reason: '第 1 行清掉了，不改旧的');
    });

    testWidgets('原文（对照 AI 读得对不对）的字跟其他字一样大：最少 18', (tester) async {
      await startSeller(tester);
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      final raw = tester.widget<Text>(find.byKey(const Key('row-1-raw')));
      final style = DefaultTextStyle.of(tester.element(find.byKey(const Key('row-1-raw')))).style.merge(raw.style);
      expect(style.fontSize, greaterThanOrEqualTo(18));
    });
  });

  group('首页、订单跟着服务器', () {
    testWidgets('App 在背景时来了新订单（Realtime 断线，不会补发）：回到前台就重新读', (tester) async {
      final api = await startSeller(tester);
      expect(find.text('新订单（2）'), findsOneWidget);
      // App 到背景
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
      api.sellerData.confirm('1cf81f7b-9e34-42dd-9f8e-fe096bcf807c', const []); // 在 WhatsApp 按了确认
      await settle(tester);
      expect(find.text('新订单（2）'), findsOneWidget, reason: '还在背景：没有人告诉 App');
      // 回到前台
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await settle(tester);
      expect(find.text('新订单（1）'), findsOneWidget);
    });

    testWidgets('「今天要送」读不到首页（没网络）：按「再试一次」连首页一起重读，网络好了就看得到', (tester) async {
      final api = await startSeller(tester);
      api.sellerHomeError = const AppError('NETWORK');
      api.simulateOrderChange(); // 首页重新读：失败
      await settle(tester);
      routerOf(tester).push('/seller/orders?tab=today');
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('连不上网络，请检查网络再试'), findsWidgets);

      api.sellerHomeError = null; // 网络好了
      await tapAndSettle(tester, find.widgetWithText(FilledButton, '再试一次'));
      await settle(tester);
      expect(find.byKey(const Key('seller-order-5c372e2f-2712-415e-bfdb-314c0d0985a3')), findsOneWidget);
    });
  });

  testWidgets('Android 在选价目表的时候把 App 关掉了：重新打开，首页拿回那张照片直接上传', (tester) async {
    final device = FakeDevice()..lostPriceList = PickedFile.memory(jpeg, name: 'IMG_0001.jpg');
    final api = await startSeller(tester, device: device, settle: false);
    await tester.pump();
    await pumpUntil(tester, find.text('刚才选的价目表找回来了，正在上传'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(device.calls, contains('recoverLostPriceList'));
    expect(api.calls, containsAllInOrder(['upload jpg image/jpeg', 'createImport image', 'startParse']));
    expect(routerOf(tester).state.uri.path, startsWith('/seller/import/'));
    expect(find.text('检查价目表'), findsOneWidget);
  });

  for (final lang in ['en', 'ms']) {
    testWidgets('$lang + 大字（1.3 倍）：「上传另一份」、选商品、会重新上架、等的画面都不会撑爆', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final device = FakeDevice();
      final api = await startSeller(tester, locale: lang, device: device);
      api.sellerData.updateProduct(productId(api, '650ml 长方饭盒连盖'), {'status': 'archived'});
      await scrollTo(tester, find.byKey(const Key('seller-import')));
      await tapAndSettle(tester, find.byKey(const Key('seller-import')));
      await tapKey(tester, 'row-3-update');
      final box650 = find.byKey(Key('choose-product-${productId(api, '650ml 长方饭盒连盖')}'));
      await scrollToSheet(tester, box650);
      await tapAndSettle(tester, box650);
      await settle(tester);
      await scrollTo(tester, find.byKey(const Key('row-3-choose')));
      await tapKey(tester, 'row-1-choose');
      expect(find.byKey(const Key('choose-none')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('choose-cancel')));
      await tapAndSettle(tester, find.byKey(const Key('review-upload-other')));
      expect(find.byKey(const Key('import-camera')), findsOneWidget);

      // 等的画面、等太久的画面（两个按钮）
      api
        ..pollTimeout = const Duration(seconds: 2)
        ..sellerData.pollsToFinish = 100000;
      device.nextImage = PickedFile.memory(jpeg);
      await tester.tap(find.byKey(const Key('import-camera')));
      await pumpUntil(tester, find.byKey(const Key('import-upload-other')));
      await pumpUntil(tester, find.byKey(const Key('import-timeout')));
      await tapAndSettle(tester, find.byKey(const Key('import-upload-other')));
      api.sellerData.pollsToFinish = 2;
      await tapAndSettle(tester, find.byKey(const Key('import-camera')));
      await settle(tester);
      expect(find.byKey(const Key('review-apply')), findsOneWidget);
    });
  }
}

/// 选商品的那一页（底下弹出来）里面上下滚动（搜索框里面左右滚的不算）
Future<void> scrollToSheet(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    150,
    scrollable: find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down),
        )
        .first,
  );
  await tester.pumpAndSettle();
}
