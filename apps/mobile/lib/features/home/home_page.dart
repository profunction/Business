import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../orders/orders_page.dart';
import '../voice/mic_button.dart';
import '../voice/voice_draft_page.dart';

/// 买家首页：上面店名 + 搜索；快捷动作（跟上次一样、按住说话下单）；常买的商品；最近的订单
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  RealtimeChannel? _channel;
  late final WholesaleApi _api;
  bool _reordering = false;
  final _search = TextEditingController();

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
    _search.dispose();
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

  void _doSearch() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    context.pushWithQuery('/browse/items', {'q': q, 'title': q});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final home = ref.watch(buyerHomeProvider);
    final h = home.value;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(h?.shopName ?? l.appTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (h != null)
              Text(
                h.zoneName.of(l.lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              key: const Key('home-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: InputDecoration(
                hintText: l.searchHint,
                prefixIcon: const Icon(Icons.search),
                fillColor: Theme.of(context).colorScheme.surfaceContainer,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: AsyncView(
        value: home,
        onRetry: () => ref.invalidate(buyerHomeProvider),
        builder: (h) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(pendingDraftsProvider);
            ref.invalidate(ordersProvider);
            return ref.refresh(buyerHomeProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _SubscriptionBanner(info: h.subscription),
              const _PendingDrafts(),
              // 快捷动作：跟上次一样 + 按住说话下单（第六步：AI 做成草稿，老板确认后才下单）
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (h.lastCheckout != null) ...[
                      Expanded(
                        child: ActionTile(
                          key: const Key('reorder'),
                          icon: Icons.replay,
                          title: l.homeReorder,
                          subtitle: l.homeReorderLast(
                            l.dateOnly(h.lastCheckout!.createdAt),
                            formatRm(h.lastCheckout!.totalSen),
                          ),
                          busy: _reordering,
                          onTap: _reorder,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Expanded(child: MicButton()),
                  ],
                ),
              ),
              const _FrequentItems(),
              SectionHeader(
                title: l.homeRecentOrders,
                actionLabel: l.seeAll,
                actionKey: const Key('go-orders'),
                onAction: () => context.go('/orders'),
              ),
              const _RecentOrders(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 还没确认的语音订单（录完没按「确认下单」就离开了）：一条细的提示
class _PendingDrafts extends ConsumerWidget {
  const _PendingDrafts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(pendingDraftsProvider).value ?? const [];
    if (drafts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: const Key('voice-pending'),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => context.push('/voice-draft/${drafts.first.id}'),
        child: NoticeBanner(
          color: AppTheme.warningBg,
          icon: Icons.record_voice_over_outlined,
          text: context.l10n.voicePendingDrafts(drafts.length),
          trailing: const Icon(Icons.chevron_right, size: 20),
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
    final days = info.trialDaysLeft(DateTime.now());
    if (days != null) {
      // 点一下看订阅
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          key: const Key('banner-subscription'),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => context.push('/subscription'),
          child: NoticeBanner(
            color: AppTheme.infoBg,
            icon: Icons.workspace_premium_outlined,
            text: l.trialBanner(days),
            trailing: const Icon(Icons.chevron_right, size: 20),
          ),
        ),
      );
    }
    if (info.hasFullAccess) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NoticeBanner(
        color: AppTheme.warningBg,
        icon: Icons.lock_open,
        text: l.freeBanner(info.freeUnlockedLimit),
        action: TextButton(
          key: const Key('banner-choose-wholesalers'),
          onPressed: () => context.push('/free-wholesalers'),
          child: Text(l.chooseWholesalers, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// 常买的商品：最近几张单里的商品，可以直接 + / − 放进购物车
class _FrequentItems extends ConsumerWidget {
  const _FrequentItems();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final items = ref.watch(frequentItemsProvider);
    final list = items.value;
    if (list == null) {
      // 读取中：一条会动的线（不是什么都不画，测试的 pumpAndSettle 才会等它读完）
      if (items.hasError) return const SizedBox.shrink();
      return const Padding(padding: EdgeInsets.only(top: 24), child: LinearProgressIndicator());
    }
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l.homeFrequent),
        GroupedCard(children: [for (final f in list) _FrequentRow(item: f)]),
      ],
    );
  }
}

class _FrequentRow extends ConsumerStatefulWidget {
  const _FrequentRow({required this.item});

  final FrequentItem item;

  @override
  ConsumerState<_FrequentRow> createState() => _FrequentRowState();
}

class _FrequentRowState extends ConsumerState<_FrequentRow> {
  int? _pending;

  Future<void> _set(int qty) async {
    final l = context.l10n;
    final adding = (ref.read(cartQuoteProvider).value?.qtyOf(widget.item.item.productId!) ?? 0) == 0;
    setState(() => _pending = qty);
    try {
      await ref.read(buyerActionsProvider).setCartQty(widget.item.item.productId!, qty);
      if (mounted && adding && qty > 0) showMessage(context, l.addedToCart);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final f = widget.item;
    final i = f.item;
    final unitName = l.unit(i.unit);
    final inCart = ref.watch(cartQuoteProvider.select((q) => q.value?.qtyOf(i.productId!) ?? 0));
    final qty = _pending ?? inCart;
    return InkWell(
      key: Key('frequent-${i.productId}'),
      onTap: () => context.pushWithQuery('/browse/wholesaler/${f.wholesalerId}', {'title': f.wholesalerName}),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.name, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${l.pricePerSellUnit(formatRm(i.unitPriceSen), unitName)} · ${l.lastOrdered(i.qty, unitName)}',
                    style: t.bodySmall,
                  ),
                  Text(f.wholesalerName, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (qty > 0)
              QtyStepper(value: qty, min: 0, onChanged: _pending != null ? null : _set)
            else
              OutlinedButton.icon(
                key: Key('frequent-add-${i.productId}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(72, 40)),
                // 第一次加：照上次买的数量（一定够起订量）
                onPressed: _pending != null ? null : () => _set(i.qty < 1 ? 1 : i.qty),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.addShort),
              ),
          ],
        ),
      ),
    );
  }
}

/// 最近的三张订单
class _RecentOrders extends ConsumerWidget {
  const _RecentOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final orders = ref.watch(ordersProvider);
    return AsyncView(
      value: orders,
      onRetry: () => ref.invalidate(ordersProvider),
      builder: (list) {
        if (list.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(l.noOrders, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
        }
        return GroupedCard(children: [for (final o in list.take(3)) OrderSummaryTile(order: o)]);
      },
    );
  }
}
