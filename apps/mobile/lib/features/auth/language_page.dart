import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// 第一次打开：三个大按钮选语言（每个按钮用它自己的语言写）
class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key, this.popAfterChoose = false});

  /// 从「设定」进来时，选完就回去
  final bool popAfterChoose;

  static const options = [('zh', '华文'), ('en', 'English'), ('ms', 'Bahasa Melayu')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sessionProvider.select((s) => s.localeCode));
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.translate, size: 72, color: Colors.black54),
              const SizedBox(height: 16),
              Text(
                '请选择语言\nChoose language\nPilih bahasa',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              for (final (code, label) in options) ...[
                FilledButton(
                  key: Key('lang-$code'),
                  style: current == code
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                        ),
                  onPressed: () async {
                    await ref.read(sessionProvider).setLocale(code);
                    if (popAfterChoose && context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(label, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
