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
/// | invoice_issued、invoice_due_soon、invoice_overdue | /seller/billing/invoices/{invoice_id} | — |
/// | payment_received | /seller/billing（有 invoice_id 就到那张账单） | /subscription |
/// | subscription_ending | — | /subscription |
///
/// 批发商的通知带 data.wholesaler_id 的话，PushNavigator 先换到那一家（一个人可以是几家批发商的成员）
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
    case 'invoice_issued' || 'invoice_due_soon' || 'invoice_overdue':
      if (!isSeller) return null;
      final invoiceId = data['invoice_id'];
      return isUuid(invoiceId) ? '/seller/billing/invoices/$invoiceId' : '/seller/billing';
    case 'payment_received':
      if (!isSeller) return '/subscription';
      final invoiceId = data['invoice_id'];
      return isUuid(invoiceId) ? '/seller/billing/invoices/$invoiceId' : '/seller/billing';
    case 'subscription_ending':
      return isSeller ? null : '/subscription';
    default:
      return null; // order_unconfirmed（客服）和不认识的
  }
}
