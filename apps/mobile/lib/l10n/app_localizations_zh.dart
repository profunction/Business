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
}
