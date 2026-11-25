// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class L10nZh extends L10n {
  L10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '新山批发';

  @override
  String get retry => '再试一次';

  @override
  String get cancel => '取消';

  @override
  String get ok => '好';

  @override
  String get save => '保存';

  @override
  String get next => '下一步';

  @override
  String get back => '返回';

  @override
  String get optional => '可以不填';

  @override
  String get errNetwork => '连不上网络，请检查网络再试';

  @override
  String get errUnknown => '出了点问题，请再试一次';

  @override
  String get errAuth => '验证码不对或过期了，请再试一次';

  @override
  String get errNotAllowed => '你没有权限做这件事';

  @override
  String get errPriceChanged => '刚刚有批发商改了价钱，请再看一次总额';

  @override
  String get errCartHasProblems => '购物车里有问题，请先处理红色的部分';

  @override
  String get errCartEmpty => '购物车是空的';

  @override
  String get errUnlockCooldown => '现在还不能换掉已选的批发商';

  @override
  String get errTooManyWholesalers => '免费版选的批发商太多了';

  @override
  String get errWholesalerNotAvailable => '这家批发商现在不送你那区';

  @override
  String get errInvalidTransition => '订单状态已经变了，请刷新再看';

  @override
  String get errOrderNotDelivered => '货还没送到，送到后才能评价';

  @override
  String get errNoPreviousOrder => '你还没下过单';

  @override
  String get languagePageTitle => '请选择语言 · Choose language · Pilih bahasa';

  @override
  String get loginTitle => '用手机号登录';

  @override
  String get loginSubtitle => '我们会发一个验证码到你的手机';

  @override
  String get phoneLabel => '手机号码';

  @override
  String get phoneInvalid => '这不像手机号码，请再检查一次';

  @override
  String get sendCode => '发送验证码';

  @override
  String get otpTitle => '输入验证码';

  @override
  String otpSentTo(String phone) {
    return '验证码已经发到 $phone';
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
  String get registerTitle => '开你的店';

  @override
  String get shopNameQuestion => '你的店叫什么名字？';

  @override
  String get shopNameHint => '例如：阿明茶餐室';

  @override
  String get shopTypeQuestion => '你的店是做什么的？';

  @override
  String get shopTypeRestaurant => '餐馆';

  @override
  String get shopTypeDrinkStall => '饮料店';

  @override
  String get shopTypeGrocery => '杂货店';

  @override
  String get shopTypeOther => '其他';

  @override
  String get zoneQuestion => '你的店在哪一区？';

  @override
  String get addressQuestion => '店的地址（送货用）';

  @override
  String get addressHint => '例如：12, Jalan Molek 1/2, Taman Molek';

  @override
  String get registerFinish => '开始用';

  @override
  String get homeReorder => '跟上次一样';

  @override
  String homeReorderLast(String date, String total) {
    return '上次：$date，$total';
  }

  @override
  String get homeShop => '买东西';

  @override
  String get homeOrders => '我的订单';

  @override
  String homeActiveOrders(int count) {
    return '$count 张进行中';
  }

  @override
  String homeCart(int count) {
    return '购物车（$count 样）';
  }

  @override
  String trialBanner(int days) {
    return '免费试用还有 $days 天，全部价钱都看得到';
  }

  @override
  String freeBanner(int count) {
    return '免费版：可以选 $count 家批发商看价钱';
  }

  @override
  String get chooseWholesalers => '选批发商';

  @override
  String get settings => '设定';

  @override
  String get browseTitle => '买东西';

  @override
  String get browseByProduct => '看商品';

  @override
  String get browseByWholesaler => '看批发商';

  @override
  String get searchHint => '找东西，例如：杯';

  @override
  String get noResults => '找不到';

  @override
  String categoryItemCount(int count) {
    return '$count 样';
  }

  @override
  String sellerCount(int count) {
    return '$count 家有卖';
  }

  @override
  String cheapestPerUnit(String sen) {
    return '最便宜每个 $sen 仙';
  }

  @override
  String get compareTitle => '比价钱';

  @override
  String perUnit(String sen) {
    return '每个 $sen 仙';
  }

  @override
  String pricePerSellUnit(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String packQty(String unit, int qty) {
    return '一$unit $qty 个';
  }

  @override
  String get priceLocked => '价钱未开放';

  @override
  String rating(String avg, int count) {
    return '$avg（$count 个评价）';
  }

  @override
  String get noRatings => '还没有评价';

  @override
  String leadTime(int days) {
    String _temp0 = intl.Intl.pluralLogic(days, locale: localeName, other: '$days 天送到', one: '明天送到', zero: '今天送到');
    return '$_temp0';
  }

  @override
  String minOrderQty(int qty, String unit) {
    return '最少买 $qty $unit';
  }

  @override
  String shippingFee(String fee) {
    return '运费 $fee';
  }

  @override
  String freeShippingOver(String amount) {
    return '满 $amount 免运费';
  }

  @override
  String minOrderAmount(String amount) {
    return '最低消费 $amount';
  }

  @override
  String get outOfStock => '缺货';

  @override
  String get lowStock => '快卖完';

  @override
  String get founding => '创始会员';

  @override
  String get addToCart => '放进购物车';

  @override
  String inCart(int qty) {
    return '购物车里有 $qty';
  }

  @override
  String get updateCart => '更新购物车';

  @override
  String get removeFromCart => '拿掉';

  @override
  String get addedToCart => '已经放进购物车';

  @override
  String get lockedHint => '免费版只看得到你选的批发商的价钱';

  @override
  String get chooseThisWholesaler => '把这家加进免费名单';

  @override
  String get freeSlotsFull => '免费名单满了，去「选批发商」换一家';

  @override
  String get unitCarton => '箱';

  @override
  String get unitPack => '包';

  @override
  String get unitBag => '袋';

  @override
  String get unitRoll => '卷';

  @override
  String get unitBundle => '扎';

  @override
  String get unitBox => '盒';

  @override
  String get unitPiece => '个';

  @override
  String get unitDozen => '打';

  @override
  String get unitKg => '公斤';

  @override
  String productCount(int count) {
    return '$count 样货';
  }

  @override
  String deliveryDays(String days) {
    return '送货日：$days';
  }

  @override
  String get weekdayShort1 => '一';

  @override
  String get weekdayShort2 => '二';

  @override
  String get weekdayShort3 => '三';

  @override
  String get weekdayShort4 => '四';

  @override
  String get weekdayShort5 => '五';

  @override
  String get weekdayShort6 => '六';

  @override
  String get weekdayShort7 => '日';

  @override
  String get paymentCod => '货到付款';

  @override
  String get paymentTransfer => '转账';

  @override
  String get paymentCredit => '月结';

  @override
  String get cartTitle => '购物车';

  @override
  String get cartEmpty => '购物车是空的';

  @override
  String get goodsSubtotal => '货价';

  @override
  String get shipping => '运费';

  @override
  String get freeShipping => '免运费';

  @override
  String get total => '总额';

  @override
  String shortOfFreeShipping(String amount) {
    return '再买 $amount 就免运费';
  }

  @override
  String shortOfMinOrder(String amount) {
    return '还差 $amount 才到最低消费';
  }

  @override
  String expectedDelivery(String date) {
    return '预计 $date 送到';
  }

  @override
  String get problemProductUnavailable => '这样货下架了，请拿掉';

  @override
  String get problemNotDelivering => '这家现在不送你那区';

  @override
  String get problemWholesalerLocked => '免费版看不到这家的价钱，不能下单';

  @override
  String get problemOutOfStock => '缺货了，请拿掉';

  @override
  String problemBelowMinQty(int qty) {
    return '最少要买 $qty';
  }

  @override
  String get goToConfirm => '下一步：确认订单';

  @override
  String get fixProblemsFirst => '请先处理红色的问题';

  @override
  String get confirmTitle => '确认订单';

  @override
  String ordersWillSplit(int count) {
    return '会分成 $count 张单，每家批发商自己送货';
  }

  @override
  String get noteLabel => '备注';

  @override
  String placeOrder(String total) {
    return '确认下单 $total';
  }

  @override
  String get priceChangedTitle => '价钱改了';

  @override
  String get reorderPriceChanges => '这几样改了价：';

  @override
  String get reorderSkipped => '这几样买不到了，已经拿掉：';

  @override
  String priceChangeLine(String name, String oldPrice, String newPrice) {
    return '$name：$oldPrice → $newPrice';
  }

  @override
  String get orderPlacedTitle => '下单成功！';

  @override
  String get orderPlacedBody => '批发商确认后会通知你';

  @override
  String get viewOrders => '看我的订单';

  @override
  String get backHome => '回首页';

  @override
  String get ordersTitle => '我的订单';

  @override
  String get noOrders => '还没有订单';

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
  String itemCount(int count) {
    return '$count 样货';
  }

  @override
  String outOfStockCount(int count) {
    return '$count 样缺货';
  }

  @override
  String orderTitle(String orderNo) {
    return '订单 $orderNo';
  }

  @override
  String orderedAt(String date) {
    return '下单：$date';
  }

  @override
  String get callWholesaler => '打电话给批发商';

  @override
  String get markReceived => '收到了';

  @override
  String get markReceivedConfirm => '确定货已经收到了？';

  @override
  String get cancelOrder => '取消订单';

  @override
  String get cancelOrderConfirm => '确定要取消这张单？';

  @override
  String get cancelReasonHint => '原因（可以不填）';

  @override
  String cancelledReason(String reason) {
    return '取消原因：$reason';
  }

  @override
  String get writeReview => '给批发商评分';

  @override
  String get editReview => '改评价';

  @override
  String get yourReview => '你的评价';

  @override
  String get itemOutOfStockLabel => '缺货（不算钱）';

  @override
  String paymentTerms(String terms) {
    return '付款方式：$terms';
  }

  @override
  String get reviewTitle => '评分';

  @override
  String get reviewQuestion => '这家批发商怎么样？';

  @override
  String get tagOnTime => '准时';

  @override
  String get tagGoodQuality => '货好';

  @override
  String get tagWellPacked => '包装好';

  @override
  String get tagGoodPrice => '价钱好';

  @override
  String get tagFriendly => '态度好';

  @override
  String get tagLate => '迟到';

  @override
  String get tagWrongItems => '送错货';

  @override
  String get tagDamaged => '有破损';

  @override
  String get tagMissingItems => '少了货';

  @override
  String get reviewCommentHint => '想说的话（可以不填）';

  @override
  String get submitReview => '送出';

  @override
  String get reviewThanks => '谢谢你的评价！';

  @override
  String get freeWholesalersTitle => '免费看价钱的批发商';

  @override
  String freeWholesalersBody(int count) {
    return '免费版可以选 $count 家批发商，完整看到他们的价钱，也可以向他们下单';
  }

  @override
  String freeWholesalersCooldown(String date) {
    return '要换掉已选的批发商，要等到 $date';
  }

  @override
  String selectedCount(int selected, int max) {
    return '已选 $selected/$max';
  }

  @override
  String get fullAccessNoNeed => '你现在全部价钱都看得到，不用选';

  @override
  String get saved => '保存好了';

  @override
  String get settingsTitle => '设定';

  @override
  String get language => '语言';

  @override
  String get myShop => '我的店';

  @override
  String get subscription => '订阅';

  @override
  String subTrial(String date) {
    return '免费试用到 $date';
  }

  @override
  String subActive(String date) {
    return '已订阅，下次续费 $date';
  }

  @override
  String subPastDue(String date) {
    return '订阅到期了，$date 前续费可以保留原价';
  }

  @override
  String get subFree => '免费版';

  @override
  String lockedPrice(String price) {
    return '你的月费锁定 $price，一直续费就不会涨';
  }

  @override
  String get subscribeComingSoon => '付费订阅很快推出';

  @override
  String get logout => '登出';

  @override
  String get logoutConfirm => '确定要登出？';

  @override
  String get sellerComingSoon => '批发商的功能正在做，很快就可以用';

  @override
  String get sellerPending => '你的批发商资料正在等客服审核';

  @override
  String get adminUseWeb => '客服请用网页后台';

  @override
  String get pushChannelName => '订单通知';

  @override
  String get pushChannelDescription => '新订单、订单状态和每天的送货总结';

  @override
  String get pushAskTitle => '打开通知？';

  @override
  String get pushAskSellerBody => '有新订单时手机会响，不会漏单。';

  @override
  String get pushAskBuyerBody => '批发商确认、缺货或出发送货时，马上通知你。';

  @override
  String get pushAskAllow => '打开通知';

  @override
  String get pushAskLater => '以后再说';

  @override
  String get pushDenied => '通知没有打开。想打开的话，到手机的「设定」→「通知」。';

  @override
  String get sellerErrUnsupportedFile => '这种文件看不懂。请拍照，或选 Excel、PDF、CSV 文件。';

  @override
  String get sellerErrFileTooLarge => '文件太大了（最多 10 MB）';

  @override
  String get sellerErrAiFailed => 'AI 读不懂这份价目表。请拍清楚一点再试一次。';

  @override
  String get sellerErrImportTimeout => 'AI 还没读完。请过几分钟再回来看。';

  @override
  String get sellerErrImportDone => '这份价目表已经处理过了';

  @override
  String sellerErrRowIncomplete(int row) {
    return '第 $row 行还缺名字、单位、包装数量或价钱';
  }

  @override
  String sellerErrRowInvalidProduct(int row) {
    return '第 $row 行对到的商品不对，请重新选';
  }

  @override
  String sellerErrDuplicateProduct(int row) {
    return '第 $row 行跟另一行改同一样商品，请改掉其中一行';
  }

  @override
  String get sellerErrItemNotInOrder => '这样东西不在这张订单里，请重新打开订单';

  @override
  String get sellerErrNotFound => '找不到，可能已经被删掉了';

  @override
  String sellerHomeNewOrders(int count) {
    return '新订单（$count）';
  }

  @override
  String get sellerNoNewOrders => '没有新订单';

  @override
  String sellerOldestWaiting(String duration) {
    return '最久的一张等了 $duration';
  }

  @override
  String sellerWaiting(String duration) {
    return '等了 $duration';
  }

  @override
  String sellerMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String sellerHours(int count) {
    return '$count 小时';
  }

  @override
  String sellerDays(int count) {
    return '$count 天';
  }

  @override
  String sellerHomeToday(int count) {
    return '今天要送（$count）';
  }

  @override
  String sellerTodayTotal(String total) {
    return '总额 $total';
  }

  @override
  String get sellerNothingToday => '今天没有要送的单';

  @override
  String get sellerHomeProducts => '商品和价钱';

  @override
  String sellerProductsActive(int count) {
    return '上架 $count 样';
  }

  @override
  String sellerProductsOutOfStock(int count) {
    return '$count 样缺货';
  }

  @override
  String sellerProductsLowStock(int count) {
    return '$count 样快卖完';
  }

  @override
  String sellerProductsDraft(int count) {
    return '$count 样草稿';
  }

  @override
  String get sellerHomeImport => '上传价目表';

  @override
  String get sellerImportNone => '拍照或选 Excel，AI 帮你建商品';

  @override
  String get sellerImportProcessing => 'AI 正在读你的价目表…';

  @override
  String get sellerImportReview => 'AI 读好了，去确认上架';

  @override
  String get sellerImportFailed => '上次的读不到，请再上传一次';

  @override
  String sellerImportApplied(String date) {
    return '$date 上架了';
  }

  @override
  String get sellerPendingBanner => '客服正在审核你的资料。审核好之前买家还看不到你，你可以先放商品和价钱。';

  @override
  String get sellerSuspendedBanner => '你的账号暂停了，买家现在看不到你。请联系客服。';

  @override
  String get sellerOrdersTitle => '订单';

  @override
  String get sellerTabPending => '新订单';

  @override
  String get sellerTabToday => '今天要送';

  @override
  String get sellerTabAll => '全部';

  @override
  String sellerTabWithCount(String label, int count) {
    return '$label（$count）';
  }

  @override
  String sellerTodayCount(int count, String total) {
    return '$count 张单，总额 $total';
  }

  @override
  String get sellerOpenSummary => '送货单（拣货、打印）';

  @override
  String sellerDeliverOn(String date) {
    return '送货：$date';
  }

  @override
  String sellerBuyerNote(String note) {
    return '买家备注：$note';
  }

  @override
  String get sellerCall => '打电话';

  @override
  String get sellerWhatsapp => 'WhatsApp';

  @override
  String sellerWhatsappHello(String orderNo) {
    return '你好，关于你的订单 $orderNo：';
  }

  @override
  String get sellerCannotOpen => '打不开，请检查手机有没有装这个 App';

  @override
  String sellerContact(String name) {
    return '联络人：$name';
  }

  @override
  String get sellerConfirm => '确认';

  @override
  String get sellerOutOfStock => '缺货';

  @override
  String get sellerChecklistTitle => '哪几样缺货？';

  @override
  String get sellerChecklistHint => '缺货的勾起来，那几样不算钱。全部都有货就直接按确认。';

  @override
  String get sellerConfirmAllInStock => '全部有货，确认';

  @override
  String sellerConfirmWithOos(int count) {
    return '确认（$count 样缺货）';
  }

  @override
  String get sellerConfirmAllOos => '全部都缺货';

  @override
  String get sellerOosConfirmTitle => '整张单都缺货？';

  @override
  String get sellerOosConfirmBody => '买家会收到通知，这张单不会送。';

  @override
  String get sellerOosConfirmButton => '整张单缺货';

  @override
  String get sellerConfirmedMsg => '已确认，买家会收到通知';

  @override
  String get sellerOosMsg => '已标缺货，买家会收到通知';

  @override
  String get sellerStartDelivery => '出发送货';

  @override
  String get sellerMarkDelivered => '已送达';

  @override
  String get sellerDeliveredConfirm => '确定货已经送到了？';

  @override
  String get sellerDeliveringMsg => '已出发，买家会收到通知';

  @override
  String get sellerDeliveredMsg => '送到了，谢谢！';

  @override
  String get sellerMyBusiness => '我的公司';

  @override
  String get sellerNotifyTitle => '新订单怎么通知你？';

  @override
  String get sellerNotifyAuto => '自动（建议）';

  @override
  String get sellerNotifyAutoHint => '手机有装 App 就用推送，没有就用 WhatsApp';

  @override
  String get sellerNotifyPush => 'App 推送';

  @override
  String get sellerNotifyWhatsapp => 'WhatsApp';

  @override
  String sellerNotifyWhatsappTo(String phone) {
    return '发到 $phone';
  }

  @override
  String get sellerNotifyNoWhatsapp => '还没有 WhatsApp 号码，客服可以帮你加';

  @override
  String get sellerWhatsappOptIn => '同意用 WhatsApp 收订单';

  @override
  String get sellerWhatsappOptInHint => '关掉的话，我们不会发 WhatsApp 给你';

  @override
  String get sellerNotifyOwnerOnly => '只有老板可以改。客服也可以帮你改。';

  @override
  String get pushSettingsTitle => '这部手机的通知';

  @override
  String get pushStatusOn => '已经打开，有新订单手机会响';

  @override
  String get pushStatusOff => '通知还没打开';

  @override
  String get pushNotSupported => '这部手机收不到 App 推送，可以改用 WhatsApp 收订单';

  @override
  String get sellerSummaryTitle => '送货单';

  @override
  String sellerSummaryHeading(String date) {
    return '送货单 $date';
  }

  @override
  String get sellerSummaryPrevDay => '前一天';

  @override
  String get sellerSummaryNextDay => '后一天';

  @override
  String sellerSummaryPending(int count) {
    return '还有 $count 张没确认';
  }

  @override
  String get sellerSummaryGoConfirm => '去确认';

  @override
  String get sellerSummaryPicking => '拣货单';

  @override
  String get sellerSummaryPickingHint => '全部单加起来，缺货的不算';

  @override
  String sellerSummaryQty(int qty, String unit) {
    return '$qty $unit';
  }

  @override
  String get sellerSummaryEmpty => '这天没有要送的单';

  @override
  String get sellerSummaryOrders => '每张单（按区、再按店）';

  @override
  String get sellerSummaryOtherArea => '其他地区';

  @override
  String get sellerSummaryPrint => '打印';

  @override
  String get sellerSummaryShare => '分享给送货员';

  @override
  String sellerSummaryPhone(String phone) {
    return '电话：$phone';
  }

  @override
  String sellerSummaryAddress(String address) {
    return '地址：$address';
  }

  @override
  String get sellerSummaryOosMark => '（缺货）';

  @override
  String get sellerSummarySignature => '收货人签名：';

  @override
  String sellerSummaryPage(int page, int total) {
    return '第 $page / $total 页';
  }

  @override
  String get sellerSummaryColItem => '商品';

  @override
  String get sellerSummaryColQty => '数量';

  @override
  String get sellerSummaryColPack => '包装';

  @override
  String get sellerSummaryPrintFailed => '打印不了，请再试一次';

  @override
  String get sellerSummaryShareFailed => '分享不了，请再试一次';

  @override
  String get sellerProductsSearch => '找商品';

  @override
  String get sellerFilterAll => '全部';

  @override
  String get sellerFilterOutOfStock => '缺货';

  @override
  String get sellerFilterDraft => '草稿';

  @override
  String get sellerStockIn => '有货';

  @override
  String get sellerStockLow => '快卖完';

  @override
  String get sellerStockOut => '缺货';

  @override
  String get sellerStatusDraft => '草稿';

  @override
  String get sellerStatusArchived => '已下架';

  @override
  String get sellerProductsEmpty => '还没有商品。按「新增商品」一样一样加，或者上传价目表让 AI 帮你建。';

  @override
  String get sellerProductsNoMatch => '找不到符合的商品';

  @override
  String get sellerAddProduct => '新增商品';

  @override
  String get sellerEditProduct => '改商品';

  @override
  String get sellerFieldName => '商品名字';

  @override
  String get sellerFieldNameHint => '例如：16安士 PP杯 95口径';

  @override
  String get sellerFieldUnit => '用什么单位卖？';

  @override
  String sellerFieldPackQty(String unit) {
    return '一$unit有几个？';
  }

  @override
  String sellerFieldPrice(String unit) {
    return '一$unit多少钱？';
  }

  @override
  String get sellerFieldPriceHint => '例如 12.50';

  @override
  String sellerFieldMinQty(String unit) {
    return '最少要买几$unit？';
  }

  @override
  String get sellerFieldStock => '还有货吗？';

  @override
  String get sellerFieldStatus => '买家看得到吗？';

  @override
  String get sellerOnSale => '上架';

  @override
  String get sellerOffSale => '下架';

  @override
  String get sellerDraftHint => '这是草稿，买家还看不到。选「上架」再保存。';

  @override
  String get sellerOffSaleHint => '下架了买家就看不到，以后可以再上架';

  @override
  String get sellerErrName => '请写商品名字';

  @override
  String get sellerErrPrice => '请写价钱，例如 12.50';

  @override
  String get sellerErrPackQty => '最少 1 个';

  @override
  String get sellerErrForm => '还有资料没填好，请看红色的地方';

  @override
  String get sellerPhoto => '照片（可以不放）';

  @override
  String get sellerPhotoTake => '拍照';

  @override
  String get sellerPhotoPick => '选照片';

  @override
  String get sellerPhotoRemove => '拿掉照片';

  @override
  String get sellerErrPhotoFile => '照片只收 JPG、PNG、WebP，最多 5 MB';

  @override
  String get sellerErrNoPermission => '请到手机的「设定」，允许这个 App 用相机和照片';

  @override
  String get sellerImportIntro => '拍价目表的照片，或选 Excel、PDF 文件。AI 会读成商品，你检查好了才上架。';

  @override
  String get sellerImportCamera => '拍照';

  @override
  String get sellerImportCameraHint => '对着纸本价目表拍，拍清楚一点';

  @override
  String get sellerImportGallery => '选照片';

  @override
  String get sellerImportGalleryHint => '手机里的照片或截图';

  @override
  String get sellerImportFile => '选文件（Excel、PDF）';

  @override
  String get sellerImportFileHint => 'Excel、PDF 或 CSV，最多 10 MB';

  @override
  String get sellerImportUploading => '正在上传…';

  @override
  String get sellerImportUploaded => '已经上传';

  @override
  String get sellerImportWaitHint => '通常要 1 到 3 分钟。你可以先离开这一页，读好了首页会告诉你。';

  @override
  String get sellerImportStillReading => '还在读，价目表长的话要久一点…';

  @override
  String get sellerImportFailedTitle => 'AI 读不到这份价目表';

  @override
  String get sellerImportRetry => '再上传一次';

  @override
  String get sellerBackHome => '回首页';

  @override
  String get sellerErrHeic => '这是 iPhone 的 HEIC 照片，AI 看不懂。请按「选照片」再选一次这张，App 会自动转成 JPG。';

  @override
  String get sellerImportErrRefused => 'AI 不肯读这份文件。请确认是价目表，再试一次。';

  @override
  String get sellerImportErrTruncated => '价目表太长，AI 读不完。请分成几张照片或几个文件，一份一份上传。';

  @override
  String get sellerReviewTitle => '检查价目表';

  @override
  String sellerReviewSummary(int total, int create, int update, int skip) {
    return '共 $total 行：新增 $create、更新 $update、跳过 $skip';
  }

  @override
  String sellerReviewUnsure(int count) {
    return '有 $count 行 AI 不太肯定，请检查黄色的';
  }

  @override
  String get sellerReviewHint => '每一行选「新增」「更新」或「跳过」。不对的按「改」。';

  @override
  String sellerReviewRow(int row) {
    return '第 $row 行';
  }

  @override
  String get sellerReviewCheck => '请检查';

  @override
  String get sellerReviewNoName => '（没有名字）';

  @override
  String get sellerReviewNoPrice => '没有价钱';

  @override
  String sellerReviewRaw(String text) {
    return '原文：$text';
  }

  @override
  String sellerReviewMatched(String name) {
    return '会更新：$name';
  }

  @override
  String sellerReviewPriceNow(String price) {
    return '现在 $price';
  }

  @override
  String get sellerReviewNoMatch => '你的商品里没有一样的，会新增。要改旧商品的价钱，按「更新」选是哪一样。';

  @override
  String get sellerReviewNoRows => 'AI 在这份价目表里找不到商品';

  @override
  String get sellerActionCreate => '新增';

  @override
  String get sellerActionUpdate => '更新';

  @override
  String get sellerActionSkip => '跳过';

  @override
  String sellerReviewMissing(String fields) {
    return '还缺：$fields';
  }

  @override
  String get sellerMissingName => '名字';

  @override
  String get sellerMissingUnit => '单位';

  @override
  String get sellerMissingPack => '包装数量';

  @override
  String get sellerMissingPrice => '价钱';

  @override
  String get sellerMissingMatch => '要更新哪样商品';

  @override
  String get sellerReviewEdit => '改';

  @override
  String sellerReviewEditTitle(int row) {
    return '改第 $row 行';
  }

  @override
  String sellerApply(int count) {
    return '确认上架（$count 样）';
  }

  @override
  String sellerApplyDone(int created, int updated) {
    return '上架好了：新增 $created 样，更新 $updated 样';
  }

  @override
  String get sellerReviewApplied => '这份价目表已经上架了';

  @override
  String get sellerReviewGoProducts => '去看商品';

  @override
  String get sellerReviewWait => '等 AI 读完';

  @override
  String get sellerImportUploadOther => '上传另一份';

  @override
  String get sellerImportCheckFailed => '查不到这份价目表读得怎样';

  @override
  String get sellerImportRecovered => '刚才选的价目表找回来了，正在上传';

  @override
  String get sellerImportErrService => 'AI 服务暂时有问题。请过几分钟再上传一次。';

  @override
  String get sellerImportErrFile => '这个文件打不开，或是空的。请重新存一次（Excel 存成 .xlsx），或拍照上传。';

  @override
  String get sellerImportErrTimeout => 'AI 读太久还没读完。价目表很长的话，请分成几份上传；不长的话，请过几分钟再试。';

  @override
  String get sellerErrPhotoTooLarge => '照片太大了（最多 7 MB）。请用「拍照」重新拍，或选小一点的照片。';

  @override
  String get sellerErrLoginExpired => '登录过期了。请到「设定」登出，再登录一次。';

  @override
  String get sellerReviewChooseProduct => '要更新哪一样商品？';

  @override
  String get sellerReviewChangeProduct => '换一样商品';

  @override
  String get sellerReviewClearMatch => '都不是（当新商品）';

  @override
  String sellerReviewUsedByRow(int row) {
    return '第 $row 行已经对到这样';
  }

  @override
  String sellerReviewWillRelist(String status) {
    return '现在是「$status」，确认后会上架给买家看';
  }

  @override
  String sellerReviewPackChange(String before, String after) {
    return '包装会改：$before → $after';
  }

  @override
  String sellerUnitPlural(String unit) {
    String _temp0 = intl.Intl.selectLogic(unit, {
      'carton': '箱',
      'pack': '包',
      'bag': '袋',
      'roll': '卷',
      'bundle': '扎',
      'box': '盒',
      'dozen': '打',
      'kg': '公斤',
      'other': '个',
    });
    return '$_temp0';
  }
}
