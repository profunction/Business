import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../l10n/app_localizations.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import 'settings_widgets.dart';

/// 设定：语言、我的店、订阅状态、登出
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final shops = session.context?.shops ?? const <MyShop>[];
    final sub = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.language, style: t.titleMedium),
          const SizedBox(height: 8),
          const LanguageCard(),
          const SizedBox(height: 20),
          Text(l.myShop, style: t.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: shops.length <= 1
                ? ListTile(leading: const Icon(Icons.storefront, size: 32), title: Text(session.shop?.name ?? ''))
                : RadioGroup<String>(
                    groupValue: session.shopId,
                    onChanged: (id) {
                      if (id != null) ref.read(sessionProvider).selectShop(id);
                    },
                    child: Column(
                      children: [for (final s in shops) RadioListTile<String>(value: s.id, title: Text(s.name))],
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Text(l.subscription, style: t.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AsyncView<SubscriptionInfo>(
                value: sub,
                onRetry: () => ref.invalidate(subscriptionProvider),
                builder: (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_subscriptionLine(l, s), style: t.titleMedium),
                    if (s.lockedPriceSen != null && s.state != SubscriptionState.lapsed) ...[
                      const SizedBox(height: 6),
                      Text(l.lockedPrice(formatRm(s.lockedPriceSen!)), style: t.bodyLarge),
                    ],
                    if (!s.hasFullAccess) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => context.push('/free-wholesalers'),
                        child: Text(l.chooseWholesalers),
                      ),
                    ],
                    if (s.state != SubscriptionState.active) ...[
                      const SizedBox(height: 10),
                      Text(l.subscribeComingSoon, style: t.bodyMedium?.copyWith(color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const LogoutButton(),
        ],
      ),
    );
  }

  String _subscriptionLine(L10n l, SubscriptionInfo s) => switch (s.state) {
    SubscriptionState.trialing when s.hasFullAccess && s.trialEndsAt != null => l.subTrial(l.dateOnly(s.trialEndsAt!)),
    SubscriptionState.active when s.currentPeriodEnd != null => l.subActive(l.dateOnly(s.currentPeriodEnd!)),
    SubscriptionState.pastDue when s.graceUntil != null => l.subPastDue(l.dateOnly(s.graceUntil!)),
    _ => l.subFree,
  };
}
