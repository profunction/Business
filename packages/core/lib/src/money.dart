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
