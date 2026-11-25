import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../push/push_prompt.dart';
import '../../widgets/common.dart';

/// 批发商首页：四个大按钮（新订单、今天要送、商品和价钱、上传价目表）。
/// 新订单一进来（Realtime）数字就自己更新。第一次打开时问要不要打开通知
class SellerHomePage extends ConsumerStatefulWidget {
  const SellerHomePage({super.key});

  @override
  ConsumerState<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends ConsumerState<SellerHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) askForPushOnce(context, ref, seller: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // 订单一有变化（新订单、WhatsApp 按了确认、买家取消）就刷新首页
    ref.watch(sellerRealtimeProvider);
    final home = ref.watch(sellerHomeProvider);
    final sessionName = ref.watch(sessionProvider.select((s) => s.wholesaler?.name));
    return Scaffold(
      appBar: AppBar(
        title: Text(home.value?.wholesaler.name ?? sessionName ?? l.appTitle),
        actions: [
          IconButton(
            key: const Key('seller-open-settings'),
            tooltip: l.settings,
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/seller/settings'),
          ),
        ],
      ),
      body: AsyncView(
        value: home,
        onRetry: () => ref.invalidate(sellerHomeProvider),
        builder: (h) => RefreshIndicator(
          onRefresh: () => ref.refresh(sellerHomeProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ..._banner(l, h.wholesaler),
              BigTile(
                key: const Key('seller-new-orders'),
                icon: Icons.notifications_active,
                title: l.sellerHomeNewOrders(h.pendingCount),
                subtitle: h.pendingCount > 0 && h.oldestPendingAt != null
                    ? l.sellerOldestWaiting(l.waited(h.oldestPendingAt!))
                    : l.sellerNoNewOrders,
                color: h.pendingCount > 0 ? const Color(0xFFE8892B) : const Color(0xFF607D8B),
                onTap: () => context.push('/seller/orders?tab=pending'),
              ),
              const SizedBox(height: 14),
              BigTile(
                key: const Key('seller-today'),
                icon: Icons.local_shipping,
                title: l.sellerHomeToday(h.todayOrderCount),
                subtitle: h.todayOrderCount > 0 ? l.sellerTodayTotal(formatRm(h.todayTotalSen)) : l.sellerNothingToday,
                color: const Color(0xFF1565C0),
                onTap: () => context.push('/seller/orders?tab=today'),
              ),
              const SizedBox(height: 14),
              BigTile(
                key: const Key('seller-products'),
                icon: Icons.inventory_2,
                title: l.sellerHomeProducts,
                subtitle: _productLine(l, h.productCounts),
                onTap: () => context.push('/seller/products'),
              ),
              const SizedBox(height: 14),
              BigTile(
                key: const Key('seller-import'),
                icon: Icons.document_scanner,
                title: l.sellerHomeImport,
                subtitle: _importLine(l, h.latestImport),
                color: const Color(0xFF6A1B9A),
                onTap: () {
                  final latest = h.latestImport;
                  // AI 读好了：直接去确认那一份；还在读：回去等那一份
                  context.push(switch (latest?.status) {
                    ImportStatus.review => '/seller/import/${latest!.id}',
                    ImportStatus.processing => '/seller/import?id=${latest!.id}',
                    _ => '/seller/import',
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 等客服审核：买家还看不到，但可以先放商品、上传价目表
  List<Widget> _banner(L10n l, SellerWholesaler w) {
    final (text, icon, color) = switch (w.status) {
      'pending' => (l.sellerPendingBanner, Icons.hourglass_top, AppTheme.warningBg),
      'suspended' => (l.sellerSuspendedBanner, Icons.block, const Color(0xFFFDE7E7)),
      _ => (null, null, null),
    };
    if (text == null) return const [];
    return [
      NoticeBanner(key: const Key('seller-status-banner'), color: color!, icon: icon!, text: text),
      const SizedBox(height: 16),
    ];
  }

  String _productLine(L10n l, ProductCounts c) => [
    l.sellerProductsActive(c.active),
    if (c.outOfStock > 0) l.sellerProductsOutOfStock(c.outOfStock),
    if (c.lowStock > 0) l.sellerProductsLowStock(c.lowStock),
    if (c.draft > 0) l.sellerProductsDraft(c.draft),
  ].join(' · ');

  String _importLine(L10n l, ImportRef? latest) => switch (latest?.status) {
    null => l.sellerImportNone,
    ImportStatus.processing => l.sellerImportProcessing,
    ImportStatus.review => l.sellerImportReview,
    ImportStatus.failed => l.sellerImportFailed,
    ImportStatus.applied => l.sellerImportApplied(l.dateOnly(latest!.createdAt)),
  };
}
