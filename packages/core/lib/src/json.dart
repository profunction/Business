// 读服务器 JSON 的小工具：服务器有时把数字传成字符串（numeric 类型），这里统一处理。

typedef Json = Map<String, dynamic>;

int asInt(Object? v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString()) ?? num.tryParse(v.toString())?.round() ?? fallback;
}

int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

bool asBool(Object? v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  return v.toString() == 'true';
}

String? asStringOrNull(Object? v) => v?.toString();

DateTime? asDateTimeOrNull(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

/// 'YYYY-MM-DD'（马来西亚时间的日期，不带时区）
DateTime? asDateOrNull(Object? v) {
  if (v == null) return null;
  final parts = v.toString().split('-');
  if (parts.length != 3) return null;
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

List<Json> asJsonList(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

List<String> asStringList(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

Json asJson(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Json? asJsonOrNull(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;
