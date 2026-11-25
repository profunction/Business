import 'package:wholesale_core/wholesale_core.dart';

/// 点通知要打开哪一页（data 来自 dispatch-notifications：type、order_id、order_no、date）。
/// null = 不用跳页（例如客服的 order_unconfirmed，App 里没有对应的页面）。
///
/// | type | 批发商 | 买家 |
/// |---|---|---|
/// | order_new | /seller/orders/{id} | — |
/// | order_status_changed、order_cancelled | /seller/orders/{id} | /orders/{id} |
/// | daily_summary | /seller/summary?date= | — |
/// | order_unconfirmed | — | — |
String? pushRoute(Map<String, String> data, {required bool isSeller}) {
  final type = data['type'] ?? data['event_type'];
  final orderId = data['order_id'];
  // 只接受 UUID，不会被奇怪的值带到别的页面
  final validOrder = isUuid(orderId);
  switch (type) {
    case 'order_new':
      if (!isSeller) return null;
      return validOrder ? '/seller/orders/$orderId' : '/seller/orders?tab=pending';
    case 'order_status_changed' || 'order_cancelled':
      if (!validOrder) return null;
      return isSeller ? '/seller/orders/$orderId' : '/orders/$orderId';
    case 'daily_summary':
      if (!isSeller) return null;
      final date = data['date'];
      return date != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)
          ? '/seller/summary?date=$date'
          : '/seller/summary';
    default:
      return null; // order_unconfirmed（客服）和不认识的
  }
}
