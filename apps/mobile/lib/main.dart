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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  final api = WholesaleApi(Supabase.instance.client);
  final session = SessionController(api: api, prefs: prefs);

  runApp(
    ProviderScope(
      // 出错时不要自动一直重试，让老板自己按「再试一次」
      retry: (_, _) => null,
      overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
      child: WholesaleApp(session: session),
    ),
  );
}

class WholesaleApp extends ConsumerStatefulWidget {
  const WholesaleApp({super.key, required this.session});

  final SessionController session;

  @override
  ConsumerState<WholesaleApp> createState() => _WholesaleAppState();
}

class _WholesaleAppState extends ConsumerState<WholesaleApp> {
  late final GoRouter _router = buildRouter(widget.session);

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(sessionProvider.select((s) => s.localeCode));
    return MaterialApp.router(
      onGenerateTitle: (context) => L10n.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: code == null ? null : Locale(code),
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

/// 忘了传 SUPABASE_URL / SUPABASE_ANON_KEY 时显示（给开发的人看的，不用翻译）
class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'App 还没设定服务器。\n请用：flutter run --dart-define-from-file=config/local.json\n（见 apps/mobile/README.md）',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }
}
