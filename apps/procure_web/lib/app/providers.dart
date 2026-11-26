import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'session.dart';
import 'url_opener.dart';

/// main.dart / main_demo.dart 里用真正的值覆盖
final apiProvider = Provider<ProcureApi>((ref) => throw UnimplementedError('apiProvider'));
final sessionProvider = ChangeNotifierProvider<ProcureSession>((ref) => throw UnimplementedError('sessionProvider'));

/// 开付款页（测试换成假的）
final urlOpenerProvider = Provider<UrlOpener>((ref) => platformUrlOpener());

/// 现在看的那一家公司的 id（换公司 → 下面的资料全部重读）
final currentCompanyIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider.select((s) => s.company?.id)));

final companyContextProvider = FutureProvider.autoDispose.family<CompanyContext, String>(
  (ref, id) => ref.watch(apiProvider).getCompanyContext(id),
);

final membersProvider = FutureProvider.autoDispose.family<CompanyMembers, String>(
  (ref, id) => ref.watch(apiProvider).listMembers(id),
);

final billingProvider = FutureProvider.autoDispose.family<CompanyBilling, String>(
  (ref, id) => ref.watch(apiProvider).getCompanyBilling(id),
);

final inboxProvider = FutureProvider.autoDispose<InboxPage>((ref) => ref.watch(apiProvider).listInbox(limit: 50));

final zonesProvider = FutureProvider.autoDispose<List<Zone>>((ref) => ref.watch(apiProvider).listZones());

final regionsProvider = FutureProvider.autoDispose<List<Region>>((ref) => ref.watch(apiProvider).listRegions());

typedef OfferQuery = ({String shopId, String search});

/// 比价：分店的 id 当 shop_id 叫 get_offers（价钱看公司的订阅）
final offersProvider = FutureProvider.autoDispose.family<List<Offer>, OfferQuery>(
  (ref, q) => ref.watch(apiProvider).getOffers(q.shopId, search: q.search.trim().isEmpty ? null : q.search.trim()),
);
