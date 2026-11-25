import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n_x.dart';
import '../../push/push_prompt.dart';
import '../../widgets/common.dart';

class OrderPlacedPage extends ConsumerStatefulWidget {
  const OrderPlacedPage({super.key, required this.orderCount});

  final int orderCount;

  @override
  ConsumerState<OrderPlacedPage> createState() => _OrderPlacedPageState();
}

class _OrderPlacedPageState extends ConsumerState<OrderPlacedPage> {
  @override
  void initState() {
    super.initState();
    // 刚下了单：问老板要不要在批发商确认 / 送货时收到通知（只问一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) askForPushOnce(context, ref, seller: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderCount = widget.orderCount;
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 110, color: Color(0xFF2E7D32)),
                  const SizedBox(height: 20),
                  Text(l.orderPlacedTitle, style: t.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  if (orderCount > 1)
                    Text(l.ordersWillSplit(orderCount), style: t.bodyLarge, textAlign: TextAlign.center),
                  Text(l.orderPlacedBody, style: t.titleMedium, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: BottomAction(
          above: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              key: const Key('placed-view-orders'),
              onPressed: () => context.go('/orders'),
              child: Text(l.viewOrders),
            ),
          ),
          child: FilledButton(
            key: const Key('placed-home'),
            onPressed: () => context.go('/home'),
            child: Text(l.backHome),
          ),
        ),
      ),
    );
  }
}
