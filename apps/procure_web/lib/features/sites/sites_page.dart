import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_scope.dart';

/// 分店 / 工地：送货区、地址、联络人、分店代号、成本中心。admin 可以加、改、封存（超过方案的分店数 → PLAN_LIMIT_SITES）
class SitesPage extends ConsumerWidget {
  const SitesPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, CompanyContext c, CompanySite? site) async {
    final l = context.l10n;
    final r = await showDialog<NewSite>(
      context: context,
      builder: (_) => _SiteDialog(site: site),
    );
    if (r == null || !context.mounted) return;
    final api = ref.read(apiProvider);
    final ok = await runAction(
      context,
      () => site == null
          ? api.addSite(c.company.id, r)
          : api.updateSite(site.id, {
              'name': r.name.trim(),
              'zone_id': r.zoneId,
              'address': r.address ?? '',
              'contact_name': r.contactName ?? '',
              'phone': r.phone ?? '',
              'site_code': r.siteCode ?? '',
              'cost_center': r.costCenter ?? '',
            }),
      success: site == null ? l.sitesAdded : l.saved,
    );
    if (ok) refreshCompany(ref, c.company.id);
  }

  Future<void> _archive(BuildContext context, WidgetRef ref, CompanyContext c, CompanySite site) async {
    final l = context.l10n;
    if (!await showConfirmDialog(context, title: l.sitesArchiveTitle(site.name), body: l.sitesArchiveBody)) return;
    if (!context.mounted) return;
    final ok = await runAction(context, () => ref.read(apiProvider).archiveSite(site.id), success: l.sitesArchived);
    if (ok) refreshCompany(ref, c.company.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return CompanyScope(
      builder: (context, c) {
        final max = c.subscription?.maxSites;
        return ListView(
          children: [
            PageHeader(
              title: l.navSites,
              subtitle: max == null ? l.sitesHint : '${l.sitesHint} ${l.sitesLimit(c.siteCount, max)}',
              actions: [
                if (c.isAdmin)
                  FilledButton.icon(
                    key: const Key('site-add'),
                    onPressed: () => _edit(context, ref, c, null),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(l.sitesAdd),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.sites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(c.isAdmin ? l.sitesEmptyAdmin : l.sitesEmpty)),
                    ),
                  for (final s in c.sites)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        key: Key('site-${s.name}'),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(s.name, style: Theme.of(context).textTheme.titleMedium),
                                  if (s.siteCode != null)
                                    Tag(s.siteCode!, color: Theme.of(context).colorScheme.primary),
                                  if (!s.isActive) Tag(l.sitesArchivedTag, color: Colors.grey),
                                ],
                              ),
                              Wrap(
                                spacing: 24,
                                children: [
                                  InfoLine(l.siteZone, s.zoneName.of(l.lang)),
                                  if (s.address != null) InfoLine(l.siteAddress, s.address!),
                                  if (s.contactName != null) InfoLine(l.siteContact, s.contactName!),
                                  if (s.costCenter != null) InfoLine(l.siteCostCenter, s.costCenter!),
                                  PhoneText(s.phone),
                                ],
                              ),
                              if (c.isAdmin && s.isActive) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      key: Key('site-edit-${s.name}'),
                                      onPressed: () => _edit(context, ref, c, s),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: Text(l.edit),
                                    ),
                                    TextButton.icon(
                                      key: Key('site-archive-${s.name}'),
                                      onPressed: () => _archive(context, ref, c, s),
                                      icon: const Icon(Icons.inventory_2_outlined),
                                      label: Text(l.sitesArchive),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SiteDialog extends ConsumerStatefulWidget {
  const _SiteDialog({this.site});

  final CompanySite? site;

  @override
  ConsumerState<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends ConsumerState<_SiteDialog> {
  late final _name = TextEditingController(text: widget.site?.name);
  late final _address = TextEditingController(text: widget.site?.address);
  late final _contact = TextEditingController(text: widget.site?.contactName);
  late final _phone = TextEditingController(text: formatMalaysianMobile(widget.site?.phone));
  late final _code = TextEditingController(text: widget.site?.siteCode);
  late final _cost = TextEditingController(text: widget.site?.costCenter);
  late String? _zoneId = widget.site?.zoneId;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _address, _contact, _phone, _code, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    final l = context.l10n;
    if (_name.text.trim().isEmpty || _zoneId == null) {
      setState(() => _error = l.siteRequired);
      return;
    }
    Navigator.pop(
      context,
      NewSite(
        name: _name.text,
        zoneId: _zoneId!,
        address: _address.text,
        contactName: _contact.text,
        phone: _phone.text,
        siteCode: _code.text,
        costCenter: _cost.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zones = ref.watch(zonesProvider);
    return AlertDialog(
      title: Text(widget.site == null ? l.sitesAdd : l.sitesEdit),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('site-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.siteName),
              ),
              const SizedBox(height: 12),
              AsyncBody(
                value: zones,
                onRetry: () => ref.invalidate(zonesProvider),
                builder: (zs) => DropdownButtonFormField<String>(
                  key: const Key('site-zone'),
                  isExpanded: true,
                  initialValue: zs.any((z) => z.id == _zoneId) ? _zoneId : null,
                  decoration: InputDecoration(labelText: l.siteZone),
                  items: [for (final z in zs) DropdownMenuItem(value: z.id, child: Text(z.name.of(l.lang)))],
                  onChanged: (v) => setState(() => _zoneId = v),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: InputDecoration(labelText: l.siteAddress),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contact,
                decoration: InputDecoration(labelText: l.siteContact),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.sitePhone),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('site-code'),
                controller: _code,
                decoration: InputDecoration(labelText: l.siteCode),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cost,
                decoration: InputDecoration(labelText: l.siteCostCenter, errorText: _error),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('dialog-ok'), onPressed: _ok, child: Text(l.save)),
      ],
    );
  }
}
