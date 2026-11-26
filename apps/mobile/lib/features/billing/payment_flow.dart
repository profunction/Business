import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/billing_config.dart';
import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 按「付款」：服务器开付款单 → 用浏览器打开网关的付款页 → 老板付完回到 App，再看一次这张付款单付了没有。
/// （网关通知服务器才算数；App 只是回来时刷新画面。）
mixin PaymentFlow<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final AppLifecycleListener _payLifecycle = AppLifecycleListener(onResume: checkPendingPayment);

  /// 刚去付的那张（回到 App 时看状态）
  String? pendingPaymentId;
  bool paying = false;

  /// 付了之后要刷新哪些资料
  void onPaid();

  @override
  void initState() {
    super.initState();
    _payLifecycle;
  }

  @override
  void dispose() {
    _payLifecycle.dispose();
    super.dispose();
  }

  Future<void> startPayment(PaymentPurpose purpose, String targetId, {int months = 1}) async {
    final l = context.l10n;
    setState(() => paying = true);
    try {
      final checkout = await ref.read(apiProvider).createPayment(purpose, targetId, months: months);
      pendingPaymentId = checkout.paymentId;
      final opened = await ref.read(paymentLauncherProvider).open(Uri.parse(checkout.checkoutUrl));
      if (!opened && mounted) showMessage(context, l.payOpenFailed, error: true);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  /// 回到 App（或按「我付了」）：看那张付款单
  Future<void> checkPendingPayment() async {
    final id = pendingPaymentId;
    if (id == null || !mounted) return;
    final l = context.l10n;
    try {
      final p = await ref.read(apiProvider).getPayment(id);
      if (!mounted) return;
      if (p.isPaid) {
        pendingPaymentId = null;
        showMessage(context, l.payDone(formatRm(p.amountSen)));
        onPaid();
      } else {
        showMessage(context, l.payNotYet);
      }
    } catch (_) {
      // 网络不好：下次回来再看
    }
  }
}
