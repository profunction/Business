/// 服务器地址和公开钥匙。用 --dart-define-from-file 传进来，例如：
///   flutter run --dart-define-from-file=config/local.json
/// 本机 Supabase 的值用 `npx supabase status` 查（Publishable key，旧版叫 anon key）。
/// 这把钥匙是公开的，不是秘密；权限靠数据库的 RLS 保护。正式环境的值也不要写死在代码里，方便换。
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseKey.isNotEmpty;
}
