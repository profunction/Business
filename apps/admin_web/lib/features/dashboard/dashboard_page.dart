import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 首页：今天要注意的事（要跟进的单、待审核的批发商），按了就去那一页
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(dashboardProvider);
    return ListView(
      children: [
        PageHeader(
          title: l.navDashboard,
          actions: [
            IconButton(
              tooltip: l.retry,
              onPressed: () => ref.invalidate(dashboardProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(dashboardProvider),
          builder: (d) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _Tile(
                  key: const Key('tile-unconfirmed'),
                  label: l.dashUnconfirmed(d.alertMinutes),
                  value: '${d.unconfirmedOrders}',
                  icon: Icons.phone_in_talk,
                  alert: d.unconfirmedOrders > 0,
                  onTap: () => context.go('/followup'),
                ),
                _Tile(
                  key: const Key('tile-pending-wholesalers'),
                  label: l.dashPendingWholesalers,
                  value: '${d.pendingWholesalers}',
                  icon: Icons.how_to_reg,
                  alert: d.pendingWholesalers > 0,
                  onTap: () => context.go('/wholesalers?status=pending'),
                ),
                _Tile(
                  label: l.dashPendingOrders,
                  value: '${d.pendingOrders}',
                  icon: Icons.hourglass_top,
                  onTap: () => context.go('/orders'),
                ),
                _Tile(
                  label: l.dashTodayOrders,
                  value: '${d.todayOrderCount}',
                  sub: '${l.dashTodayTotal} ${formatRm(d.todayTotalSen)}',
                  icon: Icons.today,
                  onTap: () => context.go('/orders'),
                ),
                _Tile(
                  label: l.dashSubscriptions,
                  value: '${d.trialing + d.active + d.pastDue}',
                  sub:
                      '${l.subTrialing} ${d.trialing} · ${l.subActive} ${d.active} · ${l.subPastDue} ${d.pastDue} · '
                      '${l.subLapsed} ${d.lapsed} · ${l.subFounding} ${d.foundingPrice}',
                  icon: Icons.card_membership,
                  onTap: () => context.go('/subscriptions'),
                ),
                _Tile(
                  label: '${l.dashMonthCommission}（${d.month == null ? '' : fmtMonth(d.month!)}）',
                  value: formatRm(d.monthCommissionSen),
                  sub: '${l.dashMonthGmv} ${formatRm(d.monthGmvSen)}',
                  icon: Icons.request_quote,
                  onTap: () => context.go('/commission'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
    this.alert = false,
    required this.onTap,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final bool alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 300,
      child: Card(
        color: alert ? scheme.errorContainer : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: alert ? scheme.onErrorContainer : scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: t.titleSmall)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(value, style: t.headlineMedium),
                if (sub != null) Text(sub!, style: t.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
