import 'package:flutter/material.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// 「比 WhatsApp 还简单」：字大、按钮大、颜色对比强。
/// 规则（docs/01-architecture.md 1.5）：字最小 18；主要按钮全宽、至少 56 高；每页一个主要动作。
class AppTheme {
  static const seed = Color(0xFF1B6E3C); // 深绿：钱、可靠

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontSize: 30, fontWeight: FontWeight.w700),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 23, fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 20, height: 1.35),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 18, height: 1.35),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 16, height: 1.3),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 17),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: const Color(0xFFF6F7F4),
      appBarTheme: AppBarTheme(
        toolbarHeight: 64,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        iconTheme: const IconThemeData(size: 30),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: text.labelLarge?.copyWith(fontSize: 22),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: text.labelLarge,
          shape: buttonShape,
          side: BorderSide(color: scheme.primary, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        labelStyle: text.bodyLarge,
        hintStyle: text.bodyLarge?.copyWith(color: Colors.black38),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE2E5DF)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 14,
        titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: Colors.black54),
      ),
      snackBarTheme: SnackBarThemeData(contentTextStyle: text.bodyLarge?.copyWith(color: Colors.white)),
      dividerTheme: const DividerThemeData(space: 1, color: Color(0xFFE2E5DF)),
    );
  }

  /// 订单状态的颜色（一定跟文字一起出现，不能只靠颜色）
  static Color statusColor(OrderStatus s) => switch (s) {
    OrderStatus.pending => const Color(0xFFB26A00),
    OrderStatus.confirmed => const Color(0xFF1565C0),
    OrderStatus.outOfStock => const Color(0xFFC62828),
    OrderStatus.delivering => const Color(0xFF6A1B9A),
    OrderStatus.delivered => const Color(0xFF2E7D32),
    OrderStatus.cancelled => const Color(0xFF616161),
  };

  static const problem = Color(0xFFC62828);

  /// 批发商的「确认」按钮（绿色 = 可以送）
  static const confirm = Color(0xFF2E7D32);
  static const warningBg = Color(0xFFFFF4E0);
  static const successBg = Color(0xFFE6F4EA);

  /// 库存的颜色（一定跟文字一起出现）：有货绿、快卖完橙、缺货红
  static Color stockColor(StockStatus s) => switch (s) {
    StockStatus.inStock => const Color(0xFF2E7D32),
    StockStatus.lowStock => const Color(0xFFB26A00),
    StockStatus.outOfStock => problem,
  };

  /// AI 不太肯定的那几行（价目表导入）：黄色框
  static const unsure = Color(0xFFE0A800);
}
