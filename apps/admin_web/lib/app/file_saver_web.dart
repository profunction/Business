import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_saver.dart';

/// 用 Blob + <a download> 让浏览器下载
class _WebFileSaver implements FileSaver {
  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    // 等浏览器开始下载再收回网址
    Future<void>.delayed(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
    return true;
  }
}

FileSaver createFileSaver() => _WebFileSaver();
