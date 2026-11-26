/// 服务器地址、公开钥匙、账单上的公司资料。用 --dart-define-from-file 传进来：
///   flutter run -d chrome --dart-define-from-file=config/local.json
/// 钥匙是公开的（Publishable key），权限靠数据库的 RLS 和 admin_* 函数里的 is_admin() 检查。
class AdminConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseKey.isNotEmpty;
}

/// 佣金账单 PDF 上「开账单的公司」。还没注册公司 / 没设定时，账单上印「公司资料未设定」，其他照样能用
class InvoiceCompany {
  const InvoiceCompany({this.name = '', this.ssmNo = '', this.address = '', this.email = '', this.bankDetails = ''});

  static const fromEnvironment = InvoiceCompany(
    name: String.fromEnvironment('INVOICE_COMPANY_NAME'),
    ssmNo: String.fromEnvironment('INVOICE_COMPANY_SSM'),
    address: String.fromEnvironment('INVOICE_COMPANY_ADDRESS'),
    email: String.fromEnvironment('INVOICE_COMPANY_EMAIL'),
    bankDetails: String.fromEnvironment('INVOICE_BANK_DETAILS'),
  );

  final String name;
  final String ssmNo;
  final String address;
  final String email;

  /// 例：Maybank 5123 4567 8901（JB Wholesale Sdn Bhd）
  final String bankDetails;

  bool get isConfigured => name.trim().isNotEmpty;
}
