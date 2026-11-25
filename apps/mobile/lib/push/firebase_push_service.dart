import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../l10n/app_localizations.dart';
import 'push_config.dart';
import 'push_service.dart';

/// Android 通知频道：新订单、订单状态、每天总结都用这一个（高重要性 → 会响、会跳出来）。
/// 服务器发的 android.notification.channel_id 也是 'orders'，AndroidManifest 的默认频道也是。
const ordersChannelId = 'orders';

/// 通知的小图示（android/app/src/main/res/drawable/ic_stat_order.xml；插件用 getIdentifier(name, "drawable") 找）
const _androidIcon = 'ic_stat_order';

/// App 在背景或被关掉时收到推送（Android 是另一个 isolate）。
/// 有 notification 的消息系统会自己显示，这里只把 Firebase 准备好，不碰画面。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final setup = PushConfig.current;
  if (setup != null) await setup.initializeFirebase();
}

/// 真正的推送：firebase_messaging（FID 登记）+ flutter_local_notifications（Android 前台显示）。
///
/// * 登记：先订阅 onRegistered 再 register()，拿到的 FID → register_device_token(fid, platform, 'fid')。
///   FID 换了（onRegistered 再触发）就再登记一次。
/// * App 开着时收到：Android 自己用本地通知显示（频道 orders）；iOS 用系统的前台显示（不另外显示，免得两条）。
/// * 点通知：getInitialMessage（App 被关掉时）、onMessageOpenedApp（在背景时）、本地通知的 payload → [taps]。
class FirebasePushService implements PushService {
  FirebasePushService._(this._setup, this._api, this._prefs);

  /// 初始化 Firebase。没有设定、出错、10 秒没回应 → null（App 改用 NoopPushService，照样能用）
  static Future<FirebasePushService?> start({
    required WholesaleApi api,
    required SharedPreferences prefs,
    PushSetup? setup,
  }) async {
    final s = setup ?? PushConfig.current;
    if (s == null) return null;
    final service = FirebasePushService._(s, api, prefs);
    try {
      await service._init().timeout(const Duration(seconds: 10));
      return service;
    } catch (e) {
      debugPrint('push disabled: $e');
      await service._dispose();
      return null;
    }
  }

  static const _kFid = 'push_fid';

  final PushSetup _setup;
  final WholesaleApi _api;
  final SharedPreferences _prefs;

  /// 单一订阅的 stream：App（PushNavigator）还没开始听之前点的通知会先存着
  final _taps = StreamController<Map<String, String>>();
  final _local = FlutterLocalNotificationsPlugin();
  final _subs = <StreamSubscription<dynamic>>[];

  bool _loggedIn = false;
  String? _uploadedFid;
  String _channelName = lookupL10n(const Locale('zh')).pushChannelName;
  String? _channelDescription;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  bool get _isAndroid => _setup.platform == TargetPlatform.android;

  @override
  bool get isEnabled => true;

  @override
  Stream<Map<String, String>> get taps => _taps.stream;

  Future<void> _init() async {
    await _setup.initializeFirebase();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (_isAndroid) {
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings(_androidIcon)),
        onDidReceiveNotificationResponse: (r) => _tapPayload(r.payload),
      );
      // 频道一定要在第一条推送到之前建好，不然 Android 用「其他」频道（不会响）
      await _createChannel(_prefs.getString('locale'));
    } else {
      // iOS：App 开着时也照样显示横幅、响声
      await _messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    }

    _subs
      ..add(FirebaseMessaging.onMessage.listen(_onForegroundMessage))
      ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => _tap(m.data)))
      // 一定要在 register() 之前订阅
      ..add(_messaging.onRegistered.listen(_onRegistered))
      ..add(_messaging.onUnregistered.listen(_onUnregistered));

    // App 本来是关掉的，被点通知打开
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _tap(initial.data);
    if (_isAndroid) {
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) _tapPayload(launch.notificationResponse?.payload);
    }
  }

  Future<void> _dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  // ---------------- 登记 ----------------

  @override
  Future<void> registerDevice({String? localeCode}) async {
    _loggedIn = true;
    try {
      if (_isAndroid && localeCode != null) await _createChannel(localeCode);
      // iOS：APNs token 还没好就先不登记（模拟器、还没开推送权限……），下次开 App 再试
      if (!_isAndroid && !await _apnsReady()) return;
      await _messaging.register(); // FID → onRegistered → _upload
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  @override
  Future<void> unregisterDevice() async {
    _loggedIn = false;
    _uploadedFid = null;
    final fid = _prefs.getString(_kFid);
    if (fid == null) return;
    try {
      await _api.unregisterDeviceToken(fid);
    } catch (e) {
      debugPrint('push unregister failed: $e');
    }
  }

  void _onRegistered(String fid) {
    unawaited(_prefs.setString(_kFid, fid));
    if (_loggedIn) unawaited(_upload(fid));
  }

  void _onUnregistered(String fid) {
    if (_prefs.getString(_kFid) == fid) unawaited(_prefs.remove(_kFid));
    if (_uploadedFid == fid) _uploadedFid = null;
    if (_loggedIn) unawaited(_api.unregisterDeviceToken(fid).catchError((_) {}));
  }

  Future<void> _upload(String fid) async {
    if (_uploadedFid == fid) return;
    try {
      await _api.registerDeviceToken(fid, platform: _setup.platformCode, kind: 'fid');
      _uploadedFid = fid;
    } catch (e) {
      debugPrint('push upload failed: $e'); // 下次开 App 再登记
    }
  }

  Future<bool> _apnsReady() async {
    for (final wait in const [0, 1, 2, 4]) {
      if (wait > 0) await Future<void>.delayed(Duration(seconds: wait));
      if (await _messaging.getAPNSToken() != null) return true;
    }
    return false;
  }

  // ---------------- 权限 ----------------

  @override
  Future<PushPermission> permissionStatus() async =>
      _permission((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async {
    final p = _permission((await _messaging.requestPermission()).authorizationStatus);
    // iOS 允许之后 APNs token 才会来，再登记一次
    if (p == PushPermission.granted && _loggedIn && !_isAndroid) unawaited(registerDevice());
    return p;
  }

  PushPermission _permission(AuthorizationStatus s) => switch (s) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
    AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
  };

  // ---------------- 显示和点通知 ----------------

  @override
  Future<void> setLocale(String localeCode) async {
    if (_isAndroid) await _createChannel(localeCode);
  }

  Future<void> _createChannel(String? localeCode) async {
    final code = const ['zh', 'en', 'ms'].contains(localeCode) ? localeCode! : 'zh';
    final l = lookupL10n(Locale(code));
    _channelName = l.pushChannelName;
    _channelDescription = l.pushChannelDescription;
    // 同一个 id 再建一次只会改名字和说明（响声、重要性改不了）
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            ordersChannelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
  }

  Future<void> _onForegroundMessage(RemoteMessage m) async {
    if (!_isAndroid) return; // iOS 系统自己显示
    final title = m.notification?.title ?? m.data['title']?.toString();
    final body = m.notification?.body ?? m.data['body']?.toString();
    if (title == null && body == null) return;
    final orderId = m.data['order_id']?.toString();
    try {
      await _local.show(
        // 同一张订单的通知会盖掉旧的
        id: (orderId ?? m.messageId ?? '${DateTime.now().microsecondsSinceEpoch}').hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            ordersChannelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: _androidIcon,
            styleInformation: body == null ? null : BigTextStyleInformation(body),
          ),
        ),
        payload: jsonEncode(pushData(m.data)),
      );
    } catch (e) {
      debugPrint('push show failed: $e');
    }
  }

  void _tap(Map<String, dynamic> data) => _taps.add(pushData(data));

  void _tapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map) _tap(Map<String, dynamic>.from(data));
    } catch (_) {}
  }
}
