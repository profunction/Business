import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/l10n_x.dart';
import '../app/theme.dart';

/// 读服务器资料的三种情况：读取中 / 出错（有「再试一次」）/ 有资料
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.onRetry, required this.builder});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v.hasError && !v.isLoading) return ErrorView(error: v.error!, onRetry: onRetry);
    if (v.hasValue) return builder(v.requireValue);
    return const Center(child: CircularProgressIndicator());
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error is AppError && (error as AppError).code == 'NETWORK' ? Icons.wifi_off : Icons.error_outline,
              size: 64,
              color: Colors.black45,
            ),
            const SizedBox(height: 16),
            Text(l.error(error), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}

/// 首页的大方块按钮
class BigTile extends StatelessWidget {
  const BigTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.color,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.primary;
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black87;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Icon(icon, size: 44, color: fg),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: fg)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: fg.withValues(alpha: 0.9)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text(badge!, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: bg)),
                  ),
                Icon(Icons.chevron_right, size: 36, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 页面底部固定的主要按钮（每页一个）
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.child, this.above});

  final Widget child;
  final Widget? above;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [?above, child]),
        ),
      ),
    );
  }
}

/// 页面上面的提示条（试用、免费版、批发商等审核……）：图标 + 一句话，右边可以放一个按钮
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
    this.textStyle,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final TextStyle? textStyle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: textStyle ?? Theme.of(context).textTheme.titleMedium)),
          ?action,
        ],
      ),
    );
  }
}

/// 按钮在忙的时候显示转圈，不让人连按两次
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
        : Text(label, textAlign: TextAlign.center);
    if (icon != null && !busy) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 28), label: child);
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

/// 几个一样大的切换按钮（「看商品」/「看批发商」、订单的「新订单 / 今天要送 / 全部」），选中的是实心。
/// 放在 Row 里，每个用 Expanded 包起来
class ModeButton extends StatelessWidget {
  const ModeButton({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    this.maxLines = 1,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  /// 窄的按钮（一排三个）可以让字换行，不要被切掉
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 8);
    final text = Text(
      label,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: maxLines > 1 ? const TextStyle(fontSize: 20, height: 1.15) : null,
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 24), const SizedBox(width: 6)],
        Flexible(child: text),
      ],
    );
    return Semantics(
      selected: selected,
      button: true,
      child: selected
          ? FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), padding: padding),
              onPressed: onTap,
              child: child,
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), padding: padding),
              onPressed: onTap,
              child: child,
            ),
    );
  }
}

/// 订单状态：颜色 + 文字
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(context.l10n.status(status), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
    );
  }
}

/// ＋ / － 数量，不用打字
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 9999,
    this.unitLabel,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;
  final String? unitLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    Widget button(IconData icon, int next, String semantic) => SizedBox(
      width: 64,
      height: 64,
      child: IconButton.filledTonal(
        tooltip: semantic,
        iconSize: 34,
        onPressed: onChanged == null || next < min || next > max ? null : () => onChanged!(next),
        icon: Icon(icon),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove, value - 1, '-'),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 80),
          child: Column(
            children: [
              Text('$value', textAlign: TextAlign.center, style: style),
              if (unitLabel != null) Text(unitLabel!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        button(Icons.add, value + 1, '+'),
      ],
    );
  }
}

/// 看不到的价钱：模糊方块。服务器根本没有传价钱过来，这里画的是假的数字
class LockedPrice extends StatelessWidget {
  const LockedPrice({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = (large ? Theme.of(context).textTheme.headlineSmall : Theme.of(context).textTheme.titleLarge)
        ?.copyWith(color: Colors.black87);
    return Semantics(
      label: context.l10n.priceLocked,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: ExcludeSemantics(child: Text('RM88.88', style: style)),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock, size: 22, color: Colors.black54),
        ],
      ),
    );
  }
}

/// ★ 4.5（12 个评价）
class RatingLine extends StatelessWidget {
  const RatingLine({super.key, required this.avg, required this.count});

  final double avg;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final style = Theme.of(context).textTheme.bodyLarge;
    if (count == 0) return Text(l.noRatings, style: style?.copyWith(color: Colors.black54));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 26),
        const SizedBox(width: 4),
        Text(l.rating(avg.toStringAsFixed(1), count), style: style),
      ],
    );
  }
}

/// 图标 + 一行字
class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: color ?? Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// 一个金额一行：左边名称，右边金额
class AmountRow extends StatelessWidget {
  const AmountRow({super.key, required this.label, required this.value, this.bold = false, this.valueColor});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = bold ? t.titleLarge : t.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value,
            style: style?.copyWith(color: valueColor, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppTheme.problem : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// 「确定要…？」两个大按钮。destructive：确定的按钮用红色（例如整张单缺货）
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  Widget? content,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      content: content,
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel ?? l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, 56),
            backgroundColor: destructive ? AppTheme.problem : null,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
