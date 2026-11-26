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

/// 公司采购网页（Flutter Web）。跑法见 apps/procure_web/README.md
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!ProcureConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Supabase.initialize(url: ProcureConfig.supabaseUrl, publishableKey: ProcureConfig.supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  final api = ProcureApi(Supabase.instance.client);
  final session = ProcureSession(api: api, prefs: prefs);
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
      child: ProcureApp(session: session),
    ),
  );
}

class ProcureApp extends ConsumerStatefulWidget {
  const ProcureApp({super.key, required this.session, this.demo = false});

  final ProcureSession session;

  /// 示范模式：上面多一条「资料是样本」
  final bool demo;

  @override
  ConsumerState<ProcureApp> createState() => _ProcureAppState();
}

class _ProcureAppState extends ConsumerState<ProcureApp> {
  late final GoRouter _router = buildRouter(widget.session, demo: widget.demo);

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(sessionProvider.select((s) => s.localeCode));
    return MaterialApp.router(
      onGenerateTitle: (context) => L10n.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: ProcureTheme.light(),
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
            '公司采购网页还没设定服务器。\n请用：flutter run -d chrome --dart-define-from-file=config/local.json\n'
            '或者先看示范模式：flutter run -d chrome -t lib/main_demo.dart（见 apps/procure_web/README.md）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
