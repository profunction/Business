import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_link.dart';

/// 订阅状态的颜色（一定跟文字一起出现）
Color companySubColor(SubscriptionState s) => switch (s) {
  SubscriptionState.trialing => const Color(0xFF1565C0),
  SubscriptionState.active => const Color(0xFF2E7D32),
  SubscriptionState.pastDue => const Color(0xFFB26A00),
  _ => const Color(0xFF616161),
};

/// 公司（第八步）：列表（名字、SSM、电话搜索；状态筛选）→ 详情
class CompaniesPage extends ConsumerStatefulWidget {
  const CompaniesPage({super.key});

  @override
  ConsumerState<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends ConsumerState<CompaniesPage> {
  CompanyStatus? _status;
  String _search = '';

  CompanyQuery get _query => (status: _status, search: _search);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(companiesProvider(_query));
    return ListView(
      children: [
        PageHeader(title: l.navCompanies, subtitle: l.coHint),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<CompanyStatus?>(
                  key: const Key('co-status-filter'),
                  isExpanded: true,
                  initialValue: _status,
                  decoration: InputDecoration(labelText: l.colStatus),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.all)),
                    for (final s in CompanyStatus.values) DropdownMenuItem(value: s, child: Text(l.companyStatus(s))),
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  key: const Key('co-search'),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.coSearchHint),
                  onSubmitted: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(companiesProvider(_query)),
          builder: (list) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.coEmpty)),
                  )
                : Column(
                    children: [
                      for (final c in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CompanyCard(company: c),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company});

  final AdminCompany company;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = company;
    final sub = c.subscription;
    return Card(
      key: Key('co-${c.name}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/companies/${c.id}'),
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
                  Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                  _StatusTag(c.status),
                  if (sub != null)
                    Tag('${sub.planName.of(l.lang)} · ${l.subscription(sub.state)}', color: companySubColor(sub.state)),
                  PhoneText(c.phone),
                ],
              ),
              Wrap(
                spacing: 24,
                children: [
                  if (c.legalName != null) InfoLine(l.coLegalName, c.legalName!),
                  if (c.ssmNo != null) InfoLine(l.colSsm, c.ssmNo!),
                  InfoLine(l.coType, l.companyType(c.type)),
                  InfoLine(l.coSitesLabel, '${c.siteCount}'),
                  InfoLine(l.coMembersLabel, '${c.memberCount}'),
                  if (sub?.accessUntil != null) InfoLine(l.coAccessUntil, fmtDateTime(sub!.accessUntil)),
                  if (c.openInvoiceSen > 0) InfoLine(l.coOpenInvoices, formatRm(c.openInvoiceSen)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.status);

  final CompanyStatus status;

  @override
  Widget build(BuildContext context) => Tag(
    context.l10n.companyStatus(status),
    color: status == CompanyStatus.active ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
    icon: status == CompanyStatus.active ? Icons.check_circle_outline : Icons.block,
  );
}

/// 一家公司：资料、订阅（设方案 / 自订价、延长试用、开账单）、分店、成员和邀请、账单（标记已付、付款链接）、付款、停权
class CompanyDetailPage extends ConsumerWidget {
  const CompanyDetailPage({super.key, required this.companyId});

  final String companyId;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, {String? success}) async {
    if (await runAction(context, action, success: success ?? context.l10n.saved)) {
      ref.invalidate(companyDetailProvider(companyId));
      ref.invalidate(companiesProvider);
    }
  }

  Future<void> _toggleStatus(BuildContext context, WidgetRef ref, AdminCompanyDetail d) async {
    final l = context.l10n;
    final api = ref.read(apiProvider);
    if (d.summary.status == CompanyStatus.active) {
      final note = await showInputDialog(context, title: l.coSuspend, label: l.wsNoteLabel, help: l.coSuspendHelp);
      if (note == null || !context.mounted) return;
      await _run(context, ref, () => api.setCompanyStatus(companyId, CompanyStatus.suspended, note: note));
    } else {
      if (!await showConfirmDialog(context, title: l.coRestore)) return;
      if (!context.mounted) return;
      await _run(context, ref, () => api.setCompanyStatus(companyId, CompanyStatus.active));
    }
  }

  Future<void> _setPlan(BuildContext context, WidgetRef ref, AdminCompanyDetail d) async {
    final r = await showDialog<_PlanChoice>(
      context: context,
      builder: (_) => _SetPlanDialog(current: d.summary.subscription),
    );
    if (r == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(apiProvider).setCompanyPlan(companyId, r.planCode, r.cycle, priceSen: r.priceSen),
    );
  }

  Future<void> _extendTrial(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final v = await showInputDialog(
      context,
      title: l.subExtendTrial,
      label: l.subDaysLabel,
      initial: '14',
      keyboard: TextInputType.number,
      validator: (s) {
        final n = int.tryParse(s.trim());
        return n == null || n < 1 || n > 90 ? l.errInvalidDays : null;
      },
    );
    if (v == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(apiProvider).extendCompanyTrial(companyId, int.parse(v.trim())));
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref, CompanyInvoice i) async {
    final l = context.l10n;
    final reference = await showInputDialog(
      context,
      title: '${l.markInvoicePaid} · ${i.invoiceNo}',
      label: l.subReferenceLabel,
      help: l.coMarkPaidHelp(formatRm(i.totalSen)),
    );
    if (reference == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref
          .read(apiProvider)
          .markCompanyInvoicePaid(
            i.id,
            method: PaymentMethod.other,
            reference: reference.trim().isEmpty ? null : reference.trim(),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(companyDetailProvider(companyId));
    return AsyncBody(
      value: value,
      onRetry: () => ref.invalidate(companyDetailProvider(companyId)),
      builder: (d) {
        final c = d.company;
        final sub = d.summary.subscription;
        final siteNames = {for (final s in d.sites) s.id: s.name};
        return ListView(
          children: [
            PageHeader(
              title: c.name,
              subtitle: c.statusNote == null ? null : l.coSuspendedBecause(c.statusNote!),
              actions: [
                TextButton.icon(
                  onPressed: () => context.go('/companies'),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l.navCompanies),
                ),
                OutlinedButton.icon(
                  key: const Key('co-status'),
                  onPressed: () => _toggleStatus(context, ref, d),
                  icon: Icon(d.summary.status == CompanyStatus.active ? Icons.block : Icons.check_circle_outline),
                  label: Text(d.summary.status == CompanyStatus.active ? l.coSuspend : l.coRestore),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Section(
                    title: l.coSectionProfile,
                    child: Wrap(
                      spacing: 24,
                      children: [
                        _StatusTag(d.summary.status),
                        InfoLine(l.coType, l.companyType(c.type)),
                        if (c.legalName != null) InfoLine(l.coLegalName, c.legalName!),
                        if (c.ssmNo != null) InfoLine(l.colSsm, c.ssmNo!),
                        if (c.tin != null) InfoLine(l.coTin, c.tin!),
                        if (c.billingEmail != null) InfoLine(l.colEmail, c.billingEmail!),
                        if (c.billingAddress != null) InfoLine(l.coBillingAddress, c.billingAddress!),
                        InfoLine(l.coRegion, c.regionName.of(l.lang)),
                        PhoneText(c.phone),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: l.coSectionSubscription,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (sub == null)
                          Text(l.subNone)
                        else ...[
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Tag(sub.planName.of(l.lang), color: Theme.of(context).colorScheme.primary),
                              Tag(l.subscription(sub.state), color: companySubColor(sub.state)),
                              if (sub.customPrice) Tag(l.coCustomPrice, color: Theme.of(context).colorScheme.tertiary),
                            ],
                          ),
                          Wrap(
                            spacing: 24,
                            children: [
                              if (sub.lockedPriceSen > 0)
                                InfoLine(l.coLockedPrice, '${formatRm(sub.lockedPriceSen)} / ${l.cycle(sub.cycle)}'),
                              if (sub.trialEndsAt != null && sub.isTrial)
                                InfoLine(l.colTrialEnds, fmtDateTime(sub.trialEndsAt)),
                              if (sub.currentPeriodEnd != null)
                                InfoLine(l.colPeriodEnd, fmtDateTime(sub.currentPeriodEnd)),
                              if (sub.graceUntil != null) InfoLine(l.coGraceUntil, fmtDateTime(sub.graceUntil)),
                              if (sub.pendingPlanCode != null)
                                InfoLine(
                                  l.coPendingPlan,
                                  '${sub.pendingPlanCode} · ${formatRm(sub.pendingPriceSen ?? 0)} / '
                                  '${l.cycle(sub.pendingCycle ?? BillingCycle.monthly)}',
                                ),
                              InfoLine(l.coLimits, l.coLimitsValue('${sub.maxSites ?? '∞'}', '${sub.maxUsers ?? '∞'}')),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              key: const Key('co-set-plan'),
                              onPressed: () => _setPlan(context, ref, d),
                              icon: const Icon(Icons.workspace_premium_outlined),
                              label: Text(l.coSetPlan),
                            ),
                            OutlinedButton.icon(
                              key: const Key('co-extend-trial'),
                              onPressed: () => _extendTrial(context, ref),
                              icon: const Icon(Icons.more_time),
                              label: Text(l.subExtendTrial),
                            ),
                            OutlinedButton.icon(
                              key: const Key('co-issue-invoice'),
                              onPressed: () => _run(
                                context,
                                ref,
                                () => ref.read(apiProvider).issueCompanyInvoice(companyId),
                                success: l.coInvoiceIssued,
                              ),
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: Text(l.issueInvoice),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: '${l.coSectionSites} (${d.sites.length})',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (d.sites.isEmpty) Text(l.coNoSites),
                        for (final s in d.sites)
                          ListTile(
                            key: Key('co-site-${s.name}'),
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(s.isActive ? Icons.store_outlined : Icons.inventory_2_outlined),
                            title: Text([s.name, if (s.siteCode != null) '(${s.siteCode})'].join(' ')),
                            subtitle: Text(
                              [
                                s.zoneName.of(l.lang),
                                if (s.costCenter != null) '${l.coCostCenter} ${s.costCenter}',
                                if (s.address != null) s.address!,
                                if (!s.isActive) l.coArchived,
                              ].join(' · '),
                            ),
                            trailing: PhoneText(s.phone),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: '${l.coSectionMembers} (${d.members.members.length})',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final m in d.members.members)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(m.isActive ? Icons.person_outline : Icons.person_off_outlined),
                            title: Text(m.fullName ?? formatMalaysianMobile(m.phone)),
                            subtitle: Text(
                              [
                                CompanyRole.values.where(m.roles.contains).map(l.companyRole).join('、'),
                                m.allSites ? l.coAllSites : m.shopIds.map((id) => siteNames[id] ?? '').join('、'),
                                if (!m.isActive) l.coInactive,
                              ].join(' · '),
                            ),
                            trailing: PhoneText(m.phone),
                          ),
                        if (d.members.invites.isNotEmpty) ...[
                          const Divider(),
                          Text(l.coInvites, style: Theme.of(context).textTheme.titleSmall),
                          for (final i in d.members.invites)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.mail_outline),
                              title: Text(formatMalaysianMobile(i.phone)),
                              subtitle: Text(
                                [
                                  CompanyRole.values.where(i.roles.contains).map(l.companyRole).join('、'),
                                  i.expired ? l.coInviteExpired : l.coInviteUntil(fmtDateTime(i.expiresAt)),
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: l.coSectionInvoices,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (d.invoices.isEmpty) Text(l.invoiceNone),
                        for (final i in d.invoices)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(i.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Tag(l.invoiceStatus(i.status), color: i.canPay ? const Color(0xFFB26A00) : Colors.grey),
                                Text('${i.planName.of(l.lang)} · ${l.cycle(i.cycle)} · ${formatRm(i.totalSen)}'),
                                if (i.dueDate != null) Text(l.coDue(fmtDay(i.dueDate))),
                                if (i.canPay) ...[
                                  FilledButton.tonalIcon(
                                    key: Key('co-paid-${i.invoiceNo}'),
                                    onPressed: () => _markPaid(context, ref, i),
                                    icon: const Icon(Icons.payments_outlined),
                                    label: Text(l.markInvoicePaid),
                                  ),
                                  OutlinedButton.icon(
                                    key: Key('co-paylink-${i.invoiceNo}'),
                                    onPressed: () =>
                                        showPaymentLink(context, ref, PaymentPurpose.companyPlan, i.id, title: c.name),
                                    icon: const Icon(Icons.link),
                                    label: Text(l.payLink),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: l.coSectionPayments,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (d.payments.isEmpty) Text(l.coNoPayments),
                        for (final p in d.payments)
                          InfoLine(
                            fmtDateTime(p.paidAt ?? p.createdAt),
                            '${formatRm(p.amountSen)} · ${l.paymentStatus(p.status)}'
                            '${p.method == null ? '' : ' · ${l.method(p.method!)}'}',
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

typedef _PlanChoice = ({String planCode, BillingCycle cycle, int? priceSen});

class _SetPlanDialog extends StatefulWidget {
  const _SetPlanDialog({this.current});

  final CompanySubscription? current;

  @override
  State<_SetPlanDialog> createState() => _SetPlanDialogState();
}

class _SetPlanDialogState extends State<_SetPlanDialog> {
  static const _plans = ['co_starter', 'co_pro', 'co_enterprise'];
  late String _plan = _plans.contains(widget.current?.planCode) ? widget.current!.planCode : 'co_starter';
  late BillingCycle _cycle = widget.current?.cycle ?? BillingCycle.monthly;
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _ok() {
    final l = context.l10n;
    final text = _price.text.trim();
    final price = text.isEmpty ? null : parseRmToSen(text);
    if ((text.isNotEmpty && price == null) || (_plan == 'co_enterprise' && price == null)) {
      setState(() => _error = l.errInvalidAmount);
      return;
    }
    Navigator.pop(context, (planCode: _plan, cycle: _cycle, priceSen: price));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.coSetPlan),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.coSetPlanHelp),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('co-plan-field'),
              initialValue: _plan,
              decoration: InputDecoration(labelText: l.coPlan),
              items: [for (final p in _plans) DropdownMenuItem(value: p, child: Text(l.planName(p)))],
              onChanged: (v) => setState(() => _plan = v ?? _plan),
            ),
            const SizedBox(height: 12),
            SegmentedButton<BillingCycle>(
              segments: [for (final c in BillingCycle.values) ButtonSegment(value: c, label: Text(l.cycle(c)))],
              selected: {_cycle},
              onSelectionChanged: (s) => setState(() => _cycle = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('co-price-field'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(labelText: l.coCustomPriceLabel, errorText: _error),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(key: const Key('dialog-ok'), onPressed: _ok, child: Text(l.confirm)),
      ],
    );
  }
}
