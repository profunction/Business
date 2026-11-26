import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_scope.dart';

/// 商品浏览和比价：选一个分店（送货区、运费照那个分店），同一样标准商品的几家放在一起，按「每个多少钱」排，
/// 最便宜的标出来。价钱看公司的订阅（get_offers，跟小店同一套规则）。下单要开申请单（第 2 期）
class BrowsePage extends ConsumerStatefulWidget {
  const BrowsePage({super.key});

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  String? _siteId;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return CompanyScope(
      builder: (context, c) {
        final sites = c.activeSites;
        final siteId = sites.any((s) => s.id == _siteId) ? _siteId : sites.firstOrNull?.id;
        return ListView(
          children: [
            PageHeader(title: l.navBrowse, subtitle: l.browseHint),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (sites.isNotEmpty)
                    SizedBox(
                      width: 300,
                      child: DropdownButtonFormField<String>(
                        key: const Key('browse-site'),
                        isExpanded: true,
                        initialValue: siteId,
                        decoration: InputDecoration(labelText: l.browseSite),
                        items: [
                          for (final s in sites)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text('${s.name} · ${s.zoneName.of(l.lang)}', overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _siteId = v),
                      ),
                    ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      key: const Key('browse-search'),
                      decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.browseSearch),
                      onSubmitted: (v) => setState(() => _search = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (siteId == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(l.browseNoSite)),
              )
            else
              _Offers(query: (shopId: siteId, search: _search)),
          ],
        );
      },
    );
  }
}

class _Offers extends ConsumerWidget {
  const _Offers({required this.query});

  final OfferQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return AsyncBody(
      value: ref.watch(offersProvider(query)),
      onRetry: () => ref.invalidate(offersProvider(query)),
      builder: (offers) {
        if (offers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(l.browseEmpty)),
          );
        }
        // 同一个标准商品放一组；没对上标准商品的各自一组
        final groups = <String, List<Offer>>{};
        for (final o in offers) {
          groups.putIfAbsent(o.catalogItemId ?? 'p:${o.productId}', () => []).add(o);
        }
        double per(Offer o) => o.pricePerBaseUnitSen ?? double.infinity;
        final list = groups.values.toList()
          ..sort((a, b) => a.first.productName.toLowerCase().compareTo(b.first.productName.toLowerCase()));
        for (final g in list) {
          g.sort((a, b) => per(a).compareTo(per(b)));
        }
        final hidden = offers.any((o) => !o.priceVisible);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hidden)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l.browsePricesHidden, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              for (final g in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _Group(offers: g),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.offers});

  final List<Offer> offers;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cheapest = offers.first.priceVisible && offers.length > 1 ? offers.first.productId : null;
    return Section(
      title: offers.length > 1
          ? l.browseCompareCount(offers.first.productName, offers.length)
          : offers.first.productName,
      child: Column(
        children: [
          for (final o in offers)
            Padding(
              key: Key('offer-${o.productId}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      '${o.wholesalerName} · ${o.productName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(l.browsePack(l.unit(o.unit), o.packQty)),
                  Text(
                    o.priceVisible && o.priceSen != null ? formatRm(o.priceSen!) : l.browsePriceHidden,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (o.priceVisible && o.pricePerBaseUnitSen != null)
                    Text(l.browsePerPiece(formatSen(o.pricePerBaseUnitSen!))),
                  if (o.minOrderQty > 1) Text(l.browseMinQty(o.minOrderQty)),
                  Text(l.browseShipping(formatRm(o.shippingFeeSen), o.leadTimeDays)),
                  if (o.stockStatus == StockStatus.outOfStock) Tag(l.browseOutOfStock, color: const Color(0xFFC62828)),
                  if (o.productId == cheapest)
                    Tag(l.browseCheapest, color: const Color(0xFF2E7D32), icon: Icons.thumb_up_alt_outlined),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
