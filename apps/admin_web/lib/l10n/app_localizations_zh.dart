// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class L10nZh extends L10n {
  L10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '新山批发 · 客服后台';

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
  String get close => '关闭';

  @override
  String get confirm => '确定';

  @override
  String get all => '全部';

  @override
  String get searchHint => '搜索';

  @override
  String get saved => '已保存';

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
  String get errNotAllowed => '没有权限（只有客服可以）';

  @override
  String get errPriceChanged => '价钱刚好改了，请看一下新的总额再下单';

  @override
  String get errCartHasProblems => '购物车有问题，请看每一行的提示';

  @override
  String get errCartEmpty => '购物车是空的';

  @override
  String get errInvalidTransition => '订单现在的状态不能这样改';

  @override
  String get errInvalidRate => '比例要在 0% 到 20% 之间，最多两位小数';

  @override
  String get errInvalidDays => '天数要在 1 到 90 之间';

  @override
  String get errInvalidMonths => '月数要在 1 到 24 之间';

  @override
  String get errInvalidAmount => '金额不对';

  @override
  String get errDuplicateReference => '这个参考号已经记过了';

  @override
  String get errSubscriptionState => '这个订阅现在不能这样改';

  @override
  String get errSubscriptionOpen => '这家店已经有新的订阅';

  @override
  String get errInvoiceState => '账单现在的状态不能这样改';

  @override
  String get errFoundingFull => '创始会员名额满了';

  @override
  String get errInvalidProduct => '商品资料不对：名称、单位、价钱、数量都要填对';

  @override
  String get errInvalidNote => '请写跟进内容';

  @override
  String get errNoPricingPlan => '系统还没设定月费（找技术）';

  @override
  String errUnknown(String code) {
    return '出错了（$code）';
  }

  @override
  String get loginTitle => '客服登录';

  @override
  String get loginSubtitle => '用手机号和验证码登录。只有客服账号可以进来。';

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
    return '$seconds 秒后可以重发';
  }

  @override
  String get changePhone => '换号码';

  @override
  String get deniedTitle => '这个账号不是客服';

  @override
  String get deniedBody => '客服后台只给客服用。请用客服的手机号登录；老板和批发商请用手机 App。';

  @override
  String get loadingContext => '正在读取资料…';

  @override
  String get navDashboard => '首页';

  @override
  String get navOrders => '全部订单';

  @override
  String get navFollowup => '待跟进';

  @override
  String get navPlaceOrder => '代下单';

  @override
  String get navWholesalers => '批发商';

  @override
  String get navSubscriptions => '订阅';

  @override
  String get navCommission => '佣金报表';

  @override
  String get navAudit => '操作记录';

  @override
  String dashUnconfirmed(int minutes) {
    return '超过 $minutes 分钟没确认';
  }

  @override
  String get dashPendingOrders => '待确认订单';

  @override
  String get dashPendingWholesalers => '待审核批发商';

  @override
  String get dashTodayOrders => '今天的订单';

  @override
  String get dashTodayTotal => '今天总额';

  @override
  String get dashMonthGmv => '这个月已送达货价';

  @override
  String get dashMonthCommission => '这个月佣金';

  @override
  String get dashSubscriptions => '订阅';

  @override
  String get subTrialing => '试用中';

  @override
  String get subActive => '有效';

  @override
  String get subPastDue => '逾期';

  @override
  String get subLapsed => '已停';

  @override
  String get subNone => '没有订阅';

  @override
  String get subFounding => '创始价';

  @override
  String get statusPending => '待确认';

  @override
  String get statusConfirmed => '已确认';

  @override
  String get statusOutOfStock => '缺货';

  @override
  String get statusDelivering => '送货中';

  @override
  String get statusDelivered => '已送达';

  @override
  String get statusCancelled => '已取消';

  @override
  String get sourceApp => 'App';

  @override
  String get sourceVoice => '语音';

  @override
  String get sourceWhatsapp => 'WhatsApp';

  @override
  String get sourceAdmin => '客服';

  @override
  String get sourceReorder => '重复下单';

  @override
  String get channelApp => 'App';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get channelAdmin => '客服';

  @override
  String get channelSystem => '系统';

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

  @override
  String get stockIn => '有货';

  @override
  String get stockLow => '快卖完';

  @override
  String get stockOut => '缺货';

  @override
  String get productActive => '上架';

  @override
  String get productDraft => '草稿';

  @override
  String get productArchived => '下架';

  @override
  String get filterFrom => '从';

  @override
  String get filterTo => '到';

  @override
  String get filterWholesaler => '批发商';

  @override
  String get filterShop => '店铺';

  @override
  String get filterStatus => '状态';

  @override
  String get filterSource => '来源';

  @override
  String filterUnconfirmed(int minutes) {
    return '只看超过 $minutes 分钟没确认';
  }

  @override
  String get filterClear => '清除筛选';

  @override
  String ordersTotal(int count) {
    return '共 $count 张';
  }

  @override
  String get ordersEmpty => '没有符合的订单';

  @override
  String get colOrderNo => '单号';

  @override
  String get colCreated => '下单时间';

  @override
  String get colShop => '店铺';

  @override
  String get colWholesaler => '批发商';

  @override
  String get colStatus => '状态';

  @override
  String get colSource => '来源';

  @override
  String get colTotal => '总额';

  @override
  String get pagePrev => '上一页';

  @override
  String get pageNext => '下一页';

  @override
  String pageRange(int from, int to, int total) {
    return '$from–$to，共 $total';
  }

  @override
  String followupHint(int minutes) {
    return '待确认超过 $minutes 分钟的订单。打电话给批发商跟进，然后记一句。';
  }

  @override
  String get followupEmpty => '没有要跟进的单';

  @override
  String pendingFor(int minutes) {
    return '等了 $minutes 分钟';
  }

  @override
  String get logFollowup => '记下跟进';

  @override
  String get followupNoteLabel => '跟进内容（例如：批发商说 3 点前确认）';

  @override
  String lastFollowup(String time, String note) {
    return '上次跟进 $time：$note';
  }

  @override
  String get openOrder => '打开订单';

  @override
  String phoneOf(String name) {
    return '$name 电话';
  }

  @override
  String orderTitle(String orderNo) {
    return '订单 $orderNo';
  }

  @override
  String get itemsTitle => '明细';

  @override
  String get eventsTitle => '进度';

  @override
  String get goodsSubtotal => '货价';

  @override
  String get shippingFee => '运费';

  @override
  String get totalLabel => '总额';

  @override
  String get expectedDelivery => '预计送达';

  @override
  String get noteLabel => '备注';

  @override
  String get outOfStockTag => '缺货';

  @override
  String get actConfirm => '代批发商确认';

  @override
  String get actConfirmHint => '勾选缺货的商品（不算钱）。全部缺货就变成「缺货」。';

  @override
  String get actOutOfStock => '整单缺货';

  @override
  String get actDelivering => '出发送货';

  @override
  String get actDelivered => '已送达';

  @override
  String get actCancel => '取消订单';

  @override
  String get cancelReasonLabel => '取消原因（会给批发商看）';

  @override
  String statusUpdated(String status) {
    return '状态已更新：$status';
  }

  @override
  String get chooseShop => '选店铺';

  @override
  String get shopSearchHint => '店名或电话';

  @override
  String get changeShop => '换一家店';

  @override
  String get shopNoApp => '没装 App';

  @override
  String get shopLocked => '未付费：只能向免费开放的批发商下单';

  @override
  String get offersSearchHint => '搜商品';

  @override
  String get offersEmpty => '没有送到这家店的商品';

  @override
  String get priceHidden => '看不到价钱';

  @override
  String perPiece(String sen) {
    return '每个 $sen 仙';
  }

  @override
  String minOrderQty(int qty) {
    return '起订 $qty';
  }

  @override
  String get add => '加入';

  @override
  String get cartTitle => '购物车';

  @override
  String get cartEmpty => '购物车是空的';

  @override
  String get clearCart => '清空';

  @override
  String get orderNoteLabel => '备注（会给批发商看）';

  @override
  String placeOrderButton(String amount) {
    return '确认下单 $amount';
  }

  @override
  String get placedTitle => '已下单';

  @override
  String placedBody(int count) {
    return '拆成 $count 张订单，批发商会收到通知：';
  }

  @override
  String get problemProductUnavailable => '商品下架了';

  @override
  String get problemNotDelivering => '不送这家店那区';

  @override
  String get problemWholesalerLocked => '未付费：这家不在免费名单';

  @override
  String get problemOutOfStock => '缺货';

  @override
  String problemBelowMinQty(int qty) {
    return '未到起订量 $qty';
  }

  @override
  String problemBelowMinOrder(String amount) {
    return '还差 $amount 才到最低消费';
  }

  @override
  String get wsStatusPending => '待审核';

  @override
  String get wsStatusActive => '营业中';

  @override
  String get wsStatusSuspended => '已停权';

  @override
  String get wsApprove => '审核通过';

  @override
  String get wsReject => '不通过';

  @override
  String get wsSuspend => '停权';

  @override
  String get wsReactivate => '恢复';

  @override
  String get wsNoteLabel => '原因（记在操作记录）';

  @override
  String wsCommission(String rate) {
    return '佣金 $rate';
  }

  @override
  String get wsRateOverride => '单独调整';

  @override
  String get wsRateFounding => '创始会员';

  @override
  String get wsRateIndustry => '行业默认';

  @override
  String get wsSetRate => '改佣金比例';

  @override
  String get wsRateLabel => '比例 %（空的 = 用默认）';

  @override
  String wsRateDefaults(String industry, String founding) {
    return '行业默认 $industry，创始会员 $founding';
  }

  @override
  String get wsFounding => '创始会员';

  @override
  String wsFoundingNo(int no) {
    return '创始 #$no';
  }

  @override
  String get wsWhatsappOptIn => '同意 WhatsApp 收订单';

  @override
  String wsProducts(int count) {
    return '商品（$count）';
  }

  @override
  String wsPendingOrders(int count) {
    return '$count 张待确认';
  }

  @override
  String get wsEmpty => '没有批发商';

  @override
  String productsTitle(String name) {
    return '$name 的商品';
  }

  @override
  String get productsHint => '客服代批发商改：每个改动都记在操作记录。';

  @override
  String get productNew => '新增商品';

  @override
  String get productEdit => '改商品';

  @override
  String get productName => '名称';

  @override
  String get productUnit => '单位';

  @override
  String get productPackQty => '一个单位有几个';

  @override
  String get productPrice => '价钱（RM）';

  @override
  String get productMinQty => '起订量';

  @override
  String get productStock => '库存';

  @override
  String get productStatus => '上架状态';

  @override
  String get productsEmpty => '还没有商品';

  @override
  String productPerUnit(String price, String unit, int qty) {
    return '$price / $unit（$qty 个）';
  }

  @override
  String get subsFoundingOnly => '只看创始价';

  @override
  String get colPlan => '锁定月费';

  @override
  String get colTrialEnds => '试用到';

  @override
  String get colPeriodEnd => '付到';

  @override
  String get colLastPayment => '上次付款';

  @override
  String get subExtendTrial => '延长试用';

  @override
  String get subDaysLabel => '延长几天（1–90）';

  @override
  String get subMarkPaid => '标记已付';

  @override
  String get subMonthsLabel => '几个月';

  @override
  String get subAmountLabel => '金额 RM（空的 = 锁定月费 x 月数）';

  @override
  String get subMethodLabel => '付款方式';

  @override
  String get subReferenceLabel => '参考号（银行转账号码）';

  @override
  String get subLapsedNewPrice => '已停：付款会新建一条订阅，按今天的月费锁定。';

  @override
  String get subCancel => '取消订阅';

  @override
  String get subCancelConfirm => '取消后马上停。之后回来要按当时的价钱重新订阅。';

  @override
  String get subReasonLabel => '原因';

  @override
  String get subSetFounding => '创始价设定';

  @override
  String get subLockedPriceLabel => '锁定月费 RM（空的 = 不改）';

  @override
  String get subsEmpty => '没有订阅';

  @override
  String get methodFpx => 'FPX';

  @override
  String get methodDuitnow => 'DuitNow';

  @override
  String get methodEwallet => '电子钱包';

  @override
  String get methodCard => '信用卡';

  @override
  String get methodOther => '现金 / 其他';

  @override
  String get commissionHint => '每家批发商这个月已送达订单的货价（不含运费）和应付佣金。比例是送达时存下来的。';

  @override
  String get prevMonth => '上个月';

  @override
  String get nextMonth => '下个月';

  @override
  String get colOrders => '送达订单';

  @override
  String get colGmv => '货价（不含运费）';

  @override
  String get colRate => '比例';

  @override
  String get colCommission => '应付佣金';

  @override
  String get colInvoice => '账单';

  @override
  String get colBillingName => '开账单名称';

  @override
  String get colSsm => 'SSM 号码';

  @override
  String get colEmail => '电邮';

  @override
  String get colPeriod => '月份';

  @override
  String get colInvoiceStatus => '账单状态';

  @override
  String get commissionTotal => '合计';

  @override
  String get exportCsv => '导出 CSV（全部）';

  @override
  String get exportPdf => '账单 PDF';

  @override
  String exported(String name) {
    return '已下载 $name';
  }

  @override
  String get exportUnsupported => '只有网页版可以下载档案';

  @override
  String get generateInvoices => '生成草稿账单';

  @override
  String invoicesGenerated(int count) {
    return '生成 / 更新了 $count 张草稿账单';
  }

  @override
  String get issueInvoice => '发出账单';

  @override
  String get markInvoicePaid => '标记已付';

  @override
  String get invoiceDraft => '草稿';

  @override
  String get invoiceIssued => '已发出';

  @override
  String get invoicePaid => '已付';

  @override
  String get invoiceOverdue => '逾期';

  @override
  String get invoiceVoid => '作废';

  @override
  String get invoiceNone => '还没有账单';

  @override
  String get commissionEmpty => '这个月还没有送达的订单';

  @override
  String get pdfInvoiceTitle => '佣金账单';

  @override
  String get pdfBillTo => '账单给';

  @override
  String get pdfInvoiceNo => '账单号码';

  @override
  String get pdfDraft => '草稿（还没发出）';

  @override
  String get pdfDueDate => '到期日';

  @override
  String get pdfDelivered => '送达日期';

  @override
  String get pdfTotalDue => '应付佣金合计';

  @override
  String get pdfNote => '佣金只算已送达订单的货价，不含运费；缺货和取消的不算。';

  @override
  String get pdfCompanyNotConfigured => '（公司资料未设定）';

  @override
  String get auditAdminOnly => '只看客服动作';

  @override
  String get auditActor => '谁';

  @override
  String get auditActingFor => '代谁';

  @override
  String get auditTable => '资料';

  @override
  String get auditChanges => '改了什么';

  @override
  String get auditEmpty => '没有记录';

  @override
  String get loadMore => '再看多一些';

  @override
  String get auditActPlaceOrder => '代下单';

  @override
  String get auditActSetCartItem => '改购物车';

  @override
  String get auditActClearCart => '清空购物车';

  @override
  String get auditActSetOrderStatus => '改订单状态';

  @override
  String get auditActConfirmOrder => '代确认订单';

  @override
  String get auditActLogFollowup => '跟进';

  @override
  String get auditActCreateProduct => '新增商品';

  @override
  String get auditActUpdateProduct => '改商品';

  @override
  String get auditActWholesalerStatus => '审核 / 停权';

  @override
  String get auditActCommissionRate => '改佣金比例';

  @override
  String get auditActWholesalerFounding => '创始会员';

  @override
  String get auditActWhatsappOptIn => 'WhatsApp 同意';

  @override
  String get auditActExtendTrial => '延长试用';

  @override
  String get auditActMarkPaid => '标记月费已付';

  @override
  String get auditActCancelSubscription => '取消订阅';

  @override
  String get auditActSubscriptionFounding => '创始价';

  @override
  String get auditActGenerateInvoices => '生成账单';

  @override
  String get auditActIssueInvoice => '发出账单';

  @override
  String get auditActInvoicePaid => '账单已付';

  @override
  String get auditActInsert => '新增';

  @override
  String get auditActUpdate => '修改';

  @override
  String get auditActDelete => '删除';
}
