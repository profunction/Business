// 每月佣金报表导出成 CSV（Excel 打得开）。金额用 RM、两位小数，不加 RM 和千位逗号，方便加总。
import 'models/admin.dart';

String _money(int sen) => '${sen < 0 ? '-' : ''}${sen.abs() ~/ 100}.${(sen.abs() % 100).toString().padLeft(2, '0')}';

String _cell(Object? v) {
  final s = v?.toString() ?? '';
  // 有逗号、引号、换行就包起来；开头是 = + - @ 的（Excel 会当公式）前面加一个单引号
  final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(s) && double.tryParse(s) == null ? "'$s" : s;
  return RegExp(r'[",\r\n]').hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
}

String _row(List<Object?> cells) => cells.map(_cell).join(',');

/// 全部批发商一行一家。headers 用画面的语言（App 传进来），null 就用英文。
/// withBom = true：开头加 UTF-8 BOM，Excel 才认得中文
String commissionReportCsv(
  CommissionReport r, {
  List<String>? headers,
  String totalLabel = 'TOTAL',
  bool withBom = true,
}) {
  final h =
      headers ??
      const [
        'Period',
        'Wholesaler',
        'Billing name',
        'SSM no.',
        'Email',
        'Delivered orders',
        'Goods total (RM, excl. shipping)',
        'Commission rate',
        'Commission due (RM)',
        'Invoice no.',
        'Invoice status',
      ];
  final lines = <String>[
    _row(h),
    for (final w in r.wholesalers)
      _row([
        r.periodLabel,
        w.name,
        w.billingName,
        w.ssmNo,
        w.billingEmail,
        w.orderCount,
        _money(w.gmvSen),
        w.rateText,
        _money(w.commissionSen),
        w.invoice?.invoiceNo,
        w.invoice?.status,
      ]),
    _row([r.periodLabel, totalLabel, '', '', '', r.orderCount, _money(r.gmvSen), '', _money(r.commissionSen), '', '']),
  ];
  return '${withBom ? '\uFEFF' : ''}${lines.join('\r\n')}\r\n';
}
