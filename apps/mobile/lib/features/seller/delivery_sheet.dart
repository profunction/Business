// 送货单的两种输出：给送货员的纯文字（WhatsApp 分享）和 A4 的 PDF（打印）。
// 都是纯函数：不碰手机功能、不上网，测试可以直接叫（字体由调用的人给）。
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../l10n/app_localizations.dart';

/// 送货单按送货区分组（服务器已经按区、再按店排好，这里只是照顺序切开）
List<({String zone, List<DeliveryOrder> orders})> groupByZone(DeliverySummary s, L10n l) {
  final groups = <({String zone, List<DeliveryOrder> orders})>[];
  for (final o in s.orders) {
    final zone = o.shop.zoneName.of(l.lang).trim();
    final name = zone.isEmpty ? l.sellerSummaryOtherArea : zone;
    if (groups.isEmpty || groups.last.zone != name) groups.add((zone: name, orders: []));
    groups.last.orders.add(o);
  }
  return groups;
}

/// 文件名：delivery-2026-11-26.pdf（ASCII，打印 / 存档用）
String deliveryFileName(DeliverySummary s) => 'delivery-${dateParam(s.date)}.pdf';

String _itemLine(DeliveryItem i, L10n l) =>
    '${i.name} ×${l.qtyUnit(i.qty, i.unit)}${i.isOutOfStock ? ' ${l.sellerSummaryOosMark}' : ''}';

String _terms(DeliveryOrder o, L10n l) => o.paymentTerms.map(l.paymentTerm).join(' / ');

/// 分享给送货员的文字（WhatsApp 会把 *字* 变粗体）
String deliveryShareText(DeliverySummary s, L10n l) {
  final b = StringBuffer()
    ..writeln('*${s.wholesalerName}*')
    ..writeln(l.sellerSummaryHeading(l.date(s.date)))
    ..writeln(l.sellerTodayCount(s.orderCount, formatRm(s.totalSen)));
  if (s.pendingCount > 0) b.writeln(l.sellerSummaryPending(s.pendingCount));
  if (s.isEmpty) {
    b.writeln(l.sellerSummaryEmpty);
    return b.toString().trimRight();
  }
  b
    ..writeln()
    ..writeln('*${l.sellerSummaryPicking}*');
  for (final p in s.picking) {
    b.writeln('- ${p.name} ×${l.qtyUnit(p.qty, p.unit)} (${l.packQty(l.unit(p.unit), p.packQty)})');
  }
  var n = 0;
  for (final g in groupByZone(s, l)) {
    b
      ..writeln()
      ..writeln('*${g.zone}*');
    for (final o in g.orders) {
      n++;
      final shop = o.shop;
      b.writeln('$n. ${shop.name} · ${o.orderNo}');
      if (shop.contactName != null) b.writeln(l.sellerContact(shop.contactName!));
      if (shop.phone != null) b.writeln(l.sellerSummaryPhone(formatMalaysianMobile(shop.phone)));
      if (shop.address != null) b.writeln(l.sellerSummaryAddress(shop.address!));
      for (final i in o.items) {
        b.writeln('- ${_itemLine(i, l)}');
      }
      b.writeln('${l.total} ${formatRm(o.totalSen)}');
      if (o.paymentTerms.isNotEmpty) b.writeln(l.paymentTerms(_terms(o, l)));
      if (o.note != null) b.writeln(l.sellerBuyerNote(o.note!));
    }
  }
  return b.toString().trimRight();
}

// ---------------- PDF ----------------

const _grey = PdfColor.fromInt(0xFF666666);
const _light = PdfColor.fromInt(0xFFEEEEEE);
const _red = PdfColor.fromInt(0xFFC62828);

/// 一张单估计印出来不超过这么高（pt），就整块放在同一页（这一页放不下就整块搬到下一页）；更长的才让它跨页。
/// A4 扣掉边、每页上面的批发商名字和下面的页码，大约还有 715pt：留很多余地，
/// 因为整块的（pw.Inseparable）比一整页还高的话，pdf 会直接出错、印不出来
const keepTogetherMaxHeight = 540.0;

/// 估计一张单印出来多高（pt），宁可估高：每个字都当成中文字那么宽（11pt 字，一行大约 16pt 高）
double estimatedOrderHeight(DeliveryOrder o, L10n l, {bool withZone = false}) {
  const line = 16.0;
  // 一段字要几行：一行放得下 perLine 个字
  int lines(String text, int perLine) => text.isEmpty ? 1 : (text.runes.length / perLine).ceil();
  final shop = o.shop;
  var h = withZone ? 32.0 : 0.0; // 区名
  h += 8 + 20.0 * lines('999. ${shop.name}  ${o.orderNo}', 36); // 上面的线、店名（13pt，编号当三位数）
  if (shop.contactName != null) h += line * lines(l.sellerContact(shop.contactName!), 40);
  if (shop.phone != null) h += line;
  if (shop.address != null) h += line * lines(l.sellerSummaryAddress(shop.address!), 40);
  h += 4;
  for (final i in o.items) {
    h += 4 + line * lines(_itemLine(i, l), 34);
  }
  h += 4 + 20; // 付款方式、总额（13pt）
  if (o.note != null) h += line * lines(l.sellerBuyerNote(o.note!), 40);
  return h + 10 + 16 + 10; // 签名的线、下面的空白
}

/// 送货员打勾用的小方块
pw.Widget _box() =>
    pw.Container(width: 11, height: 11, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)));

/// A4 送货单：每页上面有批发商名字和日期；先是拣货单，再来每张单（有打勾的小方块）。
/// [font] 要有中文字（NotoSansSC 的 TTF，PdfGoogleFonts.notoSansSCRegular() 会用 App 打包的那个）
pw.Document deliveryPdfDocument(
  DeliverySummary s,
  L10n l, {
  required pw.Font font,
  PdfPageFormat format = PdfPageFormat.a4,
}) {
  final base = pw.ThemeData.withFont(base: font, bold: font);
  final theme = base.copyWith(
    defaultTextStyle: base.defaultTextStyle.copyWith(fontSize: 11),
    tableHeader: base.tableHeader.copyWith(fontSize: 11),
    tableCell: base.tableCell.copyWith(fontSize: 11),
  );
  final doc = pw.Document(theme: theme, title: '${s.wholesalerName} ${dateParam(s.date)}', creator: l.appTitle);
  final heading = l.sellerSummaryHeading(l.date(s.date));

  pw.Widget header(pw.Context ctx) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(s.wholesalerName, style: const pw.TextStyle(fontSize: 15)),
              if (s.wholesalerPhone != null)
                pw.Text(
                  l.sellerSummaryPhone(formatMalaysianMobile(s.wholesalerPhone)),
                  style: const pw.TextStyle(fontSize: 9, color: _grey),
                ),
            ],
          ),
        ),
        pw.Text(heading, style: const pw.TextStyle(fontSize: 13)),
      ],
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Container(
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Text(
      l.sellerSummaryPage(ctx.pageNumber, ctx.pagesCount),
      style: const pw.TextStyle(fontSize: 9, color: _grey),
    ),
  );

  List<pw.Widget> picking(pw.Context ctx) => [
    pw.Text(l.sellerSummaryPicking, style: const pw.TextStyle(fontSize: 14)),
    pw.Text(l.sellerSummaryPickingHint, style: const pw.TextStyle(fontSize: 9, color: _grey)),
    pw.SizedBox(height: 4),
    pw.TableHelper.fromTextArray(
      context: ctx,
      headers: ['', l.sellerSummaryColItem, l.sellerSummaryColQty, l.sellerSummaryColPack],
      data: [
        for (final p in s.picking) [_box(), p.name, l.qtyUnit(p.qty, p.unit), l.packQty(l.unit(p.unit), p.packQty)],
      ],
      headerDecoration: const pw.BoxDecoration(color: _light),
      columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FlexColumnWidth(5),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(3),
      },
      cellAlignments: const {0: pw.Alignment.center, 2: pw.Alignment.centerRight},
      headerAlignments: const {1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerLeft},
      cellAlignment: pw.Alignment.centerLeft,
    ),
  ];

  pw.Widget itemRow(DeliveryItem i) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // 缺货的不用送：没有方块
        if (i.isOutOfStock) pw.SizedBox(width: 11) else _box(),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            _itemLine(i, l),
            style: i.isOutOfStock ? const pw.TextStyle(color: _grey, decoration: pw.TextDecoration.lineThrough) : null,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(i.isOutOfStock ? '' : formatRm(i.lineTotalSen), style: const pw.TextStyle(color: _grey)),
      ],
    ),
  );

  pw.Widget zoneHeading(String zone) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 8, bottom: 2),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    color: _light,
    child: pw.Text(zone, style: const pw.TextStyle(fontSize: 12)),
  );

  /// [zone]：这一区的第一张单，区名跟它放在一起（不会区名在页尾、单在下一页）
  List<pw.Widget> order(int n, DeliveryOrder o, {String? zone}) {
    final shop = o.shop;
    final head = pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Text('$n. ${shop.name}', style: const pw.TextStyle(fontSize: 13))),
              pw.Text(o.orderNo, style: const pw.TextStyle(color: _grey)),
            ],
          ),
          if (shop.contactName != null) pw.Text(l.sellerContact(shop.contactName!)),
          if (shop.phone != null) pw.Text(l.sellerSummaryPhone(formatMalaysianMobile(shop.phone))),
          if (shop.address != null) pw.Text(l.sellerSummaryAddress(shop.address!)),
          pw.SizedBox(height: 4),
        ],
      ),
    );
    final foot = pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text(o.paymentTerms.isEmpty ? '' : l.paymentTerms(_terms(o, l)))),
              pw.Text('${l.total} ${formatRm(o.totalSen)}', style: const pw.TextStyle(fontSize: 13)),
            ],
          ),
          if (o.note != null) pw.Text(l.sellerBuyerNote(o.note!)),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Text(l.sellerSummarySignature),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Container(
                  height: 14,
                  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final items = o.items.map(itemRow).toList();
    // 一般的单整块放在同一页（送货员不用翻页）：这一页放不下就整块搬到下一页。
    // 要用 Inseparable：直的 Column 在 MultiPage 里会被切开（Flex 竖的可以跨页）。很长的单才让它跨页
    final top = [if (zone != null) zoneHeading(zone), head];
    if (estimatedOrderHeight(o, l, withZone: zone != null) <= keepTogetherMaxHeight) {
      return [
        pw.Inseparable(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [...top, ...items, foot]),
        ),
      ];
    }
    return [...top, ...items, foot];
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 24),
      header: header,
      footer: footer,
      build: (ctx) {
        final groups = groupByZone(s, l);
        var n = 0;
        return [
          pw.Text(l.sellerTodayCount(s.orderCount, formatRm(s.totalSen)), style: const pw.TextStyle(fontSize: 13)),
          if (s.pendingCount > 0)
            pw.Text(l.sellerSummaryPending(s.pendingCount), style: const pw.TextStyle(color: _red)),
          pw.SizedBox(height: 10),
          if (s.isEmpty)
            pw.Text(l.sellerSummaryEmpty)
          else ...[
            ...picking(ctx),
            pw.SizedBox(height: 16),
            pw.Text(l.sellerSummaryOrders, style: const pw.TextStyle(fontSize: 14)),
            for (final g in groups)
              for (final (i, o) in g.orders.indexed) ...order(++n, o, zone: i == 0 ? g.zone : null),
          ],
        ];
      },
    ),
  );
  return doc;
}

/// 做好 PDF（打印用的 bytes）
Future<Uint8List> buildDeliveryPdf(
  DeliverySummary s,
  L10n l, {
  required pw.Font font,
  PdfPageFormat format = PdfPageFormat.a4,
}) => deliveryPdfDocument(s, l, font: font, format: format).save();
