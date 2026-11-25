import '../json.dart';
import 'common.dart';

enum UserRole { buyer, seller, admin }

UserRole userRoleFrom(Object? v) => switch (v?.toString()) {
  'seller' => UserRole.seller,
  'admin' => UserRole.admin,
  _ => UserRole.buyer,
};

class Profile {
  const Profile({required this.id, required this.role, this.fullName, this.phone, required this.locale});

  factory Profile.fromJson(Json j) => Profile(
    id: j['id'] as String,
    role: userRoleFrom(j['role']),
    fullName: asStringOrNull(j['full_name']),
    phone: asStringOrNull(j['phone']),
    locale: asStringOrNull(j['locale']) ?? 'zh',
  );

  final String id;
  final UserRole role;
  final String? fullName;
  final String? phone;
  final String locale;
}

class MyShop {
  const MyShop({required this.id, required this.name, required this.zoneId, required this.isOwner});

  factory MyShop.fromJson(Json j) => MyShop(
    id: j['id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    zoneId: asStringOrNull(j['zone_id']) ?? '',
    isOwner: j['member_role'] == 'owner',
  );

  final String id;
  final String name;
  final String zoneId;
  final bool isOwner;
}

class MyWholesaler {
  const MyWholesaler({required this.id, required this.name, required this.status});

  factory MyWholesaler.fromJson(Json j) => MyWholesaler(
    id: j['id'] as String,
    name: asStringOrNull(j['name']) ?? '',
    status: asStringOrNull(j['status']) ?? 'pending',
  );

  final String id;
  final String name;

  /// pending / active / suspended
  final String status;
}

/// get_my_context()：登录后我是谁、我有哪些店和批发商
class MyContext {
  const MyContext({required this.profile, required this.shops, required this.wholesalers});

  factory MyContext.fromJson(Json j) => MyContext(
    profile: Profile.fromJson(asJson(j['profile'])),
    shops: asJsonList(j['shops']).map(MyShop.fromJson).toList(),
    wholesalers: asJsonList(j['wholesalers']).map(MyWholesaler.fromJson).toList(),
  );

  final Profile profile;
  final List<MyShop> shops;
  final List<MyWholesaler> wholesalers;
}

enum SubscriptionState { trialing, active, pastDue, lapsed, none }

SubscriptionState subscriptionStateFrom(Object? v) => switch (v?.toString()) {
  'trialing' => SubscriptionState.trialing,
  'active' => SubscriptionState.active,
  'past_due' => SubscriptionState.pastDue,
  'lapsed' => SubscriptionState.lapsed,
  _ => SubscriptionState.none,
};

/// get_subscription_status()
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.hasFullAccess,
    required this.state,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.graceUntil,
    this.lockedPriceSen,
    required this.isFoundingPrice,
    this.currentPriceSen,
    required this.freeUnlockedLimit,
    required this.unlockedWholesalerIds,
    this.unlocksChangeAllowedAt,
  });

  factory SubscriptionInfo.fromJson(Json j) {
    final sub = asJsonOrNull(j['subscription']);
    return SubscriptionInfo(
      hasFullAccess: asBool(j['has_full_access']),
      state: sub == null ? SubscriptionState.none : subscriptionStateFrom(sub['status']),
      trialEndsAt: asDateTimeOrNull(sub?['trial_ends_at']),
      currentPeriodEnd: asDateTimeOrNull(sub?['current_period_end']),
      graceUntil: asDateTimeOrNull(sub?['grace_until']),
      lockedPriceSen: asIntOrNull(sub?['locked_price_sen']),
      isFoundingPrice: asBool(sub?['is_founding_price']),
      currentPriceSen: asIntOrNull(j['current_price_sen']),
      freeUnlockedLimit: asInt(j['free_unlocked_limit'], 3),
      unlockedWholesalerIds: asStringList(j['unlocked_wholesaler_ids']),
      unlocksChangeAllowedAt: asDateTimeOrNull(j['unlocks_change_allowed_at']),
    );
  }

  final bool hasFullAccess;
  final SubscriptionState state;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? graceUntil;
  final int? lockedPriceSen;
  final bool isFoundingPrice;
  final int? currentPriceSen;
  final int freeUnlockedLimit;
  final List<String> unlockedWholesalerIds;

  /// 什么时候可以再换「免费可看的批发商」；null 表示现在就可以
  final DateTime? unlocksChangeAllowedAt;

  bool get isTrial => state == SubscriptionState.trialing && hasFullAccess;

  /// 试用还剩几天（向上取整）；不是试用中就是 null
  int? trialDaysLeft(DateTime now) {
    if (!isTrial || trialEndsAt == null) return null;
    final hours = trialEndsAt!.difference(now).inHours;
    return hours <= 0 ? 0 : (hours / 24).ceil();
  }

  bool canChangeUnlocks(DateTime now) => unlocksChangeAllowedAt == null || !unlocksChangeAllowedAt!.isAfter(now);
}

class LastCheckout {
  const LastCheckout({
    required this.id,
    required this.createdAt,
    required this.totalSen,
    required this.itemCount,
    required this.wholesalerNames,
  });

  factory LastCheckout.fromJson(Json j) => LastCheckout(
    id: j['id'] as String,
    createdAt: asDateTimeOrNull(j['created_at']) ?? DateTime.now(),
    totalSen: asInt(j['total_sen']),
    itemCount: asInt(j['item_count']),
    wholesalerNames: asStringList(j['wholesaler_names']),
  );

  final String id;
  final DateTime createdAt;
  final int totalSen;
  final int itemCount;
  final List<String> wholesalerNames;
}

/// get_buyer_home()
class BuyerHome {
  const BuyerHome({
    required this.shopId,
    required this.shopName,
    required this.shopType,
    required this.zoneName,
    required this.subscription,
    required this.cartCount,
    required this.activeOrderCount,
    this.lastCheckout,
  });

  factory BuyerHome.fromJson(Json j) {
    final shop = asJson(j['shop']);
    final last = asJsonOrNull(j['last_checkout']);
    return BuyerHome(
      shopId: shop['id'] as String,
      shopName: asStringOrNull(shop['name']) ?? '',
      shopType: shopTypeFrom(shop['shop_type']),
      zoneName: LocalizedName.fromJson(shop['zone_name']),
      subscription: SubscriptionInfo.fromJson(asJson(j['subscription'])),
      cartCount: asInt(j['cart_count']),
      activeOrderCount: asInt(j['active_order_count']),
      lastCheckout: last == null ? null : LastCheckout.fromJson(last),
    );
  }

  final String shopId;
  final String shopName;
  final ShopType shopType;
  final LocalizedName zoneName;
  final SubscriptionInfo subscription;
  final int cartCount;
  final int activeOrderCount;
  final LastCheckout? lastCheckout;
}
