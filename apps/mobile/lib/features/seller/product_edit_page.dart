import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'seller_device.dart';
import 'seller_widgets.dart';

/// 新增 / 改一样商品：名字、单位（九个大按钮）、一箱几个、价钱（数字键盘）、最少买几箱（＋／－）、
/// 库存（有货 / 快卖完 / 缺货）、上架 / 下架、照片（可以不放）。底下一个「保存」
class ProductEditPage extends ConsumerWidget {
  const ProductEditPage({super.key, this.productId});

  /// null = 新增
  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final id = productId;
    if (id == null) {
      final draft = SellerProduct.draft(wholesalerId: ref.watch(wholesalerIdProvider))
          .copyWith(status: ProductStatus.active);
      return _ProductForm(initial: draft);
    }
    final product = ref.watch(sellerProductProvider(id));
    final p = product.value;
    // 读到了就一直用同一个表单（保存后重新读不会把正在改的东西洗掉）
    if (p != null) return _ProductForm(key: ValueKey(p.id), initial: p);
    return Scaffold(
      appBar: AppBar(title: Text(l.sellerEditProduct)),
      body: AsyncView(
        value: product,
        onRetry: () => ref.invalidate(sellerProductProvider(id)),
        builder: (_) => const SizedBox.shrink(),
      ),
    );
  }
}

/// 价钱：只能打数字和一个小数点，最多 2 位小数（RM999,999.99）
final _priceFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) => RegExp(r'^\d{0,6}(\.\d{0,2})?$').hasMatch(newValue.text) ? newValue : oldValue,
);

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({super.key, required this.initial});

  final SellerProduct initial;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final SellerProduct _p = widget.initial;
  late final _name = TextEditingController(text: _p.name);
  late final _pack = TextEditingController(text: _p.isNew ? '' : '${_p.packQty}');
  late final _price = TextEditingController(text: _p.isNew ? '' : senToInput(_p.priceSen));
  late SellUnit _unit = _p.unit == SellUnit.unknown ? SellUnit.piece : _p.unit;
  late int _minQty = _p.minOrderQty;
  late StockStatus _stock = _p.stockStatus;
  late ProductStatus _status = _p.status;

  /// 刚拍 / 选的照片（保存时才上传）
  Uint8List? _photo;
  bool _removePhoto = false;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    _price.dispose();
    super.dispose();
  }

  /// 已经按过保存（有红字）：打字的时候红字跟着更新
  void _changed(String _) {
    if (_showErrors) setState(() {});
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  int? get _priceSen => parseRmToSen(_price.text);
  int? get _packQty {
    final n = int.tryParse(_pack.text.trim());
    return n != null && n > 0 ? n : null;
  }

  Future<void> _pickPhoto(PickSource source) async {
    final l = context.l10n;
    try {
      final file = await ref.read(sellerDeviceProvider).pickImage(source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      checkProductPhoto(bytes);
      if (mounted) setState(() => _photo = bytes);
    } on AppError catch (e) {
      if (!mounted) return;
      showMessage(
        context,
        e.code == 'UNSUPPORTED_FILE' || e.code == 'FILE_TOO_LARGE' ? l.sellerErrPhotoFile : l.error(e),
        error: true,
      );
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    }
  }

  Future<void> _save() async {
    final l = context.l10n;
    final price = _priceSen;
    final pack = _packQty;
    if (!_nameOk || price == null || pack == null) {
      setState(() => _showErrors = true);
      showMessage(context, l.sellerErrForm, error: true);
      return;
    }
    final product = _p.copyWith(
      name: _name.text.trim(),
      unit: _unit,
      packQty: pack,
      priceSen: price,
      minOrderQty: _minQty,
      stockStatus: _stock,
      status: _status,
      photoPaths: _removePhoto && _photo == null ? const [] : null,
    );
    setState(() => _saving = true);
    try {
      await ref.read(sellerActionsProvider).saveProduct(product, photo: _photo);
      if (!mounted) return;
      showMessage(context, l.saved);
      context.pop();
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final unit = l.unit(_unit);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(text, style: t.titleMedium),
    );
    return Scaffold(
      appBar: AppBar(title: Text(_p.isNew ? l.sellerAddProduct : l.sellerEditProduct)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          label(l.sellerFieldName),
          TextField(
            key: const Key('product-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            onChanged: _changed,
            decoration: InputDecoration(
              hintText: l.sellerFieldNameHint,
              errorText: _showErrors && !_nameOk ? l.sellerErrName : null,
            ),
          ),
          label(l.sellerFieldUnit),
          ChoiceButtons<SellUnit>(
            choices: [
              for (final u in SellUnit.values.where((u) => u != SellUnit.unknown))
                (value: u, label: l.unit(u), color: null, key: Key('unit-${u.name}')),
            ],
            selected: _unit,
            onSelected: (u) => setState(() => _unit = u),
          ),
          label(l.sellerFieldPrice(unit)),
          TextField(
            key: const Key('product-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_priceFormatter],
            onChanged: _changed,
            style: t.headlineSmall,
            decoration: InputDecoration(
              prefixText: 'RM ',
              prefixStyle: t.headlineSmall,
              hintText: l.sellerFieldPriceHint,
              errorText: _showErrors && _priceSen == null ? l.sellerErrPrice : null,
            ),
          ),
          label(l.sellerFieldPackQty(unit)),
          TextField(
            key: const Key('product-pack'),
            controller: _pack,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: _changed,
            style: t.headlineSmall,
            decoration: InputDecoration(errorText: _showErrors && _packQty == null ? l.sellerErrPackQty : null),
          ),
          label(l.sellerFieldMinQty(unit)),
          Center(
            child: QtyStepper(
              key: const Key('product-min-qty'),
              value: _minQty,
              unitLabel: unit,
              onChanged: (v) => setState(() => _minQty = v),
            ),
          ),
          label(l.sellerFieldStock),
          ChoiceButtons<StockStatus>(
            choices: [
              for (final s in StockStatus.values)
                (value: s, label: l.stock(s), color: AppTheme.stockColor(s), key: Key('stock-${stockStatusCode(s)}')),
            ],
            selected: _stock,
            onSelected: (s) => setState(() => _stock = s),
          ),
          label(l.sellerFieldStatus),
          ChoiceButtons<ProductStatus>(
            columns: 2,
            choices: [
              (
                value: ProductStatus.active,
                label: l.sellerOnSale,
                color: AppTheme.confirm,
                key: const Key('status-active'),
              ),
              (
                value: ProductStatus.archived,
                label: l.sellerOffSale,
                color: const Color(0xFF616161),
                key: const Key('status-archived'),
              ),
            ],
            selected: _status,
            onSelected: (s) => setState(() => _status = s),
          ),
          if (_status != ProductStatus.active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status == ProductStatus.draft ? l.sellerDraftHint : l.sellerOffSaleHint,
                style: t.bodyLarge?.copyWith(color: Colors.black54),
              ),
            ),
          label(l.sellerPhoto),
          _photoSection(context),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: BusyButton(
          key: const Key('product-save'),
          icon: Icons.check,
          label: l.save,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }

  Widget _photoSection(BuildContext context) {
    final l = context.l10n;
    final existing = _removePhoto || _p.photoPaths.isEmpty ? null : _p.photoPaths.first;
    final Widget? preview = _photo != null
        ? Image.memory(_photo!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _PhotoPlaceholder())
        : existing != null
        ? Image.network(
            ref.read(apiProvider).productPhotoUrl(existing),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
          )
        : null;
    final buttonStyle = OutlinedButton.styleFrom(minimumSize: const Size(0, 56));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(key: const Key('product-photo'), height: 180, child: preview),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              key: const Key('photo-camera'),
              style: buttonStyle,
              onPressed: () => _pickPhoto(PickSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: Text(l.sellerPhotoTake),
            ),
            OutlinedButton.icon(
              key: const Key('photo-gallery'),
              style: buttonStyle,
              onPressed: () => _pickPhoto(PickSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: Text(l.sellerPhotoPick),
            ),
            if (preview != null)
              TextButton.icon(
                key: const Key('photo-remove'),
                onPressed: () => setState(() {
                  _photo = null;
                  _removePhoto = true;
                }),
                icon: const Icon(Icons.delete_outline),
                label: Text(l.sellerPhotoRemove),
              ),
          ],
        ),
      ],
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFE2E5DF),
    child: Center(child: Icon(Icons.image, size: 64, color: Colors.black38)),
  );
}
