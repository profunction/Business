import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/providers.dart';
import 'demo/demo_api.dart';
import 'demo/demo_session.dart';
import 'main.dart' show AdminApp;

/// 示范模式：不用服务器，数据是本机数据库导出的真实样本（tool/export_fixtures.sh）。按了会跟着变，但不会存。
///   flutter run -d chrome -t lib/main_demo.dart
/// 网址参数：?lang=zh|en|ms、?login=1（从登录开始，验证码 123456）、?buyer=1（登录的是老板，看「不是客服」页）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final q = Uri.base.queryParameters;
  final prefs = await SharedPreferences.getInstance();
  if (q['lang'] != null) await prefs.setString('admin_locale', q['lang']!);
  final api = DemoAdminApi(notAdmin: q['buyer'] == '1')..loggedIn = q['login'] != '1';
  final session = DemoSession(api: api, prefs: prefs);
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
      child: AdminApp(session: session, demo: true),
    ),
  );
}
