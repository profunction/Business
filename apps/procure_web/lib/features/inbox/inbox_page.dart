import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 收件箱：给我的通知（推送有没有发出去都在这里），新到旧。按一下标已读；账单的通知按了去方案页
class InboxPage extends ConsumerWidget {
  const InboxPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, InboxItem i) async {
    final api = ref.read(apiProvider);
    if (!i.isRead) {
      await runAction(context, () => api.markInboxRead([i.id]));
      ref.invalidate(inboxProvider);
    }
    if (!context.mounted) return;
    final companyId = i.companyId;
    final session = ref.read(sessionProvider);
    if (companyId != null && session.companies.any((c) => c.id == companyId) && session.company?.id != companyId) {
      await session.selectCompany(companyId);
    }
    if (!context.mounted) return;
    if (i.eventType.startsWith('company_invoice') ||
        i.eventType == 'payment_received' ||
        i.eventType == 'company_trial_ending') {
      context.go('/billing');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(inboxProvider);
    final unread = value.value?.unreadCount ?? 0;
    return ListView(
      children: [
        PageHeader(
          title: l.navInbox,
          subtitle: l.inboxHint,
          actions: [
            if (unread > 0)
              OutlinedButton.icon(
                key: const Key('inbox-read-all'),
                onPressed: () async {
                  if (await runAction(context, () => ref.read(apiProvider).markInboxRead(), success: l.inboxAllRead)) {
                    ref.invalidate(inboxProvider);
                  }
                },
                icon: const Icon(Icons.done_all),
                label: Text(l.inboxMarkAll),
              ),
          ],
        ),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(inboxProvider),
          builder: (page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: page.items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.inboxEmpty)),
                  )
                : Card(
                    child: Column(
                      children: [
                        for (final i in page.items)
                          Builder(
                            builder: (context) {
                              final t = l.inboxText(i);
                              final company = asStringOrNull(i.payload['company_name']);
                              return ListTile(
                                key: Key('inbox-${i.id}'),
                                leading: Icon(i.isRead ? Icons.drafts_outlined : Icons.mark_email_unread_outlined),
                                title: Text(
                                  t.title,
                                  style: TextStyle(fontWeight: i.isRead ? FontWeight.normal : FontWeight.w700),
                                ),
                                subtitle: Text(
                                  [
                                    t.body,
                                    ?company,
                                    fmtDateTime(i.createdAt),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                ),
                                trailing: i.isRead
                                    ? null
                                    : Tag(l.inboxUnread, color: Theme.of(context).colorScheme.primary),
                                onTap: () => _open(context, ref, i),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
