import 'dart:typed_data';

import 'file_saver.dart';

class _NoFileSaver implements FileSaver {
  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async => false;
}

FileSaver createFileSaver() => _NoFileSaver();
