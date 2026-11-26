import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/auth/status_pages.dart';
import '../features/billing/billing_page.dart';
import '../features/browse/browse_page.dart';
import '../features/company/company_page.dart';
import '../features/home/home_page.dart';
import '../features/inbox/inbox_page.dart';
import '../features/members/members_page.dart';
import '../features/sites/sites_page.dart';
import '../widgets/shell.dart';
import 'session.dart';

/// 没登录 → /login；读取中 → /loading；批发商账号 → /denied；还没有公司 → /register；有公司 → 网页的页面
GoRouter buildRouter(ProcureSession session, {bool demo = false}) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.uri.path;
      return switch (session.stage) {
        ProcureStage.loggedOut => path.startsWith('/login') ? null : '/login',
        ProcureStage.loading || ProcureStage.error => path == '/loading' ? null : '/loading',
        ProcureStage.denied => path == '/denied' ? null : '/denied',
        ProcureStage.noCompany => path == '/register' ? null : '/register',
        ProcureStage.ready =>
          path == '/' || path.startsWith('/login') || path == '/loading' || path == '/denied' ? '/home' : null,
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
      GoRoute(path: '/register', builder: (_, _) => const RegisterCompanyPage()),
      ShellRoute(
        builder: (context, state, child) => ProcureShell(location: state.uri.path, demo: demo, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomePage()),
          GoRoute(path: '/browse', builder: (_, _) => const BrowsePage()),
          GoRoute(path: '/sites', builder: (_, _) => const SitesPage()),
          GoRoute(path: '/members', builder: (_, _) => const MembersPage()),
          GoRoute(path: '/billing', builder: (_, _) => const BillingPage()),
          GoRoute(path: '/inbox', builder: (_, _) => const InboxPage()),
          GoRoute(path: '/company', builder: (_, _) => const CompanyPage()),
        ],
      ),
    ],
  );
}
