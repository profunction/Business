import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../voice/mic_button.dart';
import '../voice/voice_draft_page.dart';

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
          onRefresh: () {
            ref.invalidate(pendingDraftsProvider);
            return ref.refresh(buyerHomeProvider.future);
          },
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
              // 语音下单（第六步）：按住说话，AI 做成草稿，老板确认后才下单
              const SizedBox(height: 14),
              const MicButton(),
              const SizedBox(height: 14),
              const _PendingDrafts(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 还没确认的语音订单（录完没按「确认下单」就离开了）
class _PendingDrafts extends ConsumerWidget {
  const _PendingDrafts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(pendingDraftsProvider).value ?? const [];
    if (drafts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: BigTile(
        key: const Key('voice-pending'),
        icon: Icons.record_voice_over,
        title: context.l10n.voicePendingDrafts(drafts.length),
        subtitle: drafts.first.transcript,
        color: const Color(0xFFFFE0B2),
        onTap: () => context.push('/voice-draft/${drafts.first.id}'),
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
      // 点一下看订阅（不加按钮：横幅不会变高，把下面的东西挤下去）
      return InkWell(
        key: const Key('banner-subscription'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/subscription'),
        child: NoticeBanner(
          color: AppTheme.successBg,
          icon: Icons.celebration,
          text: l.trialBanner(days),
          textStyle: t.titleMedium,
        ),
      );
    }
    if (info.hasFullAccess) return const SizedBox.shrink();
    return NoticeBanner(
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
