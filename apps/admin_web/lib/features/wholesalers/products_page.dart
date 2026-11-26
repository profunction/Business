import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 代批发商管商品：上架 / 下架、改价钱、改库存、新增。全部走 admin_save_product（写操作记录）
class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key, required this.wholesalerId, required this.wholesalerName});

  final String wholesalerId;
  final String wholesalerName;

  Future<void> _save(BuildContext context, WidgetRef ref, SellerProduct? before, SellerProduct after) async {
    final fields = productChanges(before, after);
    if (fields.isEmpty) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).saveProductAsAdmin(wholesalerId, before?.id, fields),
      success: context.l10n.saved,
    );
    if (ok) {
      ref.invalidate(productsProvider(wholesalerId));
      ref.invalidate(wholesalersProvider);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, SellerProduct? p) async {
    final result = await showDialog<SellerProduct>(
      context: context,
      builder: (_) => ProductDialog(product: p ?? SellerProduct.draft(wholesalerId: wholesalerId)),
    );
    if (result != null && context.mounted) await _save(context, ref, p, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(productsProvider(wholesalerId));
    return ListView(
      children: [
        PageHeader(
          title: l.productsTitle(wholesalerName),
          subtitle: l.productsHint,
          actions: [
            FilledButton.icon(
              key: const Key('product-new'),
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: Text(l.productNew),
            ),
          ],
        ),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(productsProvider(wholesalerId)),
          builder: (products) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: products.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.productsEmpty)),
                  )
                : Card(
                    child: Column(
                      children: [
                        for (final p in products) ...[
                          _ProductRow(
                            product: p,
                            onEdit: () => _edit(context, ref, p),
                            onStock: (s) => _save(context, ref, p, p.copyWith(stockStatus: s)),
                            onStatus: (s) => _save(context, ref, p, p.copyWith(status: s)),
                          ),
                          if (p != products.last) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onEdit, required this.onStock, required this.onStatus});

  final SellerProduct product;
  final VoidCallback onEdit;
  final ValueChanged<StockStatus> onStock;
  final ValueChanged<ProductStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = product;
    return Padding(
      key: Key('product-${p.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  [
                    l.productPerUnit(formatRm(p.priceSen), l.unit(p.unit), p.packQty),
                    if (p.minOrderQty > 1) l.minOrderQty(p.minOrderQty),
                  ].join(' · '),
                ),
              ],
            ),
          ),
          SegmentedButton<StockStatus>(
            key: Key('stock-${p.id}'),
            showSelectedIcon: false,
            segments: [
              for (final s in StockStatus.values)
                ButtonSegment(
                  value: s,
                  label: Text(l.stock(s), key: Key('stock-${p.id}-${s.name}')),
                ),
            ],
            selected: {p.stockStatus},
            onSelectionChanged: (s) => onStock(s.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                key: Key('onsale-${p.id}'),
                value: p.status == ProductStatus.active,
                onChanged: (v) => onStatus(v ? ProductStatus.active : ProductStatus.archived),
              ),
              Text(l.productState(p.status)),
              const SizedBox(width: 8),
              IconButton(
                key: Key('edit-${p.id}'),
                tooltip: l.productEdit,
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 新增 / 改商品的表格
class ProductDialog extends StatefulWidget {
  const ProductDialog({super.key, required this.product});

  final SellerProduct product;

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _price = TextEditingController(text: widget.product.isNew ? '' : senToInput(widget.product.priceSen));
  late final _pack = TextEditingController(text: '${widget.product.packQty}');
  late final _moq = TextEditingController(text: '${widget.product.minOrderQty}');
  late SellUnit _unit = widget.product.unit == SellUnit.unknown ? SellUnit.piece : widget.product.unit;
  late StockStatus _stock = widget.product.stockStatus;
  late ProductStatus _status = widget.product.isNew ? ProductStatus.active : widget.product.status;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _price, _pack, _moq]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    final price = parseRmToSen(_price.text);
    final pack = int.tryParse(_pack.text.trim());
    final moq = int.tryParse(_moq.text.trim());
    final next = widget.product.copyWith(
      name: _name.text.trim(),
      priceSen: price ?? 0,
      packQty: pack ?? 0,
      minOrderQty: moq ?? 0,
      unit: _unit,
      stockStatus: _stock,
      status: _status,
    );
    if (price == null || !next.isValid) {
      setState(() => _error = context.l10n.errInvalidProduct);
      return;
    }
    Navigator.pop(context, next);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(widget.product.isNew ? l.productNew : l.productEdit),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('pf-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.productName),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('pf-price'),
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: l.productPrice),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<SellUnit>(
                      key: const Key('pf-unit'),
                      isExpanded: true,
                      initialValue: _unit,
                      decoration: InputDecoration(labelText: l.productUnit),
                      items: [
                        for (final u in SellUnit.values.where((u) => u != SellUnit.unknown))
                          DropdownMenuItem(value: u, child: Text(l.unit(u))),
                      ],
                      onChanged: (v) => setState(() => _unit = v ?? _unit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('pf-pack'),
                      controller: _pack,
                      inputFormatters: digits,
                      decoration: InputDecoration(labelText: l.productPackQty),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('pf-moq'),
                      controller: _moq,
                      inputFormatters: digits,
                      decoration: InputDecoration(labelText: l.productMinQty),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<StockStatus>(
                      isExpanded: true,
                      initialValue: _stock,
                      decoration: InputDecoration(labelText: l.productStock),
                      items: [for (final s in StockStatus.values) DropdownMenuItem(value: s, child: Text(l.stock(s)))],
                      onChanged: (v) => setState(() => _stock = v ?? _stock),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<ProductStatus>(
                      isExpanded: true,
                      initialValue: _status,
                      decoration: InputDecoration(labelText: l.productStatus),
                      items: [
                        for (final s in ProductStatus.values)
                          DropdownMenuItem(value: s, child: Text(l.productState(s))),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('pf-save'), onPressed: _ok, child: Text(l.save)),
      ],
    );
  }
}
