import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 订阅（买家月费）：每家店最新的一条。延长试用、手动标记已付（转账 / 现金）、取消、创始价
class SubscriptionsPage extends ConsumerStatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  SubscriptionState? _state;
  bool _foundingOnly = false;
  String _search = '';

  SubscriptionQuery get _query => (state: _state, foundingOnly: _foundingOnly, search: _search);

  Future<void> _run(Future<Object?> Function() action) async {
    final ok = await runAction(context, action, success: context.l10n.saved);
    if (ok) {
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  Future<void> _extend(AdminSubscription s) async {
    final l = context.l10n;
    final text = await showInputDialog(
      context,
      title: '${l.subExtendTrial} · ${s.shopName}',
      label: l.subDaysLabel,
      initial: '7',
      keyboard: TextInputType.number,
      validator: (v) {
        final n = int.tryParse(v.trim());
        return n == null || n < 1 || n > 90 ? l.errInvalidDays : null;
      },
    );
    if (text == null) return;
    await _run(() => ref.read(apiProvider).extendTrial(s.id, int.parse(text.trim())));
  }

  Future<void> _markPaid(AdminSubscription s) async {
    final r = await showDialog<_Paid>(
      context: context,
      builder: (_) => _MarkPaidDialog(sub: s),
    );
    if (r == null) return;
    await _run(
      () => ref
          .read(apiProvider)
          .markSubscriptionPaid(
            s.id,
            months: r.months,
            amountSen: r.amountSen,
            method: r.method,
            reference: r.reference,
          ),
    );
  }

  Future<void> _cancel(AdminSubscription s) async {
    final l = context.l10n;
    final reason = await showInputDialog(
      context,
      title: '${l.subCancel} · ${s.shopName}',
      label: l.subReasonLabel,
      help: l.subCancelConfirm,
    );
    if (reason == null) return;
    await _run(() => ref.read(apiProvider).cancelSubscription(s.id, reason: reason.trim().isEmpty ? null : reason));
  }

  Future<void> _founding(AdminSubscription s) async {
    final r = await showDialog<({bool founding, int? priceSen})>(
      context: context,
      builder: (_) => _FoundingDialog(sub: s),
    );
    if (r == null) return;
    await _run(() => ref.read(apiProvider).setSubscriptionFounding(s.id, r.founding, lockedPriceSen: r.priceSen));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(subscriptionsProvider(_query));
    return ListView(
      children: [
        PageHeader(title: l.navSubscriptions),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<SubscriptionState?>(
                  key: const Key('sub-state-filter'),
                  isExpanded: true,
                  initialValue: _state,
                  decoration: InputDecoration(labelText: l.colStatus),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.all)),
                    for (final s in SubscriptionState.values.where((s) => s != SubscriptionState.none))
                      DropdownMenuItem(value: s, child: Text(l.subscription(s))),
                  ],
                  onChanged: (v) => setState(() => _state = v),
                ),
              ),
              FilterChip(
                key: const Key('sub-founding-only'),
                label: Text(l.subsFoundingOnly),
                selected: _foundingOnly,
                onSelected: (v) => setState(() => _foundingOnly = v),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.shopSearchHint),
                  onSubmitted: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(subscriptionsProvider(_query)),
          builder: (subs) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: subs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.subsEmpty)),
                  )
                : Column(
                    children: [
                      for (final s in subs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SubscriptionCard(
                            sub: s,
                            onExtend: () => _extend(s),
                            onPaid: () => _markPaid(s),
                            onCancel: () => _cancel(s),
                            onFounding: () => _founding(s),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.sub,
    required this.onExtend,
    required this.onPaid,
    required this.onCancel,
    required this.onFounding,
  });

  final AdminSubscription sub;
  final VoidCallback onExtend;
  final VoidCallback onPaid;
  final VoidCallback onCancel;
  final VoidCallback onFounding;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = sub;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (s.state) {
      SubscriptionState.trialing => const Color(0xFF1565C0),
      SubscriptionState.active => const Color(0xFF2E7D32),
      SubscriptionState.pastDue => const Color(0xFFB26A00),
      _ => const Color(0xFF616161),
    };
    final pay = s.lastPayment;
    return Card(
      key: Key('sub-${s.shopName}'),
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
                Text(s.shopName, style: Theme.of(context).textTheme.titleMedium),
                Tag(l.subscription(s.state), color: color),
                if (s.isFoundingPrice) Tag(l.subFounding, color: scheme.tertiary),
                PhoneText(s.shopPhone),
              ],
            ),
            Wrap(
              spacing: 24,
              children: [
                InfoLine(l.colPlan, formatRm(s.lockedPriceSen)),
                if (s.trialEndsAt != null) InfoLine(l.colTrialEnds, fmtDateTime(s.trialEndsAt)),
                if (s.currentPeriodEnd != null) InfoLine(l.colPeriodEnd, fmtDateTime(s.currentPeriodEnd)),
                if (pay != null)
                  InfoLine(
                    l.colLastPayment,
                    '${formatRm(pay.amountSen)} · ${l.method(pay.method)} · ${fmtDateTime(pay.paidAt)}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (s.canExtendTrial)
                  OutlinedButton.icon(
                    key: Key('extend-${s.shopName}'),
                    onPressed: onExtend,
                    icon: const Icon(Icons.more_time),
                    label: Text(l.subExtendTrial),
                  ),
                FilledButton.tonalIcon(
                  key: Key('paid-${s.shopName}'),
                  onPressed: onPaid,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(l.subMarkPaid),
                ),
                OutlinedButton.icon(
                  key: Key('founding-${s.shopName}'),
                  onPressed: onFounding,
                  icon: const Icon(Icons.star_outline),
                  label: Text(l.subSetFounding),
                ),
                if (s.canCancel)
                  TextButton.icon(
                    key: Key('cancel-${s.shopName}'),
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(l.subCancel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Paid = ({int months, int? amountSen, PaymentMethod method, String? reference});

class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog({required this.sub});

  final AdminSubscription sub;

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  final _months = TextEditingController(text: '1');
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  PaymentMethod _method = PaymentMethod.duitnow;
  String? _error;

  @override
  void dispose() {
    _months.dispose();
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _ok() {
    final l = context.l10n;
    final months = int.tryParse(_months.text.trim());
    if (months == null || months < 1 || months > 24) {
      setState(() => _error = l.errInvalidMonths);
      return;
    }
    int? amount;
    if (_amount.text.trim().isNotEmpty) {
      amount = parseRmToSen(_amount.text);
      if (amount == null) {
        setState(() => _error = l.errInvalidAmount);
        return;
      }
    }
    Navigator.pop<_Paid>(context, (
      months: months,
      amountSen: amount,
      method: _method,
      reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.subMarkPaid} · ${widget.sub.shopName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.sub.state == SubscriptionState.lapsed)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(l.subLapsedNewPrice)),
            TextField(
              key: const Key('paid-months'),
              controller: _months,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.subMonthsLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('paid-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.subAmountLabel),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMethod>(
              isExpanded: true,
              initialValue: _method,
              decoration: InputDecoration(labelText: l.subMethodLabel),
              items: [for (final m in PaymentMethod.values) DropdownMenuItem(value: m, child: Text(l.method(m)))],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('paid-ref'),
              controller: _ref,
              decoration: InputDecoration(labelText: l.subReferenceLabel),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

class _FoundingDialog extends StatefulWidget {
  const _FoundingDialog({required this.sub});

  final AdminSubscription sub;

  @override
  State<_FoundingDialog> createState() => _FoundingDialogState();
}

class _FoundingDialogState extends State<_FoundingDialog> {
  late bool _founding = widget.sub.isFoundingPrice;
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.subSetFounding} · ${widget.sub.shopName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('founding-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.subFounding),
              value: _founding,
              onChanged: (v) => setState(() => _founding = v),
            ),
            TextField(
              key: const Key('founding-price'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.subLockedPriceLabel,
                helperText: '${l.colPlan} ${formatRm(widget.sub.lockedPriceSen)}',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: () {
            final text = _price.text.trim();
            final price = text.isEmpty ? null : parseRmToSen(text);
            if (text.isNotEmpty && price == null) {
              setState(() => _error = l.errInvalidAmount);
              return;
            }
            Navigator.pop<({bool founding, int? priceSen})>(context, (founding: _founding, priceSen: price));
          },
          child: Text(l.confirm),
        ),
      ],
    );
  }
}
