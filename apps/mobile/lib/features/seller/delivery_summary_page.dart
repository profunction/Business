import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'delivery_sheet.dart';
import 'seller_device.dart';

enum _Busy { print, share }

/// 送货单（今天要送）：上面换日子；拣货单（全部单加起来，给仓库拿货）；每张单按区、再按店排（送货员排路线）。
/// 底下「打印」（A4 PDF，有中文字体）和「分享给送货员」（纯文字，发 WhatsApp）
class DeliverySummaryPage extends ConsumerStatefulWidget {
  const DeliverySummaryPage({super.key, this.date});

  /// 'YYYY-MM-DD'；null = 服务器的今天（马来西亚时间）
  final String? date;

  @override
  ConsumerState<DeliverySummaryPage> createState() => _DeliverySummaryPageState();
}

class _DeliverySummaryPageState extends ConsumerState<DeliverySummaryPage> {
  late String? _date = _validDate(widget.date);
  _Busy? _busy;

  static String? _validDate(String? d) =>
      d != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) && DateTime.tryParse(d) != null ? d : null;

  void _moveDay(DateTime from, int days) =>
      setState(() => _date = dateParam(DateTime(from.year, from.month, from.day + days)));

  Future<void> _print(DeliverySummary s) async {
    final l = context.l10n;
    final device = ref.read(sellerDeviceProvider);
    setState(() => _busy = _Busy.print);
    try {
      await device.printPdf(
        name: deliveryFileName(s),
        build: (format) async => buildDeliveryPdf(s, l, font: await PdfGoogleFonts.notoSansSCRegular(), format: format),
      );
    } catch (_) {
      if (mounted) showMessage(context, l.sellerSummaryPrintFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _share(DeliverySummary s, Rect? origin) async {
    final l = context.l10n;
    final device = ref.read(sellerDeviceProvider);
    setState(() => _busy = _Busy.share);
    try {
      await device.shareText(deliveryShareText(s, l), subject: l.sellerSummaryHeading(l.date(s.date)), origin: origin);
    } catch (_) {
      if (mounted) showMessage(context, l.sellerSummaryShareFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // 新确认的单、出发送货……送货单自己更新
    ref.watch(sellerRealtimeProvider);
    final summary = ref.watch(deliverySummaryProvider(_date));
    final s = summary.value;
    // 换日子的时候新的还在读：日期先照要去的那天显示
    final shownDate = s?.date ?? (_date == null ? null : DateTime.parse(_date!));
    return Scaffold(
      appBar: AppBar(title: Text(l.sellerSummaryTitle)),
      body: Column(
        children: [
          if (shownDate != null) _DayBar(date: shownDate, onMove: (days) => _moveDay(shownDate, days)),
          Expanded(
            child: AsyncView(
              value: summary,
              onRetry: () => ref.invalidate(deliverySummaryProvider(_date)),
              builder: (s) => RefreshIndicator(
                onRefresh: () => ref.refresh(deliverySummaryProvider(_date).future),
                child: _body(context, s),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: s == null || s.isEmpty ? null : _bottom(s),
    );
  }

  Widget _bottom(DeliverySummary s) {
    final l = context.l10n;
    final busy = _busy != null;
    return BottomAction(
      above: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Builder(
          builder: (context) => OutlinedButton.icon(
            key: const Key('summary-share'),
            icon: _busy == _Busy.share
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                : const Icon(Icons.share),
            onPressed: busy
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    _share(s, box == null ? null : box.localToGlobal(Offset.zero) & box.size);
                  },
            label: Text(l.sellerSummaryShare, textAlign: TextAlign.center),
          ),
        ),
      ),
      child: BusyButton(
        key: const Key('summary-print'),
        icon: Icons.print,
        label: l.sellerSummaryPrint,
        busy: _busy == _Busy.print,
        onPressed: busy ? null : () => _print(s),
      ),
    );
  }

  Widget _body(BuildContext context, DeliverySummary s) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final groups = groupByZone(s, l);
    var n = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (s.pendingCount > 0) ...[
          NoticeBanner(
            key: const Key('summary-pending'),
            color: AppTheme.warningBg,
            icon: Icons.hourglass_top,
            text: l.sellerSummaryPending(s.pendingCount),
            action: TextButton(
              onPressed: () => context.push('/seller/orders?tab=pending'),
              child: Text(l.sellerSummaryGoConfirm, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (s.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                const Icon(Icons.local_shipping, size: 80, color: Colors.black38),
                const SizedBox(height: 12),
                Text(l.sellerSummaryEmpty, textAlign: TextAlign.center, style: t.titleLarge),
              ],
            ),
          )
        else ...[
          Card(
            color: AppTheme.successBg,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.sellerTodayCount(s.orderCount, formatRm(s.totalSen)),
                key: const Key('summary-total'),
                style: t.titleLarge,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PickingCard(summary: s),
          const SizedBox(height: 20),
          Text(l.sellerSummaryOrders, style: t.titleLarge),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.map, size: 26),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g.zone, style: t.titleMedium)),
                ],
              ),
            ),
            for (final o in g.orders) ...[_DeliveryOrderCard(no: ++n, order: o), const SizedBox(height: 12)],
          ],
        ],
      ],
    );
  }
}

/// 换日子：‹ 前一天 ｜ 11月26日周四 ｜ 后一天 ›
class _DayBar extends StatelessWidget {
  const _DayBar({required this.date, required this.onMove});

  final DateTime date;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget arrow(IconData icon, String tip, int days, Key key) => SizedBox(
      width: 64,
      height: 64,
      child: IconButton.filledTonal(
        key: key,
        tooltip: tip,
        iconSize: 36,
        onPressed: () => onMove(days),
        icon: Icon(icon),
      ),
    );
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            arrow(Icons.chevron_left, l.sellerSummaryPrevDay, -1, const Key('summary-prev-day')),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.date(date),
                key: const Key('summary-date'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(width: 8),
            arrow(Icons.chevron_right, l.sellerSummaryNextDay, 1, const Key('summary-next-day')),
          ],
        ),
      ),
    );
  }
}

/// 拣货单：每样东西一共要拿几箱 / 几包
class _PickingCard extends StatelessWidget {
  const _PickingCard({required this.summary});

  final DeliverySummary summary;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.sellerSummaryPicking, style: t.titleLarge),
            Text(l.sellerSummaryPickingHint, style: t.bodyMedium?.copyWith(color: Colors.black54)),
            const SizedBox(height: 8),
            for (final p in summary.picking) ...[
              const Divider(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: t.titleMedium),
                        Text(
                          l.packQty(l.unit(p.unit), p.packQty),
                          style: t.bodyMedium?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(l.qtyUnit(p.qty, p.unit), style: t.titleLarge),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 送货单上的一张单：店的资料、明细（缺货的划掉）、总额、付款方式、买家备注。按一下打开订单
class _DeliveryOrderCard extends StatelessWidget {
  const _DeliveryOrderCard({required this.no, required this.order});

  final int no;
  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final o = order;
    final shop = o.shop;
    return Card(
      child: InkWell(
        key: Key('summary-order-${o.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/seller/orders/${o.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$no. ${shop.name}', style: t.titleLarge),
              // 放不下（马来文的「送货中」很长、大字）就把状态放到下一行
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(o.orderNo, style: t.bodyMedium?.copyWith(color: Colors.black54)),
                  StatusChip(status: o.status),
                ],
              ),
              const SizedBox(height: 4),
              if (shop.contactName != null) InfoLine(icon: Icons.person, text: l.sellerContact(shop.contactName!)),
              if (shop.phone != null) InfoLine(icon: Icons.phone, text: formatMalaysianMobile(shop.phone)),
              if (shop.address != null) InfoLine(icon: Icons.location_on, text: shop.address!),
              const Divider(height: 20),
              for (final i in o.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${i.name}  ×${l.qtyUnit(i.qty, i.unit)}${i.isOutOfStock ? ' ${l.sellerSummaryOosMark}' : ''}',
                    style: t.titleMedium?.copyWith(
                      decoration: i.isOutOfStock ? TextDecoration.lineThrough : null,
                      color: i.isOutOfStock ? Colors.black45 : null,
                    ),
                  ),
                ),
              const Divider(height: 20),
              AmountRow(label: l.total, value: formatRm(o.totalSen), bold: true),
              if (o.paymentTerms.isNotEmpty)
                InfoLine(icon: Icons.payments, text: l.paymentTerms(o.paymentTerms.map(l.paymentTerm).join(' / '))),
              if (o.note != null) InfoLine(icon: Icons.notes, text: l.sellerBuyerNote(o.note!)),
            ],
          ),
        ),
      ),
    );
  }
}
