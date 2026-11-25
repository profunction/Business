import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import 'cart_button.dart';
import 'offer_card.dart';

/// 一家批发商的全部商品
class WholesalerProductsPage extends ConsumerWidget {
  const WholesalerProductsPage({super.key, required this.wholesalerId, required this.title});

  final String wholesalerId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final query = (catalogItemId: null, wholesalerId: wholesalerId);
    final offers = ref.watch(offersProvider(query));
    ref.watch(subscriptionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [CartButton()]),
      body: AsyncView(
        value: offers,
        onRetry: () => ref.invalidate(offersProvider(query)),
        builder: (list) {
          if (list.isEmpty) return Center(child: Text(l.noResults));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => OfferCard(offer: list[i], titleIsWholesaler: false),
          );
        },
      ),
    );
  }
}
