// 马来西亚手机号：老板可能输入 012-345 6789、0123456789、60123456789、+60 12 345 6789

/// 转成登录用的 '+60123456789'；不像马来西亚手机号就返回 null
String? normalizeMalaysianMobile(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('60')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  // 手机号是 1 开头，去掉 0 之后 9 到 10 位（例如 12-345 6789、11-1234 5678）
  if (!digits.startsWith('1') || digits.length < 9 || digits.length > 10) return null;
  return '+60$digits';
}

/// '60123456789' / '+60123456789' -> '012-345 6789'（显示用）
String formatMalaysianMobile(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('60')) digits = '0${digits.substring(2)}';
  if (digits.length == 10) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)} ${digits.substring(6)}';
  }
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)} ${digits.substring(7)}';
  }
  return digits;
}
