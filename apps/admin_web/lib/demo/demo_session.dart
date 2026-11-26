import '../app/session.dart';
import 'demo_api.dart';

/// 示范模式的登录状态：不看 Supabase，看 DemoAdminApi.loggedIn
class DemoSession extends AdminSession {
  DemoSession({required DemoAdminApi api, required super.prefs}) : _demo = api, super(api: api) {
    api.onLoggedIn = refresh;
  }

  final DemoAdminApi _demo;

  @override
  bool get isLoggedIn => _demo.loggedIn;

  @override
  Future<void> signOut() async {
    await super.signOut();
    notifyListeners();
  }
}
