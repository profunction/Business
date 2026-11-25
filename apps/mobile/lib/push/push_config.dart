import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase（推送通知）的设定。两种做法，见 apps/mobile/README.md「推送通知」：
///
/// 1. 用 --dart-define 传（config/firebase.json，值从 Firebase 主控台或 flutterfire configure 产生的
///    lib/firebase_options.dart 抄过来）：FIREBASE_API_KEY、FIREBASE_APP_ID_ANDROID、FIREBASE_APP_ID_IOS、
///    FIREBASE_MESSAGING_SENDER_ID、FIREBASE_PROJECT_ID、FIREBASE_IOS_BUNDLE_ID。
/// 2. 跑过 flutterfire configure（有 android/app/google-services.json、ios/Runner/GoogleService-Info.plist），
///    再加 --dart-define=FIREBASE_NATIVE_CONFIG=true，用原生设定档初始化。
///
/// 两种都没有 → 不启用推送，App 照样能用。网页版永远不启用（要 service worker + VAPID，第四步不做）。
class PushConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const appIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const useNativeConfig = bool.fromEnvironment('FIREBASE_NATIVE_CONFIG');

  /// 这部机器上推送要怎么初始化；null = 不启用
  static PushSetup? get current => setupFor(
    defaultTargetPlatform,
    isWeb: kIsWeb,
    apiKey: apiKey,
    appIdAndroid: appIdAndroid,
    appIdIos: appIdIos,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    iosBundleId: iosBundleId,
    useNativeConfig: useNativeConfig,
  );

  /// 纯函数，方便测试
  @visibleForTesting
  static PushSetup? setupFor(
    TargetPlatform platform, {
    required bool isWeb,
    String apiKey = '',
    String appIdAndroid = '',
    String appIdIos = '',
    String messagingSenderId = '',
    String projectId = '',
    String iosBundleId = '',
    bool useNativeConfig = false,
  }) {
    if (isWeb) return null;
    final String appId;
    switch (platform) {
      case TargetPlatform.android:
        appId = appIdAndroid;
      case TargetPlatform.iOS:
        appId = appIdIos;
      default:
        return null; // 桌面版不做推送
    }
    if ([apiKey, appId, messagingSenderId, projectId].every((v) => v.isNotEmpty)) {
      return PushSetup(
        platform: platform,
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          iosBundleId: platform == TargetPlatform.iOS && iosBundleId.isNotEmpty ? iosBundleId : null,
        ),
      );
    }
    if (useNativeConfig) return PushSetup(platform: platform, options: null);
    return null;
  }
}

class PushSetup {
  const PushSetup({required this.platform, required this.options});

  final TargetPlatform platform;

  /// null = 用 google-services.json / GoogleService-Info.plist
  final FirebaseOptions? options;

  /// register_device_token 的 p_platform
  String get platformCode => platform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<FirebaseApp> initializeFirebase() => Firebase.initializeApp(options: options);
}
