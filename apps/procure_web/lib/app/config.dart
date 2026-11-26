/// 服务器地址、公开钥匙。用 --dart-define-from-file 传进来：
///   flutter run -d chrome --dart-define-from-file=config/local.json
/// 钥匙是公开的（Publishable key），权限靠数据库的 RLS 和函数里的角色检查（_require_company_role）。
class ProcureConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseKey.isNotEmpty;
}
