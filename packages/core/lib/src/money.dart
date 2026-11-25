// 金额：服务器一律用「仙」（整数）。RM12.50 = 1250。

/// 1250 -> 'RM12.50'；负数 -> '-RM12.50'
String formatRm(int sen) {
  final negative = sen < 0;
  final abs = sen.abs();
  final ringgit = abs ~/ 100;
  final cents = (abs % 100).toString().padLeft(2, '0');
  final grouped = _groupThousands(ringgit.toString());
  return '${negative ? '-' : ''}RM$grouped.$cents';
}

/// 每个多少钱（仙），最多 2 位小数，去掉多余的 0：8.50 -> '8.5'，9.60 -> '9.6'，12.00 -> '12'
String formatSen(double sen) {
  final fixed = sen.toStringAsFixed(2);
  return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+$'), '') : fixed;
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 老板打的价钱（RM）→ 仙。直接切字串，不经过 double（12.50 一定是 1250，不会变 1249）。
/// 接受 '12'、'12.5'、'12.50'、'.5'、'RM 12.50'、'1,250.00'；最多 2 位小数、最多 RM999,999.99。
/// 看不懂、0 或负数 → null
int? parseRmToSen(String input) {
  var s = input.trim().replaceAll(RegExp(r'\s'), '');
  if (s.toLowerCase().startsWith('rm')) s = s.substring(2);
  // 千位的逗号：1,250.00（逗号后面一定是 3 个数字，12,50 这种看不懂）
  if (s.contains(',')) {
    if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d*)?$').hasMatch(s)) return null;
    s = s.replaceAll(',', '');
  }
  final m = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = m.group(1)!;
  final frac = m.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  if (whole.length > 6) return null;
  final sen = (whole.isEmpty ? 0 : int.parse(whole)) * 100 + (frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0')));
  return sen > 0 ? sen : null;
}

/// 仙 → 输入框里的文字：1250 -> '12.50'（没有 RM、没有千位逗号，改价钱时直接改这个）
String senToInput(int sen) => '${sen ~/ 100}.${(sen % 100).toString().padLeft(2, '0')}';
