import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_card.dart';

/// 开店向导：一页一个问题。店名 -> 做什么的 -> 哪一区 -> 地址（可以不填）
class RegisterShopPage extends ConsumerStatefulWidget {
  const RegisterShopPage({super.key});

  @override
  ConsumerState<RegisterShopPage> createState() => _RegisterShopPageState();
}

class _RegisterShopPageState extends ConsumerState<RegisterShopPage> {
  int _step = 0;
  final _name = TextEditingController();
  final _address = TextEditingController();
  ShopType? _type;
  String? _zoneId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _canNext => switch (_step) {
    0 => _name.text.trim().isNotEmpty,
    1 => _type != null,
    2 => _zoneId != null,
    _ => true,
  };

  Future<void> _next() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .registerShop(
            name: _name.text.trim(),
            zoneId: _zoneId!,
            shopType: _type!,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          );
      await ref.read(sessionProvider).refresh(); // router 会带去首页
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.registerTitle),
          leading: _step == 0 ? null : BackButton(onPressed: () => setState(() => _step--)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: LinearProgressIndicator(value: (_step + 1) / 4, minHeight: 6),
          ),
        ),
        body: SafeArea(child: _body(context)),
        bottomNavigationBar: BottomAction(
          child: BusyButton(
            key: const Key('register-next'),
            label: _step < 3 ? l.next : l.registerFinish,
            busy: _busy,
            onPressed: _canNext ? _next : null,
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    switch (_step) {
      case 0:
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // 公司员工（不是小店老板）登录：先告诉他是哪家公司的成员（公司采购功能之后会放在 App）
            if (ref.watch(sessionProvider).context?.companies.isNotEmpty ?? false) ...[
              CompanyMembershipCard(companies: ref.watch(sessionProvider).context!.companies),
              const SizedBox(height: 24),
            ],
            Text(l.shopNameQuestion, style: t.headlineSmall),
            const SizedBox(height: 20),
            TextField(
              key: const Key('shop-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: t.titleLarge,
              decoration: InputDecoration(hintText: l.shopNameHint),
              onChanged: (_) => setState(() {}),
            ),
          ],
        );
      case 1:
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.shopTypeQuestion, style: t.headlineSmall),
            const SizedBox(height: 20),
            for (final type in ShopType.values) ...[
              _ChoiceButton(
                label: l.shopType(type),
                icon: switch (type) {
                  ShopType.restaurant => Icons.restaurant,
                  ShopType.drinkStall => Icons.local_cafe,
                  ShopType.grocery => Icons.storefront,
                  ShopType.other => Icons.more_horiz,
                },
                selected: _type == type,
                onTap: () => setState(() => _type = type),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      case 2:
        final zones = ref.watch(zonesProvider);
        return AsyncView(
          value: zones,
          onRetry: () => ref.invalidate(zonesProvider),
          builder: (list) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l.zoneQuestion, style: t.headlineSmall),
              const SizedBox(height: 20),
              for (final z in list) ...[
                _ChoiceButton(
                  label: z.name.of(l.lang),
                  icon: Icons.place,
                  selected: _zoneId == z.id,
                  onTap: () => setState(() => _zoneId = z.id),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      default:
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.addressQuestion, style: t.headlineSmall),
            const SizedBox(height: 8),
            Text(l.optional, style: t.bodyLarge?.copyWith(color: Colors.black54)),
            const SizedBox(height: 20),
            TextField(
              key: const Key('shop-address'),
              controller: _address,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              style: t.titleMedium,
              decoration: InputDecoration(hintText: l.addressHint),
            ),
          ],
        );
    }
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? scheme.primary : const Color(0xFFD5D9D2), width: selected ? 3 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Icon(icon, size: 32, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.titleLarge)),
              if (selected) Icon(Icons.check_circle, size: 32, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
