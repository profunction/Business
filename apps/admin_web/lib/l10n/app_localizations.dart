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
  /// **'新山批发 · 客服后台'**
  String get appTitle;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @signOut.
  ///
  /// In zh, this message translates to:
  /// **'登出'**
  String get signOut;

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

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get searchHint;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get saved;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制：{text}'**
  String copied(String text);

  /// No description provided for @demoBanner.
  ///
  /// In zh, this message translates to:
  /// **'示范模式：资料是样本，按了不会真的改服务器'**
  String get demoBanner;

  /// No description provided for @errNetwork.
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器，请检查网络'**
  String get errNetwork;

  /// No description provided for @errAuth.
  ///
  /// In zh, this message translates to:
  /// **'验证码不对，或者登录过期了'**
  String get errAuth;

  /// No description provided for @errNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'没有权限（只有客服可以）'**
  String get errNotAllowed;

  /// No description provided for @errPriceChanged.
  ///
  /// In zh, this message translates to:
  /// **'价钱刚好改了，请看一下新的总额再下单'**
  String get errPriceChanged;

  /// No description provided for @errCartHasProblems.
  ///
  /// In zh, this message translates to:
  /// **'购物车有问题，请看每一行的提示'**
  String get errCartHasProblems;

  /// No description provided for @errCartEmpty.
  ///
  /// In zh, this message translates to:
  /// **'购物车是空的'**
  String get errCartEmpty;

  /// No description provided for @errInvalidTransition.
  ///
  /// In zh, this message translates to:
  /// **'订单现在的状态不能这样改'**
  String get errInvalidTransition;

  /// No description provided for @errInvalidRate.
  ///
  /// In zh, this message translates to:
  /// **'比例要在 0% 到 20% 之间，最多两位小数'**
  String get errInvalidRate;

  /// No description provided for @errInvalidDays.
  ///
  /// In zh, this message translates to:
  /// **'天数要在 1 到 90 之间'**
  String get errInvalidDays;

  /// No description provided for @errInvalidMonths.
  ///
  /// In zh, this message translates to:
  /// **'月数要在 1 到 24 之间'**
  String get errInvalidMonths;

  /// No description provided for @errInvalidAmount.
  ///
  /// In zh, this message translates to:
  /// **'金额不对'**
  String get errInvalidAmount;

  /// No description provided for @errDuplicateReference.
  ///
  /// In zh, this message translates to:
  /// **'这个参考号已经记过了'**
  String get errDuplicateReference;

  /// No description provided for @errSubscriptionState.
  ///
  /// In zh, this message translates to:
  /// **'这个订阅现在不能这样改'**
  String get errSubscriptionState;

  /// No description provided for @errSubscriptionOpen.
  ///
  /// In zh, this message translates to:
  /// **'这家店已经有新的订阅'**
  String get errSubscriptionOpen;

  /// No description provided for @errInvoiceState.
  ///
  /// In zh, this message translates to:
  /// **'账单现在的状态不能这样改'**
  String get errInvoiceState;

  /// No description provided for @errFoundingFull.
  ///
  /// In zh, this message translates to:
  /// **'创始会员名额满了'**
  String get errFoundingFull;

  /// No description provided for @errInvalidProduct.
  ///
  /// In zh, this message translates to:
  /// **'商品资料不对：名称、单位、价钱、数量都要填对'**
  String get errInvalidProduct;

  /// No description provided for @errInvalidNote.
  ///
  /// In zh, this message translates to:
  /// **'请写跟进内容'**
  String get errInvalidNote;

  /// No description provided for @errNoPricingPlan.
  ///
  /// In zh, this message translates to:
  /// **'系统还没设定月费（找技术）'**
  String get errNoPricingPlan;

  /// No description provided for @errUnknown.
  ///
  /// In zh, this message translates to:
  /// **'出错了（{code}）'**
  String errUnknown(String code);

  /// No description provided for @loginTitle.
  ///
  /// In zh, this message translates to:
  /// **'客服登录'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用手机号和验证码登录。只有客服账号可以进来。'**
  String get loginSubtitle;

  /// No description provided for @phoneLabel.
  ///
  /// In zh, this message translates to:
  /// **'手机号'**
  String get phoneLabel;

  /// No description provided for @phoneInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入马来西亚手机号，例如 012-345 6789'**
  String get phoneInvalid;

  /// No description provided for @sendCode.
  ///
  /// In zh, this message translates to:
  /// **'发验证码'**
  String get sendCode;

  /// No description provided for @otpTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入验证码'**
  String get otpTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发到 {phone}'**
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
  /// **'{seconds} 秒后可以重发'**
  String otpResendIn(int seconds);

  /// No description provided for @changePhone.
  ///
  /// In zh, this message translates to:
  /// **'换号码'**
  String get changePhone;

  /// No description provided for @deniedTitle.
  ///
  /// In zh, this message translates to:
  /// **'这个账号不是客服'**
  String get deniedTitle;

  /// No description provided for @deniedBody.
  ///
  /// In zh, this message translates to:
  /// **'客服后台只给客服用。请用客服的手机号登录；老板和批发商请用手机 App。'**
  String get deniedBody;

  /// No description provided for @loadingContext.
  ///
  /// In zh, this message translates to:
  /// **'正在读取资料…'**
  String get loadingContext;

  /// No description provided for @navDashboard.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get navDashboard;

  /// No description provided for @navOrders.
  ///
  /// In zh, this message translates to:
  /// **'全部订单'**
  String get navOrders;

  /// No description provided for @navFollowup.
  ///
  /// In zh, this message translates to:
  /// **'待跟进'**
  String get navFollowup;

  /// No description provided for @navPlaceOrder.
  ///
  /// In zh, this message translates to:
  /// **'代下单'**
  String get navPlaceOrder;

  /// No description provided for @navWholesalers.
  ///
  /// In zh, this message translates to:
  /// **'批发商'**
  String get navWholesalers;

  /// No description provided for @navSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'订阅'**
  String get navSubscriptions;

  /// No description provided for @navCommission.
  ///
  /// In zh, this message translates to:
  /// **'佣金报表'**
  String get navCommission;

  /// No description provided for @navAudit.
  ///
  /// In zh, this message translates to:
  /// **'操作记录'**
  String get navAudit;

  /// No description provided for @dashUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'超过 {minutes} 分钟没确认'**
  String dashUnconfirmed(int minutes);

  /// No description provided for @dashPendingOrders.
  ///
  /// In zh, this message translates to:
  /// **'待确认订单'**
  String get dashPendingOrders;

  /// No description provided for @dashPendingWholesalers.
  ///
  /// In zh, this message translates to:
  /// **'待审核批发商'**
  String get dashPendingWholesalers;

  /// No description provided for @dashTodayOrders.
  ///
  /// In zh, this message translates to:
  /// **'今天的订单'**
  String get dashTodayOrders;

  /// No description provided for @dashTodayTotal.
  ///
  /// In zh, this message translates to:
  /// **'今天总额'**
  String get dashTodayTotal;

  /// No description provided for @dashMonthGmv.
  ///
  /// In zh, this message translates to:
  /// **'这个月已送达货价'**
  String get dashMonthGmv;

  /// No description provided for @dashMonthCommission.
  ///
  /// In zh, this message translates to:
  /// **'这个月佣金'**
  String get dashMonthCommission;

  /// No description provided for @dashSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'订阅'**
  String get dashSubscriptions;

  /// No description provided for @subTrialing.
  ///
  /// In zh, this message translates to:
  /// **'试用中'**
  String get subTrialing;

  /// No description provided for @subActive.
  ///
  /// In zh, this message translates to:
  /// **'有效'**
  String get subActive;

  /// No description provided for @subPastDue.
  ///
  /// In zh, this message translates to:
  /// **'逾期'**
  String get subPastDue;

  /// No description provided for @subLapsed.
  ///
  /// In zh, this message translates to:
  /// **'已停'**
  String get subLapsed;

  /// No description provided for @subNone.
  ///
  /// In zh, this message translates to:
  /// **'没有订阅'**
  String get subNone;

  /// No description provided for @subFounding.
  ///
  /// In zh, this message translates to:
  /// **'创始价'**
  String get subFounding;

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

  /// No description provided for @sourceApp.
  ///
  /// In zh, this message translates to:
  /// **'App'**
  String get sourceApp;

  /// No description provided for @sourceVoice.
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get sourceVoice;

  /// No description provided for @sourceWhatsapp.
  ///
  /// In zh, this message translates to:
  /// **'WhatsApp'**
  String get sourceWhatsapp;

  /// No description provided for @sourceAdmin.
  ///
  /// In zh, this message translates to:
  /// **'客服'**
  String get sourceAdmin;

  /// No description provided for @sourceReorder.
  ///
  /// In zh, this message translates to:
  /// **'重复下单'**
  String get sourceReorder;

  /// No description provided for @channelApp.
  ///
  /// In zh, this message translates to:
  /// **'App'**
  String get channelApp;

  /// No description provided for @channelWhatsapp.
  ///
  /// In zh, this message translates to:
  /// **'WhatsApp'**
  String get channelWhatsapp;

  /// No description provided for @channelAdmin.
  ///
  /// In zh, this message translates to:
  /// **'客服'**
  String get channelAdmin;

  /// No description provided for @channelSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get channelSystem;

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
  /// **'捆'**
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

  /// No description provided for @stockIn.
  ///
  /// In zh, this message translates to:
  /// **'有货'**
  String get stockIn;

  /// No description provided for @stockLow.
  ///
  /// In zh, this message translates to:
  /// **'快卖完'**
  String get stockLow;

  /// No description provided for @stockOut.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get stockOut;

  /// No description provided for @productActive.
  ///
  /// In zh, this message translates to:
  /// **'上架'**
  String get productActive;

  /// No description provided for @productDraft.
  ///
  /// In zh, this message translates to:
  /// **'草稿'**
  String get productDraft;

  /// No description provided for @productArchived.
  ///
  /// In zh, this message translates to:
  /// **'下架'**
  String get productArchived;

  /// No description provided for @filterFrom.
  ///
  /// In zh, this message translates to:
  /// **'从'**
  String get filterFrom;

  /// No description provided for @filterTo.
  ///
  /// In zh, this message translates to:
  /// **'到'**
  String get filterTo;

  /// No description provided for @filterWholesaler.
  ///
  /// In zh, this message translates to:
  /// **'批发商'**
  String get filterWholesaler;

  /// No description provided for @filterShop.
  ///
  /// In zh, this message translates to:
  /// **'店铺'**
  String get filterShop;

  /// No description provided for @filterStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get filterStatus;

  /// No description provided for @filterSource.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get filterSource;

  /// No description provided for @filterUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'只看超过 {minutes} 分钟没确认'**
  String filterUnconfirmed(int minutes);

  /// No description provided for @filterClear.
  ///
  /// In zh, this message translates to:
  /// **'清除筛选'**
  String get filterClear;

  /// No description provided for @ordersTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 张'**
  String ordersTotal(int count);

  /// No description provided for @ordersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有符合的订单'**
  String get ordersEmpty;

  /// No description provided for @colOrderNo.
  ///
  /// In zh, this message translates to:
  /// **'单号'**
  String get colOrderNo;

  /// No description provided for @colCreated.
  ///
  /// In zh, this message translates to:
  /// **'下单时间'**
  String get colCreated;

  /// No description provided for @colShop.
  ///
  /// In zh, this message translates to:
  /// **'店铺'**
  String get colShop;

  /// No description provided for @colWholesaler.
  ///
  /// In zh, this message translates to:
  /// **'批发商'**
  String get colWholesaler;

  /// No description provided for @colStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get colStatus;

  /// No description provided for @colSource.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get colSource;

  /// No description provided for @colTotal.
  ///
  /// In zh, this message translates to:
  /// **'总额'**
  String get colTotal;

  /// No description provided for @pagePrev.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get pagePrev;

  /// No description provided for @pageNext.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get pageNext;

  /// No description provided for @pageRange.
  ///
  /// In zh, this message translates to:
  /// **'{from}–{to}，共 {total}'**
  String pageRange(int from, int to, int total);

  /// No description provided for @followupHint.
  ///
  /// In zh, this message translates to:
  /// **'待确认超过 {minutes} 分钟的订单。打电话给批发商跟进，然后记一句。'**
  String followupHint(int minutes);

  /// No description provided for @followupEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有要跟进的单'**
  String get followupEmpty;

  /// No description provided for @pendingFor.
  ///
  /// In zh, this message translates to:
  /// **'等了 {minutes} 分钟'**
  String pendingFor(int minutes);

  /// No description provided for @logFollowup.
  ///
  /// In zh, this message translates to:
  /// **'记下跟进'**
  String get logFollowup;

  /// No description provided for @followupNoteLabel.
  ///
  /// In zh, this message translates to:
  /// **'跟进内容（例如：批发商说 3 点前确认）'**
  String get followupNoteLabel;

  /// No description provided for @lastFollowup.
  ///
  /// In zh, this message translates to:
  /// **'上次跟进 {time}：{note}'**
  String lastFollowup(String time, String note);

  /// No description provided for @openOrder.
  ///
  /// In zh, this message translates to:
  /// **'打开订单'**
  String get openOrder;

  /// No description provided for @phoneOf.
  ///
  /// In zh, this message translates to:
  /// **'{name} 电话'**
  String phoneOf(String name);

  /// No description provided for @orderTitle.
  ///
  /// In zh, this message translates to:
  /// **'订单 {orderNo}'**
  String orderTitle(String orderNo);

  /// No description provided for @itemsTitle.
  ///
  /// In zh, this message translates to:
  /// **'明细'**
  String get itemsTitle;

  /// No description provided for @eventsTitle.
  ///
  /// In zh, this message translates to:
  /// **'进度'**
  String get eventsTitle;

  /// No description provided for @goodsSubtotal.
  ///
  /// In zh, this message translates to:
  /// **'货价'**
  String get goodsSubtotal;

  /// No description provided for @shippingFee.
  ///
  /// In zh, this message translates to:
  /// **'运费'**
  String get shippingFee;

  /// No description provided for @totalLabel.
  ///
  /// In zh, this message translates to:
  /// **'总额'**
  String get totalLabel;

  /// No description provided for @expectedDelivery.
  ///
  /// In zh, this message translates to:
  /// **'预计送达'**
  String get expectedDelivery;

  /// No description provided for @noteLabel.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get noteLabel;

  /// No description provided for @outOfStockTag.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get outOfStockTag;

  /// No description provided for @actConfirm.
  ///
  /// In zh, this message translates to:
  /// **'代批发商确认'**
  String get actConfirm;

  /// No description provided for @actConfirmHint.
  ///
  /// In zh, this message translates to:
  /// **'勾选缺货的商品（不算钱）。全部缺货就变成「缺货」。'**
  String get actConfirmHint;

  /// No description provided for @actOutOfStock.
  ///
  /// In zh, this message translates to:
  /// **'整单缺货'**
  String get actOutOfStock;

  /// No description provided for @actDelivering.
  ///
  /// In zh, this message translates to:
  /// **'出发送货'**
  String get actDelivering;

  /// No description provided for @actDelivered.
  ///
  /// In zh, this message translates to:
  /// **'已送达'**
  String get actDelivered;

  /// No description provided for @actCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消订单'**
  String get actCancel;

  /// No description provided for @cancelReasonLabel.
  ///
  /// In zh, this message translates to:
  /// **'取消原因（会给批发商看）'**
  String get cancelReasonLabel;

  /// No description provided for @statusUpdated.
  ///
  /// In zh, this message translates to:
  /// **'状态已更新：{status}'**
  String statusUpdated(String status);

  /// No description provided for @chooseShop.
  ///
  /// In zh, this message translates to:
  /// **'选店铺'**
  String get chooseShop;

  /// No description provided for @shopSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'店名或电话'**
  String get shopSearchHint;

  /// No description provided for @changeShop.
  ///
  /// In zh, this message translates to:
  /// **'换一家店'**
  String get changeShop;

  /// No description provided for @shopNoApp.
  ///
  /// In zh, this message translates to:
  /// **'没装 App'**
  String get shopNoApp;

  /// No description provided for @shopLocked.
  ///
  /// In zh, this message translates to:
  /// **'未付费：只能向免费开放的批发商下单'**
  String get shopLocked;

  /// No description provided for @offersSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜商品'**
  String get offersSearchHint;

  /// No description provided for @offersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有送到这家店的商品'**
  String get offersEmpty;

  /// No description provided for @priceHidden.
  ///
  /// In zh, this message translates to:
  /// **'看不到价钱'**
  String get priceHidden;

  /// No description provided for @perPiece.
  ///
  /// In zh, this message translates to:
  /// **'每个 {sen} 仙'**
  String perPiece(String sen);

  /// No description provided for @minOrderQty.
  ///
  /// In zh, this message translates to:
  /// **'起订 {qty}'**
  String minOrderQty(int qty);

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'加入'**
  String get add;

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

  /// No description provided for @clearCart.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clearCart;

  /// No description provided for @orderNoteLabel.
  ///
  /// In zh, this message translates to:
  /// **'备注（会给批发商看）'**
  String get orderNoteLabel;

  /// No description provided for @placeOrderButton.
  ///
  /// In zh, this message translates to:
  /// **'确认下单 {amount}'**
  String placeOrderButton(String amount);

  /// No description provided for @placedTitle.
  ///
  /// In zh, this message translates to:
  /// **'已下单'**
  String get placedTitle;

  /// No description provided for @placedBody.
  ///
  /// In zh, this message translates to:
  /// **'拆成 {count} 张订单，批发商会收到通知：'**
  String placedBody(int count);

  /// No description provided for @problemProductUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'商品下架了'**
  String get problemProductUnavailable;

  /// No description provided for @problemNotDelivering.
  ///
  /// In zh, this message translates to:
  /// **'不送这家店那区'**
  String get problemNotDelivering;

  /// No description provided for @problemWholesalerLocked.
  ///
  /// In zh, this message translates to:
  /// **'未付费：这家不在免费名单'**
  String get problemWholesalerLocked;

  /// No description provided for @problemOutOfStock.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get problemOutOfStock;

  /// No description provided for @problemBelowMinQty.
  ///
  /// In zh, this message translates to:
  /// **'未到起订量 {qty}'**
  String problemBelowMinQty(int qty);

  /// No description provided for @problemBelowMinOrder.
  ///
  /// In zh, this message translates to:
  /// **'还差 {amount} 才到最低消费'**
  String problemBelowMinOrder(String amount);

  /// No description provided for @wsStatusPending.
  ///
  /// In zh, this message translates to:
  /// **'待审核'**
  String get wsStatusPending;

  /// No description provided for @wsStatusActive.
  ///
  /// In zh, this message translates to:
  /// **'营业中'**
  String get wsStatusActive;

  /// No description provided for @wsStatusSuspended.
  ///
  /// In zh, this message translates to:
  /// **'已停权'**
  String get wsStatusSuspended;

  /// No description provided for @wsApprove.
  ///
  /// In zh, this message translates to:
  /// **'审核通过'**
  String get wsApprove;

  /// No description provided for @wsReject.
  ///
  /// In zh, this message translates to:
  /// **'不通过'**
  String get wsReject;

  /// No description provided for @wsSuspend.
  ///
  /// In zh, this message translates to:
  /// **'停权'**
  String get wsSuspend;

  /// No description provided for @wsReactivate.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get wsReactivate;

  /// No description provided for @wsNoteLabel.
  ///
  /// In zh, this message translates to:
  /// **'原因（记在操作记录）'**
  String get wsNoteLabel;

  /// No description provided for @wsCommission.
  ///
  /// In zh, this message translates to:
  /// **'佣金 {rate}'**
  String wsCommission(String rate);

  /// No description provided for @wsRateOverride.
  ///
  /// In zh, this message translates to:
  /// **'单独调整'**
  String get wsRateOverride;

  /// No description provided for @wsRateFounding.
  ///
  /// In zh, this message translates to:
  /// **'创始会员'**
  String get wsRateFounding;

  /// No description provided for @wsRateIndustry.
  ///
  /// In zh, this message translates to:
  /// **'行业默认'**
  String get wsRateIndustry;

  /// No description provided for @wsSetRate.
  ///
  /// In zh, this message translates to:
  /// **'改佣金比例'**
  String get wsSetRate;

  /// No description provided for @wsRateLabel.
  ///
  /// In zh, this message translates to:
  /// **'比例 %（空的 = 用默认）'**
  String get wsRateLabel;

  /// No description provided for @wsRateDefaults.
  ///
  /// In zh, this message translates to:
  /// **'行业默认 {industry}，创始会员 {founding}'**
  String wsRateDefaults(String industry, String founding);

  /// No description provided for @wsFounding.
  ///
  /// In zh, this message translates to:
  /// **'创始会员'**
  String get wsFounding;

  /// No description provided for @wsFoundingNo.
  ///
  /// In zh, this message translates to:
  /// **'创始 #{no}'**
  String wsFoundingNo(int no);

  /// No description provided for @wsWhatsappOptIn.
  ///
  /// In zh, this message translates to:
  /// **'同意 WhatsApp 收订单'**
  String get wsWhatsappOptIn;

  /// No description provided for @wsProducts.
  ///
  /// In zh, this message translates to:
  /// **'商品（{count}）'**
  String wsProducts(int count);

  /// No description provided for @wsPendingOrders.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张待确认'**
  String wsPendingOrders(int count);

  /// No description provided for @wsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有批发商'**
  String get wsEmpty;

  /// No description provided for @productsTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} 的商品'**
  String productsTitle(String name);

  /// No description provided for @productsHint.
  ///
  /// In zh, this message translates to:
  /// **'客服代批发商改：每个改动都记在操作记录。'**
  String get productsHint;

  /// No description provided for @productNew.
  ///
  /// In zh, this message translates to:
  /// **'新增商品'**
  String get productNew;

  /// No description provided for @productEdit.
  ///
  /// In zh, this message translates to:
  /// **'改商品'**
  String get productEdit;

  /// No description provided for @productName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get productName;

  /// No description provided for @productUnit.
  ///
  /// In zh, this message translates to:
  /// **'单位'**
  String get productUnit;

  /// No description provided for @productPackQty.
  ///
  /// In zh, this message translates to:
  /// **'一个单位有几个'**
  String get productPackQty;

  /// No description provided for @productPrice.
  ///
  /// In zh, this message translates to:
  /// **'价钱（RM）'**
  String get productPrice;

  /// No description provided for @productMinQty.
  ///
  /// In zh, this message translates to:
  /// **'起订量'**
  String get productMinQty;

  /// No description provided for @productStock.
  ///
  /// In zh, this message translates to:
  /// **'库存'**
  String get productStock;

  /// No description provided for @productStatus.
  ///
  /// In zh, this message translates to:
  /// **'上架状态'**
  String get productStatus;

  /// No description provided for @productsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有商品'**
  String get productsEmpty;

  /// No description provided for @productPerUnit.
  ///
  /// In zh, this message translates to:
  /// **'{price} / {unit}（{qty} 个）'**
  String productPerUnit(String price, String unit, int qty);

  /// No description provided for @subsFoundingOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看创始价'**
  String get subsFoundingOnly;

  /// No description provided for @colPlan.
  ///
  /// In zh, this message translates to:
  /// **'锁定月费'**
  String get colPlan;

  /// No description provided for @colTrialEnds.
  ///
  /// In zh, this message translates to:
  /// **'试用到'**
  String get colTrialEnds;

  /// No description provided for @colPeriodEnd.
  ///
  /// In zh, this message translates to:
  /// **'付到'**
  String get colPeriodEnd;

  /// No description provided for @colLastPayment.
  ///
  /// In zh, this message translates to:
  /// **'上次付款'**
  String get colLastPayment;

  /// No description provided for @subExtendTrial.
  ///
  /// In zh, this message translates to:
  /// **'延长试用'**
  String get subExtendTrial;

  /// No description provided for @subDaysLabel.
  ///
  /// In zh, this message translates to:
  /// **'延长几天（1–90）'**
  String get subDaysLabel;

  /// No description provided for @subMarkPaid.
  ///
  /// In zh, this message translates to:
  /// **'标记已付'**
  String get subMarkPaid;

  /// No description provided for @subMonthsLabel.
  ///
  /// In zh, this message translates to:
  /// **'几个月'**
  String get subMonthsLabel;

  /// No description provided for @subAmountLabel.
  ///
  /// In zh, this message translates to:
  /// **'金额 RM（空的 = 锁定月费 x 月数）'**
  String get subAmountLabel;

  /// No description provided for @subMethodLabel.
  ///
  /// In zh, this message translates to:
  /// **'付款方式'**
  String get subMethodLabel;

  /// No description provided for @subReferenceLabel.
  ///
  /// In zh, this message translates to:
  /// **'参考号（银行转账号码）'**
  String get subReferenceLabel;

  /// No description provided for @subLapsedNewPrice.
  ///
  /// In zh, this message translates to:
  /// **'已停：付款会新建一条订阅，按今天的月费锁定。'**
  String get subLapsedNewPrice;

  /// No description provided for @subCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消订阅'**
  String get subCancel;

  /// No description provided for @subCancelConfirm.
  ///
  /// In zh, this message translates to:
  /// **'取消后马上停。之后回来要按当时的价钱重新订阅。'**
  String get subCancelConfirm;

  /// No description provided for @subReasonLabel.
  ///
  /// In zh, this message translates to:
  /// **'原因'**
  String get subReasonLabel;

  /// No description provided for @subSetFounding.
  ///
  /// In zh, this message translates to:
  /// **'创始价设定'**
  String get subSetFounding;

  /// No description provided for @subLockedPriceLabel.
  ///
  /// In zh, this message translates to:
  /// **'锁定月费 RM（空的 = 不改）'**
  String get subLockedPriceLabel;

  /// No description provided for @subsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有订阅'**
  String get subsEmpty;

  /// No description provided for @methodFpx.
  ///
  /// In zh, this message translates to:
  /// **'FPX'**
  String get methodFpx;

  /// No description provided for @methodDuitnow.
  ///
  /// In zh, this message translates to:
  /// **'DuitNow'**
  String get methodDuitnow;

  /// No description provided for @methodEwallet.
  ///
  /// In zh, this message translates to:
  /// **'电子钱包'**
  String get methodEwallet;

  /// No description provided for @methodCard.
  ///
  /// In zh, this message translates to:
  /// **'信用卡'**
  String get methodCard;

  /// No description provided for @methodOther.
  ///
  /// In zh, this message translates to:
  /// **'现金 / 其他'**
  String get methodOther;

  /// No description provided for @commissionHint.
  ///
  /// In zh, this message translates to:
  /// **'每家批发商这个月已送达订单的货价（不含运费）和应付佣金。比例是送达时存下来的。'**
  String get commissionHint;

  /// No description provided for @prevMonth.
  ///
  /// In zh, this message translates to:
  /// **'上个月'**
  String get prevMonth;

  /// No description provided for @nextMonth.
  ///
  /// In zh, this message translates to:
  /// **'下个月'**
  String get nextMonth;

  /// No description provided for @colOrders.
  ///
  /// In zh, this message translates to:
  /// **'送达订单'**
  String get colOrders;

  /// No description provided for @colGmv.
  ///
  /// In zh, this message translates to:
  /// **'货价（不含运费）'**
  String get colGmv;

  /// No description provided for @colRate.
  ///
  /// In zh, this message translates to:
  /// **'比例'**
  String get colRate;

  /// No description provided for @colCommission.
  ///
  /// In zh, this message translates to:
  /// **'应付佣金'**
  String get colCommission;

  /// No description provided for @colInvoice.
  ///
  /// In zh, this message translates to:
  /// **'账单'**
  String get colInvoice;

  /// No description provided for @colBillingName.
  ///
  /// In zh, this message translates to:
  /// **'开账单名称'**
  String get colBillingName;

  /// No description provided for @colSsm.
  ///
  /// In zh, this message translates to:
  /// **'SSM 号码'**
  String get colSsm;

  /// No description provided for @colEmail.
  ///
  /// In zh, this message translates to:
  /// **'电邮'**
  String get colEmail;

  /// No description provided for @colPeriod.
  ///
  /// In zh, this message translates to:
  /// **'月份'**
  String get colPeriod;

  /// No description provided for @colInvoiceStatus.
  ///
  /// In zh, this message translates to:
  /// **'账单状态'**
  String get colInvoiceStatus;

  /// No description provided for @commissionTotal.
  ///
  /// In zh, this message translates to:
  /// **'合计'**
  String get commissionTotal;

  /// No description provided for @exportCsv.
  ///
  /// In zh, this message translates to:
  /// **'导出 CSV（全部）'**
  String get exportCsv;

  /// No description provided for @exportPdf.
  ///
  /// In zh, this message translates to:
  /// **'账单 PDF'**
  String get exportPdf;

  /// No description provided for @exported.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {name}'**
  String exported(String name);

  /// No description provided for @exportUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'只有网页版可以下载档案'**
  String get exportUnsupported;

  /// No description provided for @generateInvoices.
  ///
  /// In zh, this message translates to:
  /// **'生成草稿账单'**
  String get generateInvoices;

  /// No description provided for @invoicesGenerated.
  ///
  /// In zh, this message translates to:
  /// **'生成 / 更新了 {count} 张草稿账单'**
  String invoicesGenerated(int count);

  /// No description provided for @issueInvoice.
  ///
  /// In zh, this message translates to:
  /// **'发出账单'**
  String get issueInvoice;

  /// No description provided for @markInvoicePaid.
  ///
  /// In zh, this message translates to:
  /// **'标记已付'**
  String get markInvoicePaid;

  /// No description provided for @invoiceDraft.
  ///
  /// In zh, this message translates to:
  /// **'草稿'**
  String get invoiceDraft;

  /// No description provided for @invoiceIssued.
  ///
  /// In zh, this message translates to:
  /// **'已发出'**
  String get invoiceIssued;

  /// No description provided for @invoicePaid.
  ///
  /// In zh, this message translates to:
  /// **'已付'**
  String get invoicePaid;

  /// No description provided for @invoiceOverdue.
  ///
  /// In zh, this message translates to:
  /// **'逾期'**
  String get invoiceOverdue;

  /// No description provided for @invoiceVoid.
  ///
  /// In zh, this message translates to:
  /// **'作废'**
  String get invoiceVoid;

  /// No description provided for @invoiceNone.
  ///
  /// In zh, this message translates to:
  /// **'还没有账单'**
  String get invoiceNone;

  /// No description provided for @commissionEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个月还没有送达的订单'**
  String get commissionEmpty;

  /// No description provided for @pdfInvoiceTitle.
  ///
  /// In zh, this message translates to:
  /// **'佣金账单'**
  String get pdfInvoiceTitle;

  /// No description provided for @pdfBillTo.
  ///
  /// In zh, this message translates to:
  /// **'账单给'**
  String get pdfBillTo;

  /// No description provided for @pdfInvoiceNo.
  ///
  /// In zh, this message translates to:
  /// **'账单号码'**
  String get pdfInvoiceNo;

  /// No description provided for @pdfDraft.
  ///
  /// In zh, this message translates to:
  /// **'草稿（还没发出）'**
  String get pdfDraft;

  /// No description provided for @pdfDueDate.
  ///
  /// In zh, this message translates to:
  /// **'到期日'**
  String get pdfDueDate;

  /// No description provided for @pdfDelivered.
  ///
  /// In zh, this message translates to:
  /// **'送达日期'**
  String get pdfDelivered;

  /// No description provided for @pdfTotalDue.
  ///
  /// In zh, this message translates to:
  /// **'应付佣金合计'**
  String get pdfTotalDue;

  /// No description provided for @pdfNote.
  ///
  /// In zh, this message translates to:
  /// **'佣金只算已送达订单的货价，不含运费；缺货和取消的不算。'**
  String get pdfNote;

  /// No description provided for @pdfCompanyNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'（公司资料未设定）'**
  String get pdfCompanyNotConfigured;

  /// No description provided for @auditAdminOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看客服动作'**
  String get auditAdminOnly;

  /// No description provided for @auditActor.
  ///
  /// In zh, this message translates to:
  /// **'谁'**
  String get auditActor;

  /// No description provided for @auditActingFor.
  ///
  /// In zh, this message translates to:
  /// **'代谁'**
  String get auditActingFor;

  /// No description provided for @auditTable.
  ///
  /// In zh, this message translates to:
  /// **'资料'**
  String get auditTable;

  /// No description provided for @auditChanges.
  ///
  /// In zh, this message translates to:
  /// **'改了什么'**
  String get auditChanges;

  /// No description provided for @auditEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有记录'**
  String get auditEmpty;

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'再看多一些'**
  String get loadMore;

  /// No description provided for @auditActPlaceOrder.
  ///
  /// In zh, this message translates to:
  /// **'代下单'**
  String get auditActPlaceOrder;

  /// No description provided for @auditActSetCartItem.
  ///
  /// In zh, this message translates to:
  /// **'改购物车'**
  String get auditActSetCartItem;

  /// No description provided for @auditActClearCart.
  ///
  /// In zh, this message translates to:
  /// **'清空购物车'**
  String get auditActClearCart;

  /// No description provided for @auditActSetOrderStatus.
  ///
  /// In zh, this message translates to:
  /// **'改订单状态'**
  String get auditActSetOrderStatus;

  /// No description provided for @auditActConfirmOrder.
  ///
  /// In zh, this message translates to:
  /// **'代确认订单'**
  String get auditActConfirmOrder;

  /// No description provided for @auditActLogFollowup.
  ///
  /// In zh, this message translates to:
  /// **'跟进'**
  String get auditActLogFollowup;

  /// No description provided for @auditActCreateProduct.
  ///
  /// In zh, this message translates to:
  /// **'新增商品'**
  String get auditActCreateProduct;

  /// No description provided for @auditActUpdateProduct.
  ///
  /// In zh, this message translates to:
  /// **'改商品'**
  String get auditActUpdateProduct;

  /// No description provided for @auditActWholesalerStatus.
  ///
  /// In zh, this message translates to:
  /// **'审核 / 停权'**
  String get auditActWholesalerStatus;

  /// No description provided for @auditActCommissionRate.
  ///
  /// In zh, this message translates to:
  /// **'改佣金比例'**
  String get auditActCommissionRate;

  /// No description provided for @auditActWholesalerFounding.
  ///
  /// In zh, this message translates to:
  /// **'创始会员'**
  String get auditActWholesalerFounding;

  /// No description provided for @auditActWhatsappOptIn.
  ///
  /// In zh, this message translates to:
  /// **'WhatsApp 同意'**
  String get auditActWhatsappOptIn;

  /// No description provided for @auditActExtendTrial.
  ///
  /// In zh, this message translates to:
  /// **'延长试用'**
  String get auditActExtendTrial;

  /// No description provided for @auditActMarkPaid.
  ///
  /// In zh, this message translates to:
  /// **'标记月费已付'**
  String get auditActMarkPaid;

  /// No description provided for @auditActCancelSubscription.
  ///
  /// In zh, this message translates to:
  /// **'取消订阅'**
  String get auditActCancelSubscription;

  /// No description provided for @auditActSubscriptionFounding.
  ///
  /// In zh, this message translates to:
  /// **'创始价'**
  String get auditActSubscriptionFounding;

  /// No description provided for @auditActGenerateInvoices.
  ///
  /// In zh, this message translates to:
  /// **'生成账单'**
  String get auditActGenerateInvoices;

  /// No description provided for @auditActIssueInvoice.
  ///
  /// In zh, this message translates to:
  /// **'发出账单'**
  String get auditActIssueInvoice;

  /// No description provided for @auditActInvoicePaid.
  ///
  /// In zh, this message translates to:
  /// **'账单已付'**
  String get auditActInvoicePaid;

  /// No description provided for @auditActInsert.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get auditActInsert;

  /// No description provided for @auditActUpdate.
  ///
  /// In zh, this message translates to:
  /// **'修改'**
  String get auditActUpdate;

  /// No description provided for @auditActDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get auditActDelete;
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
