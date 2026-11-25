// 打印送货单用的中文字体一定要打包在 App 里（下载失败的话 PDF 会静默变成方块字）
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NotoSansSC-Regular.ttf 在 App 里，而且是 TrueType 轮廓（不是 .otf）', () async {
    final data = await rootBundle.load('google_fonts/NotoSansSC-Regular.ttf');
    expect(data.getUint32(0), 0x00010000, reason: 'OTTO（CFF）的话 pdf 只画得出 32..255 的字');
    expect(data.lengthInBytes, greaterThan(5 * 1024 * 1024));
  });

  test('PdfGoogleFonts.notoSansSCRegular() 用打包的字体，不上网', () async {
    final font = await PdfGoogleFonts.notoSansSCRegular();
    expect(font, isA<pw.TtfFont>(), reason: '找不到就会变成 Helvetica');
    expect((font as pw.TtfFont).fontName, contains('NotoSansSC'));
  });

  test('用这个字体做一份有中文、马来文、英文的 PDF', () async {
    final font = await PdfGoogleFonts.notoSansSCRegular();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    doc.addPage(pw.Page(build: (_) => pw.Text('今天要送 / Penghantaran hari ini / Today: 16安士 PP杯 x3 箱')));
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, lessThan(200 * 1024), reason: '只嵌入用到的字');
  });
}
