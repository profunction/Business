// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'JB Wholesale · Admin';

  @override
  String get language => 'Language';

  @override
  String get signOut => 'Sign out';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String get all => 'All';

  @override
  String get searchHint => 'Search';

  @override
  String get saved => 'Saved';

  @override
  String copied(String text) {
    return 'Copied: $text';
  }

  @override
  String get demoBanner => 'Demo mode: sample data, nothing is sent to the server';

  @override
  String get errNetwork => 'Cannot reach the server. Check the connection.';

  @override
  String get errAuth => 'Wrong code, or the login has expired';

  @override
  String get errNotAllowed => 'Not allowed (admins only)';

  @override
  String get errPriceChanged => 'Prices just changed. Check the new total and try again.';

  @override
  String get errCartHasProblems => 'The cart has problems. See each line.';

  @override
  String get errCartEmpty => 'The cart is empty';

  @override
  String get errInvalidTransition => 'The order cannot change to that status now';

  @override
  String get errInvalidRate => 'Rate must be 0%–20%, up to 2 decimals';

  @override
  String get errInvalidDays => 'Days must be 1–90';

  @override
  String get errInvalidMonths => 'Months must be 1–24';

  @override
  String get errInvalidAmount => 'Invalid amount';

  @override
  String get errDuplicateReference => 'This reference number was already recorded';

  @override
  String get errSubscriptionState => 'This subscription cannot be changed that way now';

  @override
  String get errSubscriptionOpen => 'This shop already has a newer subscription';

  @override
  String get errInvoiceState => 'The invoice cannot change that way now';

  @override
  String get errFoundingFull => 'Founding member quota is full';

  @override
  String get errInvalidProduct => 'Invalid product: check name, unit, price and quantities';

  @override
  String get errInvalidNote => 'Please write a note';

  @override
  String get errNoPricingPlan => 'No pricing plan set up (contact tech)';

  @override
  String errUnknown(String code) {
    return 'Something went wrong ($code)';
  }

  @override
  String get loginTitle => 'Admin sign in';

  @override
  String get loginSubtitle => 'Sign in with your phone number and a code. Admin accounts only.';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get phoneInvalid => 'Enter a Malaysian mobile number, e.g. 012-345 6789';

  @override
  String get sendCode => 'Send code';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get otpLogin => 'Sign in';

  @override
  String get otpResend => 'Resend';

  @override
  String otpResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get changePhone => 'Change number';

  @override
  String get deniedTitle => 'This account is not an admin';

  @override
  String get deniedBody =>
      'The admin site is for admin staff only. Shop owners and wholesalers please use the mobile app.';

  @override
  String get loadingContext => 'Loading…';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navOrders => 'All orders';

  @override
  String get navFollowup => 'Follow-up';

  @override
  String get navPlaceOrder => 'Order for shop';

  @override
  String get navWholesalers => 'Wholesalers';

  @override
  String get navSubscriptions => 'Subscriptions';

  @override
  String get navCommission => 'Commission';

  @override
  String get navAudit => 'Audit log';

  @override
  String dashUnconfirmed(int minutes) {
    return 'Unconfirmed > $minutes min';
  }

  @override
  String get dashPendingOrders => 'Pending orders';

  @override
  String get dashPendingWholesalers => 'Wholesalers to approve';

  @override
  String get dashTodayOrders => 'Orders today';

  @override
  String get dashTodayTotal => 'Total today';

  @override
  String get dashMonthGmv => 'Delivered goods this month';

  @override
  String get dashMonthCommission => 'Commission this month';

  @override
  String get dashSubscriptions => 'Subscriptions';

  @override
  String get subTrialing => 'Trial';

  @override
  String get subActive => 'Active';

  @override
  String get subPastDue => 'Past due';

  @override
  String get subLapsed => 'Lapsed';

  @override
  String get subNone => 'No subscription';

  @override
  String get subFounding => 'Founding price';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusOutOfStock => 'Out of stock';

  @override
  String get statusDelivering => 'Delivering';

  @override
  String get statusDelivered => 'Delivered';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get sourceApp => 'App';

  @override
  String get sourceVoice => 'Voice';

  @override
  String get sourceWhatsapp => 'WhatsApp';

  @override
  String get sourceAdmin => 'Admin';

  @override
  String get sourceReorder => 'Reorder';

  @override
  String get channelApp => 'App';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get channelAdmin => 'Admin';

  @override
  String get channelSystem => 'System';

  @override
  String get unitCarton => 'carton';

  @override
  String get unitPack => 'pack';

  @override
  String get unitBag => 'bag';

  @override
  String get unitRoll => 'roll';

  @override
  String get unitBundle => 'bundle';

  @override
  String get unitBox => 'box';

  @override
  String get unitPiece => 'piece';

  @override
  String get unitDozen => 'dozen';

  @override
  String get unitKg => 'kg';

  @override
  String get stockIn => 'In stock';

  @override
  String get stockLow => 'Low stock';

  @override
  String get stockOut => 'Out of stock';

  @override
  String get productActive => 'On sale';

  @override
  String get productDraft => 'Draft';

  @override
  String get productArchived => 'Off sale';

  @override
  String get filterFrom => 'From';

  @override
  String get filterTo => 'To';

  @override
  String get filterWholesaler => 'Wholesaler';

  @override
  String get filterShop => 'Shop';

  @override
  String get filterStatus => 'Status';

  @override
  String get filterSource => 'Source';

  @override
  String filterUnconfirmed(int minutes) {
    return 'Only unconfirmed > $minutes min';
  }

  @override
  String get filterClear => 'Clear filters';

  @override
  String ordersTotal(int count) {
    return '$count orders';
  }

  @override
  String get ordersEmpty => 'No matching orders';

  @override
  String get colOrderNo => 'Order no.';

  @override
  String get colCreated => 'Placed';

  @override
  String get colShop => 'Shop';

  @override
  String get colWholesaler => 'Wholesaler';

  @override
  String get colStatus => 'Status';

  @override
  String get colSource => 'Source';

  @override
  String get colTotal => 'Total';

  @override
  String get pagePrev => 'Previous';

  @override
  String get pageNext => 'Next';

  @override
  String pageRange(int from, int to, int total) {
    return '$from–$to of $total';
  }

  @override
  String followupHint(int minutes) {
    return 'Orders pending more than $minutes minutes. Call the wholesaler, then write a note.';
  }

  @override
  String get followupEmpty => 'Nothing to follow up';

  @override
  String pendingFor(int minutes) {
    return 'Waiting $minutes min';
  }

  @override
  String get logFollowup => 'Log follow-up';

  @override
  String get followupNoteLabel => 'Note (e.g. wholesaler will confirm by 3pm)';

  @override
  String lastFollowup(String time, String note) {
    return 'Last follow-up $time: $note';
  }

  @override
  String get openOrder => 'Open order';

  @override
  String phoneOf(String name) {
    return '$name phone';
  }

  @override
  String orderTitle(String orderNo) {
    return 'Order $orderNo';
  }

  @override
  String get itemsTitle => 'Items';

  @override
  String get eventsTitle => 'History';

  @override
  String get goodsSubtotal => 'Goods';

  @override
  String get shippingFee => 'Shipping';

  @override
  String get totalLabel => 'Total';

  @override
  String get expectedDelivery => 'Expected delivery';

  @override
  String get noteLabel => 'Note';

  @override
  String get outOfStockTag => 'Out of stock';

  @override
  String get actConfirm => 'Confirm for wholesaler';

  @override
  String get actConfirmHint => 'Tick the items that are out of stock (not charged). All ticked = out of stock.';

  @override
  String get actOutOfStock => 'Whole order out of stock';

  @override
  String get actDelivering => 'Out for delivery';

  @override
  String get actDelivered => 'Mark delivered';

  @override
  String get actCancel => 'Cancel order';

  @override
  String get cancelReasonLabel => 'Reason (shown to the wholesaler)';

  @override
  String statusUpdated(String status) {
    return 'Status updated: $status';
  }

  @override
  String get chooseShop => 'Choose a shop';

  @override
  String get shopSearchHint => 'Shop name or phone';

  @override
  String get changeShop => 'Change shop';

  @override
  String get shopNoApp => 'No app';

  @override
  String get shopLocked => 'Unpaid: can only order from the free wholesalers';

  @override
  String get offersSearchHint => 'Search products';

  @override
  String get offersEmpty => 'No products deliver to this shop';

  @override
  String get priceHidden => 'Price hidden';

  @override
  String perPiece(String sen) {
    return '$sen sen each';
  }

  @override
  String minOrderQty(int qty) {
    return 'Min $qty';
  }

  @override
  String get add => 'Add';

  @override
  String get cartTitle => 'Cart';

  @override
  String get cartEmpty => 'The cart is empty';

  @override
  String get clearCart => 'Clear';

  @override
  String get orderNoteLabel => 'Note (shown to the wholesaler)';

  @override
  String placeOrderButton(String amount) {
    return 'Place order $amount';
  }

  @override
  String get placedTitle => 'Order placed';

  @override
  String placedBody(int count) {
    return 'Split into $count orders; the wholesalers are notified:';
  }

  @override
  String get problemProductUnavailable => 'Product unavailable';

  @override
  String get problemNotDelivering => 'Does not deliver to this shop\'s zone';

  @override
  String get problemWholesalerLocked => 'Unpaid: not one of the free wholesalers';

  @override
  String get problemOutOfStock => 'Out of stock';

  @override
  String problemBelowMinQty(int qty) {
    return 'Below minimum $qty';
  }

  @override
  String problemBelowMinOrder(String amount) {
    return '$amount more to reach the minimum order';
  }

  @override
  String get wsStatusPending => 'Pending';

  @override
  String get wsStatusActive => 'Active';

  @override
  String get wsStatusSuspended => 'Suspended';

  @override
  String get wsApprove => 'Approve';

  @override
  String get wsReject => 'Reject';

  @override
  String get wsSuspend => 'Suspend';

  @override
  String get wsReactivate => 'Reactivate';

  @override
  String get wsNoteLabel => 'Reason (kept in the audit log)';

  @override
  String wsCommission(String rate) {
    return 'Commission $rate';
  }

  @override
  String get wsRateOverride => 'Custom';

  @override
  String get wsRateFounding => 'Founding';

  @override
  String get wsRateIndustry => 'Industry default';

  @override
  String get wsSetRate => 'Set commission rate';

  @override
  String get wsRateLabel => 'Rate % (empty = default)';

  @override
  String wsRateDefaults(String industry, String founding) {
    return 'Industry $industry, founding $founding';
  }

  @override
  String get wsFounding => 'Founding member';

  @override
  String wsFoundingNo(int no) {
    return 'Founding #$no';
  }

  @override
  String get wsWhatsappOptIn => 'WhatsApp opt-in';

  @override
  String wsProducts(int count) {
    return 'Products ($count)';
  }

  @override
  String wsPendingOrders(int count) {
    return '$count pending';
  }

  @override
  String get wsEmpty => 'No wholesalers';

  @override
  String productsTitle(String name) {
    return 'Products of $name';
  }

  @override
  String get productsHint => 'Changes are made on behalf of the wholesaler and kept in the audit log.';

  @override
  String get productNew => 'New product';

  @override
  String get productEdit => 'Edit product';

  @override
  String get productName => 'Name';

  @override
  String get productUnit => 'Unit';

  @override
  String get productPackQty => 'Pieces per unit';

  @override
  String get productPrice => 'Price (RM)';

  @override
  String get productMinQty => 'Minimum quantity';

  @override
  String get productStock => 'Stock';

  @override
  String get productStatus => 'Listing';

  @override
  String get productsEmpty => 'No products yet';

  @override
  String productPerUnit(String price, String unit, int qty) {
    return '$price / $unit ($qty pcs)';
  }

  @override
  String get subsFoundingOnly => 'Founding price only';

  @override
  String get colPlan => 'Locked price';

  @override
  String get colTrialEnds => 'Trial ends';

  @override
  String get colPeriodEnd => 'Paid until';

  @override
  String get colLastPayment => 'Last payment';

  @override
  String get subExtendTrial => 'Extend trial';

  @override
  String get subDaysLabel => 'Days to add (1–90)';

  @override
  String get subMarkPaid => 'Mark paid';

  @override
  String get subMonthsLabel => 'Months';

  @override
  String get subAmountLabel => 'Amount RM (empty = locked price x months)';

  @override
  String get subMethodLabel => 'Payment method';

  @override
  String get subReferenceLabel => 'Reference (bank transfer no.)';

  @override
  String get subLapsedNewPrice => 'Lapsed: paying starts a new subscription at today\'s price.';

  @override
  String get subCancel => 'Cancel subscription';

  @override
  String get subCancelConfirm => 'It stops now. Coming back later means a new subscription at that day\'s price.';

  @override
  String get subReasonLabel => 'Reason';

  @override
  String get subSetFounding => 'Founding price';

  @override
  String get subLockedPriceLabel => 'Locked price RM (empty = unchanged)';

  @override
  String get subsEmpty => 'No subscriptions';

  @override
  String get methodFpx => 'FPX';

  @override
  String get methodDuitnow => 'DuitNow';

  @override
  String get methodEwallet => 'E-wallet';

  @override
  String get methodCard => 'Card';

  @override
  String get methodOther => 'Cash / other';

  @override
  String get commissionHint =>
      'Delivered goods (excluding shipping) and commission due per wholesaler this month. Rates are those saved at delivery.';

  @override
  String get prevMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get colOrders => 'Delivered orders';

  @override
  String get colGmv => 'Goods (excl. shipping)';

  @override
  String get colRate => 'Rate';

  @override
  String get colCommission => 'Commission due';

  @override
  String get colInvoice => 'Invoice';

  @override
  String get colBillingName => 'Billing name';

  @override
  String get colSsm => 'SSM no.';

  @override
  String get colEmail => 'Email';

  @override
  String get colPeriod => 'Period';

  @override
  String get colInvoiceStatus => 'Invoice status';

  @override
  String get commissionTotal => 'Total';

  @override
  String get exportCsv => 'Export CSV (all)';

  @override
  String get exportPdf => 'Invoice PDF';

  @override
  String exported(String name) {
    return 'Downloaded $name';
  }

  @override
  String get exportUnsupported => 'Downloads work in the web version only';

  @override
  String get generateInvoices => 'Generate draft invoices';

  @override
  String invoicesGenerated(int count) {
    return '$count draft invoices generated / updated';
  }

  @override
  String get issueInvoice => 'Issue invoice';

  @override
  String get markInvoicePaid => 'Mark paid';

  @override
  String get invoiceDraft => 'Draft';

  @override
  String get invoiceIssued => 'Issued';

  @override
  String get invoicePaid => 'Paid';

  @override
  String get invoiceOverdue => 'Overdue';

  @override
  String get invoiceVoid => 'Void';

  @override
  String get invoiceNone => 'No invoice yet';

  @override
  String get commissionEmpty => 'No delivered orders this month';

  @override
  String get pdfInvoiceTitle => 'Commission invoice';

  @override
  String get pdfBillTo => 'Bill to';

  @override
  String get pdfInvoiceNo => 'Invoice no.';

  @override
  String get pdfDraft => 'Draft (not issued)';

  @override
  String get pdfDueDate => 'Due date';

  @override
  String get pdfDelivered => 'Delivered';

  @override
  String get pdfTotalDue => 'Total commission due';

  @override
  String get pdfNote =>
      'Commission is charged on delivered goods only, excluding shipping; out-of-stock and cancelled items are not charged.';

  @override
  String get pdfCompanyNotConfigured => '(Company details not configured)';

  @override
  String get auditAdminOnly => 'Admin actions only';

  @override
  String get auditActor => 'Who';

  @override
  String get auditActingFor => 'On behalf of';

  @override
  String get auditTable => 'Data';

  @override
  String get auditChanges => 'Changes';

  @override
  String get auditEmpty => 'No records';

  @override
  String get loadMore => 'Load more';

  @override
  String get auditActPlaceOrder => 'Placed order';

  @override
  String get auditActSetCartItem => 'Changed cart';

  @override
  String get auditActClearCart => 'Cleared cart';

  @override
  String get auditActSetOrderStatus => 'Changed order status';

  @override
  String get auditActConfirmOrder => 'Confirmed order';

  @override
  String get auditActLogFollowup => 'Follow-up';

  @override
  String get auditActCreateProduct => 'Created product';

  @override
  String get auditActUpdateProduct => 'Updated product';

  @override
  String get auditActWholesalerStatus => 'Approval / suspension';

  @override
  String get auditActCommissionRate => 'Changed commission rate';

  @override
  String get auditActWholesalerFounding => 'Founding member';

  @override
  String get auditActWhatsappOptIn => 'WhatsApp opt-in';

  @override
  String get auditActExtendTrial => 'Extended trial';

  @override
  String get auditActMarkPaid => 'Marked subscription paid';

  @override
  String get auditActCancelSubscription => 'Cancelled subscription';

  @override
  String get auditActSubscriptionFounding => 'Founding price';

  @override
  String get auditActGenerateInvoices => 'Generated invoices';

  @override
  String get auditActIssueInvoice => 'Issued invoice';

  @override
  String get auditActInvoicePaid => 'Invoice paid';

  @override
  String get auditActInsert => 'Insert';

  @override
  String get auditActUpdate => 'Update';

  @override
  String get auditActDelete => 'Delete';

  @override
  String get navWhatsappOrders => 'WhatsApp orders';

  @override
  String get waOrdersHint =>
      'Orders shops sent on WhatsApp (text or voice). The AI makes a draft first: check it, fix it, then place the order for the shop. Rejected ones get a WhatsApp reply with the reason (within 24 hours).';

  @override
  String get waOrdersEmpty => 'No WhatsApp orders to handle right now';

  @override
  String get waVoice => 'Voice';

  @override
  String get waText => 'Text';

  @override
  String waItems(int count) {
    return '$count item(s)';
  }

  @override
  String waUnmatchedCount(int count) {
    return '$count not matched';
  }

  @override
  String get waWindowOpen => 'Within 24 h: can reply on WhatsApp';

  @override
  String get waWindowClosed => 'Over 24 h: cannot reply on WhatsApp, please call';

  @override
  String waAiFailed(String code) {
    return 'The AI could not process it ($code). Please listen / read it yourself';
  }

  @override
  String get waMessage => 'What the shop said';

  @override
  String get waNoTranscript => '(No text: the voice note was not transcribed)';

  @override
  String get waUnmatched => 'Phrases not matched to a product';

  @override
  String get waAddItem => 'Add item';

  @override
  String get waRemove => 'Remove';

  @override
  String waSubmit(String total) {
    return 'Place order for shop $total';
  }

  @override
  String get waReject => 'Reject';

  @override
  String get waRejectReason => 'Reason (sent to the shop on WhatsApp)';

  @override
  String waSubmitted(String orders) {
    return 'Order placed: $orders';
  }

  @override
  String get waRejectedDone => 'Rejected. A WhatsApp reply has been queued';

  @override
  String get waDone => 'This one has been handled';

  @override
  String get waSearchProduct => 'Search product name';

  @override
  String get waNoProducts => 'No products found';

  @override
  String get waEmptyDraft => 'The draft has no items yet';

  @override
  String get waNotFound => 'This draft was not found';

  @override
  String waSaid(String said) {
    return 'Shop said: \"$said\"';
  }

  @override
  String get waUnsure => 'AI not sure';

  @override
  String get waTagAiFailed => 'AI failed';

  @override
  String get waTagWindowClosed => 'Over 24 h';

  @override
  String get auditActSaveDraft => 'Edit order draft';

  @override
  String get auditActSubmitDraft => 'Place WhatsApp order for shop';

  @override
  String get auditActRejectDraft => 'Reject order draft';

  @override
  String get navPayments => 'Payments';

  @override
  String get paymentsEmpty => 'No payments';

  @override
  String get payReviewOnly => 'Needs attention only';

  @override
  String payNeedsReview(String reason) {
    return 'Needs attention: $reason';
  }

  @override
  String get purposeSubscription => 'Buyer subscription';

  @override
  String get purposeListingFee => 'Founding listing fee';

  @override
  String get purposeCommission => 'Commission invoice';

  @override
  String get payStatusPending => 'Pending';

  @override
  String get payStatusPaid => 'Paid';

  @override
  String get payStatusFailed => 'Failed';

  @override
  String get payStatusRefunded => 'Refunded';

  @override
  String get colMethod => 'Method';

  @override
  String get colReference => 'Gateway ref';

  @override
  String get colTime => 'Time';

  @override
  String monthsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n months', one: '1 month');
    return '$_temp0';
  }

  @override
  String get payLink => 'Payment link';

  @override
  String get payLinkTitle => 'Payment link';

  @override
  String payLinkAmount(String amount) {
    return 'Amount $amount (calculated by the server)';
  }

  @override
  String get payLinkHelp =>
      'Copy and send it on WhatsApp. They can pay with FPX, DuitNow or e-wallets; the payment is recorded automatically.';

  @override
  String get payLinkCopy => 'Copy';

  @override
  String get payLinkCopied => 'Copied';

  @override
  String get wsListingFeePaid => 'Listing fee paid';

  @override
  String get wsListingFeeUnpaid => 'Listing fee unpaid';

  @override
  String get wsMarkListingFee => 'Mark listing fee paid';

  @override
  String get errNothingDue => 'Already paid';

  @override
  String get errPaymentNotConfigured => 'Payment gateway not configured (HITPAY_API_KEY)';

  @override
  String get errGateway => 'Payment gateway unavailable, please try again later';

  @override
  String get errTooManyPayments => 'Too many payment links, please wait';
}
