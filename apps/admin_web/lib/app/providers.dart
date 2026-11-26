import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'config.dart';
import 'file_saver.dart';
import 'session.dart';

/// main.dart / main_demo.dart 里用真正的值覆盖
final apiProvider = Provider<AdminApi>((ref) => throw UnimplementedError('apiProvider'));
final sessionProvider = ChangeNotifierProvider<AdminSession>((ref) => throw UnimplementedError('sessionProvider'));

/// 下载 CSV / PDF（测试换成假的）
final fileSaverProvider = Provider<FileSaver>((ref) => platformFileSaver());

/// 账单上的公司资料（--dart-define）
final invoiceCompanyProvider = Provider<InvoiceCompany>((ref) => InvoiceCompany.fromEnvironment);

final dashboardProvider = FutureProvider.autoDispose<AdminDashboard>((ref) => ref.watch(apiProvider).getDashboard());

final ordersPageProvider = FutureProvider.autoDispose.family<AdminOrderPage, AdminOrderFilter>(
  (ref, filter) => ref.watch(apiProvider).listAllOrders(filter),
);

final orderDetailProvider = FutureProvider.autoDispose.family<OrderDetail, String>(
  (ref, id) => ref.watch(apiProvider).getOrder(id),
);

final shopsProvider = FutureProvider.autoDispose.family<List<AdminShop>, String>(
  (ref, search) => ref.watch(apiProvider).listShops(search: search.trim().isEmpty ? null : search.trim()),
);

typedef WholesalerQuery = ({WholesalerStatus? status, String search});

final wholesalersProvider = FutureProvider.autoDispose.family<List<AdminWholesaler>, WholesalerQuery>(
  (ref, q) => ref
      .watch(apiProvider)
      .listAllWholesalers(status: q.status, search: q.search.trim().isEmpty ? null : q.search.trim()),
);

final productsProvider = FutureProvider.autoDispose.family<List<SellerProduct>, String>(
  (ref, wholesalerId) => ref.watch(apiProvider).listProductsAsAdmin(wholesalerId),
);

typedef OfferQuery = ({String shopId, String search});

final offersProvider = FutureProvider.autoDispose.family<List<Offer>, OfferQuery>(
  (ref, q) => ref.watch(apiProvider).getOffers(q.shopId, search: q.search.trim().isEmpty ? null : q.search.trim()),
);

final quoteProvider = FutureProvider.autoDispose.family<CartQuote, String>(
  (ref, shopId) => ref.watch(apiProvider).quoteCart(shopId),
);

typedef SubscriptionQuery = ({SubscriptionState? state, bool foundingOnly, String search});

final subscriptionsProvider = FutureProvider.autoDispose.family<List<AdminSubscription>, SubscriptionQuery>(
  (ref, q) => ref
      .watch(apiProvider)
      .listSubscriptions(
        state: q.state,
        foundingOnly: q.foundingOnly,
        search: q.search.trim().isEmpty ? null : q.search.trim(),
      ),
);

/// key = 那个月的 1 号
final commissionReportProvider = FutureProvider.autoDispose.family<CommissionReport, DateTime>(
  (ref, month) => ref.watch(apiProvider).getCommissionReport(month: month),
);
