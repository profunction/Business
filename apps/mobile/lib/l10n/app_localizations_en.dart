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
}
