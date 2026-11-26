import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../l10n/app_localizations.dart';

/// 把服务器的代码（单位、状态、错误）翻成三语文字
extension L10nX on BuildContext {
  L10n get l10n => L10n.of(this);
  String get lang => L10n.of(this).localeName.split('_').first;
}

extension L10nText on L10n {
  String get lang => localeName.split('_').first;

  String unit(SellUnit u) => switch (u) {
    SellUnit.carton => unitCarton,
    SellUnit.pack => unitPack,
    SellUnit.bag => unitBag,
    SellUnit.roll => unitRoll,
    SellUnit.bundle => unitBundle,
    SellUnit.box => unitBox,
    SellUnit.piece || SellUnit.unknown => unitPiece,
    SellUnit.dozen => unitDozen,
    SellUnit.kg => unitKg,
  };

  String status(OrderStatus s) => switch (s) {
    OrderStatus.pending => statusPending,
    OrderStatus.confirmed => statusConfirmed,
    OrderStatus.outOfStock => statusOutOfStock,
    OrderStatus.delivering => statusDelivering,
    OrderStatus.delivered => statusDelivered,
    OrderStatus.cancelled => statusCancelled,
  };

  String shopType(ShopType t) => switch (t) {
    ShopType.restaurant => shopTypeRestaurant,
    ShopType.drinkStall => shopTypeDrinkStall,
    ShopType.grocery => shopTypeGrocery,
    ShopType.other => shopTypeOther,
  };

  String reviewTag(ReviewTag t) => switch (t) {
    ReviewTag.onTime => tagOnTime,
    ReviewTag.goodQuality => tagGoodQuality,
    ReviewTag.wellPacked => tagWellPacked,
    ReviewTag.goodPrice => tagGoodPrice,
    ReviewTag.friendly => tagFriendly,
    ReviewTag.late => tagLate,
    ReviewTag.wrongItems => tagWrongItems,
    ReviewTag.damaged => tagDamaged,
    ReviewTag.missingItems => tagMissingItems,
  };

  String? cartProblem(CartProblem? p, {int minQty = 1}) => switch (p) {
    null => null,
    CartProblem.productUnavailable || CartProblem.unknown => problemProductUnavailable,
    CartProblem.notDelivering => problemNotDelivering,
    CartProblem.wholesalerLocked => problemWholesalerLocked,
    CartProblem.outOfStock => problemOutOfStock,
    CartProblem.belowMinQty => problemBelowMinQty(minQty),
    CartProblem.belowMinOrder => null, // 组的问题另外显示「还差多少」
  };

  String paymentTerm(String code) => switch (code) {
    'cod' => paymentCod,
    'transfer' => paymentTransfer,
    'credit' => paymentCredit,
    _ => code,
  };

  String weekdays(List<int> days) {
    if (days.length == 7) return days.map(weekdayShort).join(' ');
    return days.map(weekdayShort).join(lang == 'zh' ? '、' : ', ');
  }

  String weekdayShort(int d) => switch (d) {
    1 => weekdayShort1,
    2 => weekdayShort2,
    3 => weekdayShort3,
    4 => weekdayShort4,
    5 => weekdayShort5,
    6 => weekdayShort6,
    _ => weekdayShort7,
  };

  /// 错误代码 -> 给老板看的话
  String error(Object e) {
    final code = e is AppError ? e.code : 'UNKNOWN';
    return switch (code) {
      'NETWORK' => errNetwork,
      // 登录过期（Edge Function 说 UNAUTHORIZED、refresh 失败）不是验证码打错
      'AUTH' => e is AppError && e.detail == AppError.sessionExpired ? sellerErrLoginExpired : errAuth,
      'NOT_ALLOWED' || 'NOT_LOGGED_IN' || 'COLUMN_PROTECTED' || 'ROLE_MISMATCH' => errNotAllowed,
      'PRICE_CHANGED' => errPriceChanged,
      'CART_HAS_PROBLEMS' => errCartHasProblems,
      'CART_EMPTY' => errCartEmpty,
      'UNLOCK_COOLDOWN' => errUnlockCooldown,
      'TOO_MANY_WHOLESALERS' => errTooManyWholesalers,
      'WHOLESALER_NOT_AVAILABLE' || 'INVALID_ZONE' => errWholesalerNotAvailable,
      'INVALID_TRANSITION' || 'ORDER_NOT_FOUND' => errInvalidTransition,
      'ORDER_NOT_DELIVERED' => errOrderNotDelivered,
      'NO_PREVIOUS_ORDER' => errNoPreviousOrder,
      // 批发商端
      'ITEM_NOT_IN_ORDER' => sellerErrItemNotInOrder,
      // iPhone 的 HEIC 照片：告诉老板怎么办（用「选照片」会自动转成 JPEG）
      'UNSUPPORTED_FILE' => e is AppError && e.detail == 'heic' ? sellerErrHeic : sellerErrUnsupportedFile,
      // 照片超过 7 MB（AI 收不了），其他档案超过 10 MB
      'FILE_TOO_LARGE' => e is AppError && e.detail == 'image' ? sellerErrPhotoTooLarge : sellerErrFileTooLarge,
      'NO_PERMISSION' => sellerErrNoPermission,
      'IMPORT_TIMEOUT' => sellerErrImportTimeout,
      'IMPORT_ALREADY_RUNNING' => sellerImportStillReading,
      // parse-price-list 自己出错（没设定好、数据库出错）
      'CONFIG_MISSING' || 'DB_ERROR' || 'INTERNAL_ERROR' => sellerImportErrService,
      'IMPORT_NOT_IN_REVIEW' || 'IMPORT_NOT_PROCESSING' || 'IMPORT_ALREADY_APPLIED' => sellerErrImportDone,
      'IMPORT_ROW_INCOMPLETE' => sellerErrRowIncomplete(_row(e)),
      'IMPORT_ROW_INVALID_PRODUCT' => sellerErrRowInvalidProduct(_row(e)),
      'IMPORT_DUPLICATE_PRODUCT' => sellerErrDuplicateProduct(_row(e)),
      'IMPORT_NOT_FOUND' || 'PRODUCT_NOT_FOUND' || 'WHOLESALER_NOT_FOUND' || 'NOT_FOUND' => sellerErrNotFound,
      // parse-price-list 不肯读（这一次的导入 App 已经删掉了）：用量满了要等几分钟 / 停权 / 暂时叫不到
      'TOO_MANY_IMPORTS' => sellerErrTooManyImports(_waitMinutes(e)),
      'WHOLESALER_SUSPENDED' => sellerErrSuspended,
      'QUOTA_UNAVAILABLE' => sellerErrQuotaUnavailable,
      // 付款（第七步）
      'PAYMENT_NOT_CONFIGURED' => payErrNotReady,
      'NOTHING_DUE' => payErrNothingDue,
      'FOUNDING_FULL' => payErrFoundingFull,
      'TOO_MANY_PAYMENTS' => payErrTooMany,
      'GATEWAY_UNAVAILABLE' || 'GATEWAY_AUTH_FAILED' || 'GATEWAY_REJECTED' || 'GATEWAY_BAD_RESPONSE' => payErrGateway,
      // 语音下单（第六步）
      'TOO_MANY_VOICE_ORDERS' => voiceErrTooMany(_voiceWaitMinutes(e)),
      'NO_SPEECH' => voiceErrNoSpeech,
      'AUDIO_TOO_LONG' => voiceErrTooLong,
      'STT_NOT_CONFIGURED' ||
      'AI_NOT_CONFIGURED' ||
      'STT_BUSY' ||
      'STT_FAILED' ||
      'STT_AUTH_FAILED' ||
      'AI_BUSY' ||
      'AI_UNAVAILABLE' ||
      'AI_AUTH_FAILED' ||
      'AI_TIMEOUT' ||
      'AI_FAILED' => voiceErrUnavailable,
      'AI_REFUSED' || 'AI_INVALID_OUTPUT' || 'AI_TRUNCATED' || 'AI_REQUEST_REJECTED' => voiceErrNotUnderstood,
      'UNSUPPORTED_AUDIO' || 'AUDIO_TOO_LARGE' || 'AUDIO_NOT_FOUND' || 'INVALID_FILE_PATH' => voiceErrRecordAgain,
      'NO_ORDERABLE_PRODUCTS' => voiceErrNoProducts,
      'DRAFT_NOT_PENDING' => voiceErrNotPending,
      'DRAFT_NOT_FOUND' => voiceErrNotFound,
      'DRAFT_EMPTY' => voiceNoItems,
      'INVALID_PRODUCT' => voiceErrInvalidProduct,
      _ => errUnknown,
    };
  }

  /// 用量满了要等几分钟（无条件进位，最少 1）。函数没说的话当 10 分钟（最短的那一段）
  int _waitMinutes(Object e) {
    final wait = e is AppError ? e.retryAfter : null;
    if (wait == null) return 10;
    final m = (wait.inSeconds / 60).ceil();
    return m < 1 ? 1 : m;
  }

  /// voice-order 用量满了：detail 是要等几秒（进位成分钟，最少 1）
  int _voiceWaitMinutes(Object e) {
    final sec = int.tryParse(e is AppError ? e.detail ?? '' : '');
    if (sec == null || sec <= 0) return 10;
    return (sec / 60).ceil();
  }

  int _row(Object e) => (e is AppError ? e.rowNo : null) ?? 0;

  /// 等了多久（新订单）：12 分钟 / 3 小时 / 2 天。不到 1 分钟也说 1 分钟
  String waited(DateTime since, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(since);
    if (d.inMinutes < 60) return sellerMinutes(d.inMinutes < 1 ? 1 : d.inMinutes);
    if (d.inHours < 24) return sellerHours(d.inHours);
    return sellerDays(d.inDays);
  }

  String notifyChannel(NotifyChannel c) => switch (c) {
    NotifyChannel.auto => sellerNotifyAuto,
    NotifyChannel.push => sellerNotifyPush,
    NotifyChannel.whatsapp => sellerNotifyWhatsapp,
  };

  /// 价目表 AI 读失败的原因（price_list_imports.error_message）。代码见 supabase/functions/parse-price-list/index.ts
  /// 开头的三类：档案问题 / AI 读不到 / 网络、服务；另外 App 自己写的 START_FAILED、NETWORK、AUTH（叫不到 AI）。
  /// [fileType] 是导入的种类（照片太大跟档案太大的上限不一样）
  String importFailure(String? code, {ImportFileType? fileType}) => switch (code) {
    // 档案问题
    'UNSUPPORTED_FILE' => sellerErrUnsupportedFile,
    'FILE_TOO_LARGE' => fileType == ImportFileType.image ? sellerErrPhotoTooLarge : sellerErrFileTooLarge,
    'EMPTY_FILE' ||
    'FILE_NOT_FOUND' ||
    'INVALID_FILE_PATH' ||
    'SPREADSHEET_UNREADABLE' ||
    'EMPTY_SPREADSHEET' => sellerImportErrFile,
    // 太长：分成几份
    'TOO_MANY_ROWS' || 'AI_TRUNCATED' => sellerImportErrTruncated,
    'AI_TIMEOUT' => sellerImportErrTimeout,
    // AI 读不到
    'AI_REFUSED' => sellerImportErrRefused,
    // 网络、服务（不是照片的问题，过一会儿再试）
    'AI_BUSY' ||
    'AI_UNAVAILABLE' ||
    'AI_FAILED' ||
    'AI_AUTH_FAILED' ||
    'AI_REQUEST_REJECTED' ||
    'AI_NOT_CONFIGURED' ||
    'DOWNLOAD_FAILED' ||
    'DB_ERROR' ||
    'INTERNAL_ERROR' ||
    'START_FAILED' => sellerImportErrService,
    'QUOTA_UNAVAILABLE' => sellerErrQuotaUnavailable,
    'WHOLESALER_SUSPENDED' => sellerErrSuspended,
    'NETWORK' => errNetwork,
    'AUTH' => sellerErrLoginExpired,
    // AI_INVALID_OUTPUT、NO_PRODUCTS_FOUND、不认识的：照片请拍清楚一点；Excel / PDF 拍清楚没用，请看是不是价目表
    _ =>
      fileType == ImportFileType.excel || fileType == ImportFileType.pdf
          ? sellerImportErrNoProductsFile
          : sellerErrAiFailed,
  };

  /// 库存：有货 / 快卖完 / 缺货
  String stock(StockStatus s) => switch (s) {
    StockStatus.inStock => sellerStockIn,
    StockStatus.lowStock => sellerStockLow,
    StockStatus.outOfStock => sellerStockOut,
  };

  /// 价目表的一行要做什么：新增 / 更新 / 跳过
  String importAction(ImportRowAction a) => switch (a) {
    ImportRowAction.create => sellerActionCreate,
    ImportRowAction.update => sellerActionUpdate,
    ImportRowAction.skip => sellerActionSkip,
  };

  /// 3 箱 / 3 cartons / 1 carton
  String qtyUnit(int qty, SellUnit u) => sellerSummaryQty(qty, qty == 1 ? unit(u) : unitPlural(u));

  /// 单位的复数（英文 cartons；中文、马来文跟单数一样）
  String unitPlural(SellUnit u) => sellerUnitPlural(sellUnitCode(u));

  // ---------- 日期（全部按马来西亚时间显示） ----------

  /// 11月26日周四 / Thu, Nov 26 / Kha, 26 Nov
  String date(DateTime d) => DateFormat.MMMEd(localeName).format(d);

  /// 11月26日 14:30
  String dateTime(DateTime d) => DateFormat.MMMd(localeName).add_Hm().format(toMyt(d));

  String dateOnly(DateTime d) => DateFormat.MMMd(localeName).format(toMyt(d));

  /// 2026年10月 / Oct 2026（账单的月份）
  String month(DateTime d) => DateFormat.yMMM(localeName).format(d);

  /// 账单状态
  String invoiceStatus(String s) => switch (s) {
    'issued' => invoiceIssued,
    'overdue' => invoiceOverdue,
    'paid' => invoicePaid,
    'void' => invoiceVoid,
    _ => invoiceDraft,
  };

  String paymentMethod(PaymentMethod? m) => switch (m) {
    PaymentMethod.fpx => payMethodFpx,
    PaymentMethod.duitnow => payMethodDuitnow,
    PaymentMethod.ewallet => payMethodEwallet,
    PaymentMethod.card => payMethodCard,
    _ => payMethodOther,
  };
}

/// 服务器的时间是 UTC，马来西亚是 UTC+8（没有夏令时）
DateTime toMyt(DateTime d) {
  final utc = d.toUtc();
  return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute).add(const Duration(hours: 8));
}
