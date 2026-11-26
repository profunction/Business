import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

const _pageSize = 50;

/// 操作记录：谁、什么时候、代哪家店 / 批发商、改了什么（新到旧，按「再看多一些」往前翻）
class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  bool _adminOnly = true;
  final _rows = <AuditEntry>[];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _rows.clear();
        _hasMore = true;
      }
    });
    try {
      final page = await ref
          .read(apiProvider)
          .listAuditLogs(adminOnly: _adminOnly, limit: _pageSize, beforeId: _rows.isEmpty ? null : _rows.last.id);
      if (!mounted) return;
      setState(() {
        _rows.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListView(
      children: [
        PageHeader(
          title: l.navAudit,
          actions: [
            FilterChip(
              key: const Key('audit-admin-only'),
              label: Text(l.auditAdminOnly),
              selected: _adminOnly,
              onSelected: (v) {
                setState(() => _adminOnly = v);
                _load(reset: true);
              },
            ),
            IconButton(tooltip: l.retry, onPressed: () => _load(reset: true), icon: const Icon(Icons.refresh)),
          ],
        ),
        if (_error != null && _rows.isEmpty)
          ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
        else ...[
          if (_rows.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l.auditEmpty)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              child: Column(
                children: [
                  for (final e in _rows) ...[_AuditTile(e), if (e != _rows.last) const Divider(height: 1)],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : _hasMore
                  ? OutlinedButton(key: const Key('audit-more'), onPressed: _load, child: Text(l.loadMore))
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile(this.e);

  final AuditEntry e;

  String _value(Object? v) => v == null ? '∅' : (v is String ? v : jsonEncode(v));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final who = [
      e.actorName,
      formatMalaysianMobile(e.actorPhone),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final forWhom = [e.shopName, e.wholesalerName].whereType<String>().join(' · ');
    final keys = e.changedKeys.where((k) => k != 'updated_at').toList();
    return ExpansionTile(
      key: Key('audit-${e.id}'),
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l.auditAction(e.action), style: Theme.of(context).textTheme.titleSmall),
          if (e.tableName != null) Text(e.tableName!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      subtitle: Text(
        [
          fmtDateTime(e.createdAt),
          if (who.isNotEmpty) '${l.auditActor}: $who',
          if (forWhom.isNotEmpty) '${l.auditActingFor}: $forWhom',
        ].join('   '),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.auditChanges, style: Theme.of(context).textTheme.labelLarge),
        for (final k in keys)
          SelectableText(
            '$k: ${_value(e.before?[k])}  →  ${_value(e.after?[k])}',
            style: const TextStyle(fontSize: 13),
          ),
      ],
    );
  }
}
