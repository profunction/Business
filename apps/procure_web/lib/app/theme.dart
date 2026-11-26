import 'package:flutter/material.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// 公司采购用电脑看：桌面的界面（表格、筛选），字比手机 App 小；状态一样用颜色加文字
class ProcureTheme {
  static const seed = Color(0xFF1F4E79);

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

  /// 订阅状态的颜色（一定跟文字一起出现）
  static Color subscriptionColor(SubscriptionState s) => switch (s) {
    SubscriptionState.trialing => const Color(0xFF1565C0),
    SubscriptionState.active => const Color(0xFF2E7D32),
    SubscriptionState.pastDue => const Color(0xFFB26A00),
    _ => const Color(0xFF616161),
  };
}
