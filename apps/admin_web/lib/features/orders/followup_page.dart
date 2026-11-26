import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import 'orders_page.dart';

const followupFilter = AdminOrderFilter(unconfirmedOnly: true, limit: 200);

/// 待跟进：新订单超过 30 分钟没人确认（旧的先）。打电话给批发商，再记一句
class FollowupPage extends ConsumerWidget {
  const FollowupPage({super.key});

  Future<void> _log(BuildContext context, WidgetRef ref, AdminOrderRow o) async {
    final l = context.l10n;
    final note = await showInputDialog(
      context,
      title: '${l.logFollowup} · ${o.orderNo}',
      label: l.followupNoteLabel,
      maxLines: 3,
      validator: (v) => v.trim().isEmpty ? l.errInvalidNote : null,
    );
    if (note == null || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(apiProvider).logFollowup(o.id, note.trim()), success: l.saved);
    if (ok) ref.invalidate(ordersPageProvider(followupFilter));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final minutes = ref.watch(dashboardProvider).value?.alertMinutes ?? 30;
    final value = ref.watch(ordersPageProvider(followupFilter));
    return ListView(
      children: [
        PageHeader(
          title: l.navFollowup,
          subtitle: l.followupHint(minutes),
          actions: [
            IconButton(
              tooltip: l.retry,
              onPressed: () => ref.invalidate(ordersPageProvider(followupFilter)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(ordersPageProvider(followupFilter)),
          builder: (page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: page.orders.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.followupEmpty)),
                  )
                : Column(
                    children: [
                      for (final o in page.orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: OrderRowTile(
                              order: o,
                              onTap: () => context.go('/orders/${o.id}'),
                              extra: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (o.lastFollowupNote != null)
                                      Text(
                                        l.lastFollowup(fmtDateTime(o.lastFollowupAt), o.lastFollowupNote!),
                                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                      ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        PhoneText(o.wholesalerPhone, label: l.phoneOf(o.wholesalerName)),
                                        PhoneText(o.shopPhone, label: l.phoneOf(o.shopName)),
                                        FilledButton.tonalIcon(
                                          key: Key('followup-${o.orderNo}'),
                                          onPressed: () => _log(context, ref, o),
                                          icon: const Icon(Icons.edit_note),
                                          label: Text(l.logFollowup),
                                        ),
                                        TextButton(
                                          onPressed: () => context.go('/orders/${o.id}'),
                                          child: Text(l.openOrder),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
