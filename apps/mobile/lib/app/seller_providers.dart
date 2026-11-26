import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../push/push_service.dart';
import 'providers.dart';

/// 批发商首页：新订单、今天要送、商品数量、最近一次价目表（get_seller_home）
final sellerHomeProvider = FutureProvider.autoDispose<SellerHome>(
  (ref) => ref.watch(apiProvider).getSellerHome(ref.watch(wholesalerIdProvider)),
);

/// 收费页：创始上架费、佣金、账单（get_seller_billing）
final sellerBillingProvider = FutureProvider.autoDispose<SellerBilling>(
  (ref) => ref.watch(apiProvider).getSellerBilling(ref.watch(wholesalerIdProvider)),
);

/// 一张佣金账单的明细
final invoiceDetailProvider = FutureProvider.autoDispose.family<InvoiceDetail, String>(
  (ref, id) => ref.watch(apiProvider).getCommissionInvoice(id),
);

/// 订单列表的三个分页
enum SellerOrdersTab { pending, today, all }

/// ?tab=pending|today|all（不认识的当 pending）
SellerOrdersTab sellerOrdersTabFrom(String? v) =>
    SellerOrdersTab.values.firstWhere((t) => t.name == v, orElse: () => SellerOrdersTab.pending);

/// list_seller_orders()：
/// - pending：新订单，先来先做（服务器排好：旧到新）
/// - today：今天要送（已确认 / 送货中，送货日 = 服务器算的马来西亚今天）
/// - all：全部（pending 在最前面，其他新到旧）。只读第一页；页面用 [sellerAllOrdersProvider]（可以「再看更早的」）
final sellerOrdersProvider = FutureProvider.autoDispose.family<List<SellerOrderSummary>, SellerOrdersTab>((
  ref,
  tab,
) async {
  final api = ref.watch(apiProvider);
  final wid = ref.watch(wholesalerIdProvider);
  switch (tab) {
    case SellerOrdersTab.pending:
      return api.listSellerOrders(wid, statuses: const [OrderStatus.pending], limit: 200);
    case SellerOrdersTab.today:
      // 「今天」用服务器的（手机的时间可能不准，也可能不在马来西亚）
      final home = ref.watch(sellerHomeProvider.future);
      final today = (await home).today;
      return api.listSellerOrders(
        wid,
        statuses: const [OrderStatus.confirmed, OrderStatus.delivering],
        deliveryDate: today,
        limit: 200,
      );
    case SellerOrdersTab.all:
      return api.listSellerOrders(wid, limit: sellerAllOrdersPageSize);
  }
});

/// 「全部」一次读几张；按「再看更早的订单」再读一页（游标分页）
const sellerAllOrdersPageSize = 50;

/// 「全部」读到的订单，和后面还有没有
class SellerOrderList {
  const SellerOrderList(this.orders, {required this.hasMore});

  final List<SellerOrderSummary> orders;
  final bool hasMore;
}

/// 每一家批发商「全部」已经读了几张（重新读的时候照样读这么多，按了「再看更早的」就不会一刷新又缩回第一页）
final _sellerAllOrdersShownProvider = Provider<Map<String, int>>((ref) => {});

/// 「全部」的订单：一页一页读（list_seller_orders 的 p_after = 上一页最后一张的 cursor）
final sellerAllOrdersProvider = AsyncNotifierProvider.autoDispose<SellerAllOrders, SellerOrderList>(
  SellerAllOrders.new,
);

class SellerAllOrders extends AsyncNotifier<SellerOrderList> {
  bool _loadingMore = false;

  @override
  Future<SellerOrderList> build() async {
    final api = ref.watch(apiProvider);
    final wid = ref.watch(wholesalerIdProvider);
    final wanted = ref.read(_sellerAllOrdersShownProvider)[wid] ?? sellerAllOrdersPageSize;
    final list = <SellerOrderSummary>[];
    String? after;
    while (true) {
      final n = (wanted - list.length).clamp(1, 200);
      final page = await api.listSellerOrders(wid, limit: n, after: after);
      _append(list, page);
      after = page.isEmpty ? null : page.last.cursor;
      if (page.length < n || after == null) return SellerOrderList(list, hasMore: false);
      if (list.length >= wanted) return SellerOrderList(list, hasMore: true);
    }
  }

  /// 再读一页（更早的订单）。读不到就丢错（页面说一句话），已经读到的照样留着
  Future<void> loadMore() async {
    final current = state.value;
    final after = current == null || current.orders.isEmpty ? null : current.orders.last.cursor;
    if (current == null || !current.hasMore || after == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final api = ref.read(apiProvider);
      final wid = ref.read(wholesalerIdProvider);
      final page = await api.listSellerOrders(wid, limit: sellerAllOrdersPageSize, after: after);
      final list = [...current.orders];
      _append(list, page);
      ref.read(_sellerAllOrdersShownProvider)[wid] = list.length;
      state = AsyncData(
        SellerOrderList(list, hasMore: page.length >= sellerAllOrdersPageSize && page.last.cursor != null),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// 两页之间有单改了状态，可能出现两次：按 id 去掉重复的
  static void _append(List<SellerOrderSummary> list, List<SellerOrderSummary> page) {
    final seen = {for (final o in list) o.id};
    list.addAll(page.where((o) => seen.add(o.id)));
  }
}

/// 送货单（get_delivery_summary）。参数是 'YYYY-MM-DD'；null = 服务器算的马来西亚今天
final deliverySummaryProvider = FutureProvider.autoDispose.family<DeliverySummary, String?>(
  (ref, date) => ref
      .watch(apiProvider)
      .getDeliverySummary(ref.watch(wholesalerIdProvider), date: date == null ? null : DateTime.parse(date)),
);

/// 自己的全部商品（包括草稿和下架的）
final sellerProductsProvider = FutureProvider.autoDispose<List<SellerProduct>>(
  (ref) => ref.watch(apiProvider).listMyProducts(ref.watch(wholesalerIdProvider)),
);

/// 一样商品（改商品页）
final sellerProductProvider = FutureProvider.autoDispose.family<SellerProduct, String>(
  (ref, id) => ref.watch(apiProvider).getProduct(id),
);

/// 一份价目表导入（status：processing / review / applied / failed）
final priceListImportProvider = FutureProvider.autoDispose.family<PriceListImport, String>(
  (ref, id) => ref.watch(apiProvider).getImport(id),
);

/// 一份还在读的价目表：每 3 秒查一次（watchImport；卡住的会再叫一次 AI），读好了（review / failed）就结束。
/// 首页用：老板离开了等的页面，首页一样会知道 AI 读好了
final importProgressProvider = StreamProvider.autoDispose.family<PriceListImport, String>(
  (ref, id) => ref.watch(apiProvider).watchImport(id),
);

/// 价目表导入的每一行（AI 读到的商品）
final importRowsProvider = FutureProvider.autoDispose.family<List<PriceListImportRow>, String>(
  (ref, id) => ref.watch(apiProvider).listImportRows(id),
);

/// 设定页：通知方式、WhatsApp 号码和同意时间
final wholesalerSettingsProvider = FutureProvider.autoDispose<WholesalerSettings>(
  (ref) => ref.watch(apiProvider).getWholesalerSettings(ref.watch(wholesalerIdProvider)),
);

/// 这部手机的通知权限（设定页显示用）
final pushPermissionProvider = FutureProvider.autoDispose<PushPermission>(
  (ref) => ref.watch(pushServiceProvider).permissionStatus(),
);

/// 批发商的订单一有变化（新订单、买家取消、WhatsApp 按了确认……）就刷新首页、列表和详情。
/// App 从背景回来（例如去 WhatsApp 按了确认再回来、隔天早上打开）也全部重新读：App 在背景时 Realtime 断线，
/// 中间的变化不会补发，「今天」也可能已经换成另一天了。
/// 批发商的页面 watch 这个；没有页面在用时自动关掉（同一时间只有一个 Realtime channel）。
final sellerRealtimeProvider = Provider.autoDispose<void>((ref) {
  final api = ref.watch(apiProvider);
  // 不用 wholesalerIdProvider：登出那一刻没有批发商，它会丢错误
  final wid = ref.watch(sessionProvider.select((s) => s.wholesalerId));
  if (wid == null) return;
  var alive = true;
  void refresh() {
    if (!alive) return;
    ref.invalidate(sellerHomeProvider);
    ref.invalidate(sellerOrdersProvider);
    ref.invalidate(sellerAllOrdersProvider);
    ref.invalidate(orderDetailProvider);
    ref.invalidate(deliverySummaryProvider);
  }

  final channel = api.watchWholesalerOrders(wid, refresh);
  final lifecycle = AppLifecycleListener(onResume: refresh);
  ref.onDispose(() {
    alive = false;
    lifecycle.dispose();
    api.stopWatching(channel);
  });
});

/// 批发商改订单、改设定之后要刷新的东西，集中在这里
class SellerActions {
  SellerActions(this.ref);

  final Ref ref;

  WholesaleApi get _api => ref.read(apiProvider);
  String get _wholesalerId => ref.read(wholesalerIdProvider);

  /// 确认；outOfStockItemIds 是勾了缺货的那几样（全部都勾 = 整张单缺货）。回传订单的新状态。
  /// 失败（例如已经在 WhatsApp 按过了）也刷新，画面才会显示现在的状态
  Future<OrderStatus> confirmOrder(String orderId, List<String> outOfStockItemIds) async {
    try {
      return await _api.confirmOrder(orderId, outOfStockItemIds: outOfStockItemIds);
    } finally {
      _orderChanged(orderId);
    }
  }

  Future<void> markOutOfStock(String orderId) => _change(orderId, () => _api.markOutOfStock(orderId));

  Future<void> markDelivering(String orderId) => _change(orderId, () => _api.markDelivering(orderId));

  Future<void> markDelivered(String orderId) => _change(orderId, () => _api.markDelivered(orderId));

  /// 失败也重新读设定（例如服务器改好了、回应在路上断了）：画面显示服务器上真的设定，不是旧的
  Future<void> setNotifyChannel(NotifyChannel channel) async {
    try {
      await _api.setNotifyChannel(_wholesalerId, channel);
    } finally {
      _settingsChanged();
    }
  }

  Future<void> setWhatsappOptIn(bool optIn) async {
    try {
      await _api.setWhatsappOptIn(_wholesalerId, optIn);
    } finally {
      _settingsChanged();
    }
  }

  /// 保存一样商品（新增或修改）。有新照片就先上传，换掉原本的照片
  Future<SellerProduct> saveProduct(SellerProduct product, {Uint8List? photo}) async {
    var p = product;
    if (photo != null) p = p.copyWith(photoPaths: [await _api.uploadProductPhoto(_wholesalerId, photo)]);
    final saved = await _api.saveProduct(p);
    ref.invalidate(sellerProductsProvider);
    ref.invalidate(sellerProductProvider(saved.id));
    ref.invalidate(sellerHomeProvider);
    return saved;
  }

  /// 上传价目表 → 建导入 → 叫 AI（回传的导入还是 processing，之后用 watchImport 等）
  Future<PriceListImport> submitPriceList(Uint8List bytes, {String? fileName}) async {
    try {
      return await _api.submitPriceList(_wholesalerId, bytes, fileName: fileName);
    } finally {
      ref.invalidate(sellerHomeProvider);
    }
  }

  /// 改价目表的一行（批发商改名字、价钱、新增 / 更新 / 跳过、对到哪样商品）
  Future<PriceListImportRow> updateImportRow(PriceListImportRow row, Map<String, Object?> fields) async {
    try {
      return await _api.updateImportRow(row.id, fields);
    } finally {
      ref.invalidate(importRowsProvider(row.importId));
    }
  }

  /// 确认上架。失败（例如某一行不完整）也刷新，画面显示服务器现在的样子
  Future<ApplyImportResult> applyImport(String importId) async {
    try {
      return await _api.applyImport(importId);
    } finally {
      ref.invalidate(priceListImportProvider(importId));
      ref.invalidate(importRowsProvider(importId));
      ref.invalidate(sellerProductsProvider);
      ref.invalidate(sellerHomeProvider);
    }
  }

  Future<void> _change(String orderId, Future<void> Function() action) async {
    try {
      await action();
    } finally {
      _orderChanged(orderId);
    }
  }

  void _orderChanged(String orderId) {
    ref.invalidate(orderDetailProvider(orderId));
    ref.invalidate(sellerOrdersProvider);
    ref.invalidate(sellerAllOrdersProvider);
    ref.invalidate(sellerHomeProvider);
    ref.invalidate(deliverySummaryProvider);
  }

  void _settingsChanged() {
    ref.invalidate(wholesalerSettingsProvider);
    ref.invalidate(sellerHomeProvider);
  }
}

final sellerActionsProvider = Provider<SellerActions>(SellerActions.new);
