import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'cart_button.dart';

/// 买东西：「看商品」（分类）或「看批发商」
class BrowsePage extends ConsumerStatefulWidget {
  const BrowsePage({super.key, this.byWholesaler = false});

  final bool byWholesaler;

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  late bool _byWholesaler = widget.byWholesaler;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _doSearch() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    context.pushWithQuery('/browse/items', {'q': q, 'title': q});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.browseTitle), actions: const [CartButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    label: l.browseByProduct,
                    icon: Icons.category,
                    selected: !_byWholesaler,
                    onTap: () => setState(() => _byWholesaler = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeButton(
                    label: l.browseByWholesaler,
                    icon: Icons.store,
                    selected: _byWholesaler,
                    onTap: () => setState(() => _byWholesaler = true),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _byWholesaler ? const _WholesalerList() : _categoryList(context)),
        ],
      ),
    );
  }

  Widget _categoryList(BuildContext context) {
    final l = context.l10n;
    final cats = ref.watch(categoriesProvider);
    return AsyncView(
      value: cats,
      onRetry: () => ref.invalidate(categoriesProvider),
      builder: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            key: const Key('search-field'),
            controller: _search,
            textInputAction: TextInputAction.search,
            style: Theme.of(context).textTheme.titleMedium,
            decoration: InputDecoration(
              hintText: l.searchHint,
              prefixIcon: const Icon(Icons.search, size: 30),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _doSearch),
            ),
            onSubmitted: (_) => _doSearch(),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.noResults, textAlign: TextAlign.center),
            ),
          for (final c in list) ...[
            Card(
              child: ListTile(
                key: Key('category-${c.code}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: Icon(_categoryIcon(c.code), size: 36, color: Theme.of(context).colorScheme.primary),
                title: Text(c.name.of(l.lang), style: Theme.of(context).textTheme.titleLarge),
                subtitle: Text(l.categoryItemCount(c.itemCount)),
                trailing: const Icon(Icons.chevron_right, size: 32),
                onTap: () => context.pushWithQuery('/browse/items', {'category': c.id, 'title': c.name.of(l.lang)}),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// 「看商品」/「看批发商」：两个一样大的按钮，选中的是实心
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    return selected
        ? FilledButton(style: style, onPressed: onTap, child: child)
        : OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onTap,
            child: child,
          );
  }
}

IconData _categoryIcon(String code) => switch (code) {
  'cups' => Icons.local_drink,
  'lids' => Icons.circle_outlined,
  'food_containers' => Icons.takeout_dining,
  'bowls' => Icons.ramen_dining,
  'plastic_bags' => Icons.shopping_bag,
  'straws' => Icons.straighten,
  'cutlery' => Icons.restaurant,
  'sauce_cups' => Icons.water_drop,
  'tissue' => Icons.layers,
  _ => Icons.inventory_2,
};

class _WholesalerList extends ConsumerWidget {
  const _WholesalerList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final ws = ref.watch(wholesalersProvider);
    return AsyncView(
      value: ws,
      onRetry: () => ref.invalidate(wholesalersProvider),
      builder: (list) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: list.isEmpty ? 1 : list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (list.isEmpty) {
            return Padding(padding: const EdgeInsets.all(24), child: Text(l.noResults, textAlign: TextAlign.center));
          }
          return _WholesalerCard(w: list[i]);
        },
      ),
    );
  }
}

class _WholesalerCard extends StatelessWidget {
  const _WholesalerCard({required this.w});

  final WholesalerSummary w;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.pushWithQuery('/browse/wholesaler/${w.id}', {'title': w.name}),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(w.name, style: t.titleLarge)),
                  if (!w.priceVisible) const Icon(Icons.lock, color: Colors.black45),
                  const Icon(Icons.chevron_right, size: 32),
                ],
              ),
              if (w.isFounding)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('★ ${l.founding}', style: t.bodyMedium?.copyWith(color: const Color(0xFFB26A00))),
                ),
              const SizedBox(height: 6),
              RatingLine(avg: w.ratingAvg, count: w.ratingCount),
              const SizedBox(height: 6),
              InfoLine(icon: Icons.local_shipping, text: l.leadTime(w.leadTimeDays)),
              InfoLine(icon: Icons.event, text: l.deliveryDays(l.weekdays(w.deliveryWeekdays))),
              InfoLine(
                icon: Icons.payments,
                text: [
                  l.shippingFee(w.shippingFeeSen == 0 ? l.freeShipping : formatRm(w.shippingFeeSen)),
                  if (w.freeShippingMinSen != null) l.freeShippingOver(formatRm(w.freeShippingMinSen!)),
                ].join(' · '),
              ),
              if (w.minOrderSen != null)
                InfoLine(icon: Icons.shopping_cart_checkout, text: l.minOrderAmount(formatRm(w.minOrderSen!))),
              InfoLine(icon: Icons.inventory_2, text: l.productCount(w.productCount)),
            ],
          ),
        ),
      ),
    );
  }
}
