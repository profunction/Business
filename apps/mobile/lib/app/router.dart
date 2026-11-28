import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../features/auth/language_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/otp_page.dart';
import '../features/auth/status_pages.dart';
import '../features/billing/invoice_page.dart';
import '../features/billing/seller_billing_page.dart';
import '../features/billing/subscription_page.dart';
import '../features/browse/browse_page.dart';
import '../features/browse/catalog_items_page.dart';
import '../features/browse/compare_page.dart';
import '../features/browse/wholesaler_products_page.dart';
import '../features/cart/cart_page.dart';
import '../features/cart/checkout_page.dart';
import '../features/cart/order_placed_page.dart';
import '../features/home/home_page.dart';
import '../features/onboarding/register_shop_page.dart';
import '../features/orders/order_detail_page.dart';
import '../features/orders/orders_page.dart';
import '../features/orders/review_page.dart';
import '../features/seller/delivery_summary_page.dart';
import '../features/seller/import_page.dart';
import '../features/seller/import_review_page.dart';
import '../features/seller/product_edit_page.dart';
import '../features/seller/products_page.dart';
import '../features/seller/seller_device.dart';
import '../features/seller/seller_home_page.dart';
import '../features/seller/seller_order_detail_page.dart';
import '../features/seller/seller_orders_page.dart';
import '../features/seller/seller_settings_page.dart';
import '../features/settings/free_wholesalers_page.dart';
import '../features/settings/settings_page.dart';
import '../features/voice/voice_draft_page.dart';
import 'buyer_shell.dart';
import 'seller_providers.dart';
import 'session.dart';

/// 这些页面只在某个阶段出现；进了别的阶段就自动跳走
const _stagePages = {
  SessionStage.chooseLanguage: '/language',
  SessionStage.loggedOut: '/login',
  SessionStage.loading: '/loading',
  SessionStage.error: '/loading',
  SessionStage.needsShop: '/register',
  SessionStage.seller: '/seller',
  SessionStage.admin: '/admin',
};

GoRouter buildRouter(SessionController session) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.uri.path;
      final stage = session.stage;
      final from = state.uri.queryParameters['from'];
      // 批发商：只能在 /seller 和底下的页面；从通知 / 链接打开的页面读完资料后回去
      if (stage == SessionStage.seller) {
        if (isSellerPath(path)) return null;
        if (path == '/loading' && _isLocalPath(from) && isSellerPath(Uri.parse(from!).path)) return from;
        return '/seller';
      }
      final target = _stagePages[stage];
      if (target != null) {
        // 登录流程里可以从 /login 去 /login/otp
        if (stage == SessionStage.loggedOut && path.startsWith('/login')) return null;
        if (path == target) return null;
        // 读取资料的时候，记住原本要去哪里（例如从通知打开某张订单），读完再回去
        if (target == '/loading' && !_stagePages.values.contains(path) && !path.startsWith('/login')) {
          return Uri(path: '/loading', queryParameters: {'from': state.uri.toString()}).toString();
        }
        return target;
      }
      // 买家不能进批发商的页面
      if (isSellerPath(path)) return '/home';
      // 买家：离开所有「阶段页面」，有记住原本要去的就回去
      if (_stagePages.values.any((p) => path == p || path.startsWith('/login'))) {
        return _isLocalPath(from) && !from!.startsWith('/loading') && !isSellerPath(Uri.parse(from).path)
            ? from
            : '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/language', builder: (_, _) => const LanguagePage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/login/otp',
        builder: (_, s) => OtpPage(phone: s.uri.queryParameters['phone'] ?? ''),
      ),
      GoRoute(path: '/loading', builder: (_, _) => const LoadingPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterShopPage()),
      // 批发商端（第四步）。全部放在 /seller 底下：从通知 / 链接直接打开 /seller/orders/<id> 时，
      // 按「返回」会回到批发商首页
      GoRoute(
        path: '/seller',
        builder: (_, _) => const SellerHomePage(),
        routes: [
          GoRoute(
            path: 'orders',
            builder: (_, s) => SellerOrdersPage(initialTab: sellerOrdersTabFrom(s.uri.queryParameters['tab'])),
          ),
          GoRoute(
            path: 'orders/:id',
            builder: (_, s) => SellerOrderDetailPage(orderId: s.pathParameters['id']!),
          ),
          GoRoute(path: 'settings', builder: (_, _) => const SellerSettingsPage()),
          GoRoute(
            path: 'billing',
            builder: (_, _) => const SellerBillingPage(),
            routes: [
              GoRoute(
                path: 'invoices/:id',
                builder: (_, s) => InvoicePage(invoiceId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'summary',
            builder: (_, s) => DeliverySummaryPage(date: s.uri.queryParameters['date']),
          ),
          GoRoute(
            path: 'products',
            builder: (_, _) => const ProductsPage(),
            routes: [
              // 'new' 要放在 ':id' 前面
              GoRoute(path: 'new', builder: (_, _) => const ProductEditPage()),
              GoRoute(
                path: ':id',
                builder: (_, s) => ProductEditPage(productId: s.pathParameters['id']),
              ),
            ],
          ),
          GoRoute(
            path: 'import',
            // ?id= 等那一份读完（从首页回来看「AI 在读」的那一份）；extra = Android 把 App 关掉前选到的价目表
            builder: (_, s) => ImportPage(
              importId: s.uri.queryParameters['id'],
              recovered: s.extra is PickedFile ? s.extra! as PickedFile : null,
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ImportReviewPage(importId: s.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/admin', builder: (_, _) => const AdminPlaceholderPage()),
      // 买家：底部导航的五个分页（各自记住状态）
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => BuyerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomePage())]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/browse',
                builder: (_, s) => BrowsePage(byWholesaler: s.uri.queryParameters['by'] == 'wholesaler'),
              ),
            ],
          ),
          StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (_, _) => const CartPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/orders', builder: (_, _) => const OrdersPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsPage())]),
        ],
      ),
      // 买家的详情页：盖在分页上面（没有底部导航），按返回回到原来的分页
      GoRoute(
        path: '/browse/items',
        builder: (_, s) => CatalogItemsPage(
          categoryId: s.uri.queryParameters['category'],
          title: s.uri.queryParameters['title'] ?? '',
          search: s.uri.queryParameters['q'],
        ),
      ),
      GoRoute(
        path: '/browse/item/:id',
        builder: (_, s) =>
            ComparePage(catalogItemId: s.pathParameters['id']!, title: s.uri.queryParameters['title'] ?? ''),
      ),
      GoRoute(
        path: '/browse/wholesaler/:id',
        builder: (_, s) =>
            WholesalerProductsPage(wholesalerId: s.pathParameters['id']!, title: s.uri.queryParameters['title'] ?? ''),
      ),
      GoRoute(
        path: '/checkout',
        builder: (_, s) => CheckoutPage(reorder: s.extra is ReorderResult ? s.extra! as ReorderResult : null),
      ),
      GoRoute(
        path: '/checkout/done',
        builder: (_, s) => OrderPlacedPage(orderCount: int.tryParse(s.uri.queryParameters['n'] ?? '') ?? 1),
      ),
      GoRoute(
        path: '/voice-draft/:id',
        builder: (_, s) => VoiceDraftPage(draftId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, s) => OrderDetailPage(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders/:id/review',
        builder: (_, s) => ReviewPage(orderId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/free-wholesalers', builder: (_, _) => const FreeWholesalersPage()),
      GoRoute(path: '/subscription', builder: (_, _) => const SubscriptionPage()),
    ],
    errorBuilder: (_, _) => session.stage == SessionStage.seller ? const SellerHomePage() : const HomePage(),
  );
}

/// 现在最上面那一页的网址（包括 push 上去的；GoRouter 的 currentConfiguration.uri 只有底下那一页）
Uri currentLocation(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.isEmpty) return config.uri;
  try {
    return router.state.uri;
  } catch (_) {
    return config.uri; // 找不到页面（errorBuilder）时
  }
}

/// 批发商端的页面：/seller 和底下的
bool isSellerPath(String path) => path == '/seller' || path.startsWith('/seller/');

/// ?from= 只接受 App 自己的页面（'/orders/x'），不接受 '//别的网站' 或完整网址
bool _isLocalPath(String? from) => from != null && from.startsWith('/') && !from.startsWith('//');

/// 登录、读取资料、开店这些「过渡」页面：从通知打开的页面要等离开这些才打开
bool isTransientPage(String path) =>
    path == '/language' || path == '/loading' || path == '/register' || path == '/admin' || path.startsWith('/login');

/// push 一个页面，带上中文 / 英文 / 马来文都可以的标题参数
extension PushX on BuildContext {
  void pushWithQuery(String path, Map<String, String?> query) {
    final q = {
      for (final e in query.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    push(Uri(path: path, queryParameters: q.isEmpty ? null : q).toString());
  }
}
