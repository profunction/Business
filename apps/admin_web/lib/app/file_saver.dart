import 'dart:typed_data';

import 'file_saver_stub.dart' if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// 把档案（CSV、PDF）交给浏览器下载。网页版以外（测试、桌面）回传 false，画面显示「只有网页版可以下载」
abstract class FileSaver {
  Future<bool> save(String fileName, Uint8List bytes, String mimeType);
}

FileSaver platformFileSaver() => impl.createFileSaver();
