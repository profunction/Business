import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import 'cart_button.dart';
import 'offer_card.dart';

/// 比价钱：同一样东西，每家批发商卖多少（按每个多少钱排，最便宜的框起来）
class ComparePage extends ConsumerWidget {
  const ComparePage({super.key, required this.catalogItemId, required this.title});

  final String catalogItemId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final query = (catalogItemId: catalogItemId, wholesalerId: null);
    final offers = ref.watch(offersProvider(query));
    // 先读一次，卡片上「加进免费名单」要用
    ref.watch(subscriptionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? l.compareTitle : title), actions: const [CartButton()]),
      body: AsyncView(
        value: offers,
        onRetry: () => ref.invalidate(offersProvider(query)),
        builder: (list) {
          if (list.isEmpty) return Center(child: Text(l.noResults));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) =>
                OfferCard(offer: list[i], highlight: i == 0 && list[i].priceVisible && list.length > 1),
          );
        },
      ),
    );
  }
}
