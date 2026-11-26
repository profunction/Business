import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

const _pageSize = 50;

/// 全部订单：按日期、批发商、店铺、状态、来源筛选；也可以只看超过 30 分钟没确认的
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key, this.initialWholesalerId, this.initialShopId});

  final String? initialWholesalerId;
  final String? initialShopId;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late AdminOrderFilter _filter = AdminOrderFilter(
    wholesalerId: widget.initialWholesalerId,
    shopId: widget.initialShopId,
    limit: _pageSize,
  );

  void _set(AdminOrderFilter f) => setState(() => _filter = f);

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final current = from ? _filter.from : _filter.to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2025),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    _set(from ? _filter.copyWith(from: () => picked) : _filter.copyWith(to: () => picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(ordersPageProvider(_filter));
    final minutes = ref.watch(dashboardProvider).value?.alertMinutes ?? 30;
    return ListView(
      children: [
        PageHeader(
          title: l.navOrders,
          actions: [
            IconButton(
              tooltip: l.retry,
              onPressed: () => ref.invalidate(ordersPageProvider(_filter)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _FilterBar(filter: _filter, alertMinutes: minutes, onChanged: _set, onPickDate: _pickDate),
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(ordersPageProvider(_filter)),
          builder: (page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.ordersTotal(page.total), key: const Key('orders-total')),
                const SizedBox(height: 8),
                if (page.orders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.ordersEmpty)),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final o in page.orders) ...[
                          OrderRowTile(order: o, onTap: () => context.go('/orders/${o.id}')),
                          if (o != page.orders.last) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                if (page.total > _filter.limit)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          l.pageRange(
                            _filter.offset + 1,
                            (_filter.offset + page.orders.length).clamp(0, page.total),
                            page.total,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _filter.offset == 0
                              ? null
                              : () => _set(_filter.copyWith(offset: (_filter.offset - _pageSize).clamp(0, page.total))),
                          child: Text(l.pagePrev),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _filter.offset + _pageSize >= page.total
                              ? null
                              : () => _set(_filter.copyWith(offset: _filter.offset + _pageSize)),
                          child: Text(l.pageNext),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.filter,
    required this.alertMinutes,
    required this.onChanged,
    required this.onPickDate,
  });

  final AdminOrderFilter filter;
  final int alertMinutes;
  final ValueChanged<AdminOrderFilter> onChanged;
  final Future<void> Function({required bool from}) onPickDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final wholesalers = ref.watch(wholesalersProvider((status: null, search: ''))).value ?? const [];
    final shops = ref.watch(shopsProvider('')).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('filter-from'),
              onPressed: () => onPickDate(from: true),
              icon: const Icon(Icons.event, size: 18),
              label: Text('${l.filterFrom} ${fmtDate(filter.from)}'),
            ),
            OutlinedButton.icon(
              key: const Key('filter-to'),
              onPressed: () => onPickDate(from: false),
              icon: const Icon(Icons.event, size: 18),
              label: Text('${l.filterTo} ${fmtDate(filter.to)}'),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                key: const Key('filter-wholesaler'),
                initialValue: wholesalers.any((w) => w.id == filter.wholesalerId) ? filter.wholesalerId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.filterWholesaler),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.all)),
                  for (final w in wholesalers)
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(w.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => onChanged(filter.copyWith(wholesalerId: () => v)),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                key: const Key('filter-shop'),
                initialValue: shops.any((s) => s.id == filter.shopId) ? filter.shopId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.filterShop),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.all)),
                  for (final s in shops)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => onChanged(filter.copyWith(shopId: () => v)),
              ),
            ),
            TextButton.icon(
              key: const Key('filter-clear'),
              onPressed: () => onChanged(AdminOrderFilter(limit: filter.limit)),
              icon: const Icon(Icons.clear),
              label: Text(l.filterClear),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${l.filterStatus}:'),
            for (final s in OrderStatus.values)
              FilterChip(
                key: Key('status-${s.name}'),
                label: Text(l.status(s)),
                selected: filter.statuses.contains(s),
                onSelected: (on) => onChanged(
                  filter.copyWith(statuses: on ? {...filter.statuses, s} : ({...filter.statuses}..remove(s))),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${l.filterSource}:'),
            for (final s in OrderSource.values)
              FilterChip(
                key: Key('source-${s.name}'),
                label: Text(l.source(s)),
                selected: filter.sources.contains(s),
                onSelected: (on) =>
                    onChanged(filter.copyWith(sources: on ? {...filter.sources, s} : ({...filter.sources}..remove(s)))),
              ),
            const SizedBox(width: 12),
            FilterChip(
              key: const Key('filter-unconfirmed'),
              avatar: const Icon(Icons.timer_outlined, size: 18),
              label: Text(l.filterUnconfirmed(alertMinutes)),
              selected: filter.unconfirmedOnly,
              onSelected: (on) => onChanged(filter.copyWith(unconfirmedOnly: on)),
            ),
          ],
        ),
      ],
    );
  }
}

/// 订单一行：单号、状态、店 → 批发商、总额、时间、来源
class OrderRowTile extends StatelessWidget {
  const OrderRowTile({super.key, required this.order, required this.onTap, this.extra});

  final AdminOrderRow order;
  final VoidCallback onTap;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return InkWell(
      key: Key('order-${order.orderNo}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(order.orderNo, style: t.titleSmall),
                      StatusTag(order.status),
                      Tag(l.source(order.source), color: Theme.of(context).colorScheme.secondary),
                      if (order.pendingMinutes != null) Text(l.pendingFor(order.pendingMinutes!), style: t.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${order.shopName}  →  ${order.wholesalerName}'),
                  Text(fmtDateTime(order.createdAt), style: t.bodySmall),
                  ?extra,
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(formatRm(order.totalSen), style: t.titleMedium),
          ],
        ),
      ),
    );
  }
}
