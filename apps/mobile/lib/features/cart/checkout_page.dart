import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'cart_widgets.dart';

/// 确认订单：每家批发商的货价 + 运费，总额写在大按钮上。
/// 「跟上次一样」也来这一页，先告诉老板哪样改了价、哪样买不到。
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key, this.reorder});

  final ReorderResult? reorder;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _place(CartQuote q) async {
    final l = context.l10n;
    setState(() => _busy = true);
    Object? error;
    try {
      await ref
          .read(buyerActionsProvider)
          .placeOrder(
            expectedTotalSen: q.totalSen,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            isReorder: widget.reorder != null,
          );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      context.go('/checkout/done?n=${q.groups.length}');
    } else if (error is AppError && error.code == 'PRICE_CHANGED') {
      // 报价已经刷新了（placeOrder 会 invalidate），老板看一眼新的总额再按
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.priceChangedTitle),
          content: Text(l.errPriceChanged, style: Theme.of(context).textTheme.bodyLarge),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.ok))],
        ),
      );
    } else {
      showMessage(context, l.error(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final quote = ref.watch(cartQuoteProvider);
    final reorder = widget.reorder;

    return Scaffold(
      appBar: AppBar(title: Text(l.confirmTitle)),
      body: AsyncView(
        value: quote,
        onRetry: () => ref.invalidate(cartQuoteProvider),
        builder: (q) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (reorder != null && reorder.priceChanges.isNotEmpty)
              _Notice(
                color: AppTheme.warningBg,
                title: l.reorderPriceChanges,
                lines: [
                  for (final c in reorder.priceChanges)
                    l.priceChangeLine(c.productName, formatRm(c.oldPriceSen), formatRm(c.newPriceSen)),
                ],
              ),
            if (reorder != null && reorder.skipped.isNotEmpty)
              _Notice(
                color: AppTheme.warningBg,
                title: l.reorderSkipped,
                lines: [for (final s in reorder.skipped) s.productName],
              ),
            if (q.groups.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(l.ordersWillSplit(q.groups.length), style: t.bodyLarge),
              ),
            for (final g in q.groups) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(g.wholesalerName, style: t.titleLarge),
                      const SizedBox(height: 6),
                      for (final line in g.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${line.productName}  ×${line.qty} ${l.unit(line.unit)}',
                                  style: t.bodyLarge,
                                ),
                              ),
                              if (line.lineTotalSen != null) Text(formatRm(line.lineTotalSen!), style: t.bodyLarge),
                            ],
                          ),
                        ),
                      for (final line in g.lines.where((x) => x.problem != null))
                        InfoLine(
                          icon: Icons.error,
                          text: '${line.productName} — ${l.cartProblem(line.problem, minQty: line.minOrderQty)}',
                          color: AppTheme.problem,
                        ),
                      const Divider(height: 20),
                      GroupSummary(group: g),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    AmountRow(label: l.goodsSubtotal, value: formatRm(q.goodsTotalSen)),
                    AmountRow(
                      label: l.shipping,
                      value: q.shippingTotalSen == 0 ? l.freeShipping : formatRm(q.shippingTotalSen),
                    ),
                    const Divider(height: 20),
                    AmountRow(label: l.total, value: formatRm(q.totalSen), bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              style: t.bodyLarge,
              decoration: InputDecoration(labelText: '${l.noteLabel}（${l.optional}）'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: switch (quote.value) {
        final q? when !q.isEmpty => BottomAction(
          above: q.canPlace
              ? null
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      InfoLine(icon: Icons.error, text: l.fixProblemsFirst, color: AppTheme.problem),
                      OutlinedButton(onPressed: () => context.push('/cart'), child: Text(l.cartTitle)),
                    ],
                  ),
                ),
          child: BusyButton(
            key: const Key('place-order'),
            label: l.placeOrder(formatRm(q.totalSen)),
            busy: _busy || quote.isLoading,
            onPressed: q.canPlace ? () => _place(q) : null,
          ),
        ),
        _ => null,
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.color, required this.title, required this.lines});

  final Color color;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleMedium),
          const SizedBox(height: 6),
          for (final line in lines) Text('• $line', style: t.bodyLarge),
        ],
      ),
    );
  }
}
