// 批发商端的三语文字：三个 ARB 的 key 一样；中文用「文件」、马来文用「barang」一致；英文的数量有单复数；
// 「去确认」在英文、马来文也说清楚是去另一页；错误代码对到对的话（登录过期不是验证码打错）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jb_wholesale/app/l10n_x.dart';
import 'package:jb_wholesale/demo/demo_data.dart';
import 'package:jb_wholesale/features/seller/delivery_sheet.dart';
import 'package:jb_wholesale/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionsHttpException;
import 'package:wholesale_core/wholesale_core.dart';

Map<String, Object?> arb(String lang) =>
    (jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map).cast<String, Object?>();

Set<String> messageKeys(Map<String, Object?> m) => m.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final zh = lookupL10n(const Locale('zh'));
  final en = lookupL10n(const Locale('en'));
  final ms = lookupL10n(const Locale('ms'));

  setUpAll(initializeDateFormatting);

  test('三个 ARB 的 key 一模一样', () {
    final keys = messageKeys(arb('zh'));
    expect(messageKeys(arb('en')), keys);
    expect(messageKeys(arb('ms')), keys);
  });

  test('用词一致：中文是「文件」（不是台湾的「档案」），马来文批发商端是「barang」', () {
    final zhArb = arb('zh');
    for (final k in messageKeys(zhArb).where((k) => k.startsWith('seller'))) {
      expect(zhArb[k], isNot(contains('档案')), reason: k);
    }
    final msArb = arb('ms');
    for (final k in messageKeys(msArb).where((k) => k.startsWith('seller'))) {
      expect((msArb[k]! as String).toLowerCase(), isNot(contains('produk')), reason: k);
    }
    expect(ms.sellerHomeProducts, 'Barang & harga');
  });

  test('送货单「还有几张没确认」旁边的按钮：是去确认（打开列表），不是直接确认', () {
    expect(zh.sellerSummaryGoConfirm, '去确认');
    expect(en.sellerSummaryGoConfirm, 'Go to confirm');
    expect(ms.sellerSummaryGoConfirm, 'Pergi sahkan');
  });

  test('数量 + 单位：英文有单复数（5 cartons、1 carton），中文、马来文不变', () {
    expect(en.qtyUnit(1, SellUnit.carton), '1 carton');
    expect(en.qtyUnit(5, SellUnit.carton), '5 cartons');
    expect(en.qtyUnit(2, SellUnit.box), '2 boxes');
    expect(en.qtyUnit(3, SellUnit.piece), '3 pieces');
    expect(en.qtyUnit(2, SellUnit.dozen), '2 dozen');
    expect(en.qtyUnit(4, SellUnit.kg), '4 kg');
    expect(zh.qtyUnit(5, SellUnit.carton), '5 箱');
    expect(ms.qtyUnit(5, SellUnit.carton), '5 karton');
    for (final u in SellUnit.values) {
      expect(zh.unitPlural(u), zh.unit(u), reason: '中文没有复数：$u');
      expect(ms.unitPlural(u), ms.unit(u), reason: '马来文这里不变：$u');
    }
    // 给送货员的文字
    final summary = DeliverySummary.fromJson(asJson(jsonDecode(demoFixtures['delivery_summary']!)));
    final text = deliveryShareText(summary, en);
    expect(text, contains('×3 cartons'));
    expect(text, isNot(contains('×3 carton ')));
  });

  test('价目表确认页的总结：英文「1 row」「6 rows」、to update、skipped', () {
    expect(en.sellerReviewSummary(1, 1, 0, 0), '1 row: 1 new, 0 to update, 0 skipped');
    expect(en.sellerReviewSummary(6, 2, 2, 2), '6 rows: 2 new, 2 to update, 2 skipped');
    expect(zh.sellerReviewSummary(6, 2, 2, 2), '共 6 行：新增 2、更新 2、跳过 2');
  });

  test('错误：登录过期（Edge Function 401）不是「验证码不对」；AI 已经在读、函数出错各有说法', () {
    for (final l in [zh, en, ms]) {
      expect(l.error(const AppError('AUTH', detail: AppError.sessionExpired)), l.sellerErrLoginExpired);
      expect(l.error(const AppError('AUTH')), l.errAuth, reason: '登录时验证码打错');
      expect(l.error(const AppError('IMPORT_ALREADY_RUNNING')), l.sellerImportStillReading);
      expect(l.error(const AppError('INTERNAL_ERROR')), l.sellerImportErrService);
      expect(l.error(const AppError('FILE_TOO_LARGE', detail: 'image')), l.sellerErrPhotoTooLarge);
      expect(l.error(const AppError('FILE_TOO_LARGE')), l.sellerErrFileTooLarge);
    }
    final e = AppError.fromFunction(const FunctionsHttpException(status: 401, details: {'error': 'UNAUTHORIZED'}));
    expect(en.error(e), en.sellerErrLoginExpired);
    expect(en.sellerErrLoginExpired, contains('log in again'));
  });

  test('iPhone 问相机 / 照片权限的说明：英文、马来文、中文都有，讲清楚价目表和商品照片都会用到', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final locs = RegExp(r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist);
    expect(locs, isNotNull);
    for (final lang in ['en', 'ms', 'zh-Hans']) {
      expect(locs!.group(1), contains('<string>$lang</string>'));
    }
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(project, contains('/* InfoPlist.strings in Resources */,'), reason: '要打包进 App');
    for (final (lang, priceList, product) in [
      ('en', 'price list', 'product'),
      ('ms', 'senarai harga', 'barang'),
      ('zh-Hans', '价目表', '商品'),
    ]) {
      expect(
        project,
        contains('path = ${lang.contains('-') ? '"$lang.lproj/InfoPlist.strings"' : '$lang.lproj/InfoPlist.strings'};'),
      );
      final strings = File('ios/Runner/$lang.lproj/InfoPlist.strings').readAsStringSync();
      for (final key in ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription']) {
        final m = RegExp('"$key" = "([^"]+)";').firstMatch(strings);
        expect(m, isNotNull, reason: '$lang $key');
        expect(m!.group(1), allOf(contains(priceList), contains(product)), reason: '$lang $key');
      }
    }
  });
}
