// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'JB Wholesale';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Save';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get optional => 'Optional';

  @override
  String get errNetwork => 'No internet connection. Please check and try again.';

  @override
  String get errUnknown => 'Something went wrong. Please try again.';

  @override
  String get errAuth => 'The code is wrong or has expired. Please try again.';

  @override
  String get errNotAllowed => 'You are not allowed to do this.';

  @override
  String get errPriceChanged => 'A wholesaler just changed a price. Please check the total again.';

  @override
  String get errCartHasProblems => 'Your cart has problems. Please fix the parts in red first.';

  @override
  String get errCartEmpty => 'Your cart is empty.';

  @override
  String get errUnlockCooldown => 'You can\'t swap your chosen wholesalers yet.';

  @override
  String get errTooManyWholesalers => 'You chose too many wholesalers for the free plan.';

  @override
  String get errWholesalerNotAvailable => 'This wholesaler doesn\'t deliver to your area now.';

  @override
  String get errInvalidTransition => 'This order has changed. Please refresh.';

  @override
  String get errOrderNotDelivered => 'You can rate the order after it\'s delivered.';

  @override
  String get errNoPreviousOrder => 'You haven\'t ordered before.';

  @override
  String get languagePageTitle => '请选择语言 · Choose language · Pilih bahasa';

  @override
  String get loginTitle => 'Log in with your phone number';

  @override
  String get loginSubtitle => 'We will send a code to your phone';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get phoneInvalid => 'That doesn\'t look like a mobile number. Please check again.';

  @override
  String get sendCode => 'Send code';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSentTo(String phone) {
    return 'We sent a code to $phone';
  }

  @override
  String get otpLogin => 'Log in';

  @override
  String get otpResend => 'Send again';

  @override
  String otpResendIn(int seconds) {
    return 'Send again in ${seconds}s';
  }

  @override
  String get changePhone => 'Change number';

  @override
  String get registerTitle => 'Set up your shop';

  @override
  String get shopNameQuestion => 'What is your shop called?';

  @override
  String get shopNameHint => 'e.g. Ah Ming Kopitiam';

  @override
  String get shopTypeQuestion => 'What kind of shop is it?';

  @override
  String get shopTypeRestaurant => 'Restaurant';

  @override
  String get shopTypeDrinkStall => 'Drinks stall';

  @override
  String get shopTypeGrocery => 'Grocery';

  @override
  String get shopTypeOther => 'Other';

  @override
  String get zoneQuestion => 'Which area is your shop in?';

  @override
  String get addressQuestion => 'Shop address (for delivery)';

  @override
  String get addressHint => 'e.g. 12, Jalan Molek 1/2, Taman Molek';

  @override
  String get registerFinish => 'Start';

  @override
  String get homeReorder => 'Same as last time';

  @override
  String homeReorderLast(String date, String total) {
    return 'Last time: $date, $total';
  }

  @override
  String get homeShop => 'Shop';

  @override
  String get homeOrders => 'My orders';

  @override
  String homeActiveOrders(int count) {
    return '$count in progress';
  }

  @override
  String homeCart(int count) {
    return 'Cart ($count items)';
  }

  @override
  String trialBanner(int days) {
    return '$days days of free trial left. You can see all prices.';
  }

  @override
  String freeBanner(int count) {
    return 'Free plan: choose $count wholesalers to see their prices';
  }

  @override
  String get chooseWholesalers => 'Choose wholesalers';

  @override
  String get settings => 'Settings';

  @override
  String get browseTitle => 'Shop';

  @override
  String get browseByProduct => 'By product';

  @override
  String get browseByWholesaler => 'By wholesaler';

  @override
  String get searchHint => 'Search, e.g. cup';

  @override
  String get noResults => 'Nothing found';

  @override
  String categoryItemCount(int count) {
    return '$count items';
  }

  @override
  String sellerCount(int count) {
    return '$count sellers';
  }

  @override
  String cheapestPerUnit(String sen) {
    return 'From $sen sen each';
  }

  @override
  String get compareTitle => 'Compare prices';

  @override
  String perUnit(String sen) {
    return '$sen sen each';
  }

  @override
  String pricePerSellUnit(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String packQty(String unit, int qty) {
    return '$qty pcs per $unit';
  }

  @override
  String get priceLocked => 'Price hidden';

  @override
  String rating(String avg, int count) {
    return '$avg ($count reviews)';
  }

  @override
  String get noRatings => 'No reviews yet';

  @override
  String leadTime(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Arrives in $days days',
      one: 'Arrives tomorrow',
      zero: 'Arrives today',
    );
    return '$_temp0';
  }

  @override
  String minOrderQty(int qty, String unit) {
    return 'Min $qty $unit';
  }

  @override
  String shippingFee(String fee) {
    return 'Delivery $fee';
  }

  @override
  String freeShippingOver(String amount) {
    return 'Free delivery over $amount';
  }

  @override
  String minOrderAmount(String amount) {
    return 'Min order $amount';
  }

  @override
  String get outOfStock => 'Out of stock';

  @override
  String get lowStock => 'Low stock';

  @override
  String get founding => 'Founding member';

  @override
  String get addToCart => 'Add to cart';

  @override
  String inCart(int qty) {
    return '$qty in cart';
  }

  @override
  String get updateCart => 'Update cart';

  @override
  String get removeFromCart => 'Remove';

  @override
  String get addedToCart => 'Added to cart';

  @override
  String get lockedHint => 'On the free plan you only see prices from the wholesalers you chose';

  @override
  String get chooseThisWholesaler => 'Add this wholesaler to my free list';

  @override
  String get freeSlotsFull => 'Your free list is full. Go to \"Choose wholesalers\" to swap.';

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
  String productCount(int count) {
    return '$count products';
  }

  @override
  String deliveryDays(String days) {
    return 'Delivers: $days';
  }

  @override
  String get weekdayShort1 => 'Mon';

  @override
  String get weekdayShort2 => 'Tue';

  @override
  String get weekdayShort3 => 'Wed';

  @override
  String get weekdayShort4 => 'Thu';

  @override
  String get weekdayShort5 => 'Fri';

  @override
  String get weekdayShort6 => 'Sat';

  @override
  String get weekdayShort7 => 'Sun';

  @override
  String get paymentCod => 'Cash on delivery';

  @override
  String get paymentTransfer => 'Bank transfer';

  @override
  String get paymentCredit => 'Monthly credit';

  @override
  String get cartTitle => 'Cart';

  @override
  String get cartEmpty => 'Your cart is empty';

  @override
  String get goodsSubtotal => 'Goods';

  @override
  String get shipping => 'Delivery';

  @override
  String get freeShipping => 'Free';

  @override
  String get total => 'Total';

  @override
  String shortOfFreeShipping(String amount) {
    return 'Add $amount more for free delivery';
  }

  @override
  String shortOfMinOrder(String amount) {
    return '$amount more to reach the minimum order';
  }

  @override
  String expectedDelivery(String date) {
    return 'Arrives $date';
  }

  @override
  String get problemProductUnavailable => 'This item is no longer sold. Please remove it.';

  @override
  String get problemNotDelivering => 'This wholesaler doesn\'t deliver to your area now';

  @override
  String get problemWholesalerLocked =>
      'You can\'t see this wholesaler\'s prices on the free plan, so you can\'t order';

  @override
  String get problemOutOfStock => 'Out of stock. Please remove it.';

  @override
  String problemBelowMinQty(int qty) {
    return 'Minimum $qty';
  }

  @override
  String get goToConfirm => 'Next: review order';

  @override
  String get fixProblemsFirst => 'Please fix the problems in red first';

  @override
  String get confirmTitle => 'Review order';

  @override
  String ordersWillSplit(int count) {
    return 'This becomes $count orders. Each wholesaler delivers on their own.';
  }

  @override
  String get noteLabel => 'Note';

  @override
  String placeOrder(String total) {
    return 'Place order $total';
  }

  @override
  String get priceChangedTitle => 'Prices changed';

  @override
  String get reorderPriceChanges => 'These items changed price:';

  @override
  String get reorderSkipped => 'These items are no longer available and were removed:';

  @override
  String priceChangeLine(String name, String oldPrice, String newPrice) {
    return '$name: $oldPrice → $newPrice';
  }

  @override
  String get orderPlacedTitle => 'Order placed!';

  @override
  String get orderPlacedBody => 'We\'ll let you know when the wholesaler confirms';

  @override
  String get viewOrders => 'See my orders';

  @override
  String get backHome => 'Back to home';

  @override
  String get ordersTitle => 'My orders';

  @override
  String get noOrders => 'No orders yet';

  @override
  String get statusPending => 'Waiting';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusOutOfStock => 'Out of stock';

  @override
  String get statusDelivering => 'On the way';

  @override
  String get statusDelivered => 'Delivered';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String itemCount(int count) {
    return '$count items';
  }

  @override
  String outOfStockCount(int count) {
    return '$count out of stock';
  }

  @override
  String orderTitle(String orderNo) {
    return 'Order $orderNo';
  }

  @override
  String orderedAt(String date) {
    return 'Ordered: $date';
  }

  @override
  String get callWholesaler => 'Call wholesaler';

  @override
  String get markReceived => 'I got it';

  @override
  String get markReceivedConfirm => 'Confirm you have received the goods?';

  @override
  String get cancelOrder => 'Cancel order';

  @override
  String get cancelOrderConfirm => 'Cancel this order?';

  @override
  String get cancelReasonHint => 'Reason (optional)';

  @override
  String cancelledReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get writeReview => 'Rate this wholesaler';

  @override
  String get editReview => 'Edit review';

  @override
  String get yourReview => 'Your review';

  @override
  String get itemOutOfStockLabel => 'Out of stock (not charged)';

  @override
  String paymentTerms(String terms) {
    return 'Payment: $terms';
  }

  @override
  String get reviewTitle => 'Rate';

  @override
  String get reviewQuestion => 'How was this wholesaler?';

  @override
  String get tagOnTime => 'On time';

  @override
  String get tagGoodQuality => 'Good quality';

  @override
  String get tagWellPacked => 'Well packed';

  @override
  String get tagGoodPrice => 'Good price';

  @override
  String get tagFriendly => 'Friendly';

  @override
  String get tagLate => 'Late';

  @override
  String get tagWrongItems => 'Wrong items';

  @override
  String get tagDamaged => 'Damaged';

  @override
  String get tagMissingItems => 'Items missing';

  @override
  String get reviewCommentHint => 'Anything to add? (optional)';

  @override
  String get submitReview => 'Submit';

  @override
  String get reviewThanks => 'Thank you for your review!';

  @override
  String get freeWholesalersTitle => 'Free price access';

  @override
  String freeWholesalersBody(int count) {
    return 'On the free plan you can choose $count wholesalers. You see their full prices and can order from them.';
  }

  @override
  String freeWholesalersCooldown(String date) {
    return 'You can swap your chosen wholesalers on $date';
  }

  @override
  String selectedCount(int selected, int max) {
    return 'Chosen $selected/$max';
  }

  @override
  String get fullAccessNoNeed => 'You can see all prices now. No need to choose.';

  @override
  String get saved => 'Saved';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get myShop => 'My shop';

  @override
  String get subscription => 'Subscription';

  @override
  String subTrial(String date) {
    return 'Free trial until $date';
  }

  @override
  String subActive(String date) {
    return 'Subscribed. Next renewal $date';
  }

  @override
  String subPastDue(String date) {
    return 'Your subscription has ended. Renew before $date to keep your price.';
  }

  @override
  String get subFree => 'Free plan';

  @override
  String lockedPrice(String price) {
    return 'Your monthly fee is locked at $price as long as you keep renewing';
  }

  @override
  String get subscribeComingSoon => 'Paid plans are coming soon';

  @override
  String get logout => 'Log out';

  @override
  String get logoutConfirm => 'Log out now?';

  @override
  String get sellerComingSoon => 'Wholesaler features are being built and will be ready soon';

  @override
  String get sellerPending => 'Your wholesaler details are waiting for review';

  @override
  String get adminUseWeb => 'Customer service: please use the web admin';

  @override
  String get pushChannelName => 'Order notifications';

  @override
  String get pushChannelDescription => 'New orders, order updates and the daily delivery summary';

  @override
  String get pushAskTitle => 'Turn on notifications?';

  @override
  String get pushAskSellerBody => 'Your phone will ring when a new order comes in, so you won\'t miss any.';

  @override
  String get pushAskBuyerBody =>
      'We\'ll let you know as soon as the wholesaler confirms, runs out of stock or sends out your order.';

  @override
  String get pushAskAllow => 'Turn on';

  @override
  String get pushAskLater => 'Not now';

  @override
  String get pushDenied => 'Notifications are off. You can turn them on in your phone\'s Settings > Notifications.';

  @override
  String get sellerErrUnsupportedFile =>
      'We can\'t read this kind of file. Please take a photo, or choose an Excel, PDF or CSV file.';

  @override
  String get sellerErrFileTooLarge => 'The file is too big (10 MB max).';

  @override
  String get sellerErrAiFailed => 'The AI couldn\'t read this price list. Please take a clearer photo and try again.';

  @override
  String get sellerErrImportTimeout => 'The AI is still reading. Please check again in a few minutes.';

  @override
  String get sellerErrImportDone => 'This price list has already been handled.';

  @override
  String sellerErrRowIncomplete(int row) {
    return 'Row $row is missing a name, unit, pack size or price.';
  }

  @override
  String sellerErrRowInvalidProduct(int row) {
    return 'Row $row is matched to the wrong product. Please choose again.';
  }

  @override
  String sellerErrDuplicateProduct(int row) {
    return 'Row $row updates the same product as another row. Please change one of them.';
  }

  @override
  String get sellerErrItemNotInOrder => 'That item is not in this order. Please open the order again.';

  @override
  String get sellerErrNotFound => 'Not found. It may have been removed.';

  @override
  String sellerHomeNewOrders(int count) {
    return 'New orders ($count)';
  }

  @override
  String get sellerNoNewOrders => 'No new orders';

  @override
  String sellerOldestWaiting(String duration) {
    return 'The oldest has waited $duration';
  }

  @override
  String sellerWaiting(String duration) {
    return 'Waiting $duration';
  }

  @override
  String sellerMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count minutes', one: '1 minute');
    return '$_temp0';
  }

  @override
  String sellerHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count hours', one: '1 hour');
    return '$_temp0';
  }

  @override
  String sellerDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count days', one: '1 day');
    return '$_temp0';
  }

  @override
  String sellerHomeToday(int count) {
    return 'Deliver today ($count)';
  }

  @override
  String sellerTodayTotal(String total) {
    return 'Total $total';
  }

  @override
  String get sellerNothingToday => 'Nothing to deliver today';

  @override
  String get sellerHomeProducts => 'Products & prices';

  @override
  String sellerProductsActive(int count) {
    return '$count on sale';
  }

  @override
  String sellerProductsOutOfStock(int count) {
    return '$count out of stock';
  }

  @override
  String sellerProductsLowStock(int count) {
    return '$count running low';
  }

  @override
  String sellerProductsDraft(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count drafts', one: '1 draft');
    return '$_temp0';
  }

  @override
  String get sellerHomeImport => 'Upload price list';

  @override
  String get sellerImportNone => 'Take a photo or pick an Excel file. AI makes your product list.';

  @override
  String get sellerImportProcessing => 'AI is reading your price list…';

  @override
  String get sellerImportReview => 'AI is done. Check it and put it on sale.';

  @override
  String get sellerImportFailed => 'The last one couldn\'t be read. Please upload again.';

  @override
  String sellerImportApplied(String date) {
    return 'Put on sale on $date';
  }

  @override
  String get sellerPendingBanner =>
      'We\'re checking your details. Buyers can\'t see you until then, but you can add products and prices now.';

  @override
  String get sellerSuspendedBanner =>
      'Your account is on hold, so buyers can\'t see you now. Please contact customer service.';

  @override
  String get sellerOrdersTitle => 'Orders';

  @override
  String get sellerTabPending => 'New';

  @override
  String get sellerTabToday => 'Today';

  @override
  String get sellerTabAll => 'All';

  @override
  String sellerTabWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String sellerTodayCount(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count orders', one: '1 order');
    return '$_temp0, total $total';
  }

  @override
  String get sellerOpenSummary => 'Delivery list (picking, print)';

  @override
  String sellerDeliverOn(String date) {
    return 'Deliver: $date';
  }

  @override
  String sellerBuyerNote(String note) {
    return 'Buyer\'s note: $note';
  }

  @override
  String get sellerCall => 'Call';

  @override
  String get sellerWhatsapp => 'WhatsApp';

  @override
  String sellerWhatsappHello(String orderNo) {
    return 'Hi, about your order $orderNo:';
  }

  @override
  String get sellerCannotOpen => 'Couldn\'t open it. Is the app installed on this phone?';

  @override
  String sellerContact(String name) {
    return 'Contact: $name';
  }

  @override
  String get sellerConfirm => 'Confirm';

  @override
  String get sellerOutOfStock => 'Out of stock';

  @override
  String get sellerChecklistTitle => 'Anything out of stock?';

  @override
  String get sellerChecklistHint =>
      'Tick what you don\'t have. Those won\'t be charged. If you have everything, just confirm.';

  @override
  String get sellerConfirmAllInStock => 'All in stock, confirm';

  @override
  String sellerConfirmWithOos(int count) {
    return 'Confirm ($count out of stock)';
  }

  @override
  String get sellerConfirmAllOos => 'Everything is out of stock';

  @override
  String get sellerOosConfirmTitle => 'Is the whole order out of stock?';

  @override
  String get sellerOosConfirmBody => 'The buyer will be told, and this order won\'t be delivered.';

  @override
  String get sellerOosConfirmButton => 'Mark out of stock';

  @override
  String get sellerConfirmedMsg => 'Confirmed. The buyer will be told.';

  @override
  String get sellerOosMsg => 'Marked out of stock. The buyer will be told.';

  @override
  String get sellerStartDelivery => 'Start delivery';

  @override
  String get sellerMarkDelivered => 'Delivered';

  @override
  String get sellerDeliveredConfirm => 'Has the order been delivered?';

  @override
  String get sellerDeliveringMsg => 'On the way. The buyer will be told.';

  @override
  String get sellerDeliveredMsg => 'Delivered. Thank you!';

  @override
  String get sellerMyBusiness => 'My business';

  @override
  String get sellerNotifyTitle => 'How should we tell you about new orders?';

  @override
  String get sellerNotifyAuto => 'Automatic (recommended)';

  @override
  String get sellerNotifyAutoHint => 'App notification if the app is on your phone, otherwise WhatsApp';

  @override
  String get sellerNotifyPush => 'App notification';

  @override
  String get sellerNotifyWhatsapp => 'WhatsApp';

  @override
  String sellerNotifyWhatsappTo(String phone) {
    return 'Sent to $phone';
  }

  @override
  String get sellerNotifyNoWhatsapp => 'No WhatsApp number yet. Customer service can add it for you.';

  @override
  String get sellerWhatsappOptIn => 'Get orders on WhatsApp';

  @override
  String get sellerWhatsappOptInHint => 'If this is off, we won\'t send you WhatsApp messages';

  @override
  String get sellerNotifyOwnerOnly => 'Only the owner can change this. Customer service can also change it for you.';

  @override
  String get pushSettingsTitle => 'Notifications on this phone';

  @override
  String get pushStatusOn => 'On. Your phone will ring for new orders.';

  @override
  String get pushStatusOff => 'Notifications are not on yet';

  @override
  String get pushNotSupported => 'This phone can\'t get app notifications. You can get orders on WhatsApp instead.';

  @override
  String get sellerSummaryTitle => 'Delivery list';

  @override
  String sellerSummaryHeading(String date) {
    return 'Delivery list $date';
  }

  @override
  String get sellerSummaryPrevDay => 'Previous day';

  @override
  String get sellerSummaryNextDay => 'Next day';

  @override
  String sellerSummaryPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders are not confirmed yet',
      one: '1 order is not confirmed yet',
    );
    return '$_temp0';
  }

  @override
  String get sellerSummaryGoConfirm => 'Go to confirm';

  @override
  String get sellerSummaryPicking => 'Picking list';

  @override
  String get sellerSummaryPickingHint => 'All orders added up. Out-of-stock items are not included.';

  @override
  String sellerSummaryQty(int qty, String unit) {
    return '$qty $unit';
  }

  @override
  String get sellerSummaryEmpty => 'Nothing to deliver on this day';

  @override
  String get sellerSummaryOrders => 'Orders (by area, then shop)';

  @override
  String get sellerSummaryOtherArea => 'Other areas';

  @override
  String get sellerSummaryPrint => 'Print';

  @override
  String get sellerSummaryShare => 'Share with driver';

  @override
  String sellerSummaryPhone(String phone) {
    return 'Phone: $phone';
  }

  @override
  String sellerSummaryAddress(String address) {
    return 'Address: $address';
  }

  @override
  String get sellerSummaryOosMark => '(out of stock)';

  @override
  String get sellerSummarySignature => 'Received by:';

  @override
  String sellerSummaryPage(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get sellerSummaryColItem => 'Item';

  @override
  String get sellerSummaryColQty => 'Qty';

  @override
  String get sellerSummaryColPack => 'Pack size';

  @override
  String get sellerSummaryPrintFailed => 'Couldn\'t print. Please try again.';

  @override
  String get sellerSummaryShareFailed => 'Couldn\'t share. Please try again.';

  @override
  String get sellerProductsSearch => 'Search products';

  @override
  String get sellerFilterAll => 'All';

  @override
  String get sellerFilterOutOfStock => 'Out of stock';

  @override
  String get sellerFilterDraft => 'Drafts';

  @override
  String get sellerStockIn => 'In stock';

  @override
  String get sellerStockLow => 'Running low';

  @override
  String get sellerStockOut => 'Out of stock';

  @override
  String get sellerStatusDraft => 'Draft';

  @override
  String get sellerStatusArchived => 'Off sale';

  @override
  String get sellerProductsEmpty =>
      'No products yet. Tap \"Add product\", or upload a price list and let the AI make them for you.';

  @override
  String get sellerProductsNoMatch => 'No matching products';

  @override
  String get sellerAddProduct => 'Add product';

  @override
  String get sellerEditProduct => 'Edit product';

  @override
  String get sellerFieldName => 'Product name';

  @override
  String get sellerFieldNameHint => 'e.g. 16oz PP cup 95mm';

  @override
  String get sellerFieldUnit => 'What unit do you sell in?';

  @override
  String sellerFieldPackQty(String unit) {
    return 'How many pieces in 1 $unit?';
  }

  @override
  String sellerFieldPrice(String unit) {
    return 'Price for 1 $unit';
  }

  @override
  String get sellerFieldPriceHint => 'e.g. 12.50';

  @override
  String sellerFieldMinQty(String unit) {
    return 'Minimum order ($unit)';
  }

  @override
  String get sellerFieldStock => 'Stock';

  @override
  String get sellerFieldStatus => 'Can buyers see it?';

  @override
  String get sellerOnSale => 'On sale';

  @override
  String get sellerOffSale => 'Off sale';

  @override
  String get sellerDraftHint => 'This is a draft, so buyers can\'t see it yet. Choose \"On sale\" and save.';

  @override
  String get sellerOffSaleHint => 'Buyers won\'t see it. You can put it back on sale any time.';

  @override
  String get sellerErrName => 'Please enter the product name';

  @override
  String get sellerErrPrice => 'Please enter a price, e.g. 12.50';

  @override
  String get sellerErrPackQty => 'At least 1';

  @override
  String get sellerErrForm => 'Some details are missing. Please check the parts in red.';

  @override
  String get sellerPhoto => 'Photo (optional)';

  @override
  String get sellerPhotoTake => 'Take photo';

  @override
  String get sellerPhotoPick => 'Choose photo';

  @override
  String get sellerPhotoRemove => 'Remove photo';

  @override
  String get sellerErrPhotoFile => 'Photos must be JPG, PNG or WebP, up to 5 MB';

  @override
  String get sellerErrNoPermission => 'Please allow this app to use the camera and photos in your phone\'s Settings';

  @override
  String get sellerImportIntro =>
      'Take a photo of your price list, or choose an Excel or PDF file. The AI turns it into products, and nothing goes on sale until you check it.';

  @override
  String get sellerImportCamera => 'Take a photo';

  @override
  String get sellerImportCameraHint => 'Snap the printed price list clearly';

  @override
  String get sellerImportGallery => 'Choose a photo';

  @override
  String get sellerImportGalleryHint => 'A photo or screenshot on your phone';

  @override
  String get sellerImportFile => 'Choose a file (Excel, PDF)';

  @override
  String get sellerImportFileHint => 'Excel, PDF or CSV, up to 10 MB';

  @override
  String get sellerImportUploading => 'Uploading…';

  @override
  String get sellerImportUploaded => 'Uploaded';

  @override
  String get sellerImportWaitHint =>
      'This usually takes 1 to 3 minutes. You can leave this page. The home screen will tell you when it\'s ready.';

  @override
  String get sellerImportStillReading => 'Still reading. Long price lists take a bit longer…';

  @override
  String get sellerImportFailedTitle => 'The AI couldn\'t read this price list';

  @override
  String get sellerImportRetry => 'Upload again';

  @override
  String get sellerBackHome => 'Back to home';

  @override
  String get sellerErrHeic =>
      'This is an iPhone HEIC photo, which the AI can\'t read. Tap \"Choose a photo\" and pick it again. The app will turn it into a JPG.';

  @override
  String get sellerImportErrRefused =>
      'The AI wouldn\'t read this file. Please make sure it\'s a price list and try again.';

  @override
  String get sellerImportErrTruncated =>
      'The price list is too long for the AI to finish. Please split it into a few photos or files and upload them one at a time.';

  @override
  String get sellerReviewTitle => 'Check price list';

  @override
  String sellerReviewSummary(int total, int create, int update, int skip) {
    String _temp0 = intl.Intl.pluralLogic(total, locale: localeName, other: '$total rows', one: '1 row');
    return '$_temp0: $create new, $update to update, $skip skipped';
  }

  @override
  String sellerReviewUnsure(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The AI isn\'t sure about $count rows. Please check the yellow ones.',
      one: 'The AI isn\'t sure about 1 row. Please check the yellow one.',
    );
    return '$_temp0';
  }

  @override
  String get sellerReviewHint => 'For each row, choose New, Update or Skip. Tap Edit to fix anything wrong.';

  @override
  String sellerReviewRow(int row) {
    return 'Row $row';
  }

  @override
  String get sellerReviewCheck => 'Please check';

  @override
  String get sellerReviewNoName => '(no name)';

  @override
  String get sellerReviewNoPrice => 'No price';

  @override
  String sellerReviewRaw(String text) {
    return 'Original: $text';
  }

  @override
  String sellerReviewMatched(String name) {
    return 'Will update: $name';
  }

  @override
  String sellerReviewPriceNow(String price) {
    return 'now $price';
  }

  @override
  String get sellerReviewNoMatch =>
      'None of your products match, so it will be added as new. To change the price of one of your products, tap \"Update\" and choose it.';

  @override
  String get sellerReviewNoRows => 'The AI found no products in this price list';

  @override
  String get sellerActionCreate => 'New';

  @override
  String get sellerActionUpdate => 'Update';

  @override
  String get sellerActionSkip => 'Skip';

  @override
  String sellerReviewMissing(String fields) {
    return 'Missing: $fields';
  }

  @override
  String get sellerMissingName => 'name';

  @override
  String get sellerMissingUnit => 'unit';

  @override
  String get sellerMissingPack => 'pack size';

  @override
  String get sellerMissingPrice => 'price';

  @override
  String get sellerMissingMatch => 'which product to update';

  @override
  String get sellerReviewEdit => 'Edit';

  @override
  String sellerReviewEditTitle(int row) {
    return 'Edit row $row';
  }

  @override
  String sellerApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Put $count items on sale',
      one: 'Put 1 item on sale',
    );
    return '$_temp0';
  }

  @override
  String sellerApplyDone(int created, int updated) {
    return 'Done: $created added, $updated updated';
  }

  @override
  String get sellerReviewApplied => 'This price list is already on sale';

  @override
  String get sellerReviewGoProducts => 'See products';

  @override
  String get sellerReviewWait => 'Wait for the AI';

  @override
  String get sellerImportUploadOther => 'Upload a different one';

  @override
  String get sellerImportCheckFailed => 'We couldn\'t check this price list';

  @override
  String get sellerImportRecovered => 'We found the price list you just picked. Uploading it now.';

  @override
  String get sellerImportErrService =>
      'The AI service is having a problem right now. Please upload again in a few minutes.';

  @override
  String get sellerImportErrFile =>
      'This file can\'t be opened, or it\'s empty. Please save it again (Excel as .xlsx), or take a photo instead.';

  @override
  String get sellerImportErrTimeout =>
      'The AI took too long. If the price list is long, split it into a few parts. If not, please try again in a few minutes.';

  @override
  String get sellerErrPhotoTooLarge =>
      'The photo is too big (7 MB max). Please take it again with \"Take a photo\", or choose a smaller photo.';

  @override
  String get sellerErrLoginExpired => 'Your login has expired. Please log out in Settings and log in again.';

  @override
  String get sellerReviewChooseProduct => 'Which product should this update?';

  @override
  String get sellerReviewChangeProduct => 'Choose another product';

  @override
  String get sellerReviewClearMatch => 'None of these (add as new)';

  @override
  String sellerReviewUsedByRow(int row) {
    return 'Already matched to row $row';
  }

  @override
  String sellerReviewWillRelist(String status) {
    return 'Now \"$status\". It will go on sale to buyers.';
  }

  @override
  String sellerReviewPackChange(String before, String after) {
    return 'Packing will change: $before → $after';
  }

  @override
  String sellerUnitPlural(String unit) {
    String _temp0 = intl.Intl.selectLogic(unit, {
      'carton': 'cartons',
      'pack': 'packs',
      'bag': 'bags',
      'roll': 'rolls',
      'bundle': 'bundles',
      'box': 'boxes',
      'dozen': 'dozen',
      'kg': 'kg',
      'other': 'pieces',
    });
    return '$_temp0';
  }

  @override
  String sellerErrTooManyImports(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'You\'ve uploaded a lot just now. Please wait $minutes minutes before uploading the next one.',
      one: 'You\'ve uploaded a lot just now. Please wait 1 minute before uploading the next one.',
    );
    return '$_temp0';
  }

  @override
  String get sellerErrSuspended =>
      'Your account is on hold, so you can\'t upload price lists now. Please contact customer service.';

  @override
  String get sellerErrQuotaUnavailable =>
      'The system is too busy right now and hasn\'t started reading this one. Please upload it again in a few minutes.';

  @override
  String get sellerImportErrNoProductsFile =>
      'The AI couldn\'t find product names and prices in this file. Please check it\'s a price list (with product names and prices), then upload it again.';

  @override
  String get sellerReviewProductUnknown => 'Couldn\'t load which product this will update. Pull down to load it again.';

  @override
  String sellerReviewIncomplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows are not filled in yet (in red). Fill them in, or choose \"Skip\".',
      one: '1 row is not filled in yet (in red). Fill it in, or choose \"Skip\".',
    );
    return '$_temp0';
  }

  @override
  String sellerOrdersLimited(int count) {
    return 'Only the latest $count orders are shown here';
  }
}
