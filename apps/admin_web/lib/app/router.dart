import 'package:go_router/go_router.dart';

import '../features/audit/audit_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/status_pages.dart';
import '../features/commission/commission_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/orders/followup_page.dart';
import '../features/orders/order_detail_page.dart';
import '../features/orders/orders_page.dart';
import '../features/place_order/place_order_page.dart';
import '../features/subscriptions/subscriptions_page.dart';
import '../features/wholesalers/products_page.dart';
import '../features/wholesalers/wholesalers_page.dart';
import '../widgets/shell.dart';
import 'session.dart';

/// 没登录 → /login；读取中 → /loading；不是客服 → /denied；客服 → 后台的页面
GoRouter buildRouter(AdminSession session, {bool demo = false}) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.uri.path;
      return switch (session.stage) {
        AdminStage.loggedOut => path.startsWith('/login') ? null : '/login',
        AdminStage.loading || AdminStage.error => path == '/loading' ? null : '/loading',
        AdminStage.denied => path == '/denied' ? null : '/denied',
        AdminStage.ready =>
          path == '/' || path.startsWith('/login') || path == '/loading' || path == '/denied' ? '/dashboard' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
        routes: [
          GoRoute(
            path: 'otp',
            builder: (_, state) => OtpPage(phone: state.uri.queryParameters['phone'] ?? ''),
          ),
        ],
      ),
      GoRoute(path: '/loading', builder: (_, _) => const LoadingPage()),
      GoRoute(path: '/denied', builder: (_, _) => const DeniedPage()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.uri.path, demo: demo, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
          GoRoute(
            path: '/orders',
            builder: (_, state) => OrdersPage(
              initialWholesalerId: state.uri.queryParameters['wholesaler'],
              initialShopId: state.uri.queryParameters['shop'],
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => OrderDetailPage(orderId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/followup', builder: (_, _) => const FollowupPage()),
          GoRoute(
            path: '/place-order',
            builder: (_, state) => PlaceOrderPage(initialShopId: state.uri.queryParameters['shop']),
          ),
          GoRoute(
            path: '/wholesalers',
            builder: (_, state) => WholesalersPage(pendingOnly: state.uri.queryParameters['status'] == 'pending'),
            routes: [
              GoRoute(
                path: ':id/products',
                builder: (_, state) => ProductsPage(
                  wholesalerId: state.pathParameters['id']!,
                  wholesalerName: state.uri.queryParameters['name'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(path: '/subscriptions', builder: (_, _) => const SubscriptionsPage()),
          GoRoute(path: '/commission', builder: (_, _) => const CommissionPage()),
          GoRoute(path: '/audit', builder: (_, _) => const AuditPage()),
        ],
      ),
    ],
  );
}
