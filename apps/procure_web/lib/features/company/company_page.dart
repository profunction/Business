import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../l10n/app_localizations.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_scope.dart';

/// 公司资料（开发票、e-Invoice 用）：admin 可以改，其他人只看
class CompanyPage extends ConsumerWidget {
  const CompanyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return CompanyScope(
      builder: (context, c) => ListView(
        children: [
          PageHeader(title: l.navCompany, subtitle: c.isAdmin ? l.companyHint : l.companyReadOnly),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CompanyForm(key: ValueKey(c.company.id), ctx: c),
          ),
        ],
      ),
    );
  }
}

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm({super.key, required this.ctx});

  final CompanyContext ctx;

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  late final Company _c = widget.ctx.company;
  late final _fields = <String, TextEditingController>{
    'name': TextEditingController(text: _c.name),
    'legal_name': TextEditingController(text: _c.legalName),
    'ssm_no': TextEditingController(text: _c.ssmNo),
    'tin': TextEditingController(text: _c.tin),
    'sst_no': TextEditingController(text: _c.sstNo),
    'billing_email': TextEditingController(text: _c.billingEmail),
    'billing_contact': TextEditingController(text: _c.billingContact),
    'billing_address': TextEditingController(text: _c.billingAddress),
    'phone': TextEditingController(text: formatMalaysianMobile(_c.phone)),
  };
  late CompanyType _type = _c.type;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _label(L10n l, String key) => switch (key) {
    'name' => l.regName,
    'legal_name' => l.companyLegalName,
    'ssm_no' => l.regSsm,
    'tin' => l.companyTin,
    'sst_no' => l.companySst,
    'billing_email' => l.regBillingEmail,
    'billing_contact' => l.companyBillingContact,
    'billing_address' => l.companyBillingAddress,
    _ => l.companyPhone,
  };

  Future<void> _save() async {
    final l = context.l10n;
    setState(() => _busy = true);
    final fields = {
      for (final e in _fields.entries) e.key: e.value.text.trim(),
      'company_type': companyTypeCode(_type),
    };
    final ok = await runAction(context, () => ref.read(apiProvider).updateCompany(_c.id, fields), success: l.saved);
    if (mounted) setState(() => _busy = false);
    if (ok) refreshCompany(ref, _c.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final edit = widget.ctx.isAdmin;
    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in _fields.entries)
                SizedBox(
                  width: 340,
                  child: TextField(
                    key: Key('company-${e.key}'),
                    controller: e.value,
                    readOnly: !edit,
                    decoration: InputDecoration(labelText: _label(l, e.key)),
                  ),
                ),
              SizedBox(
                width: 340,
                child: DropdownButtonFormField<CompanyType>(
                  isExpanded: true,
                  initialValue: _type,
                  decoration: InputDecoration(labelText: l.regType),
                  items: [
                    for (final t in CompanyType.values) DropdownMenuItem(value: t, child: Text(l.companyType(t))),
                  ],
                  onChanged: edit ? (v) => setState(() => _type = v ?? _type) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoLine(l.regRegion, _c.regionName.of(l.lang)),
          if (edit) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('company-save'),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(l.save),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
