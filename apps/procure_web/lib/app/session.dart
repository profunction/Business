import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:wholesale_core/wholesale_core.dart';

/// 公司采购网页现在在哪一个阶段，决定显示哪个页面
enum ProcureStage {
  loggedOut,
  loading,
  error, // 读不到资料（多数是没网络）
  denied, // 批发商账号：不能当公司成员
  noCompany, // 登录了，还不是任何公司的成员 → 注册公司
  ready,
}

/// 登录状态、语言、我是谁、现在看的是哪一家公司（可以切换，记在浏览器）
class ProcureSession extends ChangeNotifier {
  ProcureSession({required this.api, required this.prefs}) {
    _localeCode = prefs.getString(_kLocale) ?? 'zh';
    _companyId = prefs.getString(_kCompany);
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

  static const _kLocale = 'procure_locale';
  static const _kCompany = 'procure_company';

  final ProcureApi api;
  final SharedPreferences prefs;
  StreamSubscription<dynamic>? _authSub;

  late String _localeCode;
  String? _companyId;
  MyContext? _context;
  Object? _error;
  bool _loading = false;

  /// zh（默认）/ en / ms
  String get localeCode => _localeCode;
  MyContext? get context => _context;
  Object? get error => _error;
  bool get isLoggedIn => api.client.auth.currentSession != null;

  List<MyCompany> get companies => _context?.companies ?? const [];

  /// 现在这一家（记住的那一家还是成员就用它，不然第一家）
  MyCompany? get company {
    final list = companies;
    if (list.isEmpty) return null;
    return list.where((c) => c.id == _companyId).firstOrNull ?? list.first;
  }

  ProcureStage get stage {
    if (!isLoggedIn) return ProcureStage.loggedOut;
    final c = _context;
    if (c == null) return _error != null && !_loading ? ProcureStage.error : ProcureStage.loading;
    if (c.profile.role == UserRole.seller) return ProcureStage.denied;
    return c.companies.isEmpty ? ProcureStage.noCompany : ProcureStage.ready;
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

  Future<void> selectCompany(String companyId) async {
    _companyId = companyId;
    await prefs.setString(_kCompany, companyId);
    notifyListeners();
  }

  /// 注册了新公司：读一次「我是谁」，换到那一家
  Future<void> companyRegistered(String companyId) async {
    _companyId = companyId;
    await prefs.setString(_kCompany, companyId);
    await refresh();
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
