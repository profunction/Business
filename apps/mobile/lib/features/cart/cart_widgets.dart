import 'package:flutter/material.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

/// 一家批发商的小结：货价、运费、还差多少、预计哪天送到
class GroupSummary extends StatelessWidget {
  const GroupSummary({super.key, required this.group});

  final CartGroup group;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmountRow(label: l.goodsSubtotal, value: formatRm(g.goodsSubtotalSen)),
        if (g.shippingFeeSen != null)
          AmountRow(
            label: l.shipping,
            value: g.shippingFeeSen == 0 ? l.freeShipping : formatRm(g.shippingFeeSen!),
            valueColor: g.shippingFeeSen == 0 ? const Color(0xFF2E7D32) : null,
          ),
        if (g.problem == CartProblem.belowMinOrder)
          InfoLine(icon: Icons.error, text: l.shortOfMinOrder(formatRm(g.shortBySen)), color: AppTheme.problem)
        else if (g.problem == CartProblem.notDelivering)
          InfoLine(icon: Icons.error, text: l.problemNotDelivering, color: AppTheme.problem)
        else if (g.shortOfFreeShippingSen != null)
          InfoLine(icon: Icons.lightbulb_outline, text: l.shortOfFreeShipping(formatRm(g.shortOfFreeShippingSen!))),
        if (g.expectedDeliveryDate != null && g.problem == null)
          InfoLine(icon: Icons.local_shipping, text: l.expectedDelivery(l.date(g.expectedDeliveryDate!))),
      ],
    );
  }
}
