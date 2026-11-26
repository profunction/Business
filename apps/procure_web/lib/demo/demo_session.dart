import '../app/session.dart';
import 'demo_api.dart';

/// 示范模式的登录状态：不看 Supabase，看 DemoProcureApi.loggedIn
class DemoSession extends ProcureSession {
  DemoSession({required DemoProcureApi api, required super.prefs}) : _demo = api, super(api: api) {
    api.onLoggedIn = refresh;
  }

  final DemoProcureApi _demo;

  @override
  bool get isLoggedIn => _demo.loggedIn;

  @override
  Future<void> signOut() async {
    await super.signOut();
    notifyListeners();
  }
}
