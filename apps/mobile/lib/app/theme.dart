import 'package:flutter/material.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// 「专业采购平台」风格：白 / 浅灰底，一个主色（深青色）加中性灰；颜色只用在状态上。
/// Material 3 正常尺寸：内文 14–16sp、标题 18–22sp、按钮 44–48 高、圆角 8–12、卡片细框线。
/// 各页不要自己写颜色和字号，用这里的 colorScheme / textTheme / 组件主题（以及下面的常数）。
class AppTheme {
  /// 主色：深青（可靠、专业；白字对比 > 7:1）
  static const seed = Color(0xFF0B5563);

  static const background = Color(0xFFF5F7F9);
  static const border = Color(0xFFE3E7EC);
  static const borderStrong = Color(0xFFCDD3DA);
  static const textPrimary = Color(0xFF17212B);

  /// 次要文字（白底对比 ~5.6:1，过 WCAG AA）
  static const textSecondary = Color(0xFF5B6673);

  static const radius = 10.0;
  static const cardRadius = 12.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE2EFF1),
      onPrimaryContainer: const Color(0xFF053440),
      secondary: const Color(0xFF3F5560),
      secondaryContainer: const Color(0xFFE6EDEF),
      onSecondaryContainer: const Color(0xFF14313A),
      surface: Colors.white,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF8FAFB),
      surfaceContainer: const Color(0xFFF2F5F7),
      surfaceContainerHigh: const Color(0xFFECF0F3),
      surfaceContainerHighest: const Color(0xFFE5EAEE),
      outline: borderStrong,
      outlineVariant: border,
      error: problem,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final b = base.textTheme;
    final text = b
        .copyWith(
          headlineMedium: b.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25),
          headlineSmall: b.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
          titleLarge: b.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
          titleMedium: b.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
          titleSmall: b.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
          bodyLarge: b.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
          bodyMedium: b.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
          bodySmall: b.bodySmall?.copyWith(fontSize: 13, height: 1.35, color: textSecondary),
          labelLarge: b.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          labelMedium: b.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          labelSmall: b.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: textPrimary, displayColor: textPrimary);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    OutlineInputBorder inputBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: c, width: w));

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        toolbarHeight: 56,
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        shape: const Border(bottom: BorderSide(color: border)),
        titleTextStyle: text.titleLarge?.copyWith(color: textPrimary),
        iconTheme: const IconThemeData(size: 24, color: textPrimary),
        actionsIconTheme: const IconThemeData(size: 24, color: textPrimary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 默认整行宽（每页一个主要动作）；放在一排里的小按钮各自给 minimumSize
          minimumSize: const Size.fromHeight(48),
          textStyle: text.labelLarge,
          shape: shape,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          textStyle: text.labelLarge,
          shape: shape,
          foregroundColor: seed,
          side: const BorderSide(color: borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: text.labelLarge,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: text.bodyLarge?.copyWith(color: textSecondary),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: seed),
        hintStyle: text.bodyLarge?.copyWith(color: const Color(0xFF8A94A0)),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: inputBorder(borderStrong),
        enabledBorder: inputBorder(borderStrong),
        focusedBorder: inputBorder(seed, 1.6),
        errorBorder: inputBorder(problem),
        focusedErrorBorder: inputBorder(problem, 1.6),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 10,
        minTileHeight: 52,
        horizontalTitleGap: 12,
        iconColor: textSecondary,
        titleTextStyle: text.bodyLarge?.copyWith(color: textPrimary, fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: scheme.primaryContainer,
        side: const BorderSide(color: borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: text.bodyMedium?.copyWith(color: textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        checkmarkColor: seed,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 44),
          textStyle: text.labelLarge,
          side: const BorderSide(color: borderStrong),
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          foregroundColor: textSecondary,
          shape: shape,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? seed : textSecondary),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            color: s.contains(WidgetState.selected) ? seed : textSecondary,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: problem, textColor: Colors.white),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        titleTextStyle: text.titleLarge?.copyWith(color: textPrimary),
        contentTextStyle: text.bodyMedium?.copyWith(color: textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1F2A33),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1, color: border),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: seed, linearTrackColor: scheme.primaryContainer),
      checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    );
  }

  /// 订单状态的颜色（一定跟文字一起出现，不能只靠颜色；12% 底色上的文字都过 AA）
  static Color statusColor(OrderStatus s) => switch (s) {
    OrderStatus.pending => const Color(0xFF9A5B00),
    OrderStatus.confirmed => const Color(0xFF1D5FB4),
    OrderStatus.outOfStock => const Color(0xFFB42318),
    OrderStatus.delivering => const Color(0xFF5B3FA8),
    OrderStatus.delivered => const Color(0xFF1E7A46),
    OrderStatus.cancelled => const Color(0xFF5B6673),
  };

  static const problem = Color(0xFFB42318);

  /// 批发商的「确认」按钮（绿色 = 可以送）
  static const confirm = Color(0xFF1E7A46);
  static const warningBg = Color(0xFFFFF6E5);
  static const successBg = Color(0xFFE8F4EC);

  /// 提示条：信息（主色的浅底）
  static const infoBg = Color(0xFFE8F2F4);

  /// 库存的颜色（一定跟文字一起出现）：有货绿、快卖完橙、缺货红
  static Color stockColor(StockStatus s) => switch (s) {
    StockStatus.inStock => const Color(0xFF1E7A46),
    StockStatus.lowStock => const Color(0xFF9A5B00),
    StockStatus.outOfStock => problem,
  };

  /// 快卖完 / 创始会员这类提示的文字颜色
  static const caution = Color(0xFF9A5B00);

  /// AI 不太肯定的那几行（价目表导入）：黄色框
  static const unsure = Color(0xFFE0A800);
}
