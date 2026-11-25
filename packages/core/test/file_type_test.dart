// 用魔术字节判断档案格式（价目表上传前用；不信档名和 MIME）
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

Uint8List bytes(List<int> head, [int padTo = 64]) =>
    Uint8List.fromList([...head, ...List.filled(padTo > head.length ? padTo - head.length : 0, 0x20)]);

Uint8List text(String s, {Encoding encoding = utf8}) => Uint8List.fromList(encoding.encode(s));

List<int> utf16le(String s) => [
  for (final c in s.codeUnits) ...[c & 0xFF, c >> 8],
];

void main() {
  test('图片', () {
    expect(sniffFileType(bytes([0xFF, 0xD8, 0xFF, 0xE0])), FileKind.jpeg);
    expect(sniffFileType(bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), FileKind.png);
    expect(sniffFileType(bytes(ascii.encode('GIF89a'))), FileKind.gif);
    expect(sniffFileType(bytes([...ascii.encode('RIFF'), 1, 2, 3, 4, ...ascii.encode('WEBPVP8 ')])), FileKind.webp);
    expect(sniffFileType(bytes([...ascii.encode('RIFF'), 1, 2, 3, 4, ...ascii.encode('WAVE')])), FileKind.unknown);
  });

  test('照片的档名是 .heic，内容其实是 JPEG（image_picker 压缩过）→ 当 JPEG', () {
    final k = sniffFileType(bytes([0xFF, 0xD8, 0xFF, 0xE1]), fileName: 'scaled_IMG_0001.HEIC');
    expect(k, FileKind.jpeg);
    expect(k.ext, 'jpg');
    expect(k.contentType, 'image/jpeg');
    expect(k.importType, ImportFileType.image);
    expect(k.isPriceList, isTrue);
  });

  test('真的 HEIC：认得出来，但不能上传', () {
    final heic = sniffFileType(bytes([0, 0, 0, 0x18, ...ascii.encode('ftypheic'), 0, 0, 0, 0]));
    expect(heic, FileKind.heic);
    expect(heic.isPriceList, isFalse);
    expect(sniffFileType(bytes([0, 0, 0, 0x1C, ...ascii.encode('ftypmif1')])), FileKind.heic);
    expect(sniffFileType(bytes([0, 0, 0, 0x1C, ...ascii.encode('ftypavif')])), FileKind.unknown, reason: 'AVIF 不收');
    expect(sniffFileType(bytes([0, 0, 0, 0x1C, ...ascii.encode('ftypisom')])), FileKind.unknown, reason: '影片');
  });

  test('PDF（%PDF- 前面可以有别的字节）', () {
    expect(sniffFileType(text('%PDF-1.7\n%âãÏÓ\n1 0 obj')), FileKind.pdf);
    expect(sniffFileType(bytes([0xEF, 0xBB, 0xBF, ...ascii.encode('%PDF-1.4')])), FileKind.pdf);
    expect(FileKind.pdf.importType, ImportFileType.pdf);
  });

  test('xlsx：ZIP 里有 xl/；docx 不算', () {
    final xlsx = bytes([
      0x50,
      0x4B,
      0x03,
      0x04,
      ...List.filled(26, 0),
      ...ascii.encode('[Content_Types].xml'),
      ...ascii.encode('xl/workbook.xml'),
    ], 200);
    expect(sniffFileType(xlsx, fileName: 'price.xlsx'), FileKind.xlsx);
    expect(FileKind.xlsx.importType, ImportFileType.excel);
    final docx = bytes([0x50, 0x4B, 0x03, 0x04, ...List.filled(26, 0), ...ascii.encode('word/document.xml')], 200);
    expect(sniffFileType(docx, fileName: 'price.xlsx'), FileKind.unknown, reason: '档名是 .xlsx 也不信');
  });

  test('xls：OLE2 里有 Workbook 资料流', () {
    const ole = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    expect(sniffFileType(bytes([...ole, ...List.filled(500, 0), ...utf16le('Workbook')], 1024)), FileKind.xls);
    expect(sniffFileType(bytes([...ole, ...utf16le('WordDocument')], 1024)), FileKind.unknown, reason: '.doc');
    expect(sniffFileType(bytes([...ole], 1024), fileName: 'OLD.XLS'), FileKind.xls);
    expect(FileKind.xls.contentType, 'application/vnd.ms-excel');
  });

  test('CSV：纯文字，有换行和分隔符；中文（UTF-8）也可以', () {
    final csv = text('名称,单位,价钱\n16安士 PP杯,箱,86.00\n95 平盖,箱,46.00\n');
    expect(sniffFileType(csv), FileKind.csv);
    expect(sniffFileType(csv, fileName: 'list.csv').isPriceList, isTrue);
    expect(sniffFileType(text('a;b;c\r\n1;2;3\r\n')), FileKind.csv, reason: '分号也算');
    expect(sniffFileType(text('just one line of text without separators')), FileKind.unknown);
    expect(sniffFileType(text('one line, no newline'), fileName: 'x.csv'), FileKind.csv, reason: '档名是 .csv');
    expect(FileKind.csv.importType, ImportFileType.excel, reason: 'file_type 只有 image / pdf / excel');
  });

  test('二进制垃圾、空档案', () {
    expect(sniffFileType(Uint8List(0)), FileKind.unknown);
    expect(sniffFileType(Uint8List.fromList(List.generate(300, (i) => i % 256)), fileName: 'x.csv'), FileKind.unknown);
    expect(FileKind.unknown.isPriceList, isFalse);
  });

  test('GIF：AI 读得懂，但 Storage bucket 不收（等后端加 image/gif）', () {
    expect(FileKind.gif.importType, ImportFileType.image);
    expect(FileKind.gif.isPriceList, isFalse);
  });

  test('上传的格式都在 bucket 允许的 MIME 里', () {
    for (final k in [
      FileKind.jpeg,
      FileKind.png,
      FileKind.webp,
      FileKind.pdf,
      FileKind.xlsx,
      FileKind.xls,
      FileKind.csv,
    ]) {
      expect(k.isPriceList, isTrue, reason: k.toString());
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(k.ext), isTrue, reason: 'Storage 路径只用 ASCII');
    }
  });
}
