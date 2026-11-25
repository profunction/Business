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
      'AUTH' => errAuth,
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
      'FILE_TOO_LARGE' => sellerErrFileTooLarge,
      'NO_PERMISSION' => sellerErrNoPermission,
      'IMPORT_TIMEOUT' => sellerErrImportTimeout,
      'IMPORT_NOT_IN_REVIEW' || 'IMPORT_NOT_PROCESSING' || 'IMPORT_ALREADY_APPLIED' => sellerErrImportDone,
      'IMPORT_ROW_INCOMPLETE' => sellerErrRowIncomplete(_row(e)),
      'IMPORT_ROW_INVALID_PRODUCT' => sellerErrRowInvalidProduct(_row(e)),
      'IMPORT_DUPLICATE_PRODUCT' => sellerErrDuplicateProduct(_row(e)),
      'IMPORT_NOT_FOUND' || 'PRODUCT_NOT_FOUND' || 'WHOLESALER_NOT_FOUND' || 'NOT_FOUND' => sellerErrNotFound,
      _ => errUnknown,
    };
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

  /// 价目表 AI 读失败的原因（price_list_imports.error_message，parse-price-list 写的英文代码）
  String importFailure(String? code) => switch (code) {
    'UNSUPPORTED_FILE' => sellerErrUnsupportedFile,
    'FILE_TOO_LARGE' => sellerErrFileTooLarge,
    'AI_REFUSED' => sellerImportErrRefused,
    'AI_TRUNCATED' => sellerImportErrTruncated,
    'START_FAILED' || 'NETWORK' => errNetwork,
    _ => sellerErrAiFailed, // 其他（看不清楚、服务器出错……）
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

  /// 3 箱
  String qtyUnit(int qty, SellUnit u) => sellerSummaryQty(qty, unit(u));

  // ---------- 日期（全部按马来西亚时间显示） ----------

  /// 11月26日周四 / Thu, Nov 26 / Kha, 26 Nov
  String date(DateTime d) => DateFormat.MMMEd(localeName).format(d);

  /// 11月26日 14:30
  String dateTime(DateTime d) => DateFormat.MMMd(localeName).add_Hm().format(toMyt(d));

  String dateOnly(DateTime d) => DateFormat.MMMd(localeName).format(toMyt(d));
}

/// 服务器的时间是 UTC，马来西亚是 UTC+8（没有夏令时）
DateTime toMyt(DateTime d) {
  final utc = d.toUtc();
  return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute).add(const Duration(hours: 8));
}
