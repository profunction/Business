import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../push/push_prompt.dart';
import '../../widgets/common.dart';

/// 登录后读取「我是谁」的时候；读不到（例如没网络）就给「再试一次」
class LoadingPage extends ConsumerWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final error = session.error;
    return Scaffold(
      body: SafeArea(
        child: error == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ErrorView(error: error, onRetry: session.refresh),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(onPressed: session.signOut, child: Text(context.l10n.logout)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 批发商首页（第四步的页面做好之前先显示一句话）。第一次打开时问要不要打开通知
class SellerPlaceholderPage extends ConsumerStatefulWidget {
  const SellerPlaceholderPage({super.key});

  @override
  ConsumerState<SellerPlaceholderPage> createState() => _SellerPlaceholderPageState();
}

class _SellerPlaceholderPageState extends ConsumerState<SellerPlaceholderPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) askForPushOnce(context, ref, seller: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pending = session.context?.wholesalers.any((w) => w.status == 'pending') ?? false;
    return _MessagePage(
      icon: Icons.store_mall_directory,
      title: session.context?.wholesalers.firstOrNull?.name ?? context.l10n.appTitle,
      message: pending ? context.l10n.sellerPending : context.l10n.sellerComingSoon,
    );
  }
}

class AdminPlaceholderPage extends ConsumerWidget {
  const AdminPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _MessagePage(icon: Icons.support_agent, title: context.l10n.appTitle, message: context.l10n.adminUseWeb);
}

class _MessagePage extends ConsumerWidget {
  const _MessagePage({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 80, color: Colors.black45),
              const SizedBox(height: 20),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: OutlinedButton(onPressed: ref.read(sessionProvider).signOut, child: Text(l.logout)),
      ),
    );
  }
}
