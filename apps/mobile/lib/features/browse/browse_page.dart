import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 分类（底部导航的分页）：搜索 +「看商品」（分类）或「看批发商」
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
      appBar: AppBar(
        title: Text(l.navBrowse),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(116),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  key: const Key('search-field'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _doSearch),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ModeButton(
                        label: l.browseByProduct,
                        icon: Icons.category_outlined,
                        selected: !_byWholesaler,
                        onTap: () => setState(() => _byWholesaler = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ModeButton(
                        label: l.browseByWholesaler,
                        icon: Icons.storefront_outlined,
                        selected: _byWholesaler,
                        onTap: () => setState(() => _byWholesaler = true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _byWholesaler ? const _WholesalerList() : _categoryList(context),
    );
  }

  Widget _categoryList(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final cats = ref.watch(categoriesProvider);
    return AsyncView(
      value: cats,
      onRetry: () => ref.invalidate(categoriesProvider),
      builder: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.noResults, textAlign: TextAlign.center),
            )
          else
            GroupedCard(
              dividerIndent: 64,
              children: [
                for (final c in list)
                  ListTile(
                    key: Key('category-${c.code}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: IconBadge(icon: _categoryIcon(c.code)),
                    title: Text(c.name.of(l.lang)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.categoryItemCount(c.itemCount), style: t.bodySmall),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () => context.pushWithQuery('/browse/items', {'category': c.id, 'title': c.name.of(l.lang)}),
                  ),
              ],
            ),
        ],
      ),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: list.isEmpty ? 1 : list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.noResults, textAlign: TextAlign.center),
            );
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
        onTap: () => context.pushWithQuery('/browse/wholesaler/${w.id}', {'title': w.name}),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(icon: Icons.storefront_outlined, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.name, style: t.titleSmall),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RatingLine(avg: w.ratingAvg, count: w.ratingCount),
                        if (w.isFounding) TagChip(label: l.founding, color: AppTheme.caution, icon: Icons.star),
                        if (!w.priceVisible)
                          TagChip(label: l.priceLocked, color: AppTheme.textSecondary, icon: Icons.lock_outline),
                      ],
                    ),
                    const SizedBox(height: 6),
                    InfoLine(
                      icon: Icons.local_shipping_outlined,
                      text: '${l.leadTime(w.leadTimeDays)} · ${l.deliveryDays(l.weekdays(w.deliveryWeekdays))}',
                    ),
                    InfoLine(
                      icon: Icons.payments_outlined,
                      text: [
                        l.shippingFee(w.shippingFeeSen == 0 ? l.freeShipping : formatRm(w.shippingFeeSen)),
                        if (w.freeShippingMinSen != null) l.freeShippingOver(formatRm(w.freeShippingMinSen!)),
                        if (w.minOrderSen != null) l.minOrderAmount(formatRm(w.minOrderSen!)),
                      ].join(' · '),
                    ),
                    InfoLine(icon: Icons.inventory_2_outlined, text: l.productCount(w.productCount)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
