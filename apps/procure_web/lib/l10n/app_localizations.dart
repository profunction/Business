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
  /// **'新山批发 · 公司采购'**
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

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get saved;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'修改'**
  String get edit;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

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
  /// **'没有权限（你的角色不能做这个）'**
  String get errNotAllowed;

  /// No description provided for @errRoleMismatch.
  ///
  /// In zh, this message translates to:
  /// **'批发商的账号不能当公司成员'**
  String get errRoleMismatch;

  /// No description provided for @errCompanyNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到这家公司'**
  String get errCompanyNotFound;

  /// No description provided for @errCompanySuspended.
  ///
  /// In zh, this message translates to:
  /// **'公司已停权，请联络我们的客服'**
  String get errCompanySuspended;

  /// No description provided for @errPlanInactive.
  ///
  /// In zh, this message translates to:
  /// **'公司方案停了，请先付款'**
  String get errPlanInactive;

  /// No description provided for @errPlanFeature.
  ///
  /// In zh, this message translates to:
  /// **'你们的方案没有这个功能'**
  String get errPlanFeature;

  /// No description provided for @errPlanLimitSites.
  ///
  /// In zh, this message translates to:
  /// **'方案最多 {max} 个分店，请换方案'**
  String errPlanLimitSites(String max);

  /// No description provided for @errPlanLimitUsers.
  ///
  /// In zh, this message translates to:
  /// **'方案最多 {max} 个用户（成员 + 邀请），请换方案'**
  String errPlanLimitUsers(String max);

  /// No description provided for @errLastAdmin.
  ///
  /// In zh, this message translates to:
  /// **'公司至少要有一个管理员'**
  String get errLastAdmin;

  /// No description provided for @errSiteOpenDocuments.
  ///
  /// In zh, this message translates to:
  /// **'这个分店还有没完成的单，不能封存'**
  String get errSiteOpenDocuments;

  /// No description provided for @errNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到（可能已经被别人改了）'**
  String get errNotFound;

  /// No description provided for @errAlreadyMember.
  ///
  /// In zh, this message translates to:
  /// **'这个号码已经是成员了'**
  String get errAlreadyMember;

  /// No description provided for @errSsmRegistered.
  ///
  /// In zh, this message translates to:
  /// **'这个 SSM 号码已经注册过了'**
  String get errSsmRegistered;

  /// No description provided for @errInvalidZone.
  ///
  /// In zh, this message translates to:
  /// **'请选送货区'**
  String get errInvalidZone;

  /// No description provided for @errInvalidValue.
  ///
  /// In zh, this message translates to:
  /// **'资料不对，请检查一下'**
  String get errInvalidValue;

  /// No description provided for @errNothingDue.
  ///
  /// In zh, this message translates to:
  /// **'没有要付的'**
  String get errNothingDue;

  /// No description provided for @errPaymentNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'网上付款还没开通，请用银行转账（账单上有资料）'**
  String get errPaymentNotConfigured;

  /// No description provided for @errGateway.
  ///
  /// In zh, this message translates to:
  /// **'付款网关暂时用不了，请等一下再试'**
  String get errGateway;

  /// No description provided for @errTooManyPayments.
  ///
  /// In zh, this message translates to:
  /// **'开太多付款页了，请等一下'**
  String get errTooManyPayments;

  /// No description provided for @errUseRequisition.
  ///
  /// In zh, this message translates to:
  /// **'公司分店要开申请单才能下单'**
  String get errUseRequisition;

  /// No description provided for @errUnknown.
  ///
  /// In zh, this message translates to:
  /// **'出错了（{code}）'**
  String errUnknown(String code);

  /// No description provided for @loginTitle.
  ///
  /// In zh, this message translates to:
  /// **'公司采购登录'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用手机号和验证码登录。公司的成员、还没有公司的人都可以（登录后注册公司）。'**
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
  /// **'{seconds} 秒后可以重新发送'**
  String otpResendIn(int seconds);

  /// No description provided for @changePhone.
  ///
  /// In zh, this message translates to:
  /// **'换号码'**
  String get changePhone;

  /// No description provided for @loadingContext.
  ///
  /// In zh, this message translates to:
  /// **'正在读取资料…'**
  String get loadingContext;

  /// No description provided for @deniedTitle.
  ///
  /// In zh, this message translates to:
  /// **'这个账号是批发商'**
  String get deniedTitle;

  /// No description provided for @deniedBody.
  ///
  /// In zh, this message translates to:
  /// **'公司采购网页给公司的员工用。批发商请用手机 App 接单。'**
  String get deniedBody;

  /// No description provided for @regTitle.
  ///
  /// In zh, this message translates to:
  /// **'注册公司'**
  String get regTitle;

  /// No description provided for @regSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'你还不是任何公司的成员。注册公司（你会是管理员），或者请公司的管理员用你的手机号邀请你。'**
  String get regSubtitle;

  /// No description provided for @regAnotherSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'再注册一家公司（你会是管理员）。'**
  String get regAnotherSubtitle;

  /// No description provided for @regName.
  ///
  /// In zh, this message translates to:
  /// **'公司名字'**
  String get regName;

  /// No description provided for @regType.
  ///
  /// In zh, this message translates to:
  /// **'公司类型'**
  String get regType;

  /// No description provided for @regRegion.
  ///
  /// In zh, this message translates to:
  /// **'地区'**
  String get regRegion;

  /// No description provided for @regSsm.
  ///
  /// In zh, this message translates to:
  /// **'SSM 号码（可以不填）'**
  String get regSsm;

  /// No description provided for @regSsmHelp.
  ///
  /// In zh, this message translates to:
  /// **'一家公司只能注册一次，试用也只送一次'**
  String get regSsmHelp;

  /// No description provided for @regBillingEmail.
  ///
  /// In zh, this message translates to:
  /// **'账单电邮'**
  String get regBillingEmail;

  /// No description provided for @regFirstSite.
  ///
  /// In zh, this message translates to:
  /// **'第一个分店 / 工地'**
  String get regFirstSite;

  /// No description provided for @regFirstSiteHelp.
  ///
  /// In zh, this message translates to:
  /// **'货送到哪里（可以之后再加）'**
  String get regFirstSiteHelp;

  /// No description provided for @regNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填公司名字'**
  String get regNameRequired;

  /// No description provided for @regZoneRequired.
  ///
  /// In zh, this message translates to:
  /// **'请选分店的送货区'**
  String get regZoneRequired;

  /// No description provided for @regSubmit.
  ///
  /// In zh, this message translates to:
  /// **'注册公司'**
  String get regSubmit;

  /// No description provided for @regTrialNote.
  ///
  /// In zh, this message translates to:
  /// **'第一次注册送 30 天试用（Pro 的全部功能）。同一个手机号或 SSM 拿过试用的，要先付第一期。'**
  String get regTrialNote;

  /// No description provided for @registerAnother.
  ///
  /// In zh, this message translates to:
  /// **'注册另一家公司'**
  String get registerAnother;

  /// No description provided for @switchCompany.
  ///
  /// In zh, this message translates to:
  /// **'换公司'**
  String get switchCompany;

  /// No description provided for @navHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get navHome;

  /// No description provided for @navBrowse.
  ///
  /// In zh, this message translates to:
  /// **'商品比价'**
  String get navBrowse;

  /// No description provided for @navSites.
  ///
  /// In zh, this message translates to:
  /// **'分店'**
  String get navSites;

  /// No description provided for @navMembers.
  ///
  /// In zh, this message translates to:
  /// **'成员'**
  String get navMembers;

  /// No description provided for @navBilling.
  ///
  /// In zh, this message translates to:
  /// **'方案和付款'**
  String get navBilling;

  /// No description provided for @navInbox.
  ///
  /// In zh, this message translates to:
  /// **'收件箱'**
  String get navInbox;

  /// No description provided for @navCompany.
  ///
  /// In zh, this message translates to:
  /// **'公司资料'**
  String get navCompany;

  /// No description provided for @homeRoles.
  ///
  /// In zh, this message translates to:
  /// **'我的角色：{roles}'**
  String homeRoles(String roles);

  /// No description provided for @homeSuspended.
  ///
  /// In zh, this message translates to:
  /// **'公司已停权：不能改东西，分店也看不到价钱。请联络我们的客服。'**
  String get homeSuspended;

  /// No description provided for @homeTrial.
  ///
  /// In zh, this message translates to:
  /// **'试用中，到 {date}'**
  String homeTrial(String date);

  /// No description provided for @homeActive.
  ///
  /// In zh, this message translates to:
  /// **'{plan}，用到 {date}'**
  String homeActive(String plan, String date);

  /// No description provided for @homePastDue.
  ///
  /// In zh, this message translates to:
  /// **'账单逾期，宽限到 {date}'**
  String homePastDue(String date);

  /// No description provided for @homeLapsed.
  ///
  /// In zh, this message translates to:
  /// **'方案停了：分店看不到价钱，请先付款'**
  String get homeLapsed;

  /// No description provided for @homeManagePlan.
  ///
  /// In zh, this message translates to:
  /// **'看方案和账单'**
  String get homeManagePlan;

  /// No description provided for @homePlanManaged.
  ///
  /// In zh, this message translates to:
  /// **'方案由贵公司的管理员 / 财务管理'**
  String get homePlanManaged;

  /// No description provided for @homePendingApprovals.
  ///
  /// In zh, this message translates to:
  /// **'待我审批'**
  String get homePendingApprovals;

  /// No description provided for @homeComingSoon.
  ///
  /// In zh, this message translates to:
  /// **'申请单和审批即将推出'**
  String get homeComingSoon;

  /// No description provided for @homeOpenInvites.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个邀请还没接受'**
  String homeOpenInvites(int count);

  /// No description provided for @homeUnread.
  ///
  /// In zh, this message translates to:
  /// **'没看的通知'**
  String get homeUnread;

  /// No description provided for @homeQuickActions.
  ///
  /// In zh, this message translates to:
  /// **'常用'**
  String get homeQuickActions;

  /// No description provided for @homeMySites.
  ///
  /// In zh, this message translates to:
  /// **'我能管的分店'**
  String get homeMySites;

  /// No description provided for @browseHint.
  ///
  /// In zh, this message translates to:
  /// **'选一个分店：送货区和运费照那个分店。同一样东西几家放在一起，按「每个多少钱」排。'**
  String get browseHint;

  /// No description provided for @browseSite.
  ///
  /// In zh, this message translates to:
  /// **'分店'**
  String get browseSite;

  /// No description provided for @browseSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜商品或批发商'**
  String get browseSearch;

  /// No description provided for @browseNoSite.
  ///
  /// In zh, this message translates to:
  /// **'还没有分店：先加一个分店才能比价'**
  String get browseNoSite;

  /// No description provided for @browseEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有送到这个分店的商品'**
  String get browseEmpty;

  /// No description provided for @browsePricesHidden.
  ///
  /// In zh, this message translates to:
  /// **'公司方案停了：价钱看不到。请先付款。'**
  String get browsePricesHidden;

  /// No description provided for @browseCompareCount.
  ///
  /// In zh, this message translates to:
  /// **'{name}（{count} 家）'**
  String browseCompareCount(String name, int count);

  /// No description provided for @browsePack.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个 / {unit}'**
  String browsePack(String unit, int count);

  /// No description provided for @browsePriceHidden.
  ///
  /// In zh, this message translates to:
  /// **'看不到价钱'**
  String get browsePriceHidden;

  /// No description provided for @browsePerPiece.
  ///
  /// In zh, this message translates to:
  /// **'每个 {sen} 仙'**
  String browsePerPiece(String sen);

  /// No description provided for @browseMinQty.
  ///
  /// In zh, this message translates to:
  /// **'起订 {qty}'**
  String browseMinQty(int qty);

  /// No description provided for @browseShipping.
  ///
  /// In zh, this message translates to:
  /// **'运费 {fee}，{days} 天送到'**
  String browseShipping(String fee, int days);

  /// No description provided for @browseOutOfStock.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get browseOutOfStock;

  /// No description provided for @browseCheapest.
  ///
  /// In zh, this message translates to:
  /// **'最便宜'**
  String get browseCheapest;

  /// No description provided for @sitesHint.
  ///
  /// In zh, this message translates to:
  /// **'每个分店 / 工地有自己的送货区、地址和运费。'**
  String get sitesHint;

  /// No description provided for @sitesLimit.
  ///
  /// In zh, this message translates to:
  /// **'（{count} / {max} 个）'**
  String sitesLimit(int count, int max);

  /// No description provided for @sitesAdd.
  ///
  /// In zh, this message translates to:
  /// **'加分店'**
  String get sitesAdd;

  /// No description provided for @sitesEdit.
  ///
  /// In zh, this message translates to:
  /// **'改分店'**
  String get sitesEdit;

  /// No description provided for @sitesAdded.
  ///
  /// In zh, this message translates to:
  /// **'分店加好了'**
  String get sitesAdded;

  /// No description provided for @sitesArchive.
  ///
  /// In zh, this message translates to:
  /// **'封存'**
  String get sitesArchive;

  /// No description provided for @sitesArchived.
  ///
  /// In zh, this message translates to:
  /// **'分店封存了'**
  String get sitesArchived;

  /// No description provided for @sitesArchivedTag.
  ///
  /// In zh, this message translates to:
  /// **'已封存'**
  String get sitesArchivedTag;

  /// No description provided for @sitesArchiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'封存「{name}」？'**
  String sitesArchiveTitle(String name);

  /// No description provided for @sitesArchiveBody.
  ///
  /// In zh, this message translates to:
  /// **'封存后不能再用这个分店下单（以前的记录留着），也不算在方案的分店数里。'**
  String get sitesArchiveBody;

  /// No description provided for @sitesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'你还没有可以管的分店'**
  String get sitesEmpty;

  /// No description provided for @sitesEmptyAdmin.
  ///
  /// In zh, this message translates to:
  /// **'还没有分店，按「加分店」'**
  String get sitesEmptyAdmin;

  /// No description provided for @siteName.
  ///
  /// In zh, this message translates to:
  /// **'分店名字'**
  String get siteName;

  /// No description provided for @siteZone.
  ///
  /// In zh, this message translates to:
  /// **'送货区'**
  String get siteZone;

  /// No description provided for @siteAddress.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get siteAddress;

  /// No description provided for @siteContact.
  ///
  /// In zh, this message translates to:
  /// **'联络人'**
  String get siteContact;

  /// No description provided for @sitePhone.
  ///
  /// In zh, this message translates to:
  /// **'分店电话'**
  String get sitePhone;

  /// No description provided for @siteCode.
  ///
  /// In zh, this message translates to:
  /// **'分店代号（例如 KL01）'**
  String get siteCode;

  /// No description provided for @siteCostCenter.
  ///
  /// In zh, this message translates to:
  /// **'成本中心'**
  String get siteCostCenter;

  /// No description provided for @siteRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填分店名字、选送货区'**
  String get siteRequired;

  /// No description provided for @membersHint.
  ///
  /// In zh, this message translates to:
  /// **'角色决定能做什么；不是全部分店的人只能管选的分店。'**
  String get membersHint;

  /// No description provided for @membersLimit.
  ///
  /// In zh, this message translates to:
  /// **'（方案最多 {max} 个用户）'**
  String membersLimit(int max);

  /// No description provided for @membersTitle.
  ///
  /// In zh, this message translates to:
  /// **'成员'**
  String get membersTitle;

  /// No description provided for @membersInvite.
  ///
  /// In zh, this message translates to:
  /// **'邀请成员'**
  String get membersInvite;

  /// No description provided for @membersEdit.
  ///
  /// In zh, this message translates to:
  /// **'改 {name}'**
  String membersEdit(String name);

  /// No description provided for @membersInvited.
  ///
  /// In zh, this message translates to:
  /// **'邀请好了：这个号码登录后自动加入（已经有账号的已经加好了）'**
  String get membersInvited;

  /// No description provided for @membersRoles.
  ///
  /// In zh, this message translates to:
  /// **'角色（可以选几个）'**
  String get membersRoles;

  /// No description provided for @membersAllSites.
  ///
  /// In zh, this message translates to:
  /// **'全部分店'**
  String get membersAllSites;

  /// No description provided for @membersAllSitesForced.
  ///
  /// In zh, this message translates to:
  /// **'管理员、财务永远看全部分店'**
  String get membersAllSitesForced;

  /// No description provided for @membersActive.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get membersActive;

  /// No description provided for @membersInactive.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get membersInactive;

  /// No description provided for @membersRemove.
  ///
  /// In zh, this message translates to:
  /// **'拿掉'**
  String get membersRemove;

  /// No description provided for @membersRemoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'把 {name} 拿掉？'**
  String membersRemoveTitle(String name);

  /// No description provided for @membersRemoveBody.
  ///
  /// In zh, this message translates to:
  /// **'他之后不能再看这家公司。以前做的记录照样留着。'**
  String get membersRemoveBody;

  /// No description provided for @membersRemoved.
  ///
  /// In zh, this message translates to:
  /// **'拿掉了'**
  String get membersRemoved;

  /// No description provided for @membersInvites.
  ///
  /// In zh, this message translates to:
  /// **'还没接受的邀请'**
  String get membersInvites;

  /// No description provided for @membersNoInvites.
  ///
  /// In zh, this message translates to:
  /// **'没有'**
  String get membersNoInvites;

  /// No description provided for @membersInviteExpired.
  ///
  /// In zh, this message translates to:
  /// **'过期了'**
  String get membersInviteExpired;

  /// No description provided for @membersInviteUntil.
  ///
  /// In zh, this message translates to:
  /// **'{time} 前有效'**
  String membersInviteUntil(String time);

  /// No description provided for @membersCancelInvite.
  ///
  /// In zh, this message translates to:
  /// **'取消邀请'**
  String get membersCancelInvite;

  /// No description provided for @membersInviteCancelled.
  ///
  /// In zh, this message translates to:
  /// **'邀请取消了'**
  String get membersInviteCancelled;

  /// No description provided for @membersInviteHelp.
  ///
  /// In zh, this message translates to:
  /// **'邀请 14 天内有效。对方用这个手机号登录公司采购网页（或手机 App）就会自动加入。'**
  String get membersInviteHelp;

  /// No description provided for @membersSendInvite.
  ///
  /// In zh, this message translates to:
  /// **'发邀请'**
  String get membersSendInvite;

  /// No description provided for @membersRoleRequired.
  ///
  /// In zh, this message translates to:
  /// **'至少选一个角色'**
  String get membersRoleRequired;

  /// No description provided for @membersSiteRequired.
  ///
  /// In zh, this message translates to:
  /// **'选他能管的分店，或者开「全部分店」'**
  String get membersSiteRequired;

  /// No description provided for @roleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get roleAdmin;

  /// No description provided for @roleApprover.
  ///
  /// In zh, this message translates to:
  /// **'审批'**
  String get roleApprover;

  /// No description provided for @roleFinance.
  ///
  /// In zh, this message translates to:
  /// **'财务'**
  String get roleFinance;

  /// No description provided for @roleRequester.
  ///
  /// In zh, this message translates to:
  /// **'申请人'**
  String get roleRequester;

  /// No description provided for @roleAdminHelp.
  ///
  /// In zh, this message translates to:
  /// **'公司资料、分店、成员、方案；全部看得到'**
  String get roleAdminHelp;

  /// No description provided for @roleApproverHelp.
  ///
  /// In zh, this message translates to:
  /// **'审批自己分店的申请单'**
  String get roleApproverHelp;

  /// No description provided for @roleFinanceHelp.
  ///
  /// In zh, this message translates to:
  /// **'账单、付款、对账；全部看得到'**
  String get roleFinanceHelp;

  /// No description provided for @roleRequesterHelp.
  ///
  /// In zh, this message translates to:
  /// **'开申请单、收货（只限自己的分店）'**
  String get roleRequesterHelp;

  /// No description provided for @typeCorporate.
  ///
  /// In zh, this message translates to:
  /// **'公司'**
  String get typeCorporate;

  /// No description provided for @typeFactory.
  ///
  /// In zh, this message translates to:
  /// **'工厂'**
  String get typeFactory;

  /// No description provided for @typeHotel.
  ///
  /// In zh, this message translates to:
  /// **'酒店'**
  String get typeHotel;

  /// No description provided for @typeRestaurantChain.
  ///
  /// In zh, this message translates to:
  /// **'连锁餐厅'**
  String get typeRestaurantChain;

  /// No description provided for @typeGlc.
  ///
  /// In zh, this message translates to:
  /// **'GLC'**
  String get typeGlc;

  /// No description provided for @typeOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get typeOther;

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
  /// **'没有方案'**
  String get subNone;

  /// No description provided for @cycleMonthly.
  ///
  /// In zh, this message translates to:
  /// **'月付'**
  String get cycleMonthly;

  /// No description provided for @cycleAnnual.
  ///
  /// In zh, this message translates to:
  /// **'年付'**
  String get cycleAnnual;

  /// No description provided for @perMonth.
  ///
  /// In zh, this message translates to:
  /// **'/ 月'**
  String get perMonth;

  /// No description provided for @perYear.
  ///
  /// In zh, this message translates to:
  /// **'/ 年'**
  String get perYear;

  /// No description provided for @planTrial.
  ///
  /// In zh, this message translates to:
  /// **'试用'**
  String get planTrial;

  /// No description provided for @planStarter.
  ///
  /// In zh, this message translates to:
  /// **'入门版'**
  String get planStarter;

  /// No description provided for @planPro.
  ///
  /// In zh, this message translates to:
  /// **'专业版'**
  String get planPro;

  /// No description provided for @planEnterprise.
  ///
  /// In zh, this message translates to:
  /// **'企业版'**
  String get planEnterprise;

  /// No description provided for @featRequisitions.
  ///
  /// In zh, this message translates to:
  /// **'申请单和审批'**
  String get featRequisitions;

  /// No description provided for @featMultiTier.
  ///
  /// In zh, this message translates to:
  /// **'多层审批'**
  String get featMultiTier;

  /// No description provided for @featBudgets.
  ///
  /// In zh, this message translates to:
  /// **'预算'**
  String get featBudgets;

  /// No description provided for @featRfq.
  ///
  /// In zh, this message translates to:
  /// **'询价'**
  String get featRfq;

  /// No description provided for @featReverseAuction.
  ///
  /// In zh, this message translates to:
  /// **'反向竞价'**
  String get featReverseAuction;

  /// No description provided for @featAiInsights.
  ///
  /// In zh, this message translates to:
  /// **'AI 审批助手'**
  String get featAiInsights;

  /// No description provided for @featAiSpend.
  ///
  /// In zh, this message translates to:
  /// **'AI 开支分析'**
  String get featAiSpend;

  /// No description provided for @featStatements.
  ///
  /// In zh, this message translates to:
  /// **'月结单和对账'**
  String get featStatements;

  /// No description provided for @billingHint.
  ///
  /// In zh, this message translates to:
  /// **'价钱跟着账号锁定：一直续费就一直是这个价。换方案下一期生效。'**
  String get billingHint;

  /// No description provided for @billingCurrent.
  ///
  /// In zh, this message translates to:
  /// **'现在的方案'**
  String get billingCurrent;

  /// No description provided for @billingCustomPrice.
  ///
  /// In zh, this message translates to:
  /// **'自订价'**
  String get billingCustomPrice;

  /// No description provided for @billingUntil.
  ///
  /// In zh, this message translates to:
  /// **'用到'**
  String get billingUntil;

  /// No description provided for @billingLocked.
  ///
  /// In zh, this message translates to:
  /// **'锁定价'**
  String get billingLocked;

  /// No description provided for @billingLimits.
  ///
  /// In zh, this message translates to:
  /// **'上限'**
  String get billingLimits;

  /// No description provided for @billingLimitsValue.
  ///
  /// In zh, this message translates to:
  /// **'{sites} 个分店 · {users} 个用户'**
  String billingLimitsValue(String sites, String users);

  /// No description provided for @billingNext.
  ///
  /// In zh, this message translates to:
  /// **'下一期换成'**
  String get billingNext;

  /// No description provided for @billingNoAccess.
  ///
  /// In zh, this message translates to:
  /// **'现在不能用：分店看不到价钱。付清账单就恢复。'**
  String get billingNoAccess;

  /// No description provided for @billingPlans.
  ///
  /// In zh, this message translates to:
  /// **'方案'**
  String get billingPlans;

  /// No description provided for @billingQuote.
  ///
  /// In zh, this message translates to:
  /// **'报价（联系我们）'**
  String get billingQuote;

  /// No description provided for @billingContactUs.
  ///
  /// In zh, this message translates to:
  /// **'企业方案请联系我们，客服帮你设定'**
  String get billingContactUs;

  /// No description provided for @billingChoose.
  ///
  /// In zh, this message translates to:
  /// **'选这个'**
  String get billingChoose;

  /// No description provided for @billingChooseTitle.
  ///
  /// In zh, this message translates to:
  /// **'换成{plan}？'**
  String billingChooseTitle(String plan);

  /// No description provided for @billingChooseBody.
  ///
  /// In zh, this message translates to:
  /// **'下一期开始，{price} {per}（价钱照今天锁定）。'**
  String billingChooseBody(String price, String per);

  /// No description provided for @billingPlanChanged.
  ///
  /// In zh, this message translates to:
  /// **'方案换好了'**
  String get billingPlanChanged;

  /// No description provided for @billingCurrentTag.
  ///
  /// In zh, this message translates to:
  /// **'现在的'**
  String get billingCurrentTag;

  /// No description provided for @billingNextTag.
  ///
  /// In zh, this message translates to:
  /// **'下一期'**
  String get billingNextTag;

  /// No description provided for @billingInvoices.
  ///
  /// In zh, this message translates to:
  /// **'账单'**
  String get billingInvoices;

  /// No description provided for @billingNoInvoices.
  ///
  /// In zh, this message translates to:
  /// **'还没有账单'**
  String get billingNoInvoices;

  /// No description provided for @billingDue.
  ///
  /// In zh, this message translates to:
  /// **'{date} 到期'**
  String billingDue(String date);

  /// No description provided for @billingPaidAt.
  ///
  /// In zh, this message translates to:
  /// **'{time} 付了'**
  String billingPaidAt(String time);

  /// No description provided for @billingPay.
  ///
  /// In zh, this message translates to:
  /// **'付款'**
  String get billingPay;

  /// No description provided for @billingPayTitle.
  ///
  /// In zh, this message translates to:
  /// **'付账单 {no}'**
  String billingPayTitle(String no);

  /// No description provided for @billingPayAmount.
  ///
  /// In zh, this message translates to:
  /// **'金额 {amount}（服务器算的）'**
  String billingPayAmount(String amount);

  /// No description provided for @billingPayOpened.
  ///
  /// In zh, this message translates to:
  /// **'付款页在新分页打开了（FPX、DuitNow、卡）。付好了回到这里按下面的按钮。'**
  String get billingPayOpened;

  /// No description provided for @billingPayOpenThis.
  ///
  /// In zh, this message translates to:
  /// **'请打开这个付款页（FPX、DuitNow、卡）：'**
  String get billingPayOpenThis;

  /// No description provided for @billingPaidRefresh.
  ///
  /// In zh, this message translates to:
  /// **'我付好了，刷新'**
  String get billingPaidRefresh;

  /// No description provided for @billingBankNote.
  ///
  /// In zh, this message translates to:
  /// **'也可以银行转账（写账单号码），我们的客服收到后会标记已付。'**
  String get billingBankNote;

  /// No description provided for @billingPayments.
  ///
  /// In zh, this message translates to:
  /// **'付款记录'**
  String get billingPayments;

  /// No description provided for @billingNoPayments.
  ///
  /// In zh, this message translates to:
  /// **'还没有付款'**
  String get billingNoPayments;

  /// No description provided for @invIssued.
  ///
  /// In zh, this message translates to:
  /// **'待付'**
  String get invIssued;

  /// No description provided for @invOverdue.
  ///
  /// In zh, this message translates to:
  /// **'逾期'**
  String get invOverdue;

  /// No description provided for @invPaid.
  ///
  /// In zh, this message translates to:
  /// **'已付'**
  String get invPaid;

  /// No description provided for @invVoid.
  ///
  /// In zh, this message translates to:
  /// **'作废'**
  String get invVoid;

  /// No description provided for @payPending.
  ///
  /// In zh, this message translates to:
  /// **'等付款'**
  String get payPending;

  /// No description provided for @payPaid.
  ///
  /// In zh, this message translates to:
  /// **'已付'**
  String get payPaid;

  /// No description provided for @payFailed.
  ///
  /// In zh, this message translates to:
  /// **'没付成'**
  String get payFailed;

  /// No description provided for @payRefunded.
  ///
  /// In zh, this message translates to:
  /// **'已退款'**
  String get payRefunded;

  /// No description provided for @inboxHint.
  ///
  /// In zh, this message translates to:
  /// **'给你的通知（手机推送有没有收到都在这里）'**
  String get inboxHint;

  /// No description provided for @inboxEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有通知'**
  String get inboxEmpty;

  /// No description provided for @inboxMarkAll.
  ///
  /// In zh, this message translates to:
  /// **'全部标已读'**
  String get inboxMarkAll;

  /// No description provided for @inboxAllRead.
  ///
  /// In zh, this message translates to:
  /// **'全部标已读了'**
  String get inboxAllRead;

  /// No description provided for @inboxUnread.
  ///
  /// In zh, this message translates to:
  /// **'没看'**
  String get inboxUnread;

  /// No description provided for @inboxGeneric.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get inboxGeneric;

  /// No description provided for @inboxInvoiceIssued.
  ///
  /// In zh, this message translates to:
  /// **'方案账单 {no}'**
  String inboxInvoiceIssued(String no);

  /// No description provided for @inboxInvoiceIssuedBody.
  ///
  /// In zh, this message translates to:
  /// **'金额 {amount}，{date} 到期'**
  String inboxInvoiceIssuedBody(String amount, String date);

  /// No description provided for @inboxInvoiceOverdue.
  ///
  /// In zh, this message translates to:
  /// **'方案账单 {no} 逾期了'**
  String inboxInvoiceOverdue(String no);

  /// No description provided for @inboxInvoiceOverdueBody.
  ///
  /// In zh, this message translates to:
  /// **'金额 {amount}，宽限到 {date}'**
  String inboxInvoiceOverdueBody(String amount, String date);

  /// No description provided for @inboxTrialEnding.
  ///
  /// In zh, this message translates to:
  /// **'试用快结束了'**
  String get inboxTrialEnding;

  /// No description provided for @inboxTrialEndingBody.
  ///
  /// In zh, this message translates to:
  /// **'{date} 结束，请选方案'**
  String inboxTrialEndingBody(String date);

  /// No description provided for @inboxTrialEndingChosen.
  ///
  /// In zh, this message translates to:
  /// **'{date} 结束，之后照选的方案继续'**
  String inboxTrialEndingChosen(String date);

  /// No description provided for @inboxPaid.
  ///
  /// In zh, this message translates to:
  /// **'收到付款 {amount}'**
  String inboxPaid(String amount);

  /// No description provided for @inboxPaidBody.
  ///
  /// In zh, this message translates to:
  /// **'账单 {no} 已付，谢谢！'**
  String inboxPaidBody(String no);

  /// No description provided for @companyHint.
  ///
  /// In zh, this message translates to:
  /// **'开发票、e-Invoice 用的资料。'**
  String get companyHint;

  /// No description provided for @companyReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'只有管理员可以改。'**
  String get companyReadOnly;

  /// No description provided for @companyLegalName.
  ///
  /// In zh, this message translates to:
  /// **'公司全名（SSM 上的）'**
  String get companyLegalName;

  /// No description provided for @companyTin.
  ///
  /// In zh, this message translates to:
  /// **'报税号（TIN）'**
  String get companyTin;

  /// No description provided for @companySst.
  ///
  /// In zh, this message translates to:
  /// **'SST 号码'**
  String get companySst;

  /// No description provided for @companyBillingContact.
  ///
  /// In zh, this message translates to:
  /// **'账单联络人'**
  String get companyBillingContact;

  /// No description provided for @companyBillingAddress.
  ///
  /// In zh, this message translates to:
  /// **'账单地址'**
  String get companyBillingAddress;

  /// No description provided for @companyPhone.
  ///
  /// In zh, this message translates to:
  /// **'公司电话'**
  String get companyPhone;

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
