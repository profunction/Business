import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [GroupedCard(children: [for (final i in list) _ItemRow(item: i)])],
          );
        },
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final CatalogItemSummary item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final name = item.name.of(l.lang);
    return InkWell(
      key: Key('item-${item.id}'),
      onTap: () => context.pushWithQuery('/browse/item/${item.id}', {'title': name}),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    [
                      l.sellerCount(item.offerCount),
                      if (item.fastestLeadTimeDays != null) l.leadTime(item.fastestLeadTimeDays!),
                    ].join(' · '),
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 价钱靠右
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: item.minPricePerBaseUnitSen != null
                  ? Text(
                      l.cheapestPerUnit(formatSen(item.minPricePerBaseUnitSen!)),
                      textAlign: TextAlign.right,
                      style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Flexible(child: Text(l.priceLocked, style: t.bodySmall)),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
