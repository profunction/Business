import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_scope.dart';

/// 成员和邀请（admin、finance 看得到；只有 admin 能改）。邀请：号码已经有账号就直接加，没有就等他用这个号码登录
class MembersPage extends ConsumerWidget {
  const MembersPage({super.key});

  Future<void> _invite(BuildContext context, WidgetRef ref, CompanyContext c) async {
    final l = context.l10n;
    final r = await showDialog<_MemberInput>(
      context: context,
      builder: (_) => _MemberDialog(sites: c.activeSites),
    );
    if (r == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .inviteMember(c.company.id, phone: r.phone!, roles: r.roles, allSites: r.allSites, shopIds: r.shopIds),
      success: l.membersInvited,
    );
    if (ok) refreshCompany(ref, c.company.id);
  }

  Future<void> _editMember(BuildContext context, WidgetRef ref, CompanyContext c, CompanyMember m) async {
    final l = context.l10n;
    final r = await showDialog<_MemberInput>(
      context: context,
      builder: (_) => _MemberDialog(sites: c.activeSites, member: m),
    );
    if (r == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .setMember(
            c.company.id,
            m.userId,
            roles: r.roles,
            allSites: r.allSites,
            shopIds: r.shopIds,
            isActive: r.isActive,
          ),
      success: l.saved,
    );
    if (ok) refreshCompany(ref, c.company.id);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, CompanyContext c, CompanyMember m) async {
    final l = context.l10n;
    final name = m.fullName ?? formatMalaysianMobile(m.phone);
    if (!await showConfirmDialog(context, title: l.membersRemoveTitle(name), body: l.membersRemoveBody)) return;
    if (!context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).removeMember(c.company.id, m.userId),
      success: l.membersRemoved,
    );
    if (ok) refreshCompany(ref, c.company.id);
  }

  Future<void> _cancelInvite(BuildContext context, WidgetRef ref, CompanyContext c, CompanyInvite i) async {
    final l = context.l10n;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).cancelInvite(i.id),
      success: l.membersInviteCancelled,
    );
    if (ok) refreshCompany(ref, c.company.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return CompanyScope(
      builder: (context, c) {
        if (!c.canSeeBilling) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(l.errNotAllowed)),
          );
        }
        final siteNames = {for (final s in c.sites) s.id: s.name};
        final max = c.subscription?.maxUsers;
        return ListView(
          children: [
            PageHeader(
              title: l.navMembers,
              subtitle: max == null ? l.membersHint : '${l.membersHint} ${l.membersLimit(max)}',
              actions: [
                if (c.isAdmin)
                  FilledButton.icon(
                    key: const Key('member-invite'),
                    onPressed: () => _invite(context, ref, c),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(l.membersInvite),
                  ),
              ],
            ),
            AsyncBody(
              value: ref.watch(membersProvider(c.company.id)),
              onRetry: () => ref.invalidate(membersProvider(c.company.id)),
              builder: (ms) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Section(
                      title: '${l.membersTitle} (${ms.members.where((m) => m.isActive).length})',
                      child: Column(
                        children: [
                          for (final m in ms.members)
                            _MemberRow(
                              member: m,
                              sitesText:
                                  m.allSites ||
                                      m.roles.contains(CompanyRole.admin) ||
                                      m.roles.contains(CompanyRole.finance)
                                  ? l.membersAllSites
                                  : m.shopIds.map((id) => siteNames[id] ?? '?').join(l.lang == 'zh' ? '、' : ', '),
                              onEdit: c.isAdmin ? () => _editMember(context, ref, c, m) : null,
                              onRemove: c.isAdmin ? () => _remove(context, ref, c, m) : null,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Section(
                      title: l.membersInvites,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ms.invites.isEmpty) Text(l.membersNoInvites),
                          for (final i in ms.invites)
                            Padding(
                              key: Key('invite-${i.phone}'),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Icon(Icons.mail_outline, size: 20),
                                  Text(
                                    formatMalaysianMobile(i.phone),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(l.roles(i.roles)),
                                  i.expired
                                      ? Tag(l.membersInviteExpired, color: Colors.grey)
                                      : Text(l.membersInviteUntil(fmtDateTime(i.expiresAt))),
                                  if (c.isAdmin)
                                    TextButton.icon(
                                      key: Key('invite-cancel-${i.phone}'),
                                      onPressed: () => _cancelInvite(context, ref, c, i),
                                      icon: const Icon(Icons.close),
                                      label: Text(l.membersCancelInvite),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(l.membersInviteHelp, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.sitesText, this.onEdit, this.onRemove});

  final CompanyMember member;
  final String sitesText;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = member;
    final name = m.fullName ?? formatMalaysianMobile(m.phone);
    return Padding(
      key: Key('member-$name'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(m.isActive ? Icons.person_outline : Icons.person_off_outlined, size: 20),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final r in CompanyRole.values.where(m.roles.contains))
            Tag(l.role(r), color: Theme.of(context).colorScheme.primary),
          Text(sitesText),
          if (!m.isActive) Tag(l.membersInactive, color: Colors.grey),
          PhoneText(m.phone),
          if (onEdit != null)
            OutlinedButton.icon(
              key: Key('member-edit-$name'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.edit),
            ),
          if (onRemove != null)
            TextButton.icon(
              key: Key('member-remove-$name'),
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove_outlined),
              label: Text(l.membersRemove),
            ),
        ],
      ),
    );
  }
}

typedef _MemberInput = ({String? phone, Set<CompanyRole> roles, bool allSites, List<String> shopIds, bool isActive});

/// 邀请（member 空）/ 改成员：角色（可以几个）、全部分店还是选几个、启用
class _MemberDialog extends StatefulWidget {
  const _MemberDialog({required this.sites, this.member});

  final List<CompanySite> sites;
  final CompanyMember? member;

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  final _phone = TextEditingController();
  late final Set<CompanyRole> _roles = {...?widget.member?.roles};
  late bool _allSites = widget.member?.allSites ?? true;
  late final Set<String> _shopIds = {...?widget.member?.shopIds};
  late bool _active = widget.member?.isActive ?? true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _seesAll => _roles.contains(CompanyRole.admin) || _roles.contains(CompanyRole.finance);

  void _ok() {
    final l = context.l10n;
    String? phone;
    if (widget.member == null) {
      phone = normalizeMalaysianMobile(_phone.text);
      if (phone == null) {
        setState(() => _error = l.phoneInvalid);
        return;
      }
    }
    if (_roles.isEmpty) {
      setState(() => _error = l.membersRoleRequired);
      return;
    }
    if (!_allSites && !_seesAll && _shopIds.isEmpty) {
      setState(() => _error = l.membersSiteRequired);
      return;
    }
    Navigator.pop(context, (
      phone: phone,
      roles: _roles,
      allSites: _allSites || _seesAll,
      shopIds: _shopIds.toList(),
      isActive: _active,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = widget.member;
    return AlertDialog(
      title: Text(m == null ? l.membersInvite : l.membersEdit(m.fullName ?? formatMalaysianMobile(m.phone))),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (m == null)
                TextField(
                  key: const Key('member-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
                  decoration: InputDecoration(labelText: l.phoneLabel, hintText: '012-345 6789'),
                ),
              const SizedBox(height: 8),
              Text(l.membersRoles, style: Theme.of(context).textTheme.titleSmall),
              for (final r in CompanyRole.values)
                CheckboxListTile(
                  key: Key('role-${r.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _roles.contains(r),
                  title: Text(l.role(r)),
                  subtitle: Text(l.roleHelp(r)),
                  onChanged: (v) => setState(() => v == true ? _roles.add(r) : _roles.remove(r)),
                ),
              const Divider(),
              SwitchListTile(
                key: const Key('member-all-sites'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _allSites || _seesAll,
                title: Text(l.membersAllSites),
                subtitle: _seesAll ? Text(l.membersAllSitesForced) : null,
                onChanged: _seesAll ? null : (v) => setState(() => _allSites = v),
              ),
              if (!_allSites && !_seesAll)
                for (final s in widget.sites)
                  CheckboxListTile(
                    key: Key('member-site-${s.name}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _shopIds.contains(s.id),
                    title: Text(s.name),
                    onChanged: (v) => setState(() => v == true ? _shopIds.add(s.id) : _shopIds.remove(s.id)),
                  ),
              if (m != null)
                SwitchListTile(
                  key: const Key('member-active'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  title: Text(l.membersActive),
                  onChanged: (v) => setState(() => _active = v),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: _ok,
          child: Text(m == null ? l.membersSendInvite : l.save),
        ),
      ],
    );
  }
}
