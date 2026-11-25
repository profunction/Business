import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../push/push_service.dart';
import 'providers.dart';

/// 批发商首页：新订单、今天要送、商品数量、最近一次价目表（get_seller_home）
final sellerHomeProvider = FutureProvider.autoDispose<SellerHome>(
  (ref) => ref.watch(apiProvider).getSellerHome(ref.watch(wholesalerIdProvider)),
);

/// 订单列表的三个分页
enum SellerOrdersTab { pending, today, all }

/// ?tab=pending|today|all（不认识的当 pending）
SellerOrdersTab sellerOrdersTabFrom(String? v) =>
    SellerOrdersTab.values.firstWhere((t) => t.name == v, orElse: () => SellerOrdersTab.pending);

/// list_seller_orders()：
/// - pending：新订单，先来先做（服务器排好：旧到新）
/// - today：今天要送（已确认 / 送货中，送货日 = 服务器算的马来西亚今天）
/// - all：全部（pending 在最前面，其他新到旧）
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
      return api.listSellerOrders(wid, limit: 100);
  }
});

/// 设定页：通知方式、WhatsApp 号码和同意时间
final wholesalerSettingsProvider = FutureProvider.autoDispose<WholesalerSettings>(
  (ref) => ref.watch(apiProvider).getWholesalerSettings(ref.watch(wholesalerIdProvider)),
);

/// 这部手机的通知权限（设定页显示用）
final pushPermissionProvider = FutureProvider.autoDispose<PushPermission>(
  (ref) => ref.watch(pushServiceProvider).permissionStatus(),
);

/// 批发商的订单一有变化（新订单、买家取消、WhatsApp 按了确认……）就刷新首页、列表和详情。
/// 批发商的页面 watch 这个；没有页面在用时自动关掉（同一时间只有一个 Realtime channel）。
final sellerRealtimeProvider = Provider.autoDispose<void>((ref) {
  final api = ref.watch(apiProvider);
  // 不用 wholesalerIdProvider：登出那一刻没有批发商，它会丢错误
  final wid = ref.watch(sessionProvider.select((s) => s.wholesalerId));
  if (wid == null) return;
  var alive = true;
  final channel = api.watchWholesalerOrders(wid, () {
    if (!alive) return;
    ref.invalidate(sellerHomeProvider);
    ref.invalidate(sellerOrdersProvider);
    ref.invalidate(orderDetailProvider);
  });
  ref.onDispose(() {
    alive = false;
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

  Future<void> setNotifyChannel(NotifyChannel channel) async {
    await _api.setNotifyChannel(_wholesalerId, channel);
    _settingsChanged();
  }

  Future<void> setWhatsappOptIn(bool optIn) async {
    await _api.setWhatsappOptIn(_wholesalerId, optIn);
    _settingsChanged();
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
    ref.invalidate(sellerHomeProvider);
  }

  void _settingsChanged() {
    ref.invalidate(wholesalerSettingsProvider);
    ref.invalidate(sellerHomeProvider);
  }
}

final sellerActionsProvider = Provider<SellerActions>(SellerActions.new);
