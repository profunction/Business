import '../app/session.dart';
import 'demo_api.dart';

/// 示范模式的登录状态：不看 Supabase，看 DemoApi.loggedIn
class DemoSession extends SessionController {
  DemoSession({required DemoApi api, required super.prefs}) : _demo = api, super(api: api) {
    api.onLoggedIn = refresh;
  }

  final DemoApi _demo;

  @override
  bool get isLoggedIn => _demo.loggedIn;
}
