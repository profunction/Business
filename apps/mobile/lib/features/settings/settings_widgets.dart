import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../auth/language_page.dart';

/// 设定页的「语言」：三个选项，按了马上换（买家、批发商的设定页都用）
class LanguageCard extends ConsumerWidget {
  const LanguageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final current = ref.watch(sessionProvider.select((s) => s.localeCode));
    return Card(
      child: RadioGroup<String>(
        groupValue: current,
        onChanged: (code) {
          if (code != null) ref.read(sessionProvider).setLocale(code);
        },
        child: Column(
          children: [
            for (final (code, label) in LanguagePage.options)
              RadioListTile<String>(
                key: Key('settings-lang-$code'),
                value: code,
                title: Text(label, style: t.titleMedium),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「登出」：先问一次
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return OutlinedButton.icon(
      key: const Key('logout'),
      icon: const Icon(Icons.logout),
      onPressed: () async {
        if (await confirmDialog(context, title: l.logoutConfirm, confirmLabel: l.logout)) {
          await ref.read(sessionProvider).signOut();
        }
      },
      label: Text(l.logout),
    );
  }
}
