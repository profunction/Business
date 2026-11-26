import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../cart/cart_widgets.dart';

final orderDraftProvider = FutureProvider.autoDispose.family<OrderDraft, String>(
  (ref, id) => ref.watch(apiProvider).getOrderDraft(id),
);

/// 这家店还没确认的语音草稿（首页提醒）
final pendingDraftsProvider = FutureProvider.autoDispose<List<DraftSummary>>(
  (ref) => ref.watch(apiProvider).listOrderDrafts(ref.watch(shopIdProvider)),
);

/// 确认语音订单：AI 听到什么、对到哪几样。老板可以改数量、换一样、删掉、加一样，按「确认下单」才下单
class VoiceDraftPage extends ConsumerStatefulWidget {
  const VoiceDraftPage({super.key, required this.draftId});

  final String draftId;

  @override
  ConsumerState<VoiceDraftPage> createState() => _VoiceDraftPageState();
}

class _VoiceDraftPageState extends ConsumerState<VoiceDraftPage> {
  OrderDraft? _draft;
  bool _saving = false;
  bool _placing = false;
  final _note = TextEditingController();
  bool _noteFilled = false;

  WholesaleApi get _api => ref.read(apiProvider);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _loaded(OrderDraft d) {
    _draft ??= d;
    // AI 当成「备注」的话（「明天十点前送」）先放进备注
    if (!_noteFilled) {
      _noteFilled = true;
      _note.text = d.unmatched.where((u) => u.isNote).map((u) => u.said).join('；');
    }
  }

  Future<void> _save(List<DraftItem> items, {List<UnmatchedPhrase>? unmatched}) async {
    final d = _draft!;
    setState(() => _saving = true);
    try {
      final next = await _api.saveOrderDraft(d.id, items, unmatched: unmatched);
      if (mounted) setState(() => _draft = next);
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<DraftItem> get _items => _draft!.items;

  void _setQty(int index, int qty) =>
      _save([for (final (i, x) in _items.indexed) i == index ? x.copyWith(qty: qty) : x]);

  void _remove(int index) => _save([
    for (final (i, x) in _items.indexed)
      if (i != index) x,
  ]);

  Future<void> _swap(int index) async {
    final picked = await pickOffer(context, initialSearch: null);
    if (picked == null) return;
    final old = _items[index];
    _save([
      for (final (i, x) in _items.indexed)
        if (i == index) _fromOffer(picked, qty: old.qty, said: old.said) else x,
    ]);
  }

  Future<void> _add({UnmatchedPhrase? resolving}) async {
    final picked = await pickOffer(context, initialSearch: resolving?.said);
    if (picked == null) return;
    _save(
      [..._items, _fromOffer(picked, qty: picked.minOrderQty < 1 ? 1 : picked.minOrderQty, said: resolving?.said)],
      unmatched: resolving == null
          ? null
          : [
              for (final u in _draft!.unmatched)
                if (u != resolving) u,
            ],
    );
  }

  DraftItem _fromOffer(Offer o, {required int qty, String? said}) => DraftItem(
    productId: o.productId,
    qty: qty,
    said: said,
    productName: o.productName,
    unit: o.unit,
    packQty: o.packQty,
    minOrderQty: o.minOrderQty,
    stockStatus: o.stockStatus,
    wholesalerId: o.wholesalerId,
    wholesalerName: o.wholesalerName,
    unitPriceSen: o.priceSen,
  );

  Future<void> _discard() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.voiceDiscardConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(
            key: const Key('voice-discard-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.voiceDiscard),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.rejectOrderDraft(_draft!.id);
      if (!mounted) return;
      ref.invalidate(pendingDraftsProvider);
      showMessage(context, l.voiceDiscarded);
      context.go('/home');
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    }
  }

  Future<void> _place(CartQuote q) async {
    final l = context.l10n;
    setState(() => _placing = true);
    try {
      await _api.submitOrderDraft(
        _draft!.id,
        expectedTotalSen: q.totalSen,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(pendingDraftsProvider);
      ref.invalidate(ordersProvider);
      ref.invalidate(buyerHomeProvider);
      context.go('/checkout/done?n=${q.groups.length}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
      if (e is AppError && e.code == 'PRICE_CHANGED') {
        // 价钱刚好改了：重新读草稿，老板看一眼新的总额再按
        try {
          final next = await _api.getOrderDraft(_draft!.id);
          if (mounted) setState(() => _draft = next);
        } catch (_) {}
      }
      if (mounted) showMessage(context, l.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(orderDraftProvider(widget.draftId));
    final loaded = async.value;
    if (loaded != null) _loaded(loaded);
    final d = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.voiceDraftTitle),
        actions: [
          if (d != null && d.isPending)
            TextButton(key: const Key('voice-discard'), onPressed: _discard, child: Text(l.voiceDiscard)),
        ],
      ),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(orderDraftProvider(widget.draftId)),
        builder: (loaded) => _body(_draft ?? loaded),
      ),
      bottomNavigationBar: switch (d) {
        final d? when d.isPending && d.quote != null => BottomAction(
          above: d.quote!.canPlace || d.items.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InfoLine(icon: Icons.error, text: l.fixProblemsFirst, color: AppTheme.problem),
                ),
          child: BusyButton(
            key: const Key('voice-place'),
            label: l.voiceSubmit(formatRm(d.quote!.totalSen)),
            busy: _placing || _saving,
            onPressed: d.items.isNotEmpty && d.quote!.canPlace ? () => _place(d.quote!) : null,
          ),
        ),
        _ => null,
      },
    );
  }

  Widget _body(OrderDraft d) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final problems = {
      for (final g in d.quote?.groups ?? const <CartGroup>[])
        for (final line in g.lines)
          if (line.problem != null) line.productId: l.cartProblem(line.problem, minQty: line.minOrderQty),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!d.isPending)
          NoticeBanner(
            color: AppTheme.successBg,
            icon: d.status == DraftStatus.confirmed ? Icons.check_circle : Icons.delete_outline,
            text: d.status == DraftStatus.confirmed ? l.voiceDone : l.voiceRejected,
            textStyle: t.titleMedium,
          ),
        if ((d.transcript ?? '').isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.voiceHeard, style: t.titleMedium),
                  const SizedBox(height: 6),
                  Text(d.transcript!, key: const Key('voice-transcript'), style: t.bodyLarge),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final (i, item) in d.items.indexed) _itemCard(d, i, item, problems[item.productId]),
        if (d.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l.voiceNoItems, style: t.bodyLarge),
          ),
        if (d.unmatched.any((u) => !u.isNote)) ...[
          const SizedBox(height: 8),
          Text(l.voiceUnmatched, style: t.titleMedium),
          for (final u in d.unmatched.where((u) => !u.isNote))
            Card(
              color: AppTheme.warningBg,
              child: ListTile(
                title: Text('「${u.said}」', style: t.bodyLarge),
                trailing: d.isPending
                    ? OutlinedButton(
                        key: Key('voice-find-${u.said}'),
                        onPressed: _saving ? null : () => _add(resolving: u),
                        child: Text(l.voiceFind),
                      )
                    : null,
              ),
            ),
        ],
        if (d.isPending) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('voice-add'),
            onPressed: _saving ? null : () => _add(),
            icon: const Icon(Icons.add),
            label: Text(l.voiceAddItem),
          ),
          const SizedBox(height: 12),
          if (d.quote != null && d.items.isNotEmpty) ...[
            for (final g in d.quote!.groups)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(g.wholesalerName, style: t.titleMedium),
                      GroupSummary(group: g),
                    ],
                  ),
                ),
              ),
            AmountRow(label: l.total, value: formatRm(d.quote!.totalSen), bold: true),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('voice-note'),
            controller: _note,
            maxLength: 200,
            style: t.bodyLarge,
            decoration: InputDecoration(labelText: '${l.noteLabel}（${l.optional}）'),
          ),
        ],
      ],
    );
  }

  Widget _itemCard(OrderDraft d, int index, DraftItem item, String? problem) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final editable = d.isPending && !_saving;
    return Card(
      key: Key('voice-item-$index'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName, style: t.titleLarge),
            Text(
              [
                item.wholesalerName,
                if (item.unitPriceSen != null) '${formatRm(item.unitPriceSen!)} / ${l.unit(item.unit)}',
              ].join(' · '),
              style: t.bodyMedium,
            ),
            if ((item.said ?? '').isNotEmpty) Text(l.voiceYouSaid(item.said!), style: t.bodyMedium),
            if (item.isUnsure) InfoLine(icon: Icons.help_outline, text: l.voiceUnsure, color: AppTheme.problem),
            if (problem != null) InfoLine(icon: Icons.error, text: problem, color: AppTheme.problem),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                QtyStepper(
                  key: Key('voice-qty-$index'),
                  value: item.qty,
                  unitLabel: l.unit(item.unit),
                  onChanged: editable ? (q) => _setQty(index, q) : null,
                ),
                if (d.isPending) ...[
                  TextButton.icon(
                    key: Key('voice-swap-$index'),
                    onPressed: editable ? () => _swap(index) : null,
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(l.voiceSwap),
                  ),
                  TextButton.icon(
                    key: Key('voice-remove-$index'),
                    onPressed: editable ? () => _remove(index) : null,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.voiceRemove),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 选一样可以下单的商品（看得到价钱的批发商；搜商品名字）
Future<Offer?> pickOffer(BuildContext context, {String? initialSearch}) => showModalBottomSheet<Offer>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _OfferPicker(initialSearch: initialSearch),
);

class _OfferPicker extends ConsumerStatefulWidget {
  const _OfferPicker({this.initialSearch});

  final String? initialSearch;

  @override
  ConsumerState<_OfferPicker> createState() => _OfferPickerState();
}

class _OfferPickerState extends ConsumerState<_OfferPicker> {
  late final _search = TextEditingController(text: widget.initialSearch ?? '');
  Future<List<Offer>>? _results;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run() {
    final q = _search.text.trim();
    setState(() {
      _results = ref
          .read(apiProvider)
          .getOffers(ref.read(shopIdProvider), search: q.isEmpty ? null : q)
          .then((all) => all.where((o) => o.priceVisible).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.voicePickTitle, style: t.titleLarge),
              const SizedBox(height: 8),
              TextField(
                key: const Key('voice-pick-search'),
                controller: _search,
                style: t.bodyLarge,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _run(),
                decoration: InputDecoration(
                  labelText: l.voiceSearch,
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _run),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Offer>>(
                  future: _results,
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text(l.error(snap.error!)));
                    final list = snap.data;
                    if (list == null) return const Center(child: CircularProgressIndicator());
                    if (list.isEmpty) return Center(child: Text(l.voicePickEmpty, style: t.bodyLarge));
                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final o = list[i];
                        return ListTile(
                          key: Key('voice-pick-${o.productId}'),
                          minTileHeight: 64,
                          title: Text(o.productName, style: t.titleMedium),
                          subtitle: Text(
                            '${o.wholesalerName} · ${formatRm(o.priceSen ?? 0)} / ${l.unit(o.unit)}',
                            style: t.bodyMedium,
                          ),
                          onTap: () => Navigator.pop(context, o),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
