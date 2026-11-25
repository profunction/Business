// 送货单的 PDF 和分享文字：纯函数，不用打印机、不用手机（字体用 App 打包的 NotoSansSC）
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jb_wholesale/demo/demo_data.dart';
import 'package:jb_wholesale/features/seller/delivery_sheet.dart';
import 'package:jb_wholesale/l10n/app_localizations.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// packages/core/test/fixtures/delivery_summary.json（本机数据库真实回传：2 张单、4 样拣货）
DeliverySummary fixtureSummary() => DeliverySummary.fromJson(asJson(jsonDecode(demoFixtures['delivery_summary']!)));

/// 很多张单的一天（测试跨页）：样本的单复制 n 次，店名加号码。[notes]：每张单的备注是 NOTE<第几张>END
DeliverySummary bigSummary(int n, {bool notes = false}) {
  final j = asJson(jsonDecode(demoFixtures['delivery_summary']!));
  final orders = asJsonList(j['orders']);
  j['orders'] = [
    for (var i = 0; i < n; i++)
      {
        ...orders[i % orders.length],
        'id': '00000000-0000-4000-9000-${i.toString().padLeft(12, '0')}',
        'order_no': 'JHB261125-${(100 + i).toString().padLeft(5, '0')}',
        'shop': {...asJson(orders[i % orders.length]['shop']), 'name': 'Shop ${i + 1}'},
        if (notes) 'note': 'NOTE${i}END',
      },
  ];
  j['order_count'] = n;
  return DeliverySummary.fromJson(j);
}

/// 一张有很多样东西的单（超过一页也要能印）
DeliverySummary longOrder(int items) {
  final j = asJson(jsonDecode(demoFixtures['delivery_summary']!));
  final first = asJson(asJsonList(j['orders']).first);
  final item = asJson(asJsonList(first['items']).first);
  first['items'] = [
    for (var i = 0; i < items; i++) {...item, 'name': '${item['name']} #${i + 1}'},
  ];
  j['orders'] = [first];
  return DeliverySummary.fromJson(j);
}

int pages(pw.Document doc) => doc.document.pdfPageList.pages.length;

/// 每一页印了哪些字（字跟字之间没有空格）。PDF 里的中文字是字体的编号（[<0012003a>]TJ），用字体的 unicode 表换回来
Future<List<String>> pageTexts(pw.Document doc, pw.Font font) async {
  await doc.save();
  final cmap = (font.getFont(pw.Context(document: doc.document)) as PdfTtfFont).unicodeCMap.cmap;
  final run = RegExp(r'\[<([0-9a-f]+)>\]TJ');
  String decode(String hex) => String.fromCharCodes([
    for (var i = 0; i + 4 <= hex.length; i += 4) cmap[int.parse(hex.substring(i, i + 4), radix: 16)],
  ]);
  return [
    for (final page in doc.document.pdfPageList.pages)
      [
        for (final c in page.contents)
          // 页的内容是 PdfObjectStream（pdf 没有 export），它的 buf 是画的指令
          for (final m in run.allMatches(latin1.decode(((c as dynamic).buf as PdfStream).output())))
            decode(m.group(1)!),
      ].join(),
  ];
}

/// 第几页有这段字（没有 → -1）
int pageOf(List<String> texts, String text) => texts.indexWhere((t) => t.contains(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late pw.Font font;
  final zh = lookupL10n(const Locale('zh'));
  final en = lookupL10n(const Locale('en'));
  final ms = lookupL10n(const Locale('ms'));

  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await initializeDateFormatting('ms');
    font = await PdfGoogleFonts.notoSansSCRegular();
  });

  group('PDF（打印）', () {
    test('样本：做得出 PDF，一页 A4', () async {
      final s = fixtureSummary();
      final doc = deliveryPdfDocument(s, zh, font: font);
      expect(pages(doc), 1);
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, lessThan(300 * 1024), reason: '字体只嵌入用到的字');
      expect(deliveryFileName(s), 'delivery-2026-11-25.pdf');
    });

    test('buildDeliveryPdf 回传 bytes（三种语言都可以）', () async {
      for (final l in [zh, en, ms]) {
        final bytes = await buildDeliveryPdf(fixtureSummary(), l, font: font);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: l.localeName);
      }
    });

    test('很多张单：自动换页，每张单整块放在同一页', () {
      // 样本一张单大约占 1/6 页：30 张单一定超过一页
      final many = deliveryPdfDocument(bigSummary(30), zh, font: font);
      expect(pages(many), greaterThan(2));
      final more = deliveryPdfDocument(bigSummary(60), zh, font: font);
      expect(pages(more), greaterThan(pages(many)));
    });

    test('每张单的开头（店名、单号）跟最后（备注、签收）一定在同一页：放不下就整张搬到下一页，不会切开', () async {
      // 每张单一个认得出来的备注（印在最后、签收的上面）
      final withNotes = bigSummary(60, notes: true);
      final orders = withNotes.orders;
      final texts = await pageTexts(deliveryPdfDocument(withNotes, zh, font: font), font);
      expect(texts.length, greaterThan(10));
      for (final (i, o) in orders.indexed) {
        final head = pageOf(texts, o.orderNo);
        expect(head, isNot(-1), reason: o.orderNo);
        expect(pageOf(texts, 'NOTE${i}END'), head, reason: '${o.orderNo}：单的开头跟最后在不同页');
      }
    });

    test('估计放得下一页的最长的单：照样印得出来（整块的比一页还高 pdf 会出错）', () {
      // 名字很长（每样两三行）的单，加到估计刚好不超过上限
      final j = asJson(jsonDecode(demoFixtures['delivery_summary']!));
      final first = asJson(asJsonList(j['orders']).first);
      final item = asJson(asJsonList(first['items']).first);
      first['note'] = '后门进，' * 40;
      first['shop'] = {...asJson(first['shop']), 'address': 'Jalan Demo 10, Taman Molek, ' * 6};
      final items = <Object>[];
      DeliverySummary build() => DeliverySummary.fromJson({
        ...j,
        'orders': [
          {...first, 'items': items},
        ],
      });
      while (true) {
        items.add({...item, 'name': '${'很长很长的商品名字' * 6} #${items.length}'});
        if (estimatedOrderHeight(build().orders.single, zh, withZone: true) > keepTogetherMaxHeight) {
          items.removeLast();
          break;
        }
      }
      expect(items.length, greaterThan(3));
      for (final l in [zh, en, ms]) {
        final doc = deliveryPdfDocument(build(), l, font: font);
        expect(pages(doc), greaterThanOrEqualTo(1), reason: l.localeName);
      }
    });

    test('一张单有很多样东西：可以跨页，不会印不出来', () {
      expect(pages(deliveryPdfDocument(longOrder(80), zh, font: font)), greaterThan(1));
    });

    test('这天没有单：一页，写「这天没有要送的单」', () {
      final j = asJson(jsonDecode(demoFixtures['delivery_summary']!))
        ..['orders'] = <Object>[]
        ..['picking'] = <Object>[]
        ..['order_count'] = 0;
      expect(pages(deliveryPdfDocument(DeliverySummary.fromJson(j), zh, font: font)), 1);
    });
  });

  group('分享给送货员的文字', () {
    test('拣货单 + 每张单（按区）：店名、联络人、电话、地址、明细（缺货的标出来）、总额、付款方式', () {
      final text = deliveryShareText(fixtureSummary(), zh);
      expect(text, startsWith('*示范批发 A：新山包装行*\n送货单 11月25日周三\n2 张单，总额 RM579.00\n还有 2 张没确认'));
      expect(text, contains('*拣货单*\n- 16安士 PP杯 95口径 ×3 箱 (一箱 1000 个)\n'));
      expect(text, contains('- 白色塑料汤匙 ×5 包 (一包 100 个)'));
      expect(text, contains('1. 阿明茶餐室 · JHB261125-00002\n联络人：阿明\n电话：012-000 0001\n地址：Jalan Demo 10, Taman Molek'));
      expect(text, contains('- 黑色吸管 6mm 独立包 ×4 包 （缺货）'));
      expect(text, contains('总额 RM390.00\n付款方式：货到付款 / 转账'));
      expect(text, contains('*士古来*\n2. Kedai Runcit Siti · JHB261125-00003'));
      // 拣货单不算缺货的
      final picking = text.substring(text.indexOf('*拣货单*'), text.indexOf('1. '));
      expect(picking, isNot(contains('黑色吸管')));
    });

    test('马来文', () {
      final text = deliveryShareText(fixtureSummary(), ms);
      expect(text, contains('*Senarai ambil barang*'));
      expect(text, contains('2 pesanan belum disahkan'));
      expect(text, contains('(habis stok)'));
      expect(text, contains('Bayaran: Tunai semasa terima / Pindahan bank'));
    });
  });
}
