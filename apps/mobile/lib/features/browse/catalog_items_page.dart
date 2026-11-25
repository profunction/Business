import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'cart_button.dart';

/// 一个分类（或搜索结果）里的标准商品：几家有卖、最便宜每个多少钱
class CatalogItemsPage extends ConsumerWidget {
  const CatalogItemsPage({super.key, this.categoryId, required this.title, this.search});

  final String? categoryId;
  final String title;
  final String? search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final query = (categoryId: categoryId, search: search);
    final items = ref.watch(catalogItemsProvider(query));
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [CartButton()]),
      body: AsyncView(
        value: items,
        onRetry: () => ref.invalidate(catalogItemsProvider(query)),
        builder: (list) {
          if (list.isEmpty) {
            return Center(child: Text(l.noResults, style: t.titleMedium));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _ItemCard(item: list[i]),
          );
        },
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final CatalogItemSummary item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final name = item.name.of(l.lang);
    return Card(
      child: InkWell(
        key: Key('item-${item.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.pushWithQuery('/browse/item/${item.id}', {'title': name}),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: t.titleLarge),
                    const SizedBox(height: 6),
                    Text(l.sellerCount(item.offerCount), style: t.bodyLarge),
                    const SizedBox(height: 4),
                    if (item.minPricePerBaseUnitSen != null)
                      Text(
                        l.cheapestPerUnit(formatSen(item.minPricePerBaseUnitSen!)),
                        style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                      )
                    else
                      Row(
                        children: [
                          const Icon(Icons.lock, size: 20, color: Colors.black45),
                          const SizedBox(width: 6),
                          Text(l.priceLocked, style: t.bodyLarge?.copyWith(color: Colors.black54)),
                        ],
                      ),
                    if (item.fastestLeadTimeDays != null) ...[
                      const SizedBox(height: 4),
                      Text(l.leadTime(item.fastestLeadTimeDays!), style: t.bodyMedium?.copyWith(color: Colors.black54)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
