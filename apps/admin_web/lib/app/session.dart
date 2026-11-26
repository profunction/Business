import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:wholesale_core/wholesale_core.dart';

/// 客服后台现在在哪一个阶段，决定显示哪个页面
enum AdminStage {
  loggedOut,
  loading,
  error, // 读不到资料（多数是没网络）
  denied, // 登录了，但不是客服
  ready,
}

/// 登录状态、语言、我是谁。只有 role = admin 的账号可以进后台（服务器的 admin_* 函数也会再检查）
class AdminSession extends ChangeNotifier {
  AdminSession({required this.api, required this.prefs}) {
    _localeCode = prefs.getString(_kLocale) ?? 'zh';
    _authSub = api.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.initialSession) {
        if (state.session != null) unawaited(refresh());
      } else if (state.event == AuthChangeEvent.signedOut) {
        _context = null;
        _error = null;
        notifyListeners();
      }
    });
    if (isLoggedIn) unawaited(refresh());
  }

  static const _kLocale = 'admin_locale';

  final AdminApi api;
  final SharedPreferences prefs;
  StreamSubscription<dynamic>? _authSub;

  late String _localeCode;
  MyContext? _context;
  Object? _error;
  bool _loading = false;

  /// zh（默认）/ en / ms
  String get localeCode => _localeCode;
  MyContext? get context => _context;
  Object? get error => _error;
  bool get isLoggedIn => api.client.auth.currentSession != null;

  AdminStage get stage {
    if (!isLoggedIn) return AdminStage.loggedOut;
    final c = _context;
    if (c == null) return _error != null && !_loading ? AdminStage.error : AdminStage.loading;
    return c.profile.role == UserRole.admin ? AdminStage.ready : AdminStage.denied;
  }

  Future<void> refresh() async {
    if (!isLoggedIn) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _context = await api.getMyContext();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setLocale(String code) async {
    _localeCode = code;
    await prefs.setString(_kLocale, code);
    notifyListeners();
    final c = _context;
    if (c != null) {
      try {
        await api.setMyLocale(c.profile.id, code);
      } catch (_) {}
    }
  }

  Future<void> signOut() async {
    try {
      await api.signOut();
    } finally {
      _context = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
