import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
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
          // 最上面：这家批发商的送货条件（每样商品都一样，不用每张卡都写）
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => i == 0
                ? _WholesalerHeader(offer: list.first, count: list.length)
                : OfferCard(offer: list[i - 1], titleIsWholesaler: false, showTerms: false),
          );
        },
      ),
    );
  }
}

class _WholesalerHeader extends StatelessWidget {
  const _WholesalerHeader({required this.offer, required this.count});

  final Offer offer;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = offer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.storefront_outlined, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.wholesalerName, style: t.titleMedium),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RatingLine(avg: o.ratingAvg, count: o.ratingCount),
                          if (o.isFounding) TagChip(label: l.founding, color: AppTheme.caution, icon: Icons.star),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            InfoLine(icon: Icons.local_shipping_outlined, text: l.leadTime(o.leadTimeDays)),
            InfoLine(
              icon: Icons.payments_outlined,
              text: [
                l.shippingFee(o.shippingFeeSen == 0 ? l.freeShipping : formatRm(o.shippingFeeSen)),
                if (o.freeShippingMinSen != null) l.freeShippingOver(formatRm(o.freeShippingMinSen!)),
              ].join(' · '),
            ),
            if (o.minOrderSen != null)
              InfoLine(icon: Icons.shopping_cart_checkout, text: l.minOrderAmount(formatRm(o.minOrderSen!))),
            InfoLine(icon: Icons.inventory_2_outlined, text: l.productCount(count)),
          ],
        ),
      ),
    );
  }
}
