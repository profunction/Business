import 'dart:ui' show FontFeature, ImageFilter;

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
              size: 48,
              color: AppTheme.textSecondary,
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

/// 大方块按钮（批发商首页、上传价目表的选项）。买家端不用：买家用 [ActionTile]
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
    final t = Theme.of(context).textTheme;
    final bg = color ?? scheme.primary;
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black87;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 30, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.titleLarge?.copyWith(color: fg)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: t.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.9))),
                      ],
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Text(badge!, style: t.titleSmall?.copyWith(color: bg)),
                  ),
                Icon(Icons.chevron_right, size: 26, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 白色小卡片动作（买家首页「跟上次一样」等）：主色图标 + 标题 + 一行说明
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.title, this.subtitle, required this.onTap, this.busy = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: busy ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  icon: icon,
                  child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.titleSmall?.copyWith(color: scheme.onSurface)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 浅主色底的圆角小方块 + 图标（列表、动作卡片前面）
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.background, this.size = 36, this.child});

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child ?? Icon(icon, size: size * 0.56, color: color ?? scheme.primary),
    );
  }
}

/// 小节标题：左边灰色粗体字，右边可以放「全部 >」
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.actionKey});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.titleMedium)),
          if (actionLabel != null)
            TextButton(
              key: actionKey,
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(actionLabel!), const Icon(Icons.chevron_right, size: 18)],
              ),
            ),
        ],
      ),
    );
  }
}

/// 一组白色卡片里的行，中间有细线（列表常用）
class GroupedCard extends StatelessWidget {
  const GroupedCard({super.key, required this.children, this.dividerIndent = 0});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: 1, indent: dividerIndent),
            c,
          ],
        ],
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [?above, child],
          ),
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
    this.trailing,
  });

  final Color color;
  final IconData icon;
  final String text;
  final TextStyle? textStyle;
  final Widget? action;

  /// 整条可以点的时候，右边的小箭头
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsets.fromLTRB(12, 8, action == null ? 12 : 4, 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: Color.alphaBlend(Colors.black.withValues(alpha: 0.06), color)),
      ),
      // 右边的按钮最多占四成宽（马来文的时候按钮的字换行，不会把提示挤到看不见或撑爆）
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: textStyle ?? t.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ),
            if (action != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                child: action,
              ),
            ?trailing,
          ],
        ),
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
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        : Text(label, textAlign: TextAlign.center);
    if (icon != null && !busy) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 20), label: child);
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

/// 几个一样大的切换按钮（「看商品」/「看批发商」、订单的「新订单 / 今天要送 / 全部」），选中的是浅主色底。
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
    final scheme = Theme.of(context).colorScheme;
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
    final text = Text(
      label,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: maxLines > 1 ? const TextStyle(height: 1.15) : null,
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
        Flexible(child: text),
      ],
    );
    return Semantics(
      selected: selected,
      button: true,
      child: selected
          ? FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                padding: padding,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                side: BorderSide(color: scheme.primary),
              ),
              onPressed: onTap,
              child: child,
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                padding: padding,
                foregroundColor: AppTheme.textSecondary,
              ),
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
    return TagChip(label: context.l10n.status(status), color: color);
  }
}

/// 小标签：浅底 + 同色字（状态、最便宜、快卖完……）
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// ＋ / － 数量，不用打字。外框一条细线，按钮 44 × 44
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
    final t = Theme.of(context).textTheme;
    Widget button(IconData icon, int next, String semantic) => SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: semantic,
        iconSize: 20,
        color: Theme.of(context).colorScheme.primary,
        onPressed: onChanged == null || next < min || next > max ? null : () => onChanged!(next),
        icon: Icon(icon),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderStrong),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(Icons.remove, value - 1, '-'),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40),
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              button(Icons.add, value + 1, '+'),
            ],
          ),
        ),
        if (unitLabel != null) ...[
          const SizedBox(width: 8),
          Text(unitLabel!, style: t.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
        ],
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
    final style = (large ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(color: AppTheme.textPrimary);
    return Semantics(
      label: context.l10n.priceLocked,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: ExcludeSemantics(child: Text('RM88.88', style: style)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, size: 18, color: AppTheme.textSecondary),
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
    final style = Theme.of(context).textTheme.bodyMedium;
    if (count == 0) return Text(l.noRatings, style: style?.copyWith(color: AppTheme.textSecondary));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: Color(0xFFE8A317), size: 18),
        const SizedBox(width: 4),
        Flexible(child: Text(l.rating(avg.toStringAsFixed(1), count), style: style)),
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color ?? AppTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color ?? AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个金额一行：左边名称，右边金额（数字等宽，右对齐）
class AmountRow extends StatelessWidget {
  const AmountRow({super.key, required this.label, required this.value, this.bold = false, this.valueColor});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = bold ? t.titleMedium : t.bodyMedium;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: bold ? 4 : 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: bold ? style : style?.copyWith(color: AppTheme.textSecondary)),
          ),
          Text(
            value,
            style: (bold ? t.titleLarge : style)?.copyWith(
              color: valueColor,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
      title: Text(title),
      content: content,
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel ?? l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
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
