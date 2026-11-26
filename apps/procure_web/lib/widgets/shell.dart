import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/l10n_x.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

typedef _Dest = ({String path, IconData icon, String Function(L10n) label, Set<CompanyRole>? roles});

const _billingRoles = {CompanyRole.admin, CompanyRole.finance};

final List<_Dest> _all = [
  (path: '/home', icon: Icons.dashboard_outlined, label: (l) => l.navHome, roles: null),
  (path: '/browse', icon: Icons.compare_arrows, label: (l) => l.navBrowse, roles: null),
  (path: '/sites', icon: Icons.store_mall_directory_outlined, label: (l) => l.navSites, roles: null),
  (path: '/members', icon: Icons.group_outlined, label: (l) => l.navMembers, roles: _billingRoles),
  (path: '/billing', icon: Icons.workspace_premium_outlined, label: (l) => l.navBilling, roles: _billingRoles),
  (path: '/inbox', icon: Icons.inbox_outlined, label: (l) => l.navInbox, roles: null),
  (path: '/company', icon: Icons.apartment_outlined, label: (l) => l.navCompany, roles: null),
];

/// 我这个角色看得到的页面
List<_Dest> _destinationsFor(MyCompany? c) =>
    _all.where((d) => d.roles == null || (c != null && c.roles.any(d.roles!.contains))).toList();

/// 电脑：左边导航（宽的有字）；手机宽度：左上角的选单。上面：现在的公司（可以换）、收件箱、语言、登出
class ProcureShell extends ConsumerWidget {
  const ProcureShell({super.key, required this.location, required this.child, this.demo = false});

  final String location;
  final Widget child;
  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final session = ref.watch(sessionProvider);
    final company = session.company;
    final dests = _destinationsFor(company);
    final selected = dests.indexWhere((d) => location == d.path || location.startsWith('${d.path}/'));
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 720;
    final wide = width >= 1100;
    final unread = ref.watch(inboxProvider).value?.unreadCount ?? 0;

    final rail = LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              extended: wide,
              labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              selectedIndex: selected < 0 ? null : selected,
              onDestinationSelected: (i) => context.go(dests[i].path),
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(
                    icon: Icon(d.icon, key: Key('nav-${d.path.substring(1)}')),
                    label: Text(d.label(l)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: narrow ? 0 : 16,
        title: _CompanySwitcher(company: company, companies: session.companies),
        actions: [
          IconButton(
            key: const Key('top-inbox'),
            tooltip: l.navInbox,
            onPressed: () => context.go('/inbox'),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_none),
            ),
          ),
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
          SizedBox(width: narrow ? 0 : 8),
        ],
        bottom: demo
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  child: Text(l.demoBanner, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              )
            : null,
      ),
      drawer: narrow
          ? NavigationDrawer(
              selectedIndex: selected < 0 ? null : selected,
              onDestinationSelected: (i) {
                Navigator.pop(context);
                context.go(dests[i].path);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
                  child: Text(l.appTitle, style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final d in dests)
                  NavigationDrawerDestination(
                    icon: Icon(d.icon, key: Key('nav-${d.path.substring(1)}')),
                    label: Text(d.label(l)),
                  ),
              ],
            )
          : null,
      body: narrow
          ? child
          : Row(
              children: [
                rail,
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
    );
  }
}

/// 上面的公司名字：按了可以换另一家公司，或注册新的公司
class _CompanySwitcher extends ConsumerWidget {
  const _CompanySwitcher({required this.company, required this.companies});

  final MyCompany? company;
  final List<MyCompany> companies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return PopupMenuButton<String>(
      key: const Key('company-switcher'),
      tooltip: l.switchCompany,
      onSelected: (v) {
        if (v == '+') {
          context.go('/register');
        } else {
          ref.read(sessionProvider).selectCompany(v);
          context.go('/home');
        }
      },
      itemBuilder: (_) => [
        for (final c in companies)
          CheckedPopupMenuItem(
            key: Key('switch-${c.name}'),
            value: c.id,
            checked: c.id == company?.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('switch-register'),
          value: '+',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_business_outlined),
            title: Text(l.registerAnother),
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.apartment),
          const SizedBox(width: 8),
          Flexible(child: Text(company?.name ?? l.appTitle, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}
