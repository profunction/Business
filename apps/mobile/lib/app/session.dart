import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:wholesale_core/wholesale_core.dart';

/// App 现在在哪一个阶段，决定打开哪个页面
enum SessionStage {
  chooseLanguage, // 第一次打开：先选语言
  loggedOut,
  loading,
  error, // 读不到资料（多数是没网络）
  needsShop, // 买家还没开店
  buyer,
  seller,
  admin,
}

/// 登录状态、语言、我是谁、现在用哪间店。页面跳转（router.dart）跟着这个走。
class SessionController extends ChangeNotifier {
  SessionController({required this.api, required this.prefs}) {
    _localeCode = prefs.getString(_kLocale);
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

  static const _kLocale = 'locale';
  static const _kShop = 'selected_shop_id';

  final WholesaleApi api;
  final SharedPreferences prefs;
  StreamSubscription<dynamic>? _authSub;

  String? _localeCode;
  MyContext? _context;
  Object? _error;
  bool _loading = false;

  String? get localeCode => _localeCode;
  MyContext? get context => _context;
  Object? get error => _error;
  bool get isLoggedIn => api.client.auth.currentSession != null;

  SessionStage get stage {
    if (_localeCode == null) return SessionStage.chooseLanguage;
    if (!isLoggedIn) return SessionStage.loggedOut;
    final c = _context;
    if (c == null) return _error != null && !_loading ? SessionStage.error : SessionStage.loading;
    return switch (c.profile.role) {
      UserRole.admin => SessionStage.admin,
      UserRole.seller => SessionStage.seller,
      UserRole.buyer => c.shops.isEmpty ? SessionStage.needsShop : SessionStage.buyer,
    };
  }

  /// 现在用哪间店（一个老板可以有几间店）
  MyShop? get shop {
    final shops = _context?.shops ?? const [];
    if (shops.isEmpty) return null;
    final saved = prefs.getString(_kShop);
    return shops.firstWhere((s) => s.id == saved, orElse: () => shops.first);
  }

  String? get shopId => shop?.id;

  Future<void> refresh() async {
    if (!isLoggedIn) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _context = await api.getMyContext();
      // 账号的语言跟 App 的不一样时，以 App（老板刚选的）为准
      final code = _localeCode;
      if (code != null && _context!.profile.locale != code) {
        unawaited(api.setMyLocale(_context!.profile.id, code).catchError((_) {}));
      }
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
      } catch (_) {
        // 下次 refresh 会再同步
      }
    }
  }

  Future<void> selectShop(String shopId) async {
    await prefs.setString(_kShop, shopId);
    notifyListeners();
  }

  Future<void> signOut() async {
    await prefs.remove(_kShop);
    await api.signOut();
    _context = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
