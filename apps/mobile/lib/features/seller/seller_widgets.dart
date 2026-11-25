import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 电话号码 → 国际格式的数字（60123456789）。服务器存的已经是这样；万一是 0 开头就补上 6
String? phoneDigits(String? phone) {
  if (phone == null) return null;
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('0')) d = '6$d';
  return d;
}

/// 打电话
Uri telUri(String digits) => Uri(scheme: 'tel', path: '+$digits');

/// WhatsApp：wa.me 的号码不要 +，可以先打好一句话
Uri whatsappUri(String digits, {String? text}) =>
    Uri.https('wa.me', '/$digits', text == null || text.isEmpty ? null : {'text': text});

/// 用别的 App 打开（电话、WhatsApp）。手机没装那个 App 时 Android 会丢错误，这里接住，告诉老板打不开
Future<void> openExternal(BuildContext context, Uri uri) async {
  final message = context.l10n.sellerCannotOpen;
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) showMessage(context, message, error: true);
}

/// 颜色 + 文字的小标签（库存、上架状态、价目表每一行要做什么）。不能只靠颜色
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// 库存：有货（绿）/ 快卖完（橙）/ 缺货（红）
class StockChip extends StatelessWidget {
  const StockChip({super.key, required this.status});

  final StockStatus status;

  @override
  Widget build(BuildContext context) => LabelChip(text: context.l10n.stock(status), color: AppTheme.stockColor(status));
}

/// 一个选项：值、文字，选中时的颜色（null = 主色）
typedef Choice<T> = ({T value, String label, Color? color, Key? key});

/// 一组大按钮选一个（单位、库存、上架 / 下架、新增 / 更新 / 跳过）。[columns] 一排几个；
/// 窄的手机、大字的时候字可以换行，不会被切掉。[enabled] 回传 false 的选项按不了
class ChoiceButtons<T> extends StatelessWidget {
  const ChoiceButtons({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
    this.columns = 3,
    this.enabled,
  });

  final List<Choice<T>> choices;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final int columns;
  final bool Function(T value)? enabled;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = columns.clamp(1, choices.length);
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        final rows = <Widget>[];
        for (var start = 0; start < choices.length; start += cols) {
          final slice = choices.sublist(start, (start + cols).clamp(0, choices.length));
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : gap),
              // 同一排一样高（字换行的那个也一样）
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, c) in slice.indexed) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(width: width, child: _button(context, c, scheme)),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }

  Widget _button(BuildContext context, Choice<T> c, ColorScheme scheme) {
    final isSelected = c.value == selected;
    final color = c.color ?? scheme.primary;
    final canPress = onSelected != null && (enabled?.call(c.value) ?? true);
    final label = Text(
      c.label,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 20, height: 1.15),
    );
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 10);
    final onPressed = canPress ? () => onSelected!(c.value) : null;
    return Semantics(
      selected: isSelected,
      button: true,
      child: isSelected
          ? FilledButton(
              key: c.key,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                padding: padding,
                backgroundColor: color,
              ),
              onPressed: onPressed,
              child: label,
            )
          : OutlinedButton(
              key: c.key,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                padding: padding,
                foregroundColor: c.color,
                side: BorderSide(color: canPress ? color : Colors.black26, width: 2),
              ),
              onPressed: onPressed,
              child: label,
            ),
    );
  }
}

/// 页面中间的提示（没有资料、读完了、出错了），下面可以放一个按钮
class CenterMessage extends StatelessWidget {
  const CenterMessage({super.key, required this.icon, required this.text, this.detail, this.action, this.iconColor});

  final IconData icon;
  final String text;
  final String? detail;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 80, color: iconColor ?? Colors.black38),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: t.titleLarge),
        if (detail != null) ...[
          const SizedBox(height: 10),
          Text(detail!, textAlign: TextAlign.center, style: t.bodyLarge),
        ],
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    );
  }
}
