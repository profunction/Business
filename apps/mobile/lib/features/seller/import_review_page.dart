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
import 'products_page.dart';
import 'seller_widgets.dart';

/// 这几个错误的 detail 是第几行：跳到那一行、框红色
const _rowErrors = {'IMPORT_ROW_INCOMPLETE', 'IMPORT_ROW_INVALID_PRODUCT', 'IMPORT_DUPLICATE_PRODUCT'};

/// 确认价目表：AI 读到的每一行（名字、单位、包装数量、价钱、AI 有多肯定、原文），
/// 每行选「新增 / 更新（对到哪样商品，可以自己选、换、清掉）/ 跳过」，不对的按「改」。
/// 「更新」会把下架的商品重新上架、改包装：那一行会写出来。底下「确认上架（N 样）」；
/// 这一份不要了（拍错、全部跳过）可以「上传另一份」，不会被困在这一页
class ImportReviewPage extends ConsumerStatefulWidget {
  const ImportReviewPage({super.key, required this.importId});

  final String importId;

  @override
  ConsumerState<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends ConsumerState<ImportReviewPage> {
  final _rowKeys = <int, GlobalKey>{};

  /// 框红色的那几行：还没填好就按了「确认上架」，或服务器说那一行不行
  final _highlight = <int>{};
  final _busyRows = <String>{};
  bool _applying = false;

  String get _id => widget.importId;

  GlobalKey _keyFor(int rowNo) => _rowKeys.putIfAbsent(rowNo, GlobalKey.new);

  /// 改一行。存好、而且列表也重新读好之前，这一行和「确认上架」都按不了：
  /// 不然服务器上架时可能还是旧的价钱，或上架了刚按「跳过」的那一行
  Future<void> _update(PriceListImportRow row, Map<String, Object?> fields) async {
    final l = context.l10n;
    setState(() {
      _busyRows.add(row.id);
      _highlight.remove(row.rowNo);
    });
    try {
      // 改过的行服务器会记下「看过了」（checked_at），重开 App 也记得
      await ref.read(sellerActionsProvider).updateImportRow(row, fields);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) {
        try {
          await ref.read(importRowsProvider(_id).future);
        } catch (_) {
          // 读不到的话页面会显示错误，可以再试
        }
      }
      if (mounted) setState(() => _busyRows.remove(row.id));
    }
  }

  /// 选「更新」要改哪一样商品（也可以清掉：当新商品）。商品还在读 / 读不到的话，选的那一页自己显示、可以再读
  Future<void> _chooseProduct(PriceListImportRow row, List<PriceListImportRow> rows) async {
    final usedBy = <String, int>{
      for (final r in rows)
        if (r.id != row.id && r.action == ImportRowAction.update && r.matchedProductId != null)
          r.matchedProductId!: r.rowNo,
    };
    final chosen = await showModalBottomSheet<_Chosen>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProductChooser(row: row, usedBy: usedBy),
    );
    if (chosen == null || !mounted) return;
    final p = chosen.product;
    await _update(
      row,
      p == null
          // 都不是：不对到任何商品，当新商品（没有名字的话先跳过）
          ? {'matched_product_id': null, 'action': (row.hasName ? ImportRowAction.create : ImportRowAction.skip).name}
          : {'matched_product_id': p.id, 'action': ImportRowAction.update.name},
    );
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
    // 跳过的行这一次才补齐资料（本来不能新增）：改成新增（对到商品的话改成更新）。
    // 本来就齐全、是老板自己按「跳过」的，照样跳过（不然会改掉老板不想改的商品）
    var e = edited;
    if (e.action == ImportRowAction.skip && !row.canCreate && e.canCreate) {
      e = e.copyWith(action: e.canUpdate ? ImportRowAction.update : ImportRowAction.create);
    }
    await _update(row, e.toWriteJson());
  }

  Future<void> _apply() async {
    final l = context.l10n;
    if (_busyRows.isNotEmpty) return;
    // 先自己检查：还没填好的全部框红色、跳到第一行（不用一次按一下、服务器一次只说一行）
    final notReady = [
      for (final r in ref.read(importRowsProvider(_id)).value ?? const <PriceListImportRow>[])
        if (!r.isReady) r.rowNo,
    ]..sort();
    if (notReady.isNotEmpty) {
      showMessage(context, l.sellerReviewIncomplete(notReady.length), error: true);
      _jumpTo(notReady.first, all: notReady);
      return;
    }
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

  /// 跳到某一行；框红色的是 [all]（没给就只有这一行）
  void _jumpTo(int rowNo, {List<int>? all}) {
    setState(() {
      _highlight
        ..clear()
        ..addAll(all ?? [rowNo]);
    });
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
    // 「更新」的那几行要显示对到哪样商品、现在多少钱（读不到也照样可以确认，但那几行会说读不到、往下拉再读）
    final productsValue = ref.watch(sellerProductsProvider);
    final products = {for (final p in productsValue.value ?? <SellerProduct>[]) p.id: p};
    final productsFailed = productsValue.hasError && !productsValue.isLoading;
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
            onRetry: () {
              ref.invalidate(importRowsProvider(_id));
              if (productsFailed) ref.invalidate(sellerProductsProvider);
            },
            builder: (rows) => _review(context, rows, products, productsFailed: productsFailed),
          ),
          ImportStatus.processing => CenterMessage(
            icon: Icons.hourglass_top,
            text: l.sellerImportProcessing,
            detail: l.sellerImportWaitHint,
            action: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  key: const Key('review-wait'),
                  onPressed: () => context.pushReplacement('/seller/import?id=$_id'),
                  child: Text(l.sellerReviewWait),
                ),
                const SizedBox(height: 10),
                // 卡住了、传错了：不等这一份，上传另一份
                OutlinedButton(
                  key: const Key('review-upload-other'),
                  onPressed: () => context.pushReplacement('/seller/import'),
                  child: Text(l.sellerImportUploadOther, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
          ImportStatus.failed => CenterMessage(
            icon: Icons.error_outline,
            iconColor: AppTheme.problem,
            text: l.sellerImportFailedTitle,
            detail: l.importFailure(i.errorMessage, fileType: i.fileType),
            action: FilledButton(
              key: const Key('review-upload-again'),
              onPressed: () => context.pushReplacement('/seller/import'),
              child: Text(l.sellerImportRetry),
            ),
          ),
          // 已经上架：行锁住了（服务器也不让改），只给老板看
          ImportStatus.applied => AsyncView(
            value: rows,
            onRetry: () => ref.invalidate(importRowsProvider(_id)),
            builder: (rows) => rows.isEmpty
                ? CenterMessage(
                    icon: Icons.check_circle,
                    iconColor: AppTheme.confirm,
                    text: l.sellerReviewApplied,
                    action: _goProducts(l),
                  )
                : _review(context, rows, products, productsFailed: productsFailed, readOnly: true),
          ),
        },
      ),
      bottomNavigationBar: !inReview || list == null || list.isEmpty ? null : _bottom(list),
    );
  }

  Widget _goProducts(L10n l) => FilledButton(
    key: const Key('review-products'),
    onPressed: () => context.go('/seller/products'),
    child: Text(l.sellerReviewGoProducts),
  );

  Widget _bottom(List<PriceListImportRow> rows) {
    final l = context.l10n;
    final count = rows.where((r) => r.action != ImportRowAction.skip).length;
    // 还在存某一行（改价钱、跳过）：等存好才可以上架
    final saving = _busyRows.isNotEmpty;
    return BottomAction(
      // 这一份不要了（拍错了、全部都跳过）：上传另一份，首页就不会一直回到这一页
      above: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextButton.icon(
          key: const Key('review-upload-other'),
          icon: const Icon(Icons.upload_file),
          onPressed: _applying ? null : () => context.pushReplacement('/seller/import'),
          label: Text(l.sellerImportUploadOther, textAlign: TextAlign.center),
        ),
      ),
      child: BusyButton(
        key: const Key('review-apply'),
        icon: Icons.check,
        label: l.sellerApply(count),
        busy: _applying || saving,
        onPressed: _applying || saving || count == 0 ? null : _apply,
      ),
    );
  }

  /// 往下拉：行和商品都重新读（商品读不到的话，「会更新：…」才会回来）
  Future<void> _reload() async {
    // 商品读不到不算失败：那几行会说读不到，可以再拉一次
    final products = ref.refresh(sellerProductsProvider.future).then<void>((_) {}, onError: (_) {});
    final rows = ref.refresh(importRowsProvider(_id).future);
    await Future.wait<Object?>([rows, products]);
  }

  Widget _review(
    BuildContext context,
    List<PriceListImportRow> rows,
    Map<String, SellerProduct> products, {
    required bool productsFailed,
    bool readOnly = false,
  }) {
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
    // AI 不太肯定、老板还没看过（改过）的。上架了就不用再看
    bool unsure(PriceListImportRow r) => !readOnly && r.isUnsure && !r.isChecked;
    final unsureCount = rows.where(unsure).length;
    final notReady = readOnly ? 0 : rows.where((r) => !r.isReady).length;
    // 全部都建出来（不是 ListView.builder）：上架失败时才跳得到看不见的那一行
    return RefreshIndicator(
      onRefresh: _reload,
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
                    if (readOnly) ...[
                      Text(l.sellerReviewApplied, key: const Key('review-applied'), style: t.titleMedium),
                      const SizedBox(height: 4),
                      Text(l.sellerReviewAppliedRows, style: t.bodyLarge),
                      const SizedBox(height: 10),
                      _goProducts(l),
                    ] else
                      Text(l.sellerReviewHint, style: t.bodyLarge),
                  ],
                ),
              ),
            ),
            if (unsureCount > 0) ...[
              const SizedBox(height: 12),
              NoticeBanner(
                key: const Key('review-unsure'),
                color: AppTheme.warningBg,
                icon: Icons.warning_amber,
                text: l.sellerReviewUnsure(unsureCount),
              ),
            ],
            if (notReady > 0) ...[
              const SizedBox(height: 12),
              NoticeBanner(
                key: const Key('review-incomplete'),
                color: const Color(0xFFFDE7E7),
                icon: Icons.error_outline,
                text: l.sellerReviewIncomplete(notReady),
              ),
            ],
            for (final r in rows) ...[
              const SizedBox(height: 12),
              _RowCard(
                key: _keyFor(r.rowNo),
                row: r,
                product: r.matchedProductId == null ? null : products[r.matchedProductId],
                productUnknown:
                    productsFailed && r.matchedProductId != null && !products.containsKey(r.matchedProductId),
                unsure: unsure(r),
                highlighted: _highlight.contains(r.rowNo),
                busy: _busyRows.contains(r.id),
                readOnly: readOnly,
                onAction: (a) => _update(r, {'action': a.name}),
                onChooseProduct: () => _chooseProduct(r, rows),
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
    this.productUnknown = false,
    required this.unsure,
    required this.highlighted,
    required this.busy,
    required this.onAction,
    required this.onChooseProduct,
    required this.onEdit,
    this.readOnly = false,
  });

  final PriceListImportRow row;

  /// 已经上架：只给看，不能改（没有新增 / 更新 / 跳过、改的按钮）
  final bool readOnly;

  /// 对到的商品（action = update 时会改它）
  final SellerProduct? product;

  /// 商品读不到（没网络……）：不知道会改哪一样，要说出来（往下拉再读）
  final bool productUnknown;

  /// AI 不太肯定、老板还没看过：框黄色
  final bool unsure;
  final bool highlighted;
  final bool busy;
  final ValueChanged<ImportRowAction> onAction;

  /// 选 / 换要更新的商品
  final VoidCallback onChooseProduct;
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
        : unsure
        ? AppTheme.unsure
        : const Color(0xFFE2E5DF);
    final dim = skipped ? Colors.black45 : null;
    return Container(
      key: Key('import-row-${r.rowNo}'),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFDE7E7) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: highlighted || unsure ? 3 : 1),
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
              if (unsure)
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
          if (r.action == ImportRowAction.update && product != null) ...[
            InfoLine(
              icon: Icons.sync,
              text: '${l.sellerReviewMatched(product!.name)} · ${l.sellerReviewPriceNow(formatRm(product!.priceSen))}',
              color: const Color(0xFF1565C0),
            ),
            // 上架时服务器会把对到的商品改成「上架」，单位、包装数量也照这一行改：先讲清楚
            if (product!.status != ProductStatus.active)
              InfoLine(
                icon: Icons.visibility,
                text: l.sellerReviewWillRelist(
                  product!.status == ProductStatus.draft ? l.sellerStatusDraft : l.sellerStatusArchived,
                ),
                color: _warning,
              ),
            if (_packChanges(product!))
              InfoLine(
                icon: Icons.inventory_2,
                text: l.sellerReviewPackChange(
                  l.packQty(l.unit(product!.unit), product!.packQty),
                  l.packQty(l.unit(r.unit ?? product!.unit), r.packQty ?? product!.packQty),
                ),
                color: _warning,
              ),
          ],
          if (r.action == ImportRowAction.update && product == null && productUnknown)
            InfoLine(
              key: Key('row-${r.rowNo}-product-unknown'),
              icon: Icons.sync_problem,
              text: l.sellerReviewProductUnknown,
              color: _warning,
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
              // 原文是用来对照 AI 读得对不对的：跟其他字一样大（最小 18）
              child: Text(
                l.sellerReviewRaw(r.rawText!.trim()),
                key: Key('row-${r.rowNo}-raw'),
                style: t.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ),
          if (readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LabelChip(
                  key: Key('row-${r.rowNo}-locked'),
                  text: l.importAction(r.action),
                  color: const Color(0xFF616161),
                  icon: Icons.lock,
                ),
              ),
            ),
          if (!readOnly) ...[
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
              onSelected: busy
                  ? null
                  : (a) {
                      if (a == r.action) return;
                      // 「更新」还没有对到商品：先选是哪一样
                      if (a == ImportRowAction.update && r.matchedProductId == null) {
                        onChooseProduct();
                      } else {
                        onAction(a);
                      }
                    },
            ),
            if (r.action == ImportRowAction.update) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: Key('row-${r.rowNo}-choose'),
                onPressed: busy ? null : onChooseProduct,
                icon: const Icon(Icons.swap_horiz),
                label: Text(l.sellerReviewChangeProduct, textAlign: TextAlign.center),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('row-${r.rowNo}-edit'),
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit),
              label: Text(l.sellerReviewEdit),
            ),
          ],
        ],
      ),
    );
  }

  static const _warning = Color(0xFF8A6100);

  /// 这一行会改掉商品的单位或包装数量
  bool _packChanges(SellerProduct p) =>
      (row.unit != null && row.unit != p.unit) || (row.packQty != null && row.packQty != p.packQty);
}

/// 选商品的结果：product == null = 都不是（不对到任何商品）
typedef _Chosen = ({SellerProduct? product});

/// 选「更新」要改哪一样商品：自己的全部商品（可以搜；下架、草稿的也在），已经被别行对到的会写出来。
/// 已经对到商品的行可以按「都不是」清掉。关掉回传 null。
/// 商品还在读：转圈；读不到：说原因、可以再读（不会说成「找不到符合的商品」）
class _ProductChooser extends ConsumerStatefulWidget {
  const _ProductChooser({required this.row, required this.usedBy});

  final PriceListImportRow row;

  /// 商品 id → 已经对到它的那一行（不算这一行）
  final Map<String, int> usedBy;

  @override
  ConsumerState<_ProductChooser> createState() => _ProductChooserState();
}

class _ProductChooserState extends ConsumerState<_ProductChooser> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final r = widget.row;
    final q = _search.text.trim().toLowerCase();
    final products = ref.watch(sellerProductsProvider);
    final shown = (products.value ?? const <SellerProduct>[])
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
    final rowText = r.hasName ? r.name!.trim() : r.rawText?.trim();
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.sellerReviewChooseProduct, style: t.headlineSmall),
                      Text(l.sellerReviewRow(r.rowNo), style: t.bodyLarge?.copyWith(color: Colors.black54)),
                      if (rowText != null && rowText.isNotEmpty) Text(rowText, style: t.titleMedium),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('choose-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: l.sellerProductsSearch,
                          prefixIcon: const Icon(Icons.search, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: products.hasError && !products.isLoading && !products.hasValue
                      ? SingleChildScrollView(
                          key: const Key('choose-error'),
                          child: ErrorView(
                            error: products.error!,
                            onRetry: () => ref.invalidate(sellerProductsProvider),
                          ),
                        )
                      : !products.hasValue
                      ? const Padding(
                          key: Key('choose-loading'),
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l.sellerProductsNoMatch, textAlign: TextAlign.center, style: t.titleMedium),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final p = shown[i];
                            final used = widget.usedBy[p.id];
                            return ProductCard(
                              product: p,
                              keyPrefix: 'choose-product',
                              note: used == null ? null : l.sellerReviewUsedByRow(used),
                              onTap: () => Navigator.pop(context, (product: p)),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (r.matchedProductId != null) ...[
                        OutlinedButton(
                          key: const Key('choose-none'),
                          onPressed: () => Navigator.pop(context, (product: null)),
                          child: Text(l.sellerReviewClearMatch, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 4),
                      ],
                      TextButton(
                        key: const Key('choose-cancel'),
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
