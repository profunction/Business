import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/l10n_x.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

typedef _Dest = ({String path, IconData icon, String Function(L10n) label});

final List<_Dest> _destinations = [
  (path: '/dashboard', icon: Icons.dashboard_outlined, label: (l) => l.navDashboard),
  (path: '/orders', icon: Icons.receipt_long_outlined, label: (l) => l.navOrders),
  (path: '/followup', icon: Icons.phone_in_talk_outlined, label: (l) => l.navFollowup),
  (path: '/whatsapp-orders', icon: Icons.chat_outlined, label: (l) => l.navWhatsappOrders),
  (path: '/place-order', icon: Icons.add_shopping_cart, label: (l) => l.navPlaceOrder),
  (path: '/wholesalers', icon: Icons.store_outlined, label: (l) => l.navWholesalers),
  (path: '/subscriptions', icon: Icons.card_membership_outlined, label: (l) => l.navSubscriptions),
  (path: '/commission', icon: Icons.request_quote_outlined, label: (l) => l.navCommission),
  (path: '/payments', icon: Icons.payments_outlined, label: (l) => l.navPayments),
  (path: '/audit', icon: Icons.history, label: (l) => l.navAudit),
];

/// 左边导航（电脑：有字；平板：只有图标 + 小字），上面标题、语言、登出
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child, this.demo = false});

  final String location;
  final Widget child;
  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final selected = _destinations.indexWhere((d) => location == d.path || location.startsWith('${d.path}/'));
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          PopupMenuButton<String>(
            key: const Key('language-menu'),
            tooltip: l.language,
            icon: const Icon(Icons.translate),
            onSelected: (code) => ref.read(sessionProvider).setLocale(code),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'zh', child: Text('华文')),
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
            ],
          ),
          IconButton(
            key: const Key('sign-out'),
            tooltip: l.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider).signOut(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: demo
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  child: Text(l.demoBanner, textAlign: TextAlign.center),
                ),
              )
            : null,
      ),
      body: Row(
        children: [
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    extended: wide,
                    labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                    selectedIndex: selected < 0 ? null : selected,
                    onDestinationSelected: (i) => context.go(_destinations[i].path),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon, key: Key('nav-${d.path.substring(1)}')),
                          label: Text(d.label(l)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
