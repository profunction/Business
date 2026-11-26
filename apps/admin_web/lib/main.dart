import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholesale_core/wholesale_core.dart';

import 'app/config.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/session.dart';
import 'app/theme.dart';
import 'l10n/app_localizations.dart';

/// 客服后台（Flutter Web）。跑法见 apps/admin_web/README.md
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AdminConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Supabase.initialize(url: AdminConfig.supabaseUrl, publishableKey: AdminConfig.supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  final api = AdminApi(Supabase.instance.client);
  final session = AdminSession(api: api, prefs: prefs);
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
      child: AdminApp(session: session),
    ),
  );
}

class AdminApp extends ConsumerStatefulWidget {
  const AdminApp({super.key, required this.session, this.demo = false});

  final AdminSession session;

  /// 示范模式：上面多一条「资料是样本」
  final bool demo;

  @override
  ConsumerState<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends ConsumerState<AdminApp> {
  late final GoRouter _router = buildRouter(widget.session, demo: widget.demo);

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(sessionProvider.select((s) => s.localeCode));
    return MaterialApp.router(
      onGenerateTitle: (context) => L10n.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      locale: Locale(code),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}

/// 忘了传 SUPABASE_PUBLISHABLE_KEY 时显示（给开发的人看的，不用翻译）
class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            '客服后台还没设定服务器。\n请用：flutter run -d chrome --dart-define-from-file=config/local.json\n'
            '或者先看示范模式：flutter run -d chrome -t lib/main_demo.dart（见 apps/admin_web/README.md）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
