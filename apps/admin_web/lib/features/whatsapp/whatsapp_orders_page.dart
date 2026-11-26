import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

final whatsappQueueProvider = FutureProvider.autoDispose<List<DraftSummary>>(
  (ref) => ref.watch(apiProvider).listOrderDraftQueue(),
);

final orderDraftProvider = FutureProvider.autoDispose.family<OrderDraft, String>(
  (ref, id) => ref.watch(apiProvider).getOrderDraft(id),
);

/// WhatsApp 订单：老板用 WhatsApp 发来的（文字 / 语音），AI 先做好草稿，旧的排前面
class WhatsappOrdersPage extends ConsumerWidget {
  const WhatsappOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(whatsappQueueProvider);
    return ListView(
      children: [
        PageHeader(
          title: l.navWhatsappOrders,
          subtitle: l.waOrdersHint,
          actions: [
            IconButton(
              tooltip: l.retry,
              onPressed: () => ref.invalidate(whatsappQueueProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(whatsappQueueProvider),
          builder: (rows) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.waOrdersEmpty)),
                  )
                : Column(
                    children: [
                      for (final d in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: ListTile(
                              key: Key('wa-draft-${d.id}'),
                              onTap: () => context.go('/whatsapp-orders/${d.id}'),
                              leading: Icon(d.source == DraftSource.whatsappVoice ? Icons.mic : Icons.chat),
                              title: Text('${d.shopName ?? ''} · ${fmtDateTime(d.createdAt)}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (d.transcript ?? '').isEmpty ? l.waNoTranscript : d.transcript!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Tag(
                                        d.source == DraftSource.whatsappVoice ? l.waVoice : l.waText,
                                        color: Colors.teal,
                                      ),
                                      Tag(l.waItems(d.itemCount), color: Colors.blueGrey),
                                      if (d.unmatchedCount > 0)
                                        Tag(l.waUnmatchedCount(d.unmatchedCount), color: Colors.orange),
                                      if (d.errorCode != null) Tag(l.waTagAiFailed, color: Colors.red),
                                      if (d.whatsappWindowOpen == false) Tag(l.waTagWindowClosed, color: Colors.red),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// 一张 WhatsApp 订单：看老板说什么、改草稿（数量、删掉、加商品），代老板下单或不处理（WhatsApp 回原因）
class WhatsappOrderPage extends ConsumerStatefulWidget {
  const WhatsappOrderPage({super.key, required this.draftId});

  final String draftId;

  @override
  ConsumerState<WhatsappOrderPage> createState() => _WhatsappOrderPageState();
}

class _WhatsappOrderPageState extends ConsumerState<WhatsappOrderPage> {
  OrderDraft? _draft;
  bool _busy = false;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AdminApi get _api => ref.read(apiProvider);

  Future<void> _save(List<DraftItem> items) async {
    setState(() => _busy = true);
    try {
      final next = await _api.saveOrderDraft(_draft!.id, items);
      if (mounted) setState(() => _draft = next);
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _qty(int index, int qty) {
    final items = [..._draft!.items];
    if (qty < 1) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(qty: qty);
    }
    _save(items);
  }

  void _add(Offer o) => _save([
    ..._draft!.items,
    DraftItem(
      productId: o.productId,
      qty: o.minOrderQty < 1 ? 1 : o.minOrderQty,
      productName: o.productName,
      unit: o.unit,
      wholesalerId: o.wholesalerId,
      wholesalerName: o.wholesalerName,
    ),
  ]);

  Future<void> _submit(CartQuote q) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final r = await _api.submitOrderDraft(_draft!.id, expectedTotalSen: q.totalSen);
      if (!mounted) return;
      showSnack(context, l.waSubmitted(r.orderNos));
      ref.invalidate(whatsappQueueProvider);
      context.go('/whatsapp-orders');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, l.error(e));
      if (e is AppError && e.code == 'PRICE_CHANGED') {
        final next = await _api.getOrderDraft(_draft!.id).catchError((_) => _draft!);
        if (mounted) setState(() => _draft = next);
      }
    }
  }

  Future<void> _reject() async {
    final l = context.l10n;
    final reason = await showInputDialog(context, title: l.waReject, label: l.waRejectReason, maxLines: 3);
    if (reason == null || !mounted) return;
    final ok = await runAction(
      context,
      () => _api.rejectOrderDraft(_draft!.id, reason: reason.trim().isEmpty ? null : reason.trim()),
      success: l.waRejectedDone,
    );
    if (ok && mounted) {
      ref.invalidate(whatsappQueueProvider);
      context.go('/whatsapp-orders');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(orderDraftProvider(widget.draftId));
    return ListView(
      children: [
        PageHeader(title: l.navWhatsappOrders),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(orderDraftProvider(widget.draftId)),
          builder: (loaded) =>
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _body(_draft ??= loaded)),
        ),
      ],
    );
  }

  Widget _body(OrderDraft d) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    final q = d.quote;
    final problems = {
      for (final g in q?.groups ?? const <CartGroup>[])
        for (final line in g.lines)
          if (line.problem != null) line.productId: l.cartProblem(line.problem, minQty: line.minOrderQty),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: d.shopName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tag(d.source == DraftSource.whatsappVoice ? l.waVoice : l.waText, color: Colors.teal),
                  Text(fmtDateTime(d.createdAt)),
                  PhoneText(d.senderPhone),
                ],
              ),
              if (d.whatsappWindowOpen != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    d.whatsappWindowOpen! ? l.waWindowOpen : l.waWindowClosed,
                    key: const Key('wa-window'),
                    style: TextStyle(color: d.whatsappWindowOpen! ? null : error),
                  ),
                ),
              if (d.errorCode != null) Text(l.waAiFailed(d.errorCode!), style: TextStyle(color: error)),
              const SizedBox(height: 8),
              Text(l.waMessage, style: t.titleSmall),
              SelectableText(
                (d.transcript ?? '').isEmpty ? l.waNoTranscript : d.transcript!,
                key: const Key('wa-text'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!d.isPending)
          Section(child: Text(l.waDone, key: const Key('wa-done')))
        else ...[
          Section(
            title: l.waItems(d.items.length),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.items.isEmpty) Text(l.waEmptyDraft),
                for (final (i, item) in d.items.indexed)
                  Row(
                    key: Key('wa-item-$i'),
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.productName} · ${item.wholesalerName}'),
                            if ((item.said ?? '').isNotEmpty) Text(l.waSaid(item.said!), style: t.bodySmall),
                            if (item.isUnsure) Text(l.waUnsure, style: TextStyle(color: error)),
                            if (problems[item.productId] != null)
                              Text(problems[item.productId]!, style: TextStyle(color: error)),
                          ],
                        ),
                      ),
                      IconButton(
                        key: Key('wa-minus-$i'),
                        onPressed: _busy ? null : () => _qty(i, item.qty - 1),
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${item.qty} ${l.unit(item.unit)}'),
                      IconButton(
                        key: Key('wa-plus-$i'),
                        onPressed: _busy ? null : () => _qty(i, item.qty + 1),
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        key: Key('wa-remove-$i'),
                        tooltip: l.waRemove,
                        onPressed: _busy ? null : () => _qty(i, 0),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                if (d.unmatched.isNotEmpty) ...[
                  const Divider(),
                  Text(l.waUnmatched, style: t.titleSmall),
                  for (final u in d.unmatched) Text('• ${u.said}${u.reason.isEmpty ? '' : '（${u.reason}）'}'),
                ],
                if (q != null && d.items.isNotEmpty) ...[
                  const Divider(),
                  for (final g in q.groups) ...[
                    InfoLine(g.wholesalerName, formatRm(g.totalSen)),
                    if (g.problem == CartProblem.belowMinOrder)
                      Text(l.problemBelowMinOrder(formatRm(g.shortBySen)), style: TextStyle(color: error)),
                  ],
                  InfoLine(l.totalLabel, formatRm(q.totalSen)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('wa-reject'),
                      onPressed: _busy ? null : _reject,
                      child: Text(l.waReject),
                    ),
                    FilledButton(
                      key: const Key('wa-submit'),
                      onPressed: _busy || q == null || d.items.isEmpty || !q.canPlace ? null : () => _submit(q),
                      child: Text(l.waSubmit(formatRm(q?.totalSen ?? 0))),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Section(
            title: l.waAddItem,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('wa-search'),
                  controller: _search,
                  decoration: InputDecoration(labelText: l.waSearchProduct, prefixIcon: const Icon(Icons.search)),
                  onSubmitted: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                _OfferResults(shopId: d.shopId, query: _query, busy: _busy, onPick: _add),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _OfferResults extends ConsumerWidget {
  const _OfferResults({required this.shopId, required this.query, required this.busy, required this.onPick});

  final String shopId;
  final String query;
  final bool busy;
  final ValueChanged<Offer> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(offersProvider((shopId: shopId, search: query)));
    return AsyncBody(
      value: value,
      onRetry: () => ref.invalidate(offersProvider((shopId: shopId, search: query))),
      builder: (offers) {
        final list = offers.where((o) => o.priceVisible).take(20).toList();
        if (list.isEmpty) return Text(l.waNoProducts);
        return Column(
          children: [
            for (final o in list)
              ListTile(
                key: Key('wa-add-${o.productId}'),
                dense: true,
                title: Text(o.productName),
                subtitle: Text('${o.wholesalerName} · ${formatRm(o.priceSen ?? 0)} / ${l.unit(o.unit)}'),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: busy ? null : () => onPick(o),
              ),
          ],
        );
      },
    );
  }
}
