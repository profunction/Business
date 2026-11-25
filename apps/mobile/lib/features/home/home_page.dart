import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 买家首页：几个大按钮，最上面是「跟上次一样」
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  RealtimeChannel? _channel;
  late final WholesaleApi _api;
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiProvider);
    // 批发商一按确认 / 缺货 / 送到，订单页面就自己更新
    final shopId = ref.read(sessionProvider).shopId;
    if (shopId != null) {
      _channel = _api.watchShopOrders(shopId, () {
        if (!mounted) return;
        ref.invalidate(ordersProvider);
        ref.invalidate(buyerHomeProvider);
        ref.invalidate(orderDetailProvider);
      });
    }
  }

  @override
  void dispose() {
    final c = _channel;
    if (c != null) _api.stopWatching(c);
    super.dispose();
  }

  Future<void> _reorder() async {
    setState(() => _reordering = true);
    try {
      final result = await ref.read(buyerActionsProvider).reorderLast();
      if (mounted) context.push('/checkout', extra: result);
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.error(e), error: true);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final home = ref.watch(buyerHomeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(home.value?.shopName ?? l.appTitle),
        actions: [
          IconButton(
            key: const Key('open-settings'),
            tooltip: l.settings,
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: AsyncView(
        value: home,
        onRetry: () => ref.invalidate(buyerHomeProvider),
        builder: (h) => RefreshIndicator(
          onRefresh: () => ref.refresh(buyerHomeProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SubscriptionBanner(info: h.subscription),
              const SizedBox(height: 16),
              if (h.lastCheckout != null) ...[
                BigTile(
                  key: const Key('reorder'),
                  icon: _reordering ? Icons.hourglass_top : Icons.replay,
                  title: l.homeReorder,
                  subtitle: l.homeReorderLast(
                    l.dateOnly(h.lastCheckout!.createdAt),
                    formatRm(h.lastCheckout!.totalSen),
                  ),
                  color: const Color(0xFFE8892B),
                  onTap: _reordering ? null : _reorder,
                ),
                const SizedBox(height: 14),
              ],
              BigTile(
                key: const Key('go-shop'),
                icon: Icons.shopping_basket,
                title: l.homeShop,
                onTap: () => context.push('/browse'),
              ),
              const SizedBox(height: 14),
              BigTile(
                key: const Key('go-orders'),
                icon: Icons.receipt_long,
                title: l.homeOrders,
                subtitle: h.activeOrderCount > 0 ? l.homeActiveOrders(h.activeOrderCount) : null,
                color: const Color(0xFF1565C0),
                badge: h.activeOrderCount > 0 ? '${h.activeOrderCount}' : null,
                onTap: () => context.push('/orders'),
              ),
              if (h.cartCount > 0) ...[
                const SizedBox(height: 14),
                BigTile(
                  key: const Key('go-cart'),
                  icon: Icons.shopping_cart,
                  title: l.homeCart(h.cartCount),
                  color: const Color(0xFF455A64),
                  onTap: () => context.push('/cart'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.info});

  final SubscriptionInfo info;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final days = info.trialDaysLeft(DateTime.now());
    if (days != null) {
      return _Banner(
        color: AppTheme.successBg,
        icon: Icons.celebration,
        text: l.trialBanner(days),
        textStyle: t.titleMedium,
      );
    }
    if (info.hasFullAccess) return const SizedBox.shrink();
    return _Banner(
      color: AppTheme.warningBg,
      icon: Icons.lock_open,
      text: l.freeBanner(info.freeUnlockedLimit),
      textStyle: t.titleMedium,
      action: TextButton(
        key: const Key('banner-choose-wholesalers'),
        onPressed: () => context.push('/free-wholesalers'),
        child: Text(l.chooseWholesalers),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.textStyle, this.action});

  final Color color;
  final IconData icon;
  final String text;
  final TextStyle? textStyle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: textStyle)),
          ?action,
        ],
      ),
    );
  }
}
