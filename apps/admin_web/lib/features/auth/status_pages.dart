import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 登录后读取「我是谁」；读不到（没网络）可以再试
class LoadingPage extends ConsumerWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final error = session.error;
    return Scaffold(
      body: error != null
          ? ErrorPanel(error: error, onRetry: session.refresh)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(context.l10n.loadingContext),
                ],
              ),
            ),
    );
  }
}

/// 登录了，但不是客服：只能登出
class DeniedPage extends ConsumerWidget {
  const DeniedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 48),
                const SizedBox(height: 12),
                Text(l.deniedTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(l.deniedBody, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('denied-sign-out'),
                  onPressed: () => ref.read(sessionProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: Text(l.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
