import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common.dart';
import 'seller_widgets.dart';

/// 这几个错误的 detail 是第几行：跳到那一行、框红色
const _rowErrors = {'IMPORT_ROW_INCOMPLETE', 'IMPORT_ROW_INVALID_PRODUCT', 'IMPORT_DUPLICATE_PRODUCT'};

/// 确认价目表：AI 读到的每一行（名字、单位、包装数量、价钱、AI 有多肯定、原文），
/// 每行选「新增 / 更新（对到哪样商品）/ 跳过」，不对的按「改」。底下「确认上架（N 样）」
class ImportReviewPage extends ConsumerStatefulWidget {
  const ImportReviewPage({super.key, required this.importId});

  final String importId;

  @override
  ConsumerState<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends ConsumerState<ImportReviewPage> {
  final _rowKeys = <int, GlobalKey>{};

  /// 上架失败时框红色的那一行
  int? _highlight;
  final _busyRows = <String>{};
  bool _applying = false;

  String get _id => widget.importId;

  GlobalKey _keyFor(int rowNo) => _rowKeys.putIfAbsent(rowNo, GlobalKey.new);

  Future<void> _update(PriceListImportRow row, Map<String, Object?> fields) async {
    final l = context.l10n;
    setState(() {
      _busyRows.add(row.id);
      if (_highlight == row.rowNo) _highlight = null;
    });
    try {
      await ref.read(sellerActionsProvider).updateImportRow(row, fields);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busyRows.remove(row.id));
    }
  }

  Future<void> _edit(PriceListImportRow row) async {
    final edited = await showModalBottomSheet<PriceListImportRow>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RowEditor(row: row),
    );
    if (edited == null || !mounted) return;
    // 跳过的行补齐了资料：改成新增（对到商品的话改成更新）
    var e = edited;
    if (e.action == ImportRowAction.skip && e.canCreate) {
      e = e.copyWith(action: e.canUpdate ? ImportRowAction.update : ImportRowAction.create);
    }
    await _update(row, e.toWriteJson());
  }

  Future<void> _apply() async {
    final l = context.l10n;
    setState(() => _applying = true);
    try {
      final r = await ref.read(sellerActionsProvider).applyImport(_id);
      if (!mounted) return;
      showMessage(context, l.sellerApplyDone(r.created, r.updated));
      context.go('/seller/products');
    } on AppError catch (e) {
      if (!mounted) return;
      showMessage(context, l.error(e), error: true);
      final rowNo = e.rowNo;
      if (_rowErrors.contains(e.code) && rowNo != null) _jumpTo(rowNo);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// 跳到某一行，框红色
  void _jumpTo(int rowNo) {
    setState(() => _highlight = rowNo);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _rowKeys[rowNo]?.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final imp = ref.watch(priceListImportProvider(_id));
    final rows = ref.watch(importRowsProvider(_id));
    // 「更新」的那几行要显示对到哪样商品、现在多少钱（读不到也照样可以确认）
    final products = {for (final p in ref.watch(sellerProductsProvider).value ?? <SellerProduct>[]) p.id: p};
    final inReview = imp.value?.status == ImportStatus.review;
    final list = rows.value;
    return Scaffold(
      appBar: AppBar(title: Text(l.sellerReviewTitle)),
      body: AsyncView(
        value: imp,
        onRetry: () {
          ref.invalidate(priceListImportProvider(_id));
          ref.invalidate(importRowsProvider(_id));
        },
        builder: (i) => switch (i.status) {
          ImportStatus.review => AsyncView(
            value: rows,
            onRetry: () => ref.invalidate(importRowsProvider(_id)),
            builder: (rows) => _review(context, rows, products),
          ),
          ImportStatus.processing => CenterMessage(
            icon: Icons.hourglass_top,
            text: l.sellerImportProcessing,
            detail: l.sellerImportWaitHint,
            action: FilledButton(
              key: const Key('review-wait'),
              onPressed: () => context.pushReplacement('/seller/import?id=$_id'),
              child: Text(l.sellerReviewWait),
            ),
          ),
          ImportStatus.failed => CenterMessage(
            icon: Icons.error_outline,
            iconColor: AppTheme.problem,
            text: l.sellerImportFailedTitle,
            detail: l.importFailure(i.errorMessage),
            action: FilledButton(
              key: const Key('review-upload-again'),
              onPressed: () => context.pushReplacement('/seller/import'),
              child: Text(l.sellerImportRetry),
            ),
          ),
          ImportStatus.applied => CenterMessage(
            icon: Icons.check_circle,
            iconColor: AppTheme.confirm,
            text: l.sellerReviewApplied,
            action: FilledButton(
              key: const Key('review-products'),
              onPressed: () => context.go('/seller/products'),
              child: Text(l.sellerReviewGoProducts),
            ),
          ),
        },
      ),
      bottomNavigationBar: !inReview || list == null || list.isEmpty ? null : _bottom(list),
    );
  }

  Widget _bottom(List<PriceListImportRow> rows) {
    final l = context.l10n;
    final count = rows.where((r) => r.action != ImportRowAction.skip).length;
    return BottomAction(
      child: BusyButton(
        key: const Key('review-apply'),
        icon: Icons.check,
        label: l.sellerApply(count),
        busy: _applying,
        onPressed: _applying || count == 0 ? null : _apply,
      ),
    );
  }

  Widget _review(BuildContext context, List<PriceListImportRow> rows, Map<String, SellerProduct> products) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    if (rows.isEmpty) {
      return CenterMessage(
        icon: Icons.search_off,
        text: l.sellerReviewNoRows,
        action: FilledButton(
          onPressed: () => context.pushReplacement('/seller/import'),
          child: Text(l.sellerImportRetry),
        ),
      );
    }
    int count(ImportRowAction a) => rows.where((r) => r.action == a).length;
    final unsure = rows.where((r) => r.isUnsure).length;
    // 全部都建出来（不是 ListView.builder）：上架失败时才跳得到看不见的那一行
    return RefreshIndicator(
      onRefresh: () => ref.refresh(importRowsProvider(_id).future),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: AppTheme.successBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.sellerReviewSummary(
                        rows.length,
                        count(ImportRowAction.create),
                        count(ImportRowAction.update),
                        count(ImportRowAction.skip),
                      ),
                      key: const Key('review-summary'),
                      style: t.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(l.sellerReviewHint, style: t.bodyLarge),
                  ],
                ),
              ),
            ),
            if (unsure > 0) ...[
              const SizedBox(height: 12),
              NoticeBanner(color: AppTheme.warningBg, icon: Icons.warning_amber, text: l.sellerReviewUnsure(unsure)),
            ],
            for (final r in rows) ...[
              const SizedBox(height: 12),
              _RowCard(
                key: _keyFor(r.rowNo),
                row: r,
                product: r.matchedProductId == null ? null : products[r.matchedProductId],
                highlighted: _highlight == r.rowNo,
                busy: _busyRows.contains(r.id),
                onAction: (a) => _update(r, {'action': a.name}),
                onEdit: () => _edit(r),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 还缺哪些资料（照现在选的新增 / 更新）
List<String> missingFields(PriceListImportRow r, L10n l) => switch (r.action) {
  ImportRowAction.skip => const [],
  ImportRowAction.create => [
    if (!r.hasName) l.sellerMissingName,
    if (r.unit == null) l.sellerMissingUnit,
    if (r.packQty == null) l.sellerMissingPack,
    if (r.priceSen == null) l.sellerMissingPrice,
  ],
  ImportRowAction.update => [
    if (r.matchedProductId == null) l.sellerMissingMatch,
    if (r.priceSen == null) l.sellerMissingPrice,
  ],
};

class _RowCard extends StatelessWidget {
  const _RowCard({
    super.key,
    required this.row,
    required this.product,
    required this.highlighted,
    required this.busy,
    required this.onAction,
    required this.onEdit,
  });

  final PriceListImportRow row;

  /// 对到的商品（action = update 时会改它）
  final SellerProduct? product;
  final bool highlighted;
  final bool busy;
  final ValueChanged<ImportRowAction> onAction;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final r = row;
    final skipped = r.action == ImportRowAction.skip;
    final missing = missingFields(r, l);
    final unit = r.unit == null ? null : l.unit(r.unit!);
    final border = highlighted
        ? AppTheme.problem
        : r.isUnsure
        ? AppTheme.unsure
        : const Color(0xFFE2E5DF);
    final dim = skipped ? Colors.black45 : null;
    return Container(
      key: Key('import-row-${r.rowNo}'),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFDE7E7) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: highlighted || r.isUnsure ? 3 : 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.sellerReviewRow(r.rowNo), style: t.bodyLarge?.copyWith(color: Colors.black54)),
              ),
              if (r.isUnsure)
                LabelChip(text: l.sellerReviewCheck, color: const Color(0xFF8A6100), icon: Icons.warning_amber),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.hasName ? r.name!.trim() : l.sellerReviewNoName,
            style: t.titleLarge?.copyWith(color: r.hasName ? dim : Colors.black45),
          ),
          if (r.priceSen != null)
            Text(
              unit == null ? formatRm(r.priceSen!) : l.pricePerSellUnit(formatRm(r.priceSen!), unit),
              style: t.titleMedium?.copyWith(color: dim),
            )
          else
            Text(l.sellerReviewNoPrice, style: t.titleMedium?.copyWith(color: skipped ? dim : AppTheme.problem)),
          if (unit != null && (r.packQty != null || r.minOrderQty != null))
            Text(
              [
                if (r.packQty != null) l.packQty(unit, r.packQty!),
                if (r.minOrderQty != null) l.minOrderQty(r.minOrderQty!, unit),
              ].join(' · '),
              style: t.bodyLarge?.copyWith(color: Colors.black54),
            ),
          if (r.action == ImportRowAction.update && product != null)
            InfoLine(
              icon: Icons.sync,
              text: '${l.sellerReviewMatched(product!.name)} · ${l.sellerReviewPriceNow(formatRm(product!.priceSen))}',
              color: const Color(0xFF1565C0),
            ),
          if (r.action == ImportRowAction.create && r.matchedProductId == null && r.hasName)
            InfoLine(icon: Icons.add_circle_outline, text: l.sellerReviewNoMatch),
          if (missing.isNotEmpty)
            InfoLine(
              icon: Icons.error_outline,
              text: l.sellerReviewMissing(missing.join(l.lang == 'zh' ? '、' : ', ')),
              color: AppTheme.problem,
            ),
          if (r.rawText != null && r.rawText!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l.sellerReviewRaw(r.rawText!.trim()), style: t.bodySmall?.copyWith(color: Colors.black54)),
            ),
          const SizedBox(height: 12),
          ChoiceButtons<ImportRowAction>(
            choices: [
              (
                value: ImportRowAction.create,
                label: l.sellerActionCreate,
                color: AppTheme.confirm,
                key: Key('row-${r.rowNo}-create'),
              ),
              (
                value: ImportRowAction.update,
                label: l.sellerActionUpdate,
                color: const Color(0xFF1565C0),
                key: Key('row-${r.rowNo}-update'),
              ),
              (
                value: ImportRowAction.skip,
                label: l.sellerActionSkip,
                color: const Color(0xFF616161),
                key: Key('row-${r.rowNo}-skip'),
              ),
            ],
            selected: r.action,
            // 没有对到商品就不能「更新」
            enabled: (a) => a != ImportRowAction.update || r.matchedProductId != null,
            onSelected: busy
                ? null
                : (a) {
                    if (a != r.action) onAction(a);
                  },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: Key('row-${r.rowNo}-edit'),
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit),
            label: Text(l.sellerReviewEdit),
          ),
        ],
      ),
    );
  }
}

/// 改一行：名字、单位、包装数量、价钱、最少买几。按「保存」回传改好的行，按取消回传 null
class _RowEditor extends StatefulWidget {
  const _RowEditor({required this.row});

  final PriceListImportRow row;

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final _name = TextEditingController(text: widget.row.name ?? '');
  late final _pack = TextEditingController(text: widget.row.packQty?.toString() ?? '');
  late final _price = TextEditingController(text: widget.row.priceSen == null ? '' : senToInput(widget.row.priceSen!));
  late SellUnit? _unit = widget.row.unit;
  late int? _minQty = widget.row.minOrderQty;
  bool _priceError = false;

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final priceText = _price.text.trim();
    final price = priceText.isEmpty ? null : parseRmToSen(priceText);
    if (priceText.isNotEmpty && price == null) {
      setState(() => _priceError = true);
      return;
    }
    final pack = int.tryParse(_pack.text.trim());
    final name = _name.text.trim();
    final r = widget.row;
    Navigator.pop(
      context,
      PriceListImportRow(
        id: r.id,
        importId: r.importId,
        rowNo: r.rowNo,
        rawText: r.rawText,
        name: name.isEmpty ? null : name,
        unit: _unit,
        packQty: pack != null && pack > 0 ? pack : null,
        priceSen: price,
        minOrderQty: _minQty,
        matchedProductId: r.matchedProductId,
        suggestedCatalogItemId: r.suggestedCatalogItemId,
        action: r.action,
        confidence: r.confidence,
        createdAt: r.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final unit = l.unit(_unit ?? SellUnit.piece);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: t.titleMedium),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (constraints.hasBoundedHeight ? constraints.maxHeight : MediaQuery.sizeOf(context).height) * 0.9,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    children: [
                      Text(l.sellerReviewEditTitle(widget.row.rowNo), style: t.headlineSmall),
                      if (widget.row.rawText != null)
                        Text(
                          l.sellerReviewRaw(widget.row.rawText!.trim()),
                          style: t.bodyMedium?.copyWith(color: Colors.black54),
                        ),
                      label(l.sellerFieldName),
                      TextField(key: const Key('row-edit-name'), controller: _name),
                      label(l.sellerFieldUnit),
                      ChoiceButtons<SellUnit>(
                        choices: [
                          for (final u in SellUnit.values.where((u) => u != SellUnit.unknown))
                            (value: u, label: l.unit(u), color: null, key: Key('row-edit-unit-${u.name}')),
                        ],
                        selected: _unit,
                        onSelected: (u) => setState(() => _unit = u),
                      ),
                      label(l.sellerFieldPrice(unit)),
                      TextField(
                        key: const Key('row-edit-price'),
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (o, n) => RegExp(r'^\d{0,6}(\.\d{0,2})?$').hasMatch(n.text) ? n : o,
                          ),
                        ],
                        onChanged: (_) {
                          if (_priceError) setState(() => _priceError = false);
                        },
                        decoration: InputDecoration(
                          prefixText: 'RM ',
                          hintText: l.sellerFieldPriceHint,
                          errorText: _priceError ? l.sellerErrPrice : null,
                        ),
                      ),
                      label(l.sellerFieldPackQty(unit)),
                      TextField(
                        key: const Key('row-edit-pack'),
                        controller: _pack,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      ),
                      label(l.sellerFieldMinQty(unit)),
                      Center(
                        child: QtyStepper(
                          key: const Key('row-edit-min-qty'),
                          value: _minQty ?? 1,
                          unitLabel: unit,
                          onChanged: (v) => setState(() => _minQty = v),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(key: const Key('row-edit-save'), onPressed: _save, child: Text(l.save)),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const Key('row-edit-cancel'),
                        onPressed: () => Navigator.pop(context),
                        child: Text(l.cancel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
