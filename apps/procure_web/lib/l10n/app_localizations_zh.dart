// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class L10nZh extends L10n {
  L10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '新山批发 · 公司采购';

  @override
  String get language => '语言';

  @override
  String get signOut => '登出';

  @override
  String get retry => '再试一次';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get saved => '已保存';

  @override
  String get confirm => '确定';

  @override
  String get edit => '修改';

  @override
  String get back => '返回';

  @override
  String copied(String text) {
    return '已复制：$text';
  }

  @override
  String get demoBanner => '示范模式：资料是样本，按了不会真的改服务器';

  @override
  String get errNetwork => '连不上服务器，请检查网络';

  @override
  String get errAuth => '验证码不对，或者登录过期了';

  @override
  String get errNotAllowed => '没有权限（你的角色不能做这个）';

  @override
  String get errRoleMismatch => '批发商的账号不能当公司成员';

  @override
  String get errCompanyNotFound => '找不到这家公司';

  @override
  String get errCompanySuspended => '公司已停权，请联络我们的客服';

  @override
  String get errPlanInactive => '公司方案停了，请先付款';

  @override
  String get errPlanFeature => '你们的方案没有这个功能';

  @override
  String errPlanLimitSites(String max) {
    return '方案最多 $max 个分店，请换方案';
  }

  @override
  String errPlanLimitUsers(String max) {
    return '方案最多 $max 个用户（成员 + 邀请），请换方案';
  }

  @override
  String get errLastAdmin => '公司至少要有一个管理员';

  @override
  String get errSiteOpenDocuments => '这个分店还有没完成的单，不能封存';

  @override
  String get errNotFound => '找不到（可能已经被别人改了）';

  @override
  String get errAlreadyMember => '这个号码已经是成员了';

  @override
  String get errSsmRegistered => '这个 SSM 号码已经注册过了';

  @override
  String get errInvalidZone => '请选送货区';

  @override
  String get errInvalidValue => '资料不对，请检查一下';

  @override
  String get errNothingDue => '没有要付的';

  @override
  String get errPaymentNotConfigured => '网上付款还没开通，请用银行转账（账单上有资料）';

  @override
  String get errGateway => '付款网关暂时用不了，请等一下再试';

  @override
  String get errTooManyPayments => '开太多付款页了，请等一下';

  @override
  String get errUseRequisition => '公司分店要开申请单才能下单';

  @override
  String errUnknown(String code) {
    return '出错了（$code）';
  }

  @override
  String get loginTitle => '公司采购登录';

  @override
  String get loginSubtitle => '用手机号和验证码登录。公司的成员、还没有公司的人都可以（登录后注册公司）。';

  @override
  String get phoneLabel => '手机号';

  @override
  String get phoneInvalid => '请输入马来西亚手机号，例如 012-345 6789';

  @override
  String get sendCode => '发验证码';

  @override
  String get otpTitle => '输入验证码';

  @override
  String otpSentTo(String phone) {
    return '验证码已发到 $phone';
  }

  @override
  String get otpLogin => '登录';

  @override
  String get otpResend => '重新发送';

  @override
  String otpResendIn(int seconds) {
    return '$seconds 秒后可以重新发送';
  }

  @override
  String get changePhone => '换号码';

  @override
  String get loadingContext => '正在读取资料…';

  @override
  String get deniedTitle => '这个账号是批发商';

  @override
  String get deniedBody => '公司采购网页给公司的员工用。批发商请用手机 App 接单。';

  @override
  String get regTitle => '注册公司';

  @override
  String get regSubtitle => '你还不是任何公司的成员。注册公司（你会是管理员），或者请公司的管理员用你的手机号邀请你。';

  @override
  String get regAnotherSubtitle => '再注册一家公司（你会是管理员）。';

  @override
  String get regName => '公司名字';

  @override
  String get regType => '公司类型';

  @override
  String get regRegion => '地区';

  @override
  String get regSsm => 'SSM 号码（可以不填）';

  @override
  String get regSsmHelp => '一家公司只能注册一次，试用也只送一次';

  @override
  String get regBillingEmail => '账单电邮';

  @override
  String get regFirstSite => '第一个分店 / 工地';

  @override
  String get regFirstSiteHelp => '货送到哪里（可以之后再加）';

  @override
  String get regNameRequired => '请填公司名字';

  @override
  String get regZoneRequired => '请选分店的送货区';

  @override
  String get regSubmit => '注册公司';

  @override
  String get regTrialNote => '第一次注册送 30 天试用（Pro 的全部功能）。同一个手机号或 SSM 拿过试用的，要先付第一期。';

  @override
  String get registerAnother => '注册另一家公司';

  @override
  String get switchCompany => '换公司';

  @override
  String get navHome => '首页';

  @override
  String get navBrowse => '商品比价';

  @override
  String get navSites => '分店';

  @override
  String get navMembers => '成员';

  @override
  String get navBilling => '方案和付款';

  @override
  String get navInbox => '收件箱';

  @override
  String get navCompany => '公司资料';

  @override
  String homeRoles(String roles) {
    return '我的角色：$roles';
  }

  @override
  String get homeSuspended => '公司已停权：不能改东西，分店也看不到价钱。请联络我们的客服。';

  @override
  String homeTrial(String date) {
    return '试用中，到 $date';
  }

  @override
  String homeActive(String plan, String date) {
    return '$plan，用到 $date';
  }

  @override
  String homePastDue(String date) {
    return '账单逾期，宽限到 $date';
  }

  @override
  String get homeLapsed => '方案停了：分店看不到价钱，请先付款';

  @override
  String get homeManagePlan => '看方案和账单';

  @override
  String get homePlanManaged => '方案由贵公司的管理员 / 财务管理';

  @override
  String get homePendingApprovals => '待我审批';

  @override
  String get homeComingSoon => '申请单和审批即将推出';

  @override
  String homeOpenInvites(int count) {
    return '$count 个邀请还没接受';
  }

  @override
  String get homeUnread => '没看的通知';

  @override
  String get homeQuickActions => '常用';

  @override
  String get homeMySites => '我能管的分店';

  @override
  String get browseHint => '选一个分店：送货区和运费照那个分店。同一样东西几家放在一起，按「每个多少钱」排。';

  @override
  String get browseSite => '分店';

  @override
  String get browseSearch => '搜商品或批发商';

  @override
  String get browseNoSite => '还没有分店：先加一个分店才能比价';

  @override
  String get browseEmpty => '没有送到这个分店的商品';

  @override
  String get browsePricesHidden => '公司方案停了：价钱看不到。请先付款。';

  @override
  String browseCompareCount(String name, int count) {
    return '$name（$count 家）';
  }

  @override
  String browsePack(String unit, int count) {
    return '$count 个 / $unit';
  }

  @override
  String get browsePriceHidden => '看不到价钱';

  @override
  String browsePerPiece(String sen) {
    return '每个 $sen 仙';
  }

  @override
  String browseMinQty(int qty) {
    return '起订 $qty';
  }

  @override
  String browseShipping(String fee, int days) {
    return '运费 $fee，$days 天送到';
  }

  @override
  String get browseOutOfStock => '缺货';

  @override
  String get browseCheapest => '最便宜';

  @override
  String get sitesHint => '每个分店 / 工地有自己的送货区、地址和运费。';

  @override
  String sitesLimit(int count, int max) {
    return '（$count / $max 个）';
  }

  @override
  String get sitesAdd => '加分店';

  @override
  String get sitesEdit => '改分店';

  @override
  String get sitesAdded => '分店加好了';

  @override
  String get sitesArchive => '封存';

  @override
  String get sitesArchived => '分店封存了';

  @override
  String get sitesArchivedTag => '已封存';

  @override
  String sitesArchiveTitle(String name) {
    return '封存「$name」？';
  }

  @override
  String get sitesArchiveBody => '封存后不能再用这个分店下单（以前的记录留着），也不算在方案的分店数里。';

  @override
  String get sitesEmpty => '你还没有可以管的分店';

  @override
  String get sitesEmptyAdmin => '还没有分店，按「加分店」';

  @override
  String get siteName => '分店名字';

  @override
  String get siteZone => '送货区';

  @override
  String get siteAddress => '地址';

  @override
  String get siteContact => '联络人';

  @override
  String get sitePhone => '分店电话';

  @override
  String get siteCode => '分店代号（例如 KL01）';

  @override
  String get siteCostCenter => '成本中心';

  @override
  String get siteRequired => '请填分店名字、选送货区';

  @override
  String get membersHint => '角色决定能做什么；不是全部分店的人只能管选的分店。';

  @override
  String membersLimit(int max) {
    return '（方案最多 $max 个用户）';
  }

  @override
  String get membersTitle => '成员';

  @override
  String get membersInvite => '邀请成员';

  @override
  String membersEdit(String name) {
    return '改 $name';
  }

  @override
  String get membersInvited => '邀请好了：这个号码登录后自动加入（已经有账号的已经加好了）';

  @override
  String get membersRoles => '角色（可以选几个）';

  @override
  String get membersAllSites => '全部分店';

  @override
  String get membersAllSitesForced => '管理员、财务永远看全部分店';

  @override
  String get membersActive => '启用';

  @override
  String get membersInactive => '停用';

  @override
  String get membersRemove => '拿掉';

  @override
  String membersRemoveTitle(String name) {
    return '把 $name 拿掉？';
  }

  @override
  String get membersRemoveBody => '他之后不能再看这家公司。以前做的记录照样留着。';

  @override
  String get membersRemoved => '拿掉了';

  @override
  String get membersInvites => '还没接受的邀请';

  @override
  String get membersNoInvites => '没有';

  @override
  String get membersInviteExpired => '过期了';

  @override
  String membersInviteUntil(String time) {
    return '$time 前有效';
  }

  @override
  String get membersCancelInvite => '取消邀请';

  @override
  String get membersInviteCancelled => '邀请取消了';

  @override
  String get membersInviteHelp => '邀请 14 天内有效。对方用这个手机号登录公司采购网页（或手机 App）就会自动加入。';

  @override
  String get membersSendInvite => '发邀请';

  @override
  String get membersRoleRequired => '至少选一个角色';

  @override
  String get membersSiteRequired => '选他能管的分店，或者开「全部分店」';

  @override
  String get roleAdmin => '管理员';

  @override
  String get roleApprover => '审批';

  @override
  String get roleFinance => '财务';

  @override
  String get roleRequester => '申请人';

  @override
  String get roleAdminHelp => '公司资料、分店、成员、方案；全部看得到';

  @override
  String get roleApproverHelp => '审批自己分店的申请单';

  @override
  String get roleFinanceHelp => '账单、付款、对账；全部看得到';

  @override
  String get roleRequesterHelp => '开申请单、收货（只限自己的分店）';

  @override
  String get typeCorporate => '公司';

  @override
  String get typeFactory => '工厂';

  @override
  String get typeHotel => '酒店';

  @override
  String get typeRestaurantChain => '连锁餐厅';

  @override
  String get typeGlc => 'GLC';

  @override
  String get typeOther => '其他';

  @override
  String get subTrialing => '试用中';

  @override
  String get subActive => '有效';

  @override
  String get subPastDue => '逾期';

  @override
  String get subLapsed => '已停';

  @override
  String get subNone => '没有方案';

  @override
  String get cycleMonthly => '月付';

  @override
  String get cycleAnnual => '年付';

  @override
  String get perMonth => '/ 月';

  @override
  String get perYear => '/ 年';

  @override
  String get planTrial => '试用';

  @override
  String get planStarter => '入门版';

  @override
  String get planPro => '专业版';

  @override
  String get planEnterprise => '企业版';

  @override
  String get featRequisitions => '申请单和审批';

  @override
  String get featMultiTier => '多层审批';

  @override
  String get featBudgets => '预算';

  @override
  String get featRfq => '询价';

  @override
  String get featReverseAuction => '反向竞价';

  @override
  String get featAiInsights => 'AI 审批助手';

  @override
  String get featAiSpend => 'AI 开支分析';

  @override
  String get featStatements => '月结单和对账';

  @override
  String get billingHint => '价钱跟着账号锁定：一直续费就一直是这个价。换方案下一期生效。';

  @override
  String get billingCurrent => '现在的方案';

  @override
  String get billingCustomPrice => '自订价';

  @override
  String get billingUntil => '用到';

  @override
  String get billingLocked => '锁定价';

  @override
  String get billingLimits => '上限';

  @override
  String billingLimitsValue(String sites, String users) {
    return '$sites 个分店 · $users 个用户';
  }

  @override
  String get billingNext => '下一期换成';

  @override
  String get billingNoAccess => '现在不能用：分店看不到价钱。付清账单就恢复。';

  @override
  String get billingPlans => '方案';

  @override
  String get billingQuote => '报价（联系我们）';

  @override
  String get billingContactUs => '企业方案请联系我们，客服帮你设定';

  @override
  String get billingChoose => '选这个';

  @override
  String billingChooseTitle(String plan) {
    return '换成$plan？';
  }

  @override
  String billingChooseBody(String price, String per) {
    return '下一期开始，$price $per（价钱照今天锁定）。';
  }

  @override
  String get billingPlanChanged => '方案换好了';

  @override
  String get billingCurrentTag => '现在的';

  @override
  String get billingNextTag => '下一期';

  @override
  String get billingInvoices => '账单';

  @override
  String get billingNoInvoices => '还没有账单';

  @override
  String billingDue(String date) {
    return '$date 到期';
  }

  @override
  String billingPaidAt(String time) {
    return '$time 付了';
  }

  @override
  String get billingPay => '付款';

  @override
  String billingPayTitle(String no) {
    return '付账单 $no';
  }

  @override
  String billingPayAmount(String amount) {
    return '金额 $amount（服务器算的）';
  }

  @override
  String get billingPayOpened => '付款页在新分页打开了（FPX、DuitNow、卡）。付好了回到这里按下面的按钮。';

  @override
  String get billingPayOpenThis => '请打开这个付款页（FPX、DuitNow、卡）：';

  @override
  String get billingPaidRefresh => '我付好了，刷新';

  @override
  String get billingBankNote => '也可以银行转账（写账单号码），我们的客服收到后会标记已付。';

  @override
  String get billingPayments => '付款记录';

  @override
  String get billingNoPayments => '还没有付款';

  @override
  String get invIssued => '待付';

  @override
  String get invOverdue => '逾期';

  @override
  String get invPaid => '已付';

  @override
  String get invVoid => '作废';

  @override
  String get payPending => '等付款';

  @override
  String get payPaid => '已付';

  @override
  String get payFailed => '没付成';

  @override
  String get payRefunded => '已退款';

  @override
  String get inboxHint => '给你的通知（手机推送有没有收到都在这里）';

  @override
  String get inboxEmpty => '没有通知';

  @override
  String get inboxMarkAll => '全部标已读';

  @override
  String get inboxAllRead => '全部标已读了';

  @override
  String get inboxUnread => '没看';

  @override
  String get inboxGeneric => '通知';

  @override
  String inboxInvoiceIssued(String no) {
    return '方案账单 $no';
  }

  @override
  String inboxInvoiceIssuedBody(String amount, String date) {
    return '金额 $amount，$date 到期';
  }

  @override
  String inboxInvoiceOverdue(String no) {
    return '方案账单 $no 逾期了';
  }

  @override
  String inboxInvoiceOverdueBody(String amount, String date) {
    return '金额 $amount，宽限到 $date';
  }

  @override
  String get inboxTrialEnding => '试用快结束了';

  @override
  String inboxTrialEndingBody(String date) {
    return '$date 结束，请选方案';
  }

  @override
  String inboxTrialEndingChosen(String date) {
    return '$date 结束，之后照选的方案继续';
  }

  @override
  String inboxPaid(String amount) {
    return '收到付款 $amount';
  }

  @override
  String inboxPaidBody(String no) {
    return '账单 $no 已付，谢谢！';
  }

  @override
  String get companyHint => '开发票、e-Invoice 用的资料。';

  @override
  String get companyReadOnly => '只有管理员可以改。';

  @override
  String get companyLegalName => '公司全名（SSM 上的）';

  @override
  String get companyTin => '报税号（TIN）';

  @override
  String get companySst => 'SST 号码';

  @override
  String get companyBillingContact => '账单联络人';

  @override
  String get companyBillingAddress => '账单地址';

  @override
  String get companyPhone => '公司电话';

  @override
  String get unitCarton => '箱';

  @override
  String get unitPack => '包';

  @override
  String get unitBag => '袋';

  @override
  String get unitRoll => '卷';

  @override
  String get unitBundle => '捆';

  @override
  String get unitBox => '盒';

  @override
  String get unitPiece => '个';

  @override
  String get unitDozen => '打';

  @override
  String get unitKg => '公斤';
}
