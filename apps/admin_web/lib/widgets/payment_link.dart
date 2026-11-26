import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/l10n_x.dart';
import '../app/providers.dart';
import 'common.dart';

/// 代老板 / 批发商开付款链接（Edge Function create-payment，金额由服务器算），复制下来用 WhatsApp 发给他。
/// 买家在网页付月费不用经过 App（App Store / Google Play 的规定，见 docs/07-billing.md）。
Future<void> showPaymentLink(
  BuildContext context,
  WidgetRef ref,
  PaymentPurpose purpose,
  String targetId, {
  required String title,
  int months = 1,
}) async {
  final l = context.l10n;
  PaymentCheckout? checkout;
  final ok = await runAction(
    context,
    () async => checkout = await ref.read(apiProvider).createPayment(purpose, targetId, months: months),
  );
  if (!ok || checkout == null || !context.mounted) return;
  final c = checkout!;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${l.payLinkTitle} · $title'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.payLinkAmount(formatRm(c.amountSen)), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(c.checkoutUrl, key: const Key('pay-link-url')),
            const SizedBox(height: 8),
            Text(l.payLinkHelp, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
        FilledButton.icon(
          key: const Key('pay-link-copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: c.checkoutUrl));
            if (context.mounted) {
              showSnack(context, l.payLinkCopied);
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(l.payLinkCopy),
        ),
      ],
    ),
  );
}
