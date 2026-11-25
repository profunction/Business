import 'dart:async';

/// 通知权限的状态
enum PushPermission {
  /// 可以显示通知
  granted,

  /// 还没问过
  notDetermined,

  /// 老板拒绝了（要到手机设定才能再打开）
  denied,
}

/// 推送通知。App 只认这个介面：正式 App 用 FirebasePushService，示范模式和测试用 [NoopPushService]。
abstract class PushService {
  /// 这部机器有没有启用推送（没有 Firebase 设定、网页版 → false）
  bool get isEnabled;

  /// 老板点了通知（App 在背景、被关掉了、或在前台显示的本地通知）。内容是 FCM 的 data：
  /// {type, order_id, order_no, date}，值全部是字串。App 还没准备好之前点的会先存着
  Stream<Map<String, String>> get taps;

  /// 登录后（买家、批发商都要）：把这部手机的推送目标登记到服务器。每次开 App 都会再登记一次（更新 last_seen_at）。
  /// localeCode 用来设定 Android 通知频道的名字。失败不会丢错误（推送只是加分，不能挡住 App）
  Future<void> registerDevice({String? localeCode});

  /// 登出前：把这部手机从服务器删掉，免得下一个人登录前还收到上一个人的通知
  Future<void> unregisterDevice();

  /// 换语言：Android 通知频道的名字跟着换
  Future<void> setLocale(String localeCode);

  Future<PushPermission> permissionStatus();

  /// 跳出系统的「允许通知？」。拒绝了也不会怎样，App 照样能用
  Future<PushPermission> requestPermission();
}

/// 不做任何事（示范模式、测试、网页版、没有 Firebase 设定）
class NoopPushService implements PushService {
  const NoopPushService();

  @override
  bool get isEnabled => false;

  @override
  Stream<Map<String, String>> get taps => const Stream.empty();

  @override
  Future<void> registerDevice({String? localeCode}) async {}

  @override
  Future<void> unregisterDevice() async {}

  @override
  Future<void> setLocale(String localeCode) async {}

  @override
  Future<PushPermission> permissionStatus() async => PushPermission.denied;

  @override
  Future<PushPermission> requestPermission() async => PushPermission.denied;
}

/// FCM 的 data 都是字串；保险起见把其他型别也转成字串
Map<String, String> pushData(Map<String, dynamic> data) => {
  for (final e in data.entries)
    if (e.value != null) e.key: e.value.toString(),
};
