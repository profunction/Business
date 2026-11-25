import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/providers.dart';
import 'demo/demo_api.dart';
import 'demo/demo_session.dart';
import 'main.dart' show WholesaleApp;

/// 示范模式：不用服务器，数据是本机数据库导出的真实样本。用来看画面、截图。
///   flutter run -t lib/main_demo.dart
/// 网页版可以加参数：?lang=zh|en|ms（不加 = 先选语言）、?free=1（未付费老板）、?new=1（还没开店）、?login=1（从登录开始）、
/// ?seller=1（用示范批发商 A 的账号，进批发商端）、?pending=1（批发商还在等客服审核）、?staff=1（批发商的员工）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final q = Uri.base.queryParameters;
  final prefs = await SharedPreferences.getInstance();
  if (q['lang'] != null) {
    await prefs.setString('locale', q['lang']!);
  } else {
    await prefs.remove('locale');
  }
  final api = DemoApi(freeUser: q['free'] == '1', newUser: q['new'] == '1', seller: q['seller'] == '1')
    ..loggedIn = q['login'] != '1';
  if (q['pending'] == '1') api.sellerData.wholesalerStatus = 'pending';
  if (q['staff'] == '1') api.sellerData.memberRole = 'staff';
  final session = DemoSession(api: api, prefs: prefs);
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [apiProvider.overrideWithValue(api), sessionProvider.overrideWith((ref) => session)],
      child: WholesaleApp(session: session),
    ),
  );
}
