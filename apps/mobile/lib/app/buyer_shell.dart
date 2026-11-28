import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'l10n_x.dart';
import 'providers.dart';
import 'theme.dart';

/// 买家的五个分页：首页 / 分类 / 购物车 / 订单 / 我的。每个分页自己记住状态（滚到哪里、选了哪个模式）。
/// 分页的路径（/home、/browse、/cart、/orders、/settings）在 router.dart 的 StatefulShellRoute；
/// 详情页（商品、订单详情、确认订单……）盖在整个画面上面，按返回回到原来的分页。
class BuyerShell extends ConsumerWidget {
  const BuyerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// 分页的路径，顺序跟底部按钮一样
  static const tabPaths = ['/home', '/browse', '/cart', '/orders', '/settings'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final cartCount = ref.watch(cartQuoteProvider.select((q) => q.value?.lineCount ?? 0));
    Widget badge(int n, IconData icon) => Badge(
      isLabelVisible: n > 0,
      label: Text('$n'),
      child: Icon(icon),
    );
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          // 再按一次现在的分页：回到那一页的最上面一层
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            NavigationDestination(
              key: const Key('nav-home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l.navHome,
            ),
            NavigationDestination(
              key: const Key('nav-browse'),
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view),
              label: l.navBrowse,
            ),
            NavigationDestination(
              key: const Key('nav-cart'),
              icon: badge(cartCount, Icons.shopping_cart_outlined),
              selectedIcon: badge(cartCount, Icons.shopping_cart),
              label: l.navCart,
            ),
            NavigationDestination(
              key: const Key('nav-orders'),
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: l.navOrders,
            ),
            NavigationDestination(
              key: const Key('nav-me'),
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l.navMe,
            ),
          ],
        ),
      ),
    );
  }
}
