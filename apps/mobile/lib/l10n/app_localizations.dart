import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ms.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ms'), Locale('zh')];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'新山批发'**
  String get appTitle;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'再试一次'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'好'**
  String get ok;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @next.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get next;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @optional.
  ///
  /// In zh, this message translates to:
  /// **'可以不填'**
  String get optional;

  /// No description provided for @errNetwork.
  ///
  /// In zh, this message translates to:
  /// **'连不上网络，请检查网络再试'**
  String get errNetwork;

  /// No description provided for @errUnknown.
  ///
  /// In zh, this message translates to:
  /// **'出了点问题，请再试一次'**
  String get errUnknown;

  /// No description provided for @errAuth.
  ///
  /// In zh, this message translates to:
  /// **'验证码不对或过期了，请再试一次'**
  String get errAuth;

  /// No description provided for @errNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'你没有权限做这件事'**
  String get errNotAllowed;

  /// No description provided for @errPriceChanged.
  ///
  /// In zh, this message translates to:
  /// **'刚刚有批发商改了价钱，请再看一次总额'**
  String get errPriceChanged;

  /// No description provided for @errCartHasProblems.
  ///
  /// In zh, this message translates to:
  /// **'购物车里有问题，请先处理红色的部分'**
  String get errCartHasProblems;

  /// No description provided for @errCartEmpty.
  ///
  /// In zh, this message translates to:
  /// **'购物车是空的'**
  String get errCartEmpty;

  /// No description provided for @errUnlockCooldown.
  ///
  /// In zh, this message translates to:
  /// **'现在还不能换掉已选的批发商'**
  String get errUnlockCooldown;

  /// No description provided for @errTooManyWholesalers.
  ///
  /// In zh, this message translates to:
  /// **'免费版选的批发商太多了'**
  String get errTooManyWholesalers;

  /// No description provided for @errWholesalerNotAvailable.
  ///
  /// In zh, this message translates to:
  /// **'这家批发商现在不送你那区'**
  String get errWholesalerNotAvailable;

  /// No description provided for @errInvalidTransition.
  ///
  /// In zh, this message translates to:
  /// **'订单状态已经变了，请刷新再看'**
  String get errInvalidTransition;

  /// No description provided for @errOrderNotDelivered.
  ///
  /// In zh, this message translates to:
  /// **'货还没送到，送到后才能评价'**
  String get errOrderNotDelivered;

  /// No description provided for @errNoPreviousOrder.
  ///
  /// In zh, this message translates to:
  /// **'你还没下过单'**
  String get errNoPreviousOrder;

  /// No description provided for @languagePageTitle.
  ///
  /// In zh, this message translates to:
  /// **'请选择语言 · Choose language · Pilih bahasa'**
  String get languagePageTitle;

  /// No description provided for @loginTitle.
  ///
  /// In zh, this message translates to:
  /// **'用手机号登录'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'我们会发一个验证码到你的手机'**
  String get loginSubtitle;

  /// No description provided for @phoneLabel.
  ///
  /// In zh, this message translates to:
  /// **'手机号码'**
  String get phoneLabel;

  /// No description provided for @phoneInvalid.
  ///
  /// In zh, this message translates to:
  /// **'这不像手机号码，请再检查一次'**
  String get phoneInvalid;

  /// No description provided for @sendCode.
  ///
  /// In zh, this message translates to:
  /// **'发送验证码'**
  String get sendCode;

  /// No description provided for @otpTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入验证码'**
  String get otpTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In zh, this message translates to:
  /// **'验证码已经发到 {phone}'**
  String otpSentTo(String phone);

  /// No description provided for @otpLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get otpLogin;

  /// No description provided for @otpResend.
  ///
  /// In zh, this message translates to:
  /// **'重新发送'**
  String get otpResend;

  /// No description provided for @otpResendIn.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒后可以重新发送'**
  String otpResendIn(int seconds);

  /// No description provided for @changePhone.
  ///
  /// In zh, this message translates to:
  /// **'换号码'**
  String get changePhone;

  /// No description provided for @registerTitle.
  ///
  /// In zh, this message translates to:
  /// **'开你的店'**
  String get registerTitle;

  /// No description provided for @shopNameQuestion.
  ///
  /// In zh, this message translates to:
  /// **'你的店叫什么名字？'**
  String get shopNameQuestion;

  /// No description provided for @shopNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：阿明茶餐室'**
  String get shopNameHint;

  /// No description provided for @shopTypeQuestion.
  ///
  /// In zh, this message translates to:
  /// **'你的店是做什么的？'**
  String get shopTypeQuestion;

  /// No description provided for @shopTypeRestaurant.
  ///
  /// In zh, this message translates to:
  /// **'餐馆'**
  String get shopTypeRestaurant;

  /// No description provided for @shopTypeDrinkStall.
  ///
  /// In zh, this message translates to:
  /// **'饮料店'**
  String get shopTypeDrinkStall;

  /// No description provided for @shopTypeGrocery.
  ///
  /// In zh, this message translates to:
  /// **'杂货店'**
  String get shopTypeGrocery;

  /// No description provided for @shopTypeOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get shopTypeOther;

  /// No description provided for @zoneQuestion.
  ///
  /// In zh, this message translates to:
  /// **'你的店在哪一区？'**
  String get zoneQuestion;

  /// No description provided for @addressQuestion.
  ///
  /// In zh, this message translates to:
  /// **'店的地址（送货用）'**
  String get addressQuestion;

  /// No description provided for @addressHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：12, Jalan Molek 1/2, Taman Molek'**
  String get addressHint;

  /// No description provided for @registerFinish.
  ///
  /// In zh, this message translates to:
  /// **'开始用'**
  String get registerFinish;

  /// No description provided for @homeReorder.
  ///
  /// In zh, this message translates to:
  /// **'跟上次一样'**
  String get homeReorder;

  /// No description provided for @homeReorderLast.
  ///
  /// In zh, this message translates to:
  /// **'上次：{date}，{total}'**
  String homeReorderLast(String date, String total);

  /// No description provided for @homeShop.
  ///
  /// In zh, this message translates to:
  /// **'买东西'**
  String get homeShop;

  /// No description provided for @homeOrders.
  ///
  /// In zh, this message translates to:
  /// **'我的订单'**
  String get homeOrders;

  /// No description provided for @homeActiveOrders.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张进行中'**
  String homeActiveOrders(int count);

  /// No description provided for @homeCart.
  ///
  /// In zh, this message translates to:
  /// **'购物车（{count} 样）'**
  String homeCart(int count);

  /// No description provided for @trialBanner.
  ///
  /// In zh, this message translates to:
  /// **'免费试用还有 {days} 天，全部价钱都看得到'**
  String trialBanner(int days);

  /// No description provided for @freeBanner.
  ///
  /// In zh, this message translates to:
  /// **'免费版：可以选 {count} 家批发商看价钱'**
  String freeBanner(int count);

  /// No description provided for @chooseWholesalers.
  ///
  /// In zh, this message translates to:
  /// **'选批发商'**
  String get chooseWholesalers;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设定'**
  String get settings;

  /// No description provided for @browseTitle.
  ///
  /// In zh, this message translates to:
  /// **'买东西'**
  String get browseTitle;

  /// No description provided for @browseByProduct.
  ///
  /// In zh, this message translates to:
  /// **'看商品'**
  String get browseByProduct;

  /// No description provided for @browseByWholesaler.
  ///
  /// In zh, this message translates to:
  /// **'看批发商'**
  String get browseByWholesaler;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'找东西，例如：杯'**
  String get searchHint;

  /// No description provided for @noResults.
  ///
  /// In zh, this message translates to:
  /// **'找不到'**
  String get noResults;

  /// No description provided for @categoryItemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 样'**
  String categoryItemCount(int count);

  /// No description provided for @sellerCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 家有卖'**
  String sellerCount(int count);

  /// No description provided for @cheapestPerUnit.
  ///
  /// In zh, this message translates to:
  /// **'最便宜每个 {sen} 仙'**
  String cheapestPerUnit(String sen);

  /// No description provided for @compareTitle.
  ///
  /// In zh, this message translates to:
  /// **'比价钱'**
  String get compareTitle;

  /// No description provided for @perUnit.
  ///
  /// In zh, this message translates to:
  /// **'每个 {sen} 仙'**
  String perUnit(String sen);

  /// No description provided for @pricePerSellUnit.
  ///
  /// In zh, this message translates to:
  /// **'{price} / {unit}'**
  String pricePerSellUnit(String price, String unit);

  /// No description provided for @packQty.
  ///
  /// In zh, this message translates to:
  /// **'一{unit} {qty} 个'**
  String packQty(String unit, int qty);

  /// No description provided for @priceLocked.
  ///
  /// In zh, this message translates to:
  /// **'价钱未开放'**
  String get priceLocked;

  /// No description provided for @rating.
  ///
  /// In zh, this message translates to:
  /// **'{avg}（{count} 个评价）'**
  String rating(String avg, int count);

  /// No description provided for @noRatings.
  ///
  /// In zh, this message translates to:
  /// **'还没有评价'**
  String get noRatings;

  /// No description provided for @leadTime.
  ///
  /// In zh, this message translates to:
  /// **'{days, plural, =0{今天送到} =1{明天送到} other{{days} 天送到}}'**
  String leadTime(int days);

  /// No description provided for @minOrderQty.
  ///
  /// In zh, this message translates to:
  /// **'最少买 {qty} {unit}'**
  String minOrderQty(int qty, String unit);

  /// No description provided for @shippingFee.
  ///
  /// In zh, this message translates to:
  /// **'运费 {fee}'**
  String shippingFee(String fee);

  /// No description provided for @freeShippingOver.
  ///
  /// In zh, this message translates to:
  /// **'满 {amount} 免运费'**
  String freeShippingOver(String amount);

  /// No description provided for @minOrderAmount.
  ///
  /// In zh, this message translates to:
  /// **'最低消费 {amount}'**
  String minOrderAmount(String amount);

  /// No description provided for @outOfStock.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get outOfStock;

  /// No description provided for @lowStock.
  ///
  /// In zh, this message translates to:
  /// **'快卖完'**
  String get lowStock;

  /// No description provided for @founding.
  ///
  /// In zh, this message translates to:
  /// **'创始会员'**
  String get founding;

  /// No description provided for @addToCart.
  ///
  /// In zh, this message translates to:
  /// **'放进购物车'**
  String get addToCart;

  /// No description provided for @inCart.
  ///
  /// In zh, this message translates to:
  /// **'购物车里有 {qty}'**
  String inCart(int qty);

  /// No description provided for @updateCart.
  ///
  /// In zh, this message translates to:
  /// **'更新购物车'**
  String get updateCart;

  /// No description provided for @removeFromCart.
  ///
  /// In zh, this message translates to:
  /// **'拿掉'**
  String get removeFromCart;

  /// No description provided for @addedToCart.
  ///
  /// In zh, this message translates to:
  /// **'已经放进购物车'**
  String get addedToCart;

  /// No description provided for @lockedHint.
  ///
  /// In zh, this message translates to:
  /// **'免费版只看得到你选的批发商的价钱'**
  String get lockedHint;

  /// No description provided for @chooseThisWholesaler.
  ///
  /// In zh, this message translates to:
  /// **'把这家加进免费名单'**
  String get chooseThisWholesaler;

  /// No description provided for @freeSlotsFull.
  ///
  /// In zh, this message translates to:
  /// **'免费名单满了，去「选批发商」换一家'**
  String get freeSlotsFull;

  /// No description provided for @unitCarton.
  ///
  /// In zh, this message translates to:
  /// **'箱'**
  String get unitCarton;

  /// No description provided for @unitPack.
  ///
  /// In zh, this message translates to:
  /// **'包'**
  String get unitPack;

  /// No description provided for @unitBag.
  ///
  /// In zh, this message translates to:
  /// **'袋'**
  String get unitBag;

  /// No description provided for @unitRoll.
  ///
  /// In zh, this message translates to:
  /// **'卷'**
  String get unitRoll;

  /// No description provided for @unitBundle.
  ///
  /// In zh, this message translates to:
  /// **'扎'**
  String get unitBundle;

  /// No description provided for @unitBox.
  ///
  /// In zh, this message translates to:
  /// **'盒'**
  String get unitBox;

  /// No description provided for @unitPiece.
  ///
  /// In zh, this message translates to:
  /// **'个'**
  String get unitPiece;

  /// No description provided for @unitDozen.
  ///
  /// In zh, this message translates to:
  /// **'打'**
  String get unitDozen;

  /// No description provided for @unitKg.
  ///
  /// In zh, this message translates to:
  /// **'公斤'**
  String get unitKg;

  /// No description provided for @productCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 样货'**
  String productCount(int count);

  /// No description provided for @deliveryDays.
  ///
  /// In zh, this message translates to:
  /// **'送货日：{days}'**
  String deliveryDays(String days);

  /// No description provided for @weekdayShort1.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get weekdayShort1;

  /// No description provided for @weekdayShort2.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get weekdayShort2;

  /// No description provided for @weekdayShort3.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get weekdayShort3;

  /// No description provided for @weekdayShort4.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get weekdayShort4;

  /// No description provided for @weekdayShort5.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get weekdayShort5;

  /// No description provided for @weekdayShort6.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get weekdayShort6;

  /// No description provided for @weekdayShort7.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get weekdayShort7;

  /// No description provided for @paymentCod.
  ///
  /// In zh, this message translates to:
  /// **'货到付款'**
  String get paymentCod;

  /// No description provided for @paymentTransfer.
  ///
  /// In zh, this message translates to:
  /// **'转账'**
  String get paymentTransfer;

  /// No description provided for @paymentCredit.
  ///
  /// In zh, this message translates to:
  /// **'月结'**
  String get paymentCredit;

  /// No description provided for @cartTitle.
  ///
  /// In zh, this message translates to:
  /// **'购物车'**
  String get cartTitle;

  /// No description provided for @cartEmpty.
  ///
  /// In zh, this message translates to:
  /// **'购物车是空的'**
  String get cartEmpty;

  /// No description provided for @goodsSubtotal.
  ///
  /// In zh, this message translates to:
  /// **'货价'**
  String get goodsSubtotal;

  /// No description provided for @shipping.
  ///
  /// In zh, this message translates to:
  /// **'运费'**
  String get shipping;

  /// No description provided for @freeShipping.
  ///
  /// In zh, this message translates to:
  /// **'免运费'**
  String get freeShipping;

  /// No description provided for @total.
  ///
  /// In zh, this message translates to:
  /// **'总额'**
  String get total;

  /// No description provided for @shortOfFreeShipping.
  ///
  /// In zh, this message translates to:
  /// **'再买 {amount} 就免运费'**
  String shortOfFreeShipping(String amount);

  /// No description provided for @shortOfMinOrder.
  ///
  /// In zh, this message translates to:
  /// **'还差 {amount} 才到最低消费'**
  String shortOfMinOrder(String amount);

  /// No description provided for @expectedDelivery.
  ///
  /// In zh, this message translates to:
  /// **'预计 {date} 送到'**
  String expectedDelivery(String date);

  /// No description provided for @problemProductUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这样货下架了，请拿掉'**
  String get problemProductUnavailable;

  /// No description provided for @problemNotDelivering.
  ///
  /// In zh, this message translates to:
  /// **'这家现在不送你那区'**
  String get problemNotDelivering;

  /// No description provided for @problemWholesalerLocked.
  ///
  /// In zh, this message translates to:
  /// **'免费版看不到这家的价钱，不能下单'**
  String get problemWholesalerLocked;

  /// No description provided for @problemOutOfStock.
  ///
  /// In zh, this message translates to:
  /// **'缺货了，请拿掉'**
  String get problemOutOfStock;

  /// No description provided for @problemBelowMinQty.
  ///
  /// In zh, this message translates to:
  /// **'最少要买 {qty}'**
  String problemBelowMinQty(int qty);

  /// No description provided for @goToConfirm.
  ///
  /// In zh, this message translates to:
  /// **'下一步：确认订单'**
  String get goToConfirm;

  /// No description provided for @fixProblemsFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先处理红色的问题'**
  String get fixProblemsFirst;

  /// No description provided for @confirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认订单'**
  String get confirmTitle;

  /// No description provided for @ordersWillSplit.
  ///
  /// In zh, this message translates to:
  /// **'会分成 {count} 张单，每家批发商自己送货'**
  String ordersWillSplit(int count);

  /// No description provided for @noteLabel.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get noteLabel;

  /// No description provided for @placeOrder.
  ///
  /// In zh, this message translates to:
  /// **'确认下单 {total}'**
  String placeOrder(String total);

  /// No description provided for @priceChangedTitle.
  ///
  /// In zh, this message translates to:
  /// **'价钱改了'**
  String get priceChangedTitle;

  /// No description provided for @reorderPriceChanges.
  ///
  /// In zh, this message translates to:
  /// **'这几样改了价：'**
  String get reorderPriceChanges;

  /// No description provided for @reorderSkipped.
  ///
  /// In zh, this message translates to:
  /// **'这几样买不到了，已经拿掉：'**
  String get reorderSkipped;

  /// No description provided for @priceChangeLine.
  ///
  /// In zh, this message translates to:
  /// **'{name}：{oldPrice} → {newPrice}'**
  String priceChangeLine(String name, String oldPrice, String newPrice);

  /// No description provided for @orderPlacedTitle.
  ///
  /// In zh, this message translates to:
  /// **'下单成功！'**
  String get orderPlacedTitle;

  /// No description provided for @orderPlacedBody.
  ///
  /// In zh, this message translates to:
  /// **'批发商确认后会通知你'**
  String get orderPlacedBody;

  /// No description provided for @viewOrders.
  ///
  /// In zh, this message translates to:
  /// **'看我的订单'**
  String get viewOrders;

  /// No description provided for @backHome.
  ///
  /// In zh, this message translates to:
  /// **'回首页'**
  String get backHome;

  /// No description provided for @ordersTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的订单'**
  String get ordersTitle;

  /// No description provided for @noOrders.
  ///
  /// In zh, this message translates to:
  /// **'还没有订单'**
  String get noOrders;

  /// No description provided for @statusPending.
  ///
  /// In zh, this message translates to:
  /// **'待确认'**
  String get statusPending;

  /// No description provided for @statusConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'已确认'**
  String get statusConfirmed;

  /// No description provided for @statusOutOfStock.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get statusOutOfStock;

  /// No description provided for @statusDelivering.
  ///
  /// In zh, this message translates to:
  /// **'送货中'**
  String get statusDelivering;

  /// No description provided for @statusDelivered.
  ///
  /// In zh, this message translates to:
  /// **'已送达'**
  String get statusDelivered;

  /// No description provided for @statusCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get statusCancelled;

  /// No description provided for @itemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 样货'**
  String itemCount(int count);

  /// No description provided for @outOfStockCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 样缺货'**
  String outOfStockCount(int count);

  /// No description provided for @orderTitle.
  ///
  /// In zh, this message translates to:
  /// **'订单 {orderNo}'**
  String orderTitle(String orderNo);

  /// No description provided for @orderedAt.
  ///
  /// In zh, this message translates to:
  /// **'下单：{date}'**
  String orderedAt(String date);

  /// No description provided for @callWholesaler.
  ///
  /// In zh, this message translates to:
  /// **'打电话给批发商'**
  String get callWholesaler;

  /// No description provided for @markReceived.
  ///
  /// In zh, this message translates to:
  /// **'收到了'**
  String get markReceived;

  /// No description provided for @markReceivedConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定货已经收到了？'**
  String get markReceivedConfirm;

  /// No description provided for @cancelOrder.
  ///
  /// In zh, this message translates to:
  /// **'取消订单'**
  String get cancelOrder;

  /// No description provided for @cancelOrderConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要取消这张单？'**
  String get cancelOrderConfirm;

  /// No description provided for @cancelReasonHint.
  ///
  /// In zh, this message translates to:
  /// **'原因（可以不填）'**
  String get cancelReasonHint;

  /// No description provided for @cancelledReason.
  ///
  /// In zh, this message translates to:
  /// **'取消原因：{reason}'**
  String cancelledReason(String reason);

  /// No description provided for @writeReview.
  ///
  /// In zh, this message translates to:
  /// **'给批发商评分'**
  String get writeReview;

  /// No description provided for @editReview.
  ///
  /// In zh, this message translates to:
  /// **'改评价'**
  String get editReview;

  /// No description provided for @yourReview.
  ///
  /// In zh, this message translates to:
  /// **'你的评价'**
  String get yourReview;

  /// No description provided for @itemOutOfStockLabel.
  ///
  /// In zh, this message translates to:
  /// **'缺货（不算钱）'**
  String get itemOutOfStockLabel;

  /// No description provided for @paymentTerms.
  ///
  /// In zh, this message translates to:
  /// **'付款方式：{terms}'**
  String paymentTerms(String terms);

  /// No description provided for @reviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'评分'**
  String get reviewTitle;

  /// No description provided for @reviewQuestion.
  ///
  /// In zh, this message translates to:
  /// **'这家批发商怎么样？'**
  String get reviewQuestion;

  /// No description provided for @tagOnTime.
  ///
  /// In zh, this message translates to:
  /// **'准时'**
  String get tagOnTime;

  /// No description provided for @tagGoodQuality.
  ///
  /// In zh, this message translates to:
  /// **'货好'**
  String get tagGoodQuality;

  /// No description provided for @tagWellPacked.
  ///
  /// In zh, this message translates to:
  /// **'包装好'**
  String get tagWellPacked;

  /// No description provided for @tagGoodPrice.
  ///
  /// In zh, this message translates to:
  /// **'价钱好'**
  String get tagGoodPrice;

  /// No description provided for @tagFriendly.
  ///
  /// In zh, this message translates to:
  /// **'态度好'**
  String get tagFriendly;

  /// No description provided for @tagLate.
  ///
  /// In zh, this message translates to:
  /// **'迟到'**
  String get tagLate;

  /// No description provided for @tagWrongItems.
  ///
  /// In zh, this message translates to:
  /// **'送错货'**
  String get tagWrongItems;

  /// No description provided for @tagDamaged.
  ///
  /// In zh, this message translates to:
  /// **'有破损'**
  String get tagDamaged;

  /// No description provided for @tagMissingItems.
  ///
  /// In zh, this message translates to:
  /// **'少了货'**
  String get tagMissingItems;

  /// No description provided for @reviewCommentHint.
  ///
  /// In zh, this message translates to:
  /// **'想说的话（可以不填）'**
  String get reviewCommentHint;

  /// No description provided for @submitReview.
  ///
  /// In zh, this message translates to:
  /// **'送出'**
  String get submitReview;

  /// No description provided for @reviewThanks.
  ///
  /// In zh, this message translates to:
  /// **'谢谢你的评价！'**
  String get reviewThanks;

  /// No description provided for @freeWholesalersTitle.
  ///
  /// In zh, this message translates to:
  /// **'免费看价钱的批发商'**
  String get freeWholesalersTitle;

  /// No description provided for @freeWholesalersBody.
  ///
  /// In zh, this message translates to:
  /// **'免费版可以选 {count} 家批发商，完整看到他们的价钱，也可以向他们下单'**
  String freeWholesalersBody(int count);

  /// No description provided for @freeWholesalersCooldown.
  ///
  /// In zh, this message translates to:
  /// **'要换掉已选的批发商，要等到 {date}'**
  String freeWholesalersCooldown(String date);

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {selected}/{max}'**
  String selectedCount(int selected, int max);

  /// No description provided for @fullAccessNoNeed.
  ///
  /// In zh, this message translates to:
  /// **'你现在全部价钱都看得到，不用选'**
  String get fullAccessNoNeed;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'保存好了'**
  String get saved;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设定'**
  String get settingsTitle;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @myShop.
  ///
  /// In zh, this message translates to:
  /// **'我的店'**
  String get myShop;

  /// No description provided for @subscription.
  ///
  /// In zh, this message translates to:
  /// **'订阅'**
  String get subscription;

  /// No description provided for @subTrial.
  ///
  /// In zh, this message translates to:
  /// **'免费试用到 {date}'**
  String subTrial(String date);

  /// No description provided for @subActive.
  ///
  /// In zh, this message translates to:
  /// **'已订阅，下次续费 {date}'**
  String subActive(String date);

  /// No description provided for @subPastDue.
  ///
  /// In zh, this message translates to:
  /// **'订阅到期了，{date} 前续费可以保留原价'**
  String subPastDue(String date);

  /// No description provided for @subFree.
  ///
  /// In zh, this message translates to:
  /// **'免费版'**
  String get subFree;

  /// No description provided for @lockedPrice.
  ///
  /// In zh, this message translates to:
  /// **'你的月费锁定 {price}，一直续费就不会涨'**
  String lockedPrice(String price);

  /// No description provided for @subscribeComingSoon.
  ///
  /// In zh, this message translates to:
  /// **'付费订阅很快推出'**
  String get subscribeComingSoon;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'登出'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要登出？'**
  String get logoutConfirm;

  /// No description provided for @sellerComingSoon.
  ///
  /// In zh, this message translates to:
  /// **'批发商的功能正在做，很快就可以用'**
  String get sellerComingSoon;

  /// No description provided for @sellerPending.
  ///
  /// In zh, this message translates to:
  /// **'你的批发商资料正在等客服审核'**
  String get sellerPending;

  /// No description provided for @adminUseWeb.
  ///
  /// In zh, this message translates to:
  /// **'客服请用网页后台'**
  String get adminUseWeb;

  /// No description provided for @pushChannelName.
  ///
  /// In zh, this message translates to:
  /// **'订单通知'**
  String get pushChannelName;

  /// No description provided for @pushChannelDescription.
  ///
  /// In zh, this message translates to:
  /// **'新订单、订单状态和每天的送货总结'**
  String get pushChannelDescription;

  /// No description provided for @pushAskTitle.
  ///
  /// In zh, this message translates to:
  /// **'打开通知？'**
  String get pushAskTitle;

  /// No description provided for @pushAskSellerBody.
  ///
  /// In zh, this message translates to:
  /// **'有新订单时手机会响，不会漏单。'**
  String get pushAskSellerBody;

  /// No description provided for @pushAskBuyerBody.
  ///
  /// In zh, this message translates to:
  /// **'批发商确认、缺货或出发送货时，马上通知你。'**
  String get pushAskBuyerBody;

  /// No description provided for @pushAskAllow.
  ///
  /// In zh, this message translates to:
  /// **'打开通知'**
  String get pushAskAllow;

  /// No description provided for @pushAskLater.
  ///
  /// In zh, this message translates to:
  /// **'以后再说'**
  String get pushAskLater;

  /// No description provided for @pushDenied.
  ///
  /// In zh, this message translates to:
  /// **'通知没有打开。想打开的话，到手机的「设定」→「通知」。'**
  String get pushDenied;

  /// No description provided for @sellerErrUnsupportedFile.
  ///
  /// In zh, this message translates to:
  /// **'这种档案看不懂。请拍照，或选 Excel、PDF、CSV 档案。'**
  String get sellerErrUnsupportedFile;

  /// No description provided for @sellerErrFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'档案太大了（最多 10 MB）'**
  String get sellerErrFileTooLarge;

  /// No description provided for @sellerErrAiFailed.
  ///
  /// In zh, this message translates to:
  /// **'AI 读不懂这份价目表。请拍清楚一点再试一次。'**
  String get sellerErrAiFailed;

  /// No description provided for @sellerErrImportTimeout.
  ///
  /// In zh, this message translates to:
  /// **'AI 还没读完。请过几分钟再回来看。'**
  String get sellerErrImportTimeout;

  /// No description provided for @sellerErrImportDone.
  ///
  /// In zh, this message translates to:
  /// **'这份价目表已经处理过了'**
  String get sellerErrImportDone;

  /// No description provided for @sellerErrRowIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'第 {row} 行还缺名字、单位、包装数量或价钱'**
  String sellerErrRowIncomplete(int row);

  /// No description provided for @sellerErrRowInvalidProduct.
  ///
  /// In zh, this message translates to:
  /// **'第 {row} 行对到的商品不对，请重新选'**
  String sellerErrRowInvalidProduct(int row);

  /// No description provided for @sellerErrDuplicateProduct.
  ///
  /// In zh, this message translates to:
  /// **'第 {row} 行跟另一行改同一样商品，请改掉其中一行'**
  String sellerErrDuplicateProduct(int row);

  /// No description provided for @sellerErrItemNotInOrder.
  ///
  /// In zh, this message translates to:
  /// **'这样东西不在这张订单里，请重新打开订单'**
  String get sellerErrItemNotInOrder;

  /// No description provided for @sellerErrNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到，可能已经被删掉了'**
  String get sellerErrNotFound;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ms', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'ms':
      return L10nMs();
    case 'zh':
      return L10nZh();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
