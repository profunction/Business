import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_admin/app/file_saver.dart';
import 'package:jb_admin/app/providers.dart';
import 'package:jb_admin/demo/demo_api.dart';
import 'package:jb_admin/demo/demo_session.dart';
import 'package:jb_admin/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用的下载：记下档名和内容，不会真的下载
class FakeSaver implements FileSaver {
  final files = <String, Uint8List>{};

  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async {
    files[fileName] = bytes;
    return true;
  }
}

const desktop = Size(1440, 1000);
const tablet = Size(820, 1180);

/// 用示范模式开客服后台（不连服务器）。loggedIn = false 从登录开始
Future<({DemoAdminApi api, FakeSaver saver})> pumpAdmin(
  WidgetTester tester, {
  Size size = desktop,
  bool loggedIn = true,
  bool notAdmin = false,
  String locale = 'zh',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'admin_locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final api = DemoAdminApi(notAdmin: notAdmin, delay: const Duration(milliseconds: 10))..loggedIn = loggedIn;
  final session = DemoSession(api: api, prefs: prefs);
  final saver = FakeSaver();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => session),
        fileSaverProvider.overrideWithValue(saver),
      ],
      child: AdminApp(session: session, demo: true),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, saver: saver);
}

/// 按左边的导航
Future<void> goTo(WidgetTester tester, String path) async {
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

/// 对话框的输入框打字，按「确定」
Future<void> fillDialog(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('dialog-field')), text);
  await tester.tap(find.byKey(const Key('dialog-ok')));
  await tester.pumpAndSettle();
}
