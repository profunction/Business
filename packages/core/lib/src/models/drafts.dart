import '../json.dart';
import 'common.dart';
import 'orders.dart';

/// 草稿从哪里来：App 语音 / WhatsApp 文字 / WhatsApp 语音 / 客服
enum DraftSource { appVoice, whatsappText, whatsappVoice, admin }

DraftSource draftSourceFrom(Object? v) => switch (v?.toString()) {
  'app_voice' => DraftSource.appVoice,
  'whatsapp_text' => DraftSource.whatsappText,
  'whatsapp_voice' => DraftSource.whatsappVoice,
  _ => DraftSource.admin,
};

extension DraftSourceX on DraftSource {
  bool get isWhatsapp => this == DraftSource.whatsappText || this == DraftSource.whatsappVoice;
}

enum DraftStatus { pendingReview, confirmed, rejected }

DraftStatus draftStatusFrom(Object? v) => switch (v?.toString()) {
  'confirmed' => DraftStatus.confirmed,
  'rejected' => DraftStatus.rejected,
  _ => DraftStatus.pendingReview,
};

String draftStatusCode(DraftStatus s) => switch (s) {
  DraftStatus.pendingReview => 'pending_review',
  DraftStatus.confirmed => 'confirmed',
  DraftStatus.rejected => 'rejected',
};

/// AI 对不上商品的一句话
class UnmatchedPhrase {
  const UnmatchedPhrase({required this.said, this.reason = ''});

  factory UnmatchedPhrase.fromJson(Json j) =>
      UnmatchedPhrase(said: asStringOrNull(j['said']) ?? '', reason: asStringOrNull(j['reason']) ?? '');

  final String said;
  final String reason;

  /// AI 说这是一句要客服 / 老板看的话（「十点前送」），不是商品
  bool get isNote => reason == 'note';

  Json toJson() => {'said': said, 'reason': reason};
}

/// 草稿的一行（get_order_draft 的 items）
class DraftItem {
  const DraftItem({
    required this.productId,
    required this.qty,
    this.id,
    this.said,
    this.confidence,
    this.productName = '',
    this.unit = SellUnit.unknown,
    this.packQty = 1,
    this.minOrderQty = 1,
    this.stockStatus = StockStatus.inStock,
    this.wholesalerId = '',
    this.wholesalerName = '',
    this.unitPriceSen,
    this.orderable = true,
  });

  factory DraftItem.fromJson(Json j) => DraftItem(
    id: asStringOrNull(j['id']),
    productId: j['product_id'] as String,
    qty: asInt(j['qty'], 1),
    said: asStringOrNull(j['said']),
    confidence: asDoubleOrNull(j['confidence']),
    productName: asStringOrNull(j['product_name']) ?? '',
    unit: sellUnitFrom(j['unit']),
    packQty: asInt(j['pack_qty'], 1),
    minOrderQty: asInt(j['min_order_qty'], 1),
    stockStatus: stockStatusFrom(j['stock_status']),
    wholesalerId: asStringOrNull(j['wholesaler_id']) ?? '',
    wholesalerName: asStringOrNull(j['wholesaler_name']) ?? '',
    unitPriceSen: asIntOrNull(j['unit_price_sen']),
    orderable: asBool(j['orderable'], true),
  );

  final String? id;
  final String productId;
  final int qty;

  /// 老板原本怎么说
  final String? said;

  /// AI 有多确定（人加的是 null）
  final double? confidence;
  final String productName;
  final SellUnit unit;
  final int packQty;
  final int minOrderQty;
  final StockStatus stockStatus;
  final String wholesalerId;
  final String wholesalerName;

  /// 看不到价钱的批发商：null
  final int? unitPriceSen;
  final bool orderable;

  /// AI 不太确定（要老板看一下）
  bool get isUnsure => confidence != null && confidence! < 0.7;

  DraftItem copyWith({int? qty}) => DraftItem(
    id: id,
    productId: productId,
    qty: qty ?? this.qty,
    said: said,
    confidence: confidence,
    productName: productName,
    unit: unit,
    packQty: packQty,
    minOrderQty: minOrderQty,
    stockStatus: stockStatus,
    wholesalerId: wholesalerId,
    wholesalerName: wholesalerName,
    unitPriceSen: unitPriceSen,
    orderable: orderable,
  );

  /// save_order_draft 要的格式
  Json toSaveJson() => {
    'product_id': productId,
    'qty': qty,
    if (said != null) 'said': said,
    if (confidence != null) 'confidence': confidence,
  };
}

/// get_order_draft()
class OrderDraft {
  const OrderDraft({
    required this.id,
    required this.shopId,
    required this.source,
    required this.status,
    required this.items,
    this.shopName = '',
    this.transcript,
    this.language,
    this.unmatched = const [],
    this.createdAt,
    this.checkoutId,
    this.rejectReason,
    this.hasAudio = false,
    this.senderPhone,
    this.whatsappWindowOpen,
    this.errorCode,
    this.quote,
  });

  factory OrderDraft.fromJson(Json j) {
    final quote = asJsonOrNull(j['quote']);
    return OrderDraft(
      id: j['id'] as String,
      shopId: asStringOrNull(j['shop_id']) ?? '',
      shopName: asStringOrNull(j['shop_name']) ?? '',
      source: draftSourceFrom(j['source']),
      status: draftStatusFrom(j['status']),
      transcript: asStringOrNull(j['transcript']),
      language: asStringOrNull(j['language']),
      unmatched: asJsonList(j['unmatched']).map(UnmatchedPhrase.fromJson).toList(),
      createdAt: asDateTimeOrNull(j['created_at']),
      checkoutId: asStringOrNull(j['checkout_id']),
      rejectReason: asStringOrNull(j['reject_reason']),
      hasAudio: asBool(j['has_audio']),
      senderPhone: asStringOrNull(j['sender_phone']),
      whatsappWindowOpen: j['whatsapp_window_open'] == null ? null : asBool(j['whatsapp_window_open']),
      errorCode: asStringOrNull(j['error_code']),
      items: asJsonList(j['items']).map(DraftItem.fromJson).toList(),
      quote: quote == null ? null : CartQuote.fromJson(quote),
    );
  }

  final String id;
  final String shopId;
  final String shopName;
  final DraftSource source;
  final DraftStatus status;

  /// 语音转出来的文字 / WhatsApp 原文
  final String? transcript;
  final String? language;
  final List<UnmatchedPhrase> unmatched;
  final DateTime? createdAt;
  final String? checkoutId;
  final String? rejectReason;
  final bool hasAudio;

  /// 只有客服看得到
  final String? senderPhone;

  /// WhatsApp 的 24 小时窗口还开着（客服：可以用 WhatsApp 回）；不是 WhatsApp 的 / 不是客服：null
  final bool? whatsappWindowOpen;

  /// 语音转文字 / AI 失败的原因（客服看）
  final String? errorCode;
  final List<DraftItem> items;

  /// 待确认的才有：照现在的草稿算的报价
  final CartQuote? quote;

  bool get isPending => status == DraftStatus.pendingReview;
}

/// list_order_drafts() / admin_list_order_drafts() 的一行
class DraftSummary {
  const DraftSummary({
    required this.id,
    required this.source,
    required this.status,
    required this.itemCount,
    required this.unmatchedCount,
    this.createdAt,
    this.transcript,
    this.shopId,
    this.shopName,
    this.shopPhone,
    this.senderPhone,
    this.errorCode,
    this.whatsappWindowOpen,
  });

  factory DraftSummary.fromJson(Json j) => DraftSummary(
    id: j['id'] as String,
    source: draftSourceFrom(j['source']),
    status: draftStatusFrom(j['status']),
    itemCount: asInt(j['item_count']),
    unmatchedCount: asInt(j['unmatched_count']),
    createdAt: asDateTimeOrNull(j['created_at']),
    transcript: asStringOrNull(j['transcript']),
    shopId: asStringOrNull(j['shop_id']),
    shopName: asStringOrNull(j['shop_name']),
    shopPhone: asStringOrNull(j['shop_phone']),
    senderPhone: asStringOrNull(j['sender_phone']),
    errorCode: asStringOrNull(j['error_code']),
    whatsappWindowOpen: j['whatsapp_window_open'] == null ? null : asBool(j['whatsapp_window_open']),
  );

  final String id;
  final DraftSource source;
  final DraftStatus status;
  final int itemCount;
  final int unmatchedCount;
  final DateTime? createdAt;
  final String? transcript;
  final String? shopId;
  final String? shopName;
  final String? shopPhone;
  final String? senderPhone;
  final String? errorCode;
  final bool? whatsappWindowOpen;
}

/// submit_order_draft()
class DraftSubmitResult {
  const DraftSubmitResult({required this.checkoutId, required this.orderNos, required this.totalSen, this.draft});

  factory DraftSubmitResult.fromJson(Json j) {
    final d = asJsonOrNull(j['draft']);
    return DraftSubmitResult(
      checkoutId: j['checkout_id'] as String,
      orderNos: asStringOrNull(j['order_nos']) ?? '',
      totalSen: asInt(j['total_sen']),
      draft: d == null ? null : OrderDraft.fromJson(d),
    );
  }

  final String checkoutId;

  /// 「JHB261129-00001, JHB261129-00002」
  final String orderNos;
  final int totalSen;
  final OrderDraft? draft;
}
