import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 批发商的订单：三个大按钮切换「新订单」（先来先做）/「今天要送」/「全部」，选一张单
class SellerOrdersPage extends ConsumerStatefulWidget {
  const SellerOrdersPage({super.key, this.initialTab = SellerOrdersTab.pending});

  final SellerOrdersTab initialTab;

  @override
  ConsumerState<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends ConsumerState<SellerOrdersPage> {
  late SellerOrdersTab _tab = widget.initialTab;
  bool _loadingMore = false;

  Future<void> _refresh() {
    // 「今天要送」的日期和按钮上的数字来自首页
    ref.invalidate(sellerHomeProvider);
    if (_tab == SellerOrdersTab.all) return ref.refresh(sellerAllOrdersProvider.future);
    return ref.refresh(sellerOrdersProvider(_tab).future);
  }

  /// 「全部」：再读一页更早的订单
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      await ref.read(sellerAllOrdersProvider.notifier).loadMore();
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.error(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.watch(sellerRealtimeProvider);
    final home = ref.watch(sellerHomeProvider).value;
    // 「全部」一页一页读（后面还有就显示「再看更早的订单」）；其他两个一次读完
    final all = _tab == SellerOrdersTab.all;
    final AsyncValue<SellerOrderList> orders = all
        ? ref.watch(sellerAllOrdersProvider)
        : ref.watch(sellerOrdersProvider(_tab)).whenData((o) => SellerOrderList(o, hasMore: false));

    String label(SellerOrdersTab t) {
      final (name, count) = switch (t) {
        SellerOrdersTab.pending => (l.sellerTabPending, home?.pendingCount),
        SellerOrdersTab.today => (l.sellerTabToday, home?.todayOrderCount),
        SellerOrdersTab.all => (l.sellerTabAll, null),
      };
      return count == null ? name : l.sellerTabWithCount(name, count);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.sellerOrdersTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            // 三个按钮一样高（字换行的那个也一样）
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in SellerOrdersTab.values) ...[
                    if (t != SellerOrdersTab.values.first) const SizedBox(width: 8),
                    Expanded(
                      child: ModeButton(
                        key: Key('seller-tab-${t.name}'),
                        label: label(t),
                        selected: _tab == t,
                        maxLines: 2,
                        onTap: () => setState(() => _tab = t),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: orders,
              // 「今天要送」要先有首页（日期）：首页读失败的话也要重读，不然一直按都一样失败
              onRetry: () {
                ref.invalidate(sellerHomeProvider);
                if (all) {
                  ref.invalidate(sellerAllOrdersProvider);
                } else {
                  ref.invalidate(sellerOrdersProvider(_tab));
                }
              },
              builder: (o) => RefreshIndicator(
                onRefresh: _refresh,
                child: _list(context, o.orders, hasMore: o.hasMore),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<SellerOrderSummary> list, {required bool hasMore}) {
    final l = context.l10n;
    if (list.isEmpty) {
      final text = switch (_tab) {
        SellerOrdersTab.pending => l.sellerNoNewOrders,
        SellerOrdersTab.today => l.sellerNothingToday,
        SellerOrdersTab.all => l.noOrders,
      };
      return ListView(
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.receipt_long, size: 80, color: Colors.black38),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          ),
        ],
      );
    }
    final showToday = _tab == SellerOrdersTab.today;
    final head = showToday ? 1 : 0;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: list.length + head + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (showToday && i == 0) {
          return _TodayHeader(count: list.length, totalSen: list.fold(0, (n, o) => n + o.totalSen));
        }
        if (i - head == list.length) {
          // 更早的订单还没读：按一下再读一页
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              key: const Key('seller-orders-more'),
              onPressed: _loadingMore ? null : _loadMore,
              icon: _loadingMore
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.expand_more),
              label: Text(l.sellerOrdersLoadMore, textAlign: TextAlign.center),
            ),
          );
        }
        return SellerOrderCard(order: list[i - head]);
      },
    );
  }
}

/// 今天要送：几张单、总额，还有送货单（拣货、打印）
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.count, required this.totalSen});

  final int count;
  final int totalSen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      color: AppTheme.successBg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.sellerTodayCount(count, formatRm(totalSen)), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('seller-open-summary'),
              icon: const Icon(Icons.print),
              onPressed: () => context.push('/seller/summary'),
              label: Text(l.sellerOpenSummary, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张单：店名、区、几样、总额、什么时候下单、哪天送、状态
class SellerOrderCard extends StatelessWidget {
  const SellerOrderCard({super.key, required this.order});

  final SellerOrderSummary order;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = order;
    final zone = o.zoneName.of(l.lang);
    return Card(
      child: InkWell(
        key: Key('seller-order-${o.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/seller/orders/${o.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border(left: BorderSide(color: AppTheme.statusColor(o.status), width: 8)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 放不下（马来文的「送货中」很长、大字）就把状态放到下一行
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(o.shopName, style: t.titleLarge),
                  StatusChip(status: o.status),
                ],
              ),
              const SizedBox(height: 4),
              if (zone.isNotEmpty) InfoLine(icon: Icons.place, text: zone),
              InfoLine(icon: Icons.schedule, text: l.orderedAt(l.dateTime(o.createdAt))),
              if (o.status == OrderStatus.pending)
                InfoLine(
                  icon: Icons.hourglass_top,
                  text: l.sellerWaiting(l.waited(o.createdAt)),
                  color: AppTheme.statusColor(OrderStatus.pending),
                ),
              if (o.status.isActive && o.expectedDeliveryDate != null)
                InfoLine(icon: Icons.local_shipping, text: l.sellerDeliverOn(l.date(o.expectedDeliveryDate!))),
              if (o.outOfStockCount > 0 && o.status != OrderStatus.outOfStock)
                InfoLine(
                  icon: Icons.warning_amber,
                  text: l.outOfStockCount(o.outOfStockCount),
                  color: AppTheme.problem,
                ),
              if (o.note != null) InfoLine(icon: Icons.notes, text: l.sellerBuyerNote(o.note!)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text(l.itemCount(o.itemCount), style: t.bodyLarge)),
                  const SizedBox(width: 8),
                  Text(formatRm(o.totalSen), style: t.titleLarge),
                ],
              ),
              Text(o.orderNo, style: t.bodyMedium?.copyWith(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
