import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// App 里能不能出现「付款」按钮（App Store 3.1.1 / Google Play 付款政策，结论见 docs/07-billing.md 最上面）：
///   * 买家月费 = 在 App 里解锁的数字服务：iOS / Android 的商店版本默认不放付款按钮、不放去网页付款的链接或文字。
///     老板在网页（客服用 WhatsApp / 短信发的付款链接）付了，App 照样认得（订阅状态由服务器决定）。
///     --dart-define=BUYER_IN_APP_PAY=web（默认：只有网页版显示）| all（全部显示，例如以后接了应用内购买或商店规定改了）| none
///   * 批发商的佣金账单、创始上架费 = 实体货物交易的平台费（B2B），不是在 App 里用的数字内容：默认显示。
///     --dart-define=SELLER_IN_APP_PAY=false 可以关掉。
class BillingPolicy {
  const BillingPolicy({required this.buyerCanPay, required this.sellerCanPay});

  /// 照编译参数和平台决定
  factory BillingPolicy.fromEnvironment({bool isWeb = kIsWeb}) {
    const buyer = String.fromEnvironment('BUYER_IN_APP_PAY', defaultValue: 'web');
    const seller = bool.fromEnvironment('SELLER_IN_APP_PAY', defaultValue: true);
    return BillingPolicy(
      buyerCanPay: switch (buyer) {
        'all' => true,
        'none' => false,
        _ => isWeb,
      },
      sellerCanPay: seller,
    );
  }

  /// 买家「我的订阅」页显示月数和付款按钮
  final bool buyerCanPay;

  /// 批发商的账单 / 上架费显示付款按钮
  final bool sellerCanPay;
}

final billingPolicyProvider = Provider<BillingPolicy>((ref) => BillingPolicy.fromEnvironment());

/// 用手机的浏览器打开网关的付款页（不在 App 里面开 WebView：网银 App 要能跳回来）。测试换成假的
abstract class PaymentLauncher {
  Future<bool> open(Uri url);
}

class BrowserPaymentLauncher implements PaymentLauncher {
  const BrowserPaymentLauncher();

  @override
  Future<bool> open(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}

final paymentLauncherProvider = Provider<PaymentLauncher>((ref) => const BrowserPaymentLauncher());
