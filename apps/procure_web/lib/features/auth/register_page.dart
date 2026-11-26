import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 注册公司：名字、类型、地区、SSM（可以不填）、账单电邮、第一个分店（名字、送货区、地址、联络人、电话）。
/// 注册的人当 admin（全部角色），送 30 天试用（同一个号码 / SSM 只送一次；没有试用就要先付第一期）
class RegisterCompanyPage extends ConsumerStatefulWidget {
  const RegisterCompanyPage({super.key});

  @override
  ConsumerState<RegisterCompanyPage> createState() => _RegisterCompanyPageState();
}

class _RegisterCompanyPageState extends ConsumerState<RegisterCompanyPage> {
  final _name = TextEditingController();
  final _ssm = TextEditingController();
  final _email = TextEditingController();
  final _site = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  CompanyType _type = CompanyType.corporate;
  String? _regionId;
  String? _zoneId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _ssm, _email, _site, _address, _contact, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(List<Region> regions) async {
    final l = context.l10n;
    final region = _regionId ?? regions.firstOrNull?.id;
    if (_name.text.trim().isEmpty || region == null) {
      setState(() => _error = l.regNameRequired);
      return;
    }
    if (_site.text.trim().isNotEmpty && _zoneId == null) {
      setState(() => _error = l.regZoneRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(apiProvider)
          .registerCompany(
            name: _name.text,
            type: _type,
            regionId: region,
            ssmNo: _ssm.text,
            billingEmail: _email.text,
            firstSite: _site.text.trim().isEmpty
                ? null
                : NewSite(
                    name: _site.text,
                    zoneId: _zoneId!,
                    address: _address.text,
                    contactName: _contact.text,
                    phone: _phone.text,
                  ),
          );
      await ref.read(sessionProvider).companyRegistered(id);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = l.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = ref.watch(sessionProvider);
    final regions = ref.watch(regionsProvider);
    final zones = ref.watch(zonesProvider);
    final hasCompany = session.companies.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.regTitle),
        leading: hasCompany
            ? IconButton(tooltip: l.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home'))
            : null,
        actions: [
          PopupMenuButton<String>(
            tooltip: l.language,
            icon: const Icon(Icons.translate),
            onSelected: (code) => ref.read(sessionProvider).setLocale(code),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'zh', child: Text('华文')),
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
            ],
          ),
          IconButton(
            key: const Key('register-sign-out'),
            tooltip: l.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider).signOut(),
          ),
        ],
      ),
      body: AsyncBody(
        value: regions,
        onRetry: () => ref.invalidate(regionsProvider),
        builder: (rs) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(hasCompany ? l.regAnotherSubtitle : l.regSubtitle),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('reg-name'),
                        controller: _name,
                        decoration: InputDecoration(labelText: l.regName),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 280,
                            child: DropdownButtonFormField<CompanyType>(
                              key: const Key('reg-type'),
                              isExpanded: true,
                              initialValue: _type,
                              decoration: InputDecoration(labelText: l.regType),
                              items: [
                                for (final t in CompanyType.values)
                                  DropdownMenuItem(value: t, child: Text(l.companyType(t))),
                              ],
                              onChanged: (v) => setState(() => _type = v ?? _type),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: DropdownButtonFormField<String>(
                              key: const Key('reg-region'),
                              isExpanded: true,
                              initialValue: _regionId ?? rs.firstOrNull?.id,
                              decoration: InputDecoration(labelText: l.regRegion),
                              items: [
                                for (final r in rs) DropdownMenuItem(value: r.id, child: Text(r.name.of(l.lang))),
                              ],
                              onChanged: (v) => setState(() => _regionId = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('reg-ssm'),
                        controller: _ssm,
                        decoration: InputDecoration(labelText: l.regSsm, helperText: l.regSsmHelp, helperMaxLines: 2),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('reg-email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: l.regBillingEmail),
                      ),
                      const SizedBox(height: 20),
                      Text(l.regFirstSite, style: Theme.of(context).textTheme.titleMedium),
                      Text(l.regFirstSiteHelp, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('reg-site-name'),
                        controller: _site,
                        decoration: InputDecoration(labelText: l.siteName),
                      ),
                      const SizedBox(height: 12),
                      AsyncBody(
                        value: zones,
                        onRetry: () => ref.invalidate(zonesProvider),
                        builder: (zs) => DropdownButtonFormField<String>(
                          key: const Key('reg-site-zone'),
                          isExpanded: true,
                          initialValue: _zoneId,
                          decoration: InputDecoration(labelText: l.siteZone),
                          items: [for (final z in zs) DropdownMenuItem(value: z.id, child: Text(z.name.of(l.lang)))],
                          onChanged: (v) => setState(() => _zoneId = v),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('reg-site-address'),
                        controller: _address,
                        decoration: InputDecoration(labelText: l.siteAddress),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 280,
                            child: TextField(
                              controller: _contact,
                              decoration: InputDecoration(labelText: l.siteContact),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(labelText: l.sitePhone),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('reg-submit'),
                        onPressed: _busy ? null : () => _submit(rs),
                        icon: _busy
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_business_outlined),
                        label: Text(l.regSubmit),
                      ),
                      const SizedBox(height: 8),
                      Text(l.regTrialNote, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
