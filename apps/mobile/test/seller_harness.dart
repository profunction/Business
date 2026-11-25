// 批发商端的 widget 测试共用：用示范模式（DemoApi(seller: true)）开 App，手机宽度 400。
// 手机功能（拍照、选文件、分享、打印、打电话）全部换成假的，不会碰到 platform channel。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jb_wholesale/app/providers.dart';
import 'package:jb_wholesale/demo/demo_api.dart';
import 'package:jb_wholesale/demo/demo_session.dart';
import 'package:jb_wholesale/features/seller/seller_device.dart';
import 'package:jb_wholesale/main.dart';
import 'package:jb_wholesale/push/push_service.dart';
import 'package:jb_wholesale/widgets/common.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// 假的手机功能：下一次拍照 / 选照片 / 选文件回传什么；记下分享的文字和打印的 PDF
class FakeDevice implements SellerDevice {
  final calls = <String>[];
  PickedFile? nextImage;
  PickedFile? nextFile;
  Object? pickError;
  final shared = <String>[];
  final printed = <Uint8List>[];

  @override
  Future<PickedFile?> pickImage(PickSource source, {double maxWidth = 2576, int imageQuality = 85}) async {
    calls.add('pickImage ${source.name} ${maxWidth.round()} $imageQuality');
    if (pickError != null) throw pickError!;
    return nextImage;
  }

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    calls.add('pickFile ${extensions.join(',')}');
    if (pickError != null) throw pickError!;
    return nextFile;
  }

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    calls.add('share $subject');
    shared.add(text);
  }

  @override
  Future<void> printPdf({required String name, required Future<Uint8List> Function(PdfPageFormat format) build}) async {
    calls.add('print $name');
    printed.add(await build(PdfPageFormat.a4));
  }
}

class FakePush implements PushService {
  PushPermission status = PushPermission.notDetermined;
  PushPermission answer = PushPermission.granted;
  final calls = <String>[];

  @override
  bool get isEnabled => true;

  @override
  Stream<Map<String, String>> get taps => const Stream.empty();

  @override
  Future<void> registerDevice({String? localeCode}) async {}

  @override
  Future<void> unregisterDevice() async {}

  @override
  Future<void> setLocale(String localeCode) async {}

  @override
  Future<PushPermission> permissionStatus() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    calls.add('ask');
    return status = answer;
  }
}

Future<DemoApi> startSeller(
  WidgetTester tester, {
  String locale = 'zh',
  String status = 'active',
  String role = 'owner',
  PushService? push,
  SellerDevice? device,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'locale': locale, 'push_permission_asked': true});
  final prefs = await SharedPreferences.getInstance();
  final api = DemoApi(seller: true);
  api.sellerData
    ..wholesalerStatus = status
    ..memberRole = role;
  final p = push ?? const NoopPushService();
  final session = DemoSession(api: api, prefs: prefs, push: p);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => session),
        pushServiceProvider.overrideWithValue(p),
        sellerDeviceProvider.overrideWithValue(device ?? FakeDevice()),
      ],
      child: WholesaleApp(session: session, push: p),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return api;
}

GoRouter routerOf(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig! as GoRouter;

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// 按左上角的返回（pageBack() 找的是英文的 'Back' 提示，中文 / 马来文找不到）
/// 回到上一页：那一页的资料在看不到的时候不会刷新（Riverpod 3 会暂停），回去才重新读，所以也等一下
Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  await settle(tester);
}

/// 列表比屏幕长的时候，先滚到看得见
/// 页面上下滚的那一个（输入框里面左右滚的不算）
final pageScrollable = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: pageScrollable);
  await tester.pumpAndSettle();
}

/// 示范资料要等 150ms；画面还显示旧的资料时没有动画，pumpAndSettle 不会等
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// 不会真的打开电话 / WhatsApp，记下要打开的网址。fail = 手机没装那个 App（Android 会丢 PlatformException）
class FakeLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  bool fail = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => !fail;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (fail) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    launched.add('${options.mode.name} $url');
    return true;
  }
}

FakeLauncher fakeLauncher() {
  final previous = UrlLauncherPlatform.instance;
  final fake = FakeLauncher();
  UrlLauncherPlatform.instance = fake;
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  return fake;
}

Finder amount(String label, String value) =>
    find.byWidgetPredicate((w) => w is AmountRow && w.label == label && w.value == value);

Future<void> openOrder(WidgetTester tester, {required String tile, required String id}) async {
  await tapAndSettle(tester, find.byKey(Key(tile)));
  await tapAndSettle(tester, find.byKey(Key('seller-order-$id')));
}
