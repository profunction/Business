import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/company_scope.dart';

/// 首页：方案状态（试用还剩几天、宽限期、停了）、待我审批、分店、成员、收件箱，和常用的几个按钮
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return CompanyScope(
      builder: (context, c) {
        final sub = c.subscription;
        return ListView(
          children: [
            PageHeader(title: c.company.name, subtitle: l.homeRoles(l.roles(c.myRoles))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.company.status == CompanyStatus.suspended) ...[
                    _Banner(icon: Icons.block, color: const Color(0xFFC62828), text: l.homeSuspended),
                    const SizedBox(height: 12),
                  ],
                  if (sub != null) _PlanBanner(sub: sub, canManage: c.canSeeBilling),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tile(
                        key: const Key('tile-approvals'),
                        icon: Icons.fact_check_outlined,
                        label: l.homePendingApprovals,
                        value: '${c.pendingApprovals}',
                        hint: l.homeComingSoon,
                      ),
                      _Tile(
                        key: const Key('tile-sites'),
                        icon: Icons.store_mall_directory_outlined,
                        label: l.navSites,
                        value: '${c.siteCount}${sub?.maxSites == null ? '' : ' / ${sub!.maxSites}'}',
                        onTap: () => context.go('/sites'),
                      ),
                      if (c.canSeeBilling)
                        _Tile(
                          key: const Key('tile-members'),
                          icon: Icons.group_outlined,
                          label: l.navMembers,
                          value: '${c.memberCount}${sub?.maxUsers == null ? '' : ' / ${sub!.maxUsers}'}',
                          hint: c.openInvites > 0 ? l.homeOpenInvites(c.openInvites) : null,
                          onTap: () => context.go('/members'),
                        ),
                      _Tile(
                        key: const Key('tile-inbox'),
                        icon: Icons.inbox_outlined,
                        label: l.homeUnread,
                        value: '${c.unreadInbox}',
                        onTap: () => context.go('/inbox'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Section(
                    title: l.homeQuickActions,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('quick-browse'),
                          onPressed: () => context.go('/browse'),
                          icon: const Icon(Icons.compare_arrows),
                          label: Text(l.navBrowse),
                        ),
                        if (c.isAdmin)
                          OutlinedButton.icon(
                            key: const Key('quick-invite'),
                            onPressed: () => context.go('/members'),
                            icon: const Icon(Icons.person_add_alt),
                            label: Text(l.membersInvite),
                          ),
                        if (c.isAdmin)
                          OutlinedButton.icon(
                            key: const Key('quick-site'),
                            onPressed: () => context.go('/sites'),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: Text(l.sitesAdd),
                          ),
                        if (c.canSeeBilling)
                          OutlinedButton.icon(
                            key: const Key('quick-billing'),
                            onPressed: () => context.go('/billing'),
                            icon: const Icon(Icons.workspace_premium_outlined),
                            label: Text(l.navBilling),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Section(
                    title: l.homeMySites,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.activeSites.isEmpty) Text(c.isAdmin ? l.sitesEmptyAdmin : l.sitesEmpty),
                        for (final s in c.activeSites)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.store_outlined),
                            title: Text(s.name),
                            subtitle: Text(s.zoneName.of(l.lang)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlanBanner extends StatelessWidget {
  const _PlanBanner({required this.sub, required this.canManage});

  final CompanySubscription sub;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final until = sub.accessUntil;
    final text = switch (sub.state) {
      SubscriptionState.trialing => l.homeTrial(fmtDateTime(until)),
      SubscriptionState.active => l.homeActive(l.planName(sub.planCode), fmtDateTime(until)),
      SubscriptionState.pastDue => l.homePastDue(fmtDateTime(until)),
      _ => l.homeLapsed,
    };
    return _Banner(
      key: const Key('plan-banner'),
      icon: sub.hasAccess ? Icons.verified_outlined : Icons.warning_amber_outlined,
      color: ProcureTheme.subscriptionColor(sub.state),
      text: text,
      action: canManage
          ? TextButton(onPressed: () => context.go('/billing'), child: Text(l.homeManagePlan))
          : Text(l.homePlanManaged, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.color, required this.text, this.action});

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, color: color),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.label, required this.value, this.hint, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: t.titleSmall)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(value, style: t.headlineSmall),
                if (hint != null) Text(hint!, style: t.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
