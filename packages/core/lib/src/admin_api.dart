part of 'api.dart';

/// 客服后台（apps/admin_web）用的服务器调用：全部是 admin_* 数据库函数（supabase/migrations/20261128000100_admin.sql），
/// 函数里面检查 is_admin() 并写操作记录（audit_logs）。登录、看商品（getOffers）、报价（quoteCart）、
/// 订单详情（getOrder）跟手机 App 一样用 [WholesaleApi] 的。
class AdminApi extends WholesaleApi {
  AdminApi(super.client);

  static String _month(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';

  // ---------------- 首页、店铺、批发商 ----------------

  Future<AdminDashboard> getDashboard() async => AdminDashboard.fromJson(await _rpcJson('admin_dashboard'));

  Future<List<AdminShop>> listShops({String? search, int limit = 50}) async =>
      (await _rpcList('admin_list_shops', {'p_search': search, 'p_limit': limit})).map(AdminShop.fromJson).toList();

  /// 待审核的排最前面
  Future<List<AdminWholesaler>> listAllWholesalers({WholesalerStatus? status, String? search}) async => (await _rpcList(
    'admin_list_wholesalers',
    {'p_status': status?.name, 'p_search': search},
  )).map(AdminWholesaler.fromJson).toList();

  // ---------------- WhatsApp 订单（第六步） ----------------

  /// 草稿队列：默认待确认的 WhatsApp 订单（旧的先）。channel：'whatsapp' / 'app' / null（全部）
  Future<List<DraftSummary>> listOrderDraftQueue({
    DraftStatus? status = DraftStatus.pendingReview,
    String? channel = 'whatsapp',
  }) async => (await _rpcList('admin_list_order_drafts', {
    'p_status': status == null ? null : draftStatusCode(status),
    'p_channel': channel,
  })).map(DraftSummary.fromJson).toList();

  // ---------------- 订单 ----------------

  Future<AdminOrderPage> listAllOrders(AdminOrderFilter filter) async =>
      AdminOrderPage.fromJson(await _rpcJson('admin_list_orders', filter.toParams()));

  /// 跟进名单：打过电话了，记一句
  Future<void> logFollowup(String orderId, String note) =>
      _call(() => client.rpc<dynamic>('admin_log_followup', params: {'p_order_id': orderId, 'p_note': note}));

  /// 代改状态（缺货、送货中、已送达、取消），回传最新的订单详情
  Future<OrderDetail> setOrderStatusAsAdmin(String orderId, OrderStatus status, {String? note}) async =>
      OrderDetail.fromJson(
        await _rpcJson('admin_set_order_status', {
          'p_order_id': orderId,
          'p_status': orderStatusCode(status),
          'p_note': note,
        }),
      );

  /// 代批发商确认（可以标几样缺货）
  Future<OrderDetail> confirmOrderAsAdmin(String orderId, {List<String> outOfStockItemIds = const []}) async =>
      OrderDetail.fromJson(
        await _rpcJson('admin_confirm_order', {'p_order_id': orderId, 'p_out_of_stock_item_ids': outOfStockItemIds}),
      );

  // ---------------- 代买家下单 ----------------

  /// qty 0 = 拿掉。回传最新报价
  Future<CartQuote> setCartItemAsAdmin(String shopId, String productId, int qty) async => CartQuote.fromJson(
    await _rpcJson('admin_set_cart_item', {'p_shop_id': shopId, 'p_product_id': productId, 'p_qty': qty}),
  );

  Future<void> clearCartAsAdmin(String shopId) =>
      _call(() => client.rpc<dynamic>('admin_clear_cart', params: {'p_shop_id': shopId}));

  /// 总额跟服务器算的不一样 → AppError('PRICE_CHANGED')，error.quote 是新报价
  Future<AdminPlacedOrder> placeOrderAsAdmin(String shopId, {required int expectedTotalSen, String? note}) async =>
      AdminPlacedOrder.fromJson(
        await _rpcJson('admin_place_order', {
          'p_shop_id': shopId,
          'p_expected_total_sen': expectedTotalSen,
          'p_note': note == null || note.trim().isEmpty ? null : note.trim(),
        }),
      );

  // ---------------- 代批发商管商品 ----------------

  Future<List<SellerProduct>> listProductsAsAdmin(String wholesalerId) async =>
      (await _rpcList('admin_list_products', {'p_wholesaler_id': wholesalerId})).map(SellerProduct.fromJson).toList();

  /// productId 空 = 新增。fields 用 [productChanges] 算（只送改了的栏）
  Future<SellerProduct> saveProductAsAdmin(String wholesalerId, String? productId, Json fields) async =>
      SellerProduct.fromJson(
        await _rpcJson('admin_save_product', {
          'p_wholesaler_id': wholesalerId,
          'p_product_id': productId,
          'p_fields': fields,
        }),
      );

  // ---------------- 批发商：审核、佣金比例、创始会员 ----------------

  Future<AdminWholesaler> setWholesalerStatus(String wholesalerId, WholesalerStatus status, {String? note}) async =>
      AdminWholesaler.fromJson(
        await _rpcJson('admin_set_wholesaler_status', {
          'p_wholesaler_id': wholesalerId,
          'p_status': status.name,
          'p_note': note,
        }),
      );

  /// rate：0.015 = 1.5%；null = 取消单独调整
  Future<AdminWholesaler> setCommissionRate(String wholesalerId, double? rate) async => AdminWholesaler.fromJson(
    await _rpcJson('admin_set_commission_rate', {'p_wholesaler_id': wholesalerId, 'p_rate': rate}),
  );

  Future<AdminWholesaler> setWholesalerFounding(String wholesalerId, bool isFounding) async => AdminWholesaler.fromJson(
    await _rpcJson('admin_set_wholesaler_founding', {'p_wholesaler_id': wholesalerId, 'p_is_founding': isFounding}),
  );

  /// 登记同意用 WhatsApp 收消息（shopId、wholesalerId 给一个）。回传同意的时间（取消 = null）
  Future<DateTime?> setWhatsappOptInAsAdmin({String? shopId, String? wholesalerId, required bool optIn}) =>
      _call(() async {
        final v = await client.rpc<dynamic>(
          'admin_set_whatsapp_opt_in',
          params: {'p_shop_id': shopId, 'p_wholesaler_id': wholesalerId, 'p_opt_in': optIn},
        );
        return asDateTimeOrNull(v);
      });

  // ---------------- 订阅 ----------------

  Future<List<AdminSubscription>> listSubscriptions({
    SubscriptionState? state,
    bool foundingOnly = false,
    String? search,
  }) async => (await _rpcList('admin_list_subscriptions', {
    'p_status': state == null ? null : subscriptionStateCode(state),
    'p_founding_only': foundingOnly,
    'p_search': search,
  })).map(AdminSubscription.fromJson).toList();

  Future<AdminSubscription> extendTrial(String subscriptionId, int days) async => AdminSubscription.fromJson(
    await _rpcJson('admin_extend_trial', {'p_subscription_id': subscriptionId, 'p_days': days}),
  );

  Future<AdminSubscription> markSubscriptionPaid(
    String subscriptionId, {
    int months = 1,
    int? amountSen,
    PaymentMethod method = PaymentMethod.other,
    String? reference,
  }) async => AdminSubscription.fromJson(
    await _rpcJson('admin_mark_subscription_paid', {
      'p_subscription_id': subscriptionId,
      'p_months': months,
      'p_amount_sen': amountSen,
      'p_method': method.name,
      'p_reference': reference,
    }),
  );

  Future<AdminSubscription> cancelSubscription(String subscriptionId, {String? reason}) async =>
      AdminSubscription.fromJson(
        await _rpcJson('admin_cancel_subscription', {'p_subscription_id': subscriptionId, 'p_reason': reason}),
      );

  Future<AdminSubscription> setSubscriptionFounding(
    String subscriptionId,
    bool isFounding, {
    int? lockedPriceSen,
  }) async => AdminSubscription.fromJson(
    await _rpcJson('admin_set_subscription_founding', {
      'p_subscription_id': subscriptionId,
      'p_is_founding': isFounding,
      'p_locked_price_sen': lockedPriceSen,
    }),
  );

  // ---------------- 佣金报表和账单 ----------------

  /// month 空 = 这个月（马来西亚时间）
  Future<CommissionReport> getCommissionReport({DateTime? month}) async => CommissionReport.fromJson(
    await _rpcJson('admin_commission_report', {'p_period_month': month == null ? null : _month(month)}),
  );

  /// 生成 / 重算那个月的草稿账单，回传几张
  Future<int> generateInvoices(DateTime month) => _call(
    () async => asInt(await client.rpc<dynamic>('admin_generate_invoices', params: {'p_period_month': _month(month)})),
  );

  Future<CommissionInvoice> issueInvoice(String invoiceId) async =>
      CommissionInvoice.fromJson(await _rpcJson('admin_issue_invoice', {'p_invoice_id': invoiceId}));

  Future<CommissionInvoice> markInvoicePaid(
    String invoiceId, {
    PaymentMethod method = PaymentMethod.other,
    String? reference,
  }) async => CommissionInvoice.fromJson(
    await _rpcJson('admin_mark_invoice_paid', {
      'p_invoice_id': invoiceId,
      'p_method': method.name,
      'p_reference': reference,
    }),
  );

  // ---------------- 操作记录 ----------------

  /// 新到旧；beforeId = 上一页最后一行的 id
  /// 付款记录（网关的和客服手动记的）。reviewOnly = 只看收到钱但要处理的
  Future<List<PaymentInfo>> listPayments({
    PaymentStatus? status,
    PaymentPurpose? purpose,
    bool reviewOnly = false,
  }) async => (await _rpcList('admin_list_payments', {
    'p_status': status?.name,
    'p_purpose': purpose == null ? null : paymentPurposeCode(purpose),
    'p_review_only': reviewOnly,
  })).map(PaymentInfo.fromJson).toList();

  /// 批发商转账 / 现金付了创始上架费（还不是创始会员的自动编号；名额满 → FOUNDING_QUOTA_FULL）
  Future<AdminWholesaler> markListingFeePaid(
    String wholesalerId, {
    PaymentMethod method = PaymentMethod.other,
    String? reference,
  }) async => AdminWholesaler.fromJson(
    await _rpcJson('admin_mark_listing_fee_paid', {
      'p_wholesaler_id': wholesalerId,
      'p_method': method.name,
      'p_reference': reference,
    }),
  );

  Future<List<AuditEntry>> listAuditLogs({
    String? action,
    String? tableName,
    String? shopId,
    String? wholesalerId,
    bool adminOnly = false,
    int limit = 100,
    int? beforeId,
  }) async => (await _rpcList('admin_list_audit_logs', {
    'p_action': action,
    'p_table': tableName,
    'p_shop_id': shopId,
    'p_wholesaler_id': wholesalerId,
    'p_admin_only': adminOnly,
    'p_limit': limit,
    'p_before_id': beforeId,
  })).map(AuditEntry.fromJson).toList();
}
