import 'dart:math';

final _secure = Random.secure();

/// 随机的 UUID v4（上传档案的名字用：只有 ASCII，不会撞名）
String newUuidV4([Random? random]) {
  final r = random ?? _secure;
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0F) | 0x40; // 版本 4
  b[8] = (b[8] & 0x3F) | 0x80; // RFC 4122
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

bool isUuid(String? s) => s != null && _uuidPattern.hasMatch(s);
