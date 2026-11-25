// 用档案开头的「魔术字节」判断真正的格式，不信档名和 MIME：
// 手机相册的照片常常是 HEIC，image_picker 压缩后会变成 JPEG 但档名还是 .heic。
import 'dart:convert';
import 'dart:typed_data';

import 'models/seller.dart';

enum SniffedType { jpeg, png, webp, gif, pdf, xlsx, xls, csv, heic, unknown }

/// 认出来的档案格式：上传用的副档名和 Content-Type，以及 price_list_imports.file_type
class FileKind {
  const FileKind._(this.type, this.ext, this.contentType, this.importType);

  static const jpeg = FileKind._(SniffedType.jpeg, 'jpg', 'image/jpeg', ImportFileType.image);
  static const png = FileKind._(SniffedType.png, 'png', 'image/png', ImportFileType.image);
  static const webp = FileKind._(SniffedType.webp, 'webp', 'image/webp', ImportFileType.image);
  static const gif = FileKind._(SniffedType.gif, 'gif', 'image/gif', ImportFileType.image);
  static const pdf = FileKind._(SniffedType.pdf, 'pdf', 'application/pdf', ImportFileType.pdf);
  static const xlsx = FileKind._(
    SniffedType.xlsx,
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ImportFileType.excel,
  );
  static const xls = FileKind._(SniffedType.xls, 'xls', 'application/vnd.ms-excel', ImportFileType.excel);
  static const csv = FileKind._(SniffedType.csv, 'csv', 'text/csv', ImportFileType.excel);

  /// AI 不收 HEIC：认得出来，但不能上传
  static const heic = FileKind._(SniffedType.heic, 'heic', 'image/heic', null);
  static const unknown = FileKind._(SniffedType.unknown, 'bin', 'application/octet-stream', null);

  final SniffedType type;
  final String ext;
  final String contentType;

  /// null = 价目表不收这种档案
  final ImportFileType? importType;

  /// Storage bucket 'price-lists' 允许的格式（跟 _setup_seller_storage() 的 allowed_mime_types 一致）
  static const priceListContentTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'text/csv',
  };

  /// 可以当价目表上传（AI 读得懂，Storage 也收）
  bool get isPriceList => importType != null && priceListContentTypes.contains(contentType);

  @override
  String toString() => 'FileKind(${type.name})';
}

/// 价目表档案的大小上限（跟 Storage bucket 一样：10 MB）
const priceListMaxBytes = 10 * 1024 * 1024;

/// 看档案开头判断格式。[fileName] 只用来帮忙认 CSV（纯文字没有魔术字节）和分不清的旧版 Office 档。
FileKind sniffFileType(Uint8List bytes, {String? fileName}) {
  if (bytes.isEmpty) return FileKind.unknown;
  final ext = _extension(fileName);

  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return FileKind.jpeg;
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return FileKind.png;
  if (_startsWith(bytes, ascii.encode('GIF87a')) || _startsWith(bytes, ascii.encode('GIF89a'))) return FileKind.gif;
  if (_startsWith(bytes, ascii.encode('RIFF')) && _matchesAt(bytes, 8, ascii.encode('WEBP'))) return FileKind.webp;
  // PDF 规定 %PDF- 要在前 1024 个字节里（前面可能有垃圾）
  if (_indexOf(bytes, ascii.encode('%PDF-'), end: 1024) >= 0) return FileKind.pdf;
  // HEIC / HEIF：ISO BMFF，第 4..8 个字节是 'ftyp'，后面是品牌
  if (_matchesAt(bytes, 4, ascii.encode('ftyp')) && bytes.length >= 12) {
    final brand = ascii.decode(bytes.sublist(8, 12), allowInvalid: true).toLowerCase();
    if (_heicBrands.contains(brand)) return FileKind.heic;
    return FileKind.unknown; // avif、mp4、mov……
  }
  // ZIP：xlsx 里一定有 xl/ 文件夹（中央目录的档名不压缩，整个档案搜得到）
  if (_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04])) {
    if (_indexOf(bytes, ascii.encode('xl/')) >= 0) return FileKind.xlsx;
    return FileKind.unknown; // docx、普通 zip……
  }
  // 旧版 Office（OLE2）：Excel 的资料流叫 Workbook（或更旧的 Book），档名是 UTF-16LE
  if (_startsWith(bytes, const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    if (_indexOf(bytes, _utf16le('Workbook')) >= 0 || _indexOf(bytes, _utf16le('Book')) >= 0) return FileKind.xls;
    return ext == 'xls' ? FileKind.xls : FileKind.unknown;
  }
  if (_looksLikeCsv(bytes, ext)) return FileKind.csv;
  return FileKind.unknown;
}

const _heicBrands = {'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'hevm', 'hevs', 'mif1', 'msf1'};

String? _extension(String? fileName) {
  if (fileName == null) return null;
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}

/// CSV 没有魔术字节：前 8 KB 没有 NUL、几乎都是可以印的字（UTF-8 / GB18030 都可以），
/// 档名是 .csv / .txt，或者内容有换行和分隔符（逗号、分号、tab）
bool _looksLikeCsv(Uint8List bytes, String? ext) {
  final sample = bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes;
  var control = 0;
  var newlines = 0;
  var separators = 0;
  for (final b in sample) {
    if (b == 0) return false;
    if (b == 0x0A) {
      newlines++;
    } else if (b == 0x2C || b == 0x3B || b == 0x09) {
      separators++;
    } else if (b < 0x20 && b != 0x0D && b != 0x0C) {
      control++;
    }
  }
  if (control > sample.length ~/ 100) return false;
  if (ext == 'csv' || ext == 'txt' || ext == 'tsv') return true;
  return newlines > 0 && separators >= newlines;
}

List<int> _utf16le(String s) => [
  for (final c in s.codeUnits) ...[c & 0xFF, c >> 8],
];

bool _startsWith(Uint8List bytes, List<int> prefix) => _matchesAt(bytes, 0, prefix);

bool _matchesAt(Uint8List bytes, int offset, List<int> pattern) {
  if (bytes.length < offset + pattern.length) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (bytes[offset + i] != pattern[i]) return false;
  }
  return true;
}

int _indexOf(Uint8List bytes, List<int> pattern, {int? end}) {
  final last = (end == null ? bytes.length : (end < bytes.length ? end : bytes.length)) - pattern.length;
  outer:
  for (var i = 0; i <= last; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}
