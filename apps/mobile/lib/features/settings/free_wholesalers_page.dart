import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 未付费用户选「免费看价钱的批发商」（最多 3 家；拿掉已选的，30 天一次）
class FreeWholesalersPage extends ConsumerStatefulWidget {
  const FreeWholesalersPage({super.key});

  @override
  ConsumerState<FreeWholesalersPage> createState() => _FreeWholesalersPageState();
}

class _FreeWholesalersPageState extends ConsumerState<FreeWholesalersPage> {
  Set<String>? _selected;
  bool _busy = false;

  Future<void> _save() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(buyerActionsProvider).setUnlockedWholesalers(_selected!.toList());
      if (!mounted) return;
      showMessage(context, l.saved);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final sub = ref.watch(subscriptionProvider);
    final ws = ref.watch(wholesalersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.freeWholesalersTitle)),
      body: AsyncView<SubscriptionInfo>(
        value: sub,
        onRetry: () => ref.invalidate(subscriptionProvider),
        builder: (s) {
          if (s.hasFullAccess) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.fullAccessNoNeed, style: t.titleLarge, textAlign: TextAlign.center),
              ),
            );
          }
          final original = s.unlockedWholesalerIds.toSet();
          final selected = _selected ??= {...original};
          final canRemove = s.canChangeUnlocks(DateTime.now());
          return AsyncView<List<WholesalerSummary>>(
            value: ws,
            onRetry: () => ref.invalidate(wholesalersProvider),
            builder: (list) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l.freeWholesalersBody(s.freeUnlockedLimit), style: t.bodyLarge),
                if (!canRemove && s.unlocksChangeAllowedAt != null) ...[
                  const SizedBox(height: 8),
                  InfoLine(
                    icon: Icons.schedule,
                    text: l.freeWholesalersCooldown(l.date(toMyt(s.unlocksChangeAllowedAt!))),
                  ),
                ],
                const SizedBox(height: 12),
                Text(l.selectedCount(selected.length, s.freeUnlockedLimit), style: t.titleLarge),
                const SizedBox(height: 8),
                for (final w in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: CheckboxListTile(
                        key: Key('free-${w.id}'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(w.name, style: t.titleMedium),
                        subtitle: Text('${l.productCount(w.productCount)} · ${l.leadTime(w.leadTimeDays)}'),
                        value: selected.contains(w.id),
                        onChanged: (on) {
                          final isOriginal = original.contains(w.id);
                          if (on == true && selected.length >= s.freeUnlockedLimit) return;
                          if (on == false && isOriginal && !canRemove) return;
                          setState(() => on == true ? selected.add(w.id) : selected.remove(w.id));
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BottomAction(
        child: BusyButton(
          key: const Key('save-free'),
          label: l.save,
          busy: _busy,
          onPressed: _selected == null ? null : _save,
        ),
      ),
    );
  }
}
