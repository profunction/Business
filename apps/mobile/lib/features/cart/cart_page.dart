import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../voice/mic_button.dart';
import 'cart_widgets.dart';

/// 购物车：改数量、拿掉。按批发商分组，每组显示运费和问题。
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final quote = ref.watch(cartQuoteProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.cartTitle)),
      body: AsyncView(
        value: quote,
        onRetry: () => ref.invalidate(cartQuoteProvider),
        builder: (q) {
          if (q.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.black38),
                  const SizedBox(height: 12),
                  Text(l.cartEmpty, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: MicButton(compact: true)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            // 最上面：语音下单（第六步；做成另一张草稿，不会动到这个购物车）
            itemCount: q.groups.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, i) => i == 0 ? const MicButton(compact: true) : _GroupCard(group: q.groups[i - 1]),
          );
        },
      ),
      bottomNavigationBar: switch (quote.value) {
        final q? when !q.isEmpty => BottomAction(
          above: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                AmountRow(label: l.total, value: formatRm(q.totalSen), bold: true),
                if (!q.canPlace) InfoLine(icon: Icons.error, text: l.fixProblemsFirst, color: AppTheme.problem),
              ],
            ),
          ),
          child: FilledButton(
            key: const Key('go-checkout'),
            onPressed: q.canPlace ? () => context.push('/checkout') : null,
            child: Text(l.goToConfirm),
          ),
        ),
        _ => null,
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final CartGroup group;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(group.wholesalerName, style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            for (final line in group.lines) _CartLineTile(line: line),
            const Divider(height: 24),
            GroupSummary(group: group),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends ConsumerStatefulWidget {
  const _CartLineTile({required this.line});

  final CartLine line;

  @override
  ConsumerState<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends ConsumerState<_CartLineTile> {
  int? _pending;

  Future<void> _set(int qty) async {
    setState(() => _pending = qty);
    try {
      await ref.read(buyerActionsProvider).setCartQty(widget.line.productId, qty);
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.error(e), error: true);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final line = widget.line;
    final unitName = l.unit(line.unit);
    final problem = l.cartProblem(line.problem, minQty: line.minOrderQty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(line.productName, style: t.titleMedium)),
              IconButton(
                tooltip: l.removeFromCart,
                iconSize: 30,
                onPressed: _pending != null ? null : () => _set(0),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (line.unitPriceSen != null)
            Text(
              '${l.pricePerSellUnit(formatRm(line.unitPriceSen!), unitName)} · ${l.packQty(unitName, line.packQty)}',
              style: t.bodyMedium,
            )
          else
            const LockedPrice(),
          const SizedBox(height: 6),
          Row(
            children: [
              QtyStepper(
                value: _pending ?? line.qty,
                min: 1,
                unitLabel: unitName,
                onChanged: _pending != null ? null : _set,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: line.lineTotalSen != null
                        ? Text(formatRm(line.lineTotalSen!), style: t.titleLarge)
                        : const SizedBox(),
                  ),
                ),
              ),
            ],
          ),
          if (problem != null) InfoLine(icon: Icons.error, text: problem, color: AppTheme.problem),
        ],
      ),
    );
  }
}
