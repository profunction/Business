import 'package:flutter/material.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// 客服用电脑看：字比手机 App 小，资料多一点；状态一样用颜色加文字
class AdminTheme {
  static const seed = Color(0xFF1B6E4A);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// 订单状态的颜色（一定跟文字一起出现）
  static Color statusColor(OrderStatus s) => switch (s) {
    OrderStatus.pending => const Color(0xFFB26A00),
    OrderStatus.confirmed => const Color(0xFF1565C0),
    OrderStatus.delivering => const Color(0xFF6A1B9A),
    OrderStatus.delivered => const Color(0xFF2E7D32),
    OrderStatus.outOfStock => const Color(0xFFC62828),
    OrderStatus.cancelled => const Color(0xFF616161),
  };
}
