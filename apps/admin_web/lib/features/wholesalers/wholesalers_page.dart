import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_link.dart';

/// 批发商：审核（自己注册的要客服通过才出现在买家面前）、停权 / 恢复、佣金比例、创始会员、WhatsApp 同意；
/// 也可以进去代他管商品
class WholesalersPage extends ConsumerStatefulWidget {
  const WholesalersPage({super.key, this.pendingOnly = false});

  final bool pendingOnly;

  @override
  ConsumerState<WholesalersPage> createState() => _WholesalersPageState();
}

class _WholesalersPageState extends ConsumerState<WholesalersPage> {
  late WholesalerStatus? _status = widget.pendingOnly ? WholesalerStatus.pending : null;
  String _search = '';

  WholesalerQuery get _query => (status: _status, search: _search);

  void _refresh() {
    ref.invalidate(wholesalersProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _setStatus(AdminWholesaler w, WholesalerStatus status) async {
    final l = context.l10n;
    String? note;
    if (status == WholesalerStatus.suspended) {
      note = await showInputDialog(context, title: '${l.wholesalerStatus(status)} · ${w.name}', label: l.wsNoteLabel);
      if (note == null) return;
    }
    if (!mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).setWholesalerStatus(w.id, status, note: note),
      success: l.saved,
    );
    if (ok) _refresh();
  }

  Future<void> _setRate(AdminWholesaler w) async {
    final l = context.l10n;
    final current = w.commissionRateOverride;
    final text = await showInputDialog(
      context,
      title: '${l.wsSetRate} · ${w.name}',
      label: l.wsRateLabel,
      help: l.wsRateDefaults(
        w.industryDefaultRate == null ? '-' : formatRate(w.industryDefaultRate!),
        w.industryFoundingRate == null ? '-' : formatRate(w.industryFoundingRate!),
      ),
      initial: current == null ? '' : formatSen(current * 100),
      keyboard: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) => v.trim().isEmpty || parsePercent(v) != null ? null : l.errInvalidRate,
    );
    if (text == null || !mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).setCommissionRate(w.id, text.trim().isEmpty ? null : parsePercent(text)),
      success: l.saved,
    );
    if (ok) _refresh();
  }

  Future<void> _markListingFee(AdminWholesaler w) async {
    final l = context.l10n;
    final reference = await showInputDialog(
      context,
      title: '${l.wsMarkListingFee} · ${w.name}',
      label: l.subReferenceLabel,
    );
    if (reference == null || !mounted) return;
    await _toggle(
      () =>
          ref.read(apiProvider).markListingFeePaid(w.id, reference: reference.trim().isEmpty ? null : reference.trim()),
    );
  }

  Future<void> _toggle(Future<Object?> Function() action) async {
    final ok = await runAction(context, action, success: context.l10n.saved);
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = ref.watch(wholesalersProvider(_query));
    final api = ref.read(apiProvider);
    return ListView(
      children: [
        PageHeader(title: l.navWholesalers),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<WholesalerStatus?>(
                key: const Key('ws-status-filter'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: null, label: Text(l.all)),
                  for (final s in WholesalerStatus.values)
                    ButtonSegment(
                      value: s,
                      label: Text(l.wholesalerStatus(s), key: Key('ws-filter-${s.name}')),
                    ),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  key: const Key('ws-search'),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.searchHint),
                  onSubmitted: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: value,
          onRetry: () => ref.invalidate(wholesalersProvider(_query)),
          builder: (list) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.wsEmpty)),
                  )
                : Column(
                    children: [
                      for (final w in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _WholesalerCard(
                            w: w,
                            onStatus: (s) => _setStatus(w, s),
                            onRate: () => _setRate(w),
                            onFounding: (v) => _toggle(() => api.setWholesalerFounding(w.id, v)),
                            onOptIn: (v) => _toggle(() => api.setWhatsappOptInAsAdmin(wholesalerId: w.id, optIn: v)),
                            onListingFee: () => _markListingFee(w),
                            onPayLink: () =>
                                showPaymentLink(context, ref, PaymentPurpose.listingFee, w.id, title: w.name),
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

/// '1.5' / '1.5%' → 0.015；不是 0–20、超过两位小数 → null
double? parsePercent(String input) {
  final s = input.trim().replaceAll('%', '').trim();
  if (!RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(s)) return null;
  final v = double.parse(s);
  if (v < 0 || v > 20) return null;
  // 用整数算，避免 1.15 / 100 变成 0.011499999
  final parts = s.split('.');
  final hundredths = int.parse(parts[0]) * 100 + (parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return hundredths / 10000;
}

class _WholesalerCard extends StatelessWidget {
  const _WholesalerCard({
    required this.w,
    required this.onStatus,
    required this.onRate,
    required this.onFounding,
    required this.onOptIn,
    required this.onListingFee,
    required this.onPayLink,
  });

  final AdminWholesaler w;
  final VoidCallback onListingFee;
  final VoidCallback onPayLink;
  final ValueChanged<WholesalerStatus> onStatus;
  final VoidCallback onRate;
  final ValueChanged<bool> onFounding;
  final ValueChanged<bool> onOptIn;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final statusColor = switch (w.status) {
      WholesalerStatus.pending => const Color(0xFFB26A00),
      WholesalerStatus.active => const Color(0xFF2E7D32),
      WholesalerStatus.suspended => scheme.error,
    };
    return Card(
      key: Key('ws-${w.id}'),
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
                Text(w.name, style: Theme.of(context).textTheme.titleMedium),
                Tag(l.wholesalerStatus(w.status), color: statusColor),
                if (w.isFounding && w.foundingNo != null) Tag(l.wsFoundingNo(w.foundingNo!), color: scheme.tertiary),
                if (w.isFounding)
                  Tag(
                    w.foundingFeePaidAt != null ? l.wsListingFeePaid : l.wsListingFeeUnpaid,
                    color: w.foundingFeePaidAt != null ? const Color(0xFF2E7D32) : const Color(0xFFB26A00),
                  ),
                Text(l.wsCommission('${formatRate(w.commissionRate)}（${l.rateSource(w.commissionRateSource)}）')),
                if (w.pendingOrderCount > 0) Text(l.wsPendingOrders(w.pendingOrderCount)),
              ],
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (w.contactName != null) Text(w.contactName!),
                PhoneText(w.contactPhone),
                if (w.industryName != null) Text(w.industryName!.of(l.lang)),
                if (w.regionName != null) Text(w.regionName!.of(l.lang)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (w.status == WholesalerStatus.pending) ...[
                  FilledButton.icon(
                    key: Key('approve-${w.id}'),
                    onPressed: () => onStatus(WholesalerStatus.active),
                    icon: const Icon(Icons.check),
                    label: Text(l.wsApprove),
                  ),
                  OutlinedButton(
                    key: Key('reject-${w.id}'),
                    onPressed: () => onStatus(WholesalerStatus.suspended),
                    child: Text(l.wsReject),
                  ),
                ],
                if (w.status == WholesalerStatus.active)
                  OutlinedButton.icon(
                    key: Key('suspend-${w.id}'),
                    onPressed: () => onStatus(WholesalerStatus.suspended),
                    icon: const Icon(Icons.block),
                    label: Text(l.wsSuspend),
                  ),
                if (w.status == WholesalerStatus.suspended)
                  OutlinedButton.icon(
                    key: Key('reactivate-${w.id}'),
                    onPressed: () => onStatus(WholesalerStatus.active),
                    icon: const Icon(Icons.restore),
                    label: Text(l.wsReactivate),
                  ),
                OutlinedButton.icon(
                  key: Key('rate-${w.id}'),
                  onPressed: onRate,
                  icon: const Icon(Icons.percent),
                  label: Text(l.wsSetRate),
                ),
                FilledButton.tonalIcon(
                  key: Key('products-${w.id}'),
                  onPressed: () => context.go(
                    Uri(path: '/wholesalers/${w.id}/products', queryParameters: {'name': w.name}).toString(),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(l.wsProducts(w.activeProductCount)),
                ),
                TextButton(onPressed: () => context.go('/orders?wholesaler=${w.id}'), child: Text(l.navOrders)),
                _Switch(key: Key('founding-${w.id}'), label: l.wsFounding, value: w.isFounding, onChanged: onFounding),
                if (w.foundingFeePaidAt == null) ...[
                  OutlinedButton.icon(
                    key: Key('listingfee-${w.id}'),
                    onPressed: onListingFee,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(l.wsMarkListingFee),
                  ),
                  OutlinedButton.icon(
                    key: Key('listinglink-${w.id}'),
                    onPressed: onPayLink,
                    icon: const Icon(Icons.link),
                    label: Text(l.payLink),
                  ),
                ],
                _Switch(
                  key: Key('optin-${w.id}'),
                  label: l.wsWhatsappOptIn,
                  value: w.whatsappOptInAt != null,
                  onChanged: onOptIn,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: value, onChanged: onChanged),
            Text(label),
          ],
        ),
      ),
    );
  }
}
