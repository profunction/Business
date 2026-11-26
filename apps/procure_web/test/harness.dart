import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_procure/app/providers.dart';
import 'package:jb_procure/app/url_opener.dart';
import 'package:jb_procure/demo/demo_api.dart';
import 'package:jb_procure/demo/demo_session.dart';
import 'package:jb_procure/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用的「开新分页」：记下网址
class FakeOpener implements UrlOpener {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

const desktop = Size(1280, 900);
const phone = Size(400, 860);

/// 用示范模式开公司采购网页（不连服务器）。loggedIn = false 从登录开始
Future<({DemoProcureApi api, FakeOpener opener})> pumpProcure(
  WidgetTester tester, {
  Size size = desktop,
  bool loggedIn = true,
  String? role,
  bool noCompany = false,
  bool seller = false,
  String locale = 'zh',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'procure_locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final api = DemoProcureApi(role: role, noCompany: noCompany, seller: seller, delay: const Duration(milliseconds: 10))
    ..loggedIn = loggedIn;
  final session = DemoSession(api: api, prefs: prefs);
  final opener = FakeOpener();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => session),
        urlOpenerProvider.overrideWithValue(opener),
      ],
      child: ProcureApp(session: session, demo: true),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, opener: opener);
}

/// 按导航（手机宽度先打开左上角的选单）
Future<void> goTo(WidgetTester tester, String path) async {
  final menu = find.byIcon(Icons.menu);
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(Key('nav-$path')));
  await tester.pumpAndSettle();
}

/// 按一个东西（先滚到看得到）
Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// 滚回最上面（ListView 里看不到的东西不会建出来）
Future<void> scrollTop(WidgetTester tester) async {
  final list = find.byType(ListView);
  if (list.evaluate().isEmpty) return;
  await tester.drag(list.first, const Offset(0, 4000));
  await tester.pumpAndSettle();
}
