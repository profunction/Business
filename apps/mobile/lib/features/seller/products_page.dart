import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/seller_providers.dart';
import '../../widgets/common.dart';
import 'seller_widgets.dart';

enum ProductFilter { all, outOfStock, draft }

/// 批发商自己的商品：名字、每箱多少钱、一箱几个、库存（颜色 + 文字）、草稿 / 下架。
/// 上面搜索和三个筛选（全部 / 缺货 / 草稿），底下「新增商品」
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _search = TextEditingController();
  var _filter = ProductFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 缺货：只算上架中的（跟首页 get_seller_home 的 product_counts.out_of_stock 一样）。
  /// 下架、草稿的买家本来就看不到，不算缺货
  static bool _outOfStock(SellerProduct p) =>
      p.status == ProductStatus.active && p.stockStatus == StockStatus.outOfStock;

  bool _matches(SellerProduct p) {
    final ok = switch (_filter) {
      ProductFilter.all => true,
      ProductFilter.outOfStock => _outOfStock(p),
      ProductFilter.draft => p.status == ProductStatus.draft,
    };
    final q = _search.text.trim().toLowerCase();
    return ok && (q.isEmpty || p.name.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final products = ref.watch(sellerProductsProvider);
    final all = products.value ?? const <SellerProduct>[];
    String label(ProductFilter f) {
      final (name, count) = switch (f) {
        ProductFilter.all => (l.sellerFilterAll, null),
        ProductFilter.outOfStock => (l.sellerFilterOutOfStock, all.where(_outOfStock).length),
        ProductFilter.draft => (l.sellerFilterDraft, all.where((p) => p.status == ProductStatus.draft).length),
      };
      return count == null || products.value == null ? name : l.sellerTabWithCount(name, count);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.sellerHomeProducts)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('products-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.sellerProductsSearch,
                prefixIcon: const Icon(Icons.search, size: 28),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.cancel,
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final f in ProductFilter.values) ...[
                    if (f != ProductFilter.values.first) const SizedBox(width: 8),
                    Expanded(
                      child: ModeButton(
                        key: Key('products-filter-${f.name}'),
                        label: label(f),
                        selected: _filter == f,
                        maxLines: 2,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: products,
              onRetry: () => ref.invalidate(sellerProductsProvider),
              builder: (list) => RefreshIndicator(
                onRefresh: () => ref.refresh(sellerProductsProvider.future),
                child: _list(context, list),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton.icon(
          key: const Key('products-add'),
          icon: const Icon(Icons.add, size: 28),
          onPressed: () => context.push('/seller/products/new'),
          label: Text(l.sellerAddProduct),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<SellerProduct> list) {
    final l = context.l10n;
    final shown = list.where(_matches).toList();
    if (shown.isEmpty) {
      return CenterMessage(
        icon: Icons.inventory_2,
        text: list.isEmpty ? l.sellerProductsEmpty : l.sellerProductsNoMatch,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => ProductCard(product: shown[i]),
    );
  }
}

/// 一样商品：名字、价钱 / 单位、一箱几个、起订量；库存和上架状态（颜色 + 文字）。
/// 按了打开改商品页；[onTap] 有给的话改成做那件事（价目表确认页选「更新哪一样」）
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.onTap, this.keyPrefix = 'product', this.note});

  final SellerProduct product;
  final VoidCallback? onTap;

  /// 按的地方的 key：`'$keyPrefix-$id'`（例如 product-…、choose-product-…）
  final String keyPrefix;

  /// 最底下多一行字（例如「第 2 行已经对到这样」）
  final String? note;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final p = product;
    final unit = l.unit(p.unit);
    final hidden = p.status != ProductStatus.active;
    return Card(
      child: InkWell(
        key: Key('$keyPrefix-${p.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ?? () => context.push('/seller/products/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: t.titleLarge?.copyWith(color: hidden ? Colors.black54 : null)),
              const SizedBox(height: 4),
              Text(l.pricePerSellUnit(formatRm(p.priceSen), unit), style: t.titleLarge),
              Text(
                [l.packQty(unit, p.packQty), if (p.minOrderQty > 1) l.minOrderQty(p.minOrderQty, unit)].join(' · '),
                style: t.bodyLarge?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StockChip(status: p.stockStatus),
                  if (p.status == ProductStatus.draft)
                    LabelChip(text: l.sellerStatusDraft, color: const Color(0xFF6A1B9A), icon: Icons.edit_note),
                  if (p.status == ProductStatus.archived)
                    LabelChip(text: l.sellerStatusArchived, color: const Color(0xFF616161), icon: Icons.visibility_off),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 6),
                Text(note!, style: t.bodyLarge?.copyWith(color: const Color(0xFF8A6100))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
