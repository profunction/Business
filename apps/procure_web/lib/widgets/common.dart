import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/l10n_x.dart';

/// 读取中 / 出错（可以再试）/ 有资料
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, required this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // 重新读取时先留着旧的资料（筛选、翻页时画面不会一闪）
    if (value.hasValue && !value.hasError) return builder(value.requireValue);
    if (value.hasError) return ErrorPanel(error: value.error!, onRetry: onRetry);
    return const Center(
      child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.onRetry});

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
            Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(l.error(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}

/// 有颜色也有文字的小标签
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 每一页上面的标题、说明、按钮
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: t.headlineSmall),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: t.bodySmall?.color)),
                  ),
                ),
            ],
          ),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// 「标签：值」一行
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

/// 电话：点一下复制（客服用电脑打电话 / 开 WhatsApp Web）
class PhoneText extends StatelessWidget {
  const PhoneText(this.phone, {super.key, this.label});

  final String? phone;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = formatMalaysianMobile(phone);
    if (p.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: p));
        if (context.mounted) showSnack(context, context.l10n.copied(p));
      },
      icon: const Icon(Icons.phone, size: 16),
      label: Text(label == null ? p : '$label  $p'),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 做一件事：成功显示 success，失败显示服务器的错误（三语）。回传有没有成功
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, context.l10n.error(e));
    return false;
  }
}

Future<bool> showConfirmDialog(BuildContext context, {required String title, String? body, String? okLabel}) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(okLabel ?? l.confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 一个输入框的对话框。validator 回传错误文字（null = 可以）。按取消回传 null
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? help,
  TextInputType? keyboard,
  String? Function(String)? validator,
  int maxLines = 1,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _InputDialog(
      title: title,
      label: label,
      initial: initial,
      help: help,
      keyboard: keyboard,
      validator: validator,
      maxLines: maxLines,
    ),
  );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.help,
    this.keyboard,
    this.validator,
    this.maxLines = 1,
  });

  final String title;
  final String label;
  final String initial;
  final String? help;
  final TextInputType? keyboard;
  final String? Function(String)? validator;
  final int maxLines;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final e = widget.validator?.call(_c.text);
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    Navigator.pop(context, _c.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.help != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.help!)),
            TextField(
              key: const Key('dialog-field'),
              controller: _c,
              autofocus: true,
              keyboardType: widget.keyboard,
              maxLines: widget.maxLines,
              decoration: InputDecoration(labelText: widget.label, errorText: _error, errorMaxLines: 3),
              onSubmitted: widget.maxLines == 1 ? (_) => _ok() : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('dialog-ok'), onPressed: _ok, child: Text(l.confirm)),
      ],
    );
  }
}

/// 卡片包着的一块内容
class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.child, this.padding = const EdgeInsets.all(16)});

  final String? title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
