import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../push/push_service.dart';
import '../../widgets/common.dart';
import '../settings/settings_widgets.dart';

/// 批发商的设定：语言、我的公司、新订单怎么通知（App 推送 / WhatsApp）、这部手机的通知、登出。
/// 通知方式只有老板能改（数据库 RLS：wholesalers 只有老板能 update），员工只看得到现在用哪一种
class SellerSettingsPage extends ConsumerStatefulWidget {
  const SellerSettingsPage({super.key});

  @override
  ConsumerState<SellerSettingsPage> createState() => _SellerSettingsPageState();
}

class _SellerSettingsPageState extends ConsumerState<SellerSettingsPage> {
  /// 刚按的通知方式（服务器回来之前先显示选中的）
  NotifyChannel? _savingChannel;
  bool _saving = false;

  Future<void> _save(Future<void> Function(SellerActions actions) change, {NotifyChannel? channel}) async {
    final l = context.l10n;
    setState(() {
      _saving = true;
      _savingChannel = channel;
    });
    try {
      await change(ref.read(sellerActionsProvider));
      // 等新的设定读回来再放开，免得选项先跳回旧的
      await ref.read(wholesalerSettingsProvider.future);
      if (mounted) showMessage(context, l.saved);
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingChannel = null;
        });
      }
    }
  }

  Future<void> _enablePush() async {
    final l = context.l10n;
    PushPermission result;
    try {
      result = await ref.read(pushServiceProvider).requestPermission();
    } catch (_) {
      result = PushPermission.denied;
    }
    ref.invalidate(pushPermissionProvider);
    if (result != PushPermission.granted && mounted) showMessage(context, l.pushDenied);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final wholesalers = session.context?.wholesalers ?? const <MyWholesaler>[];
    final current = session.wholesaler;
    final settings = ref.watch(wholesalerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.language, style: t.titleMedium),
          const SizedBox(height: 8),
          const LanguageCard(),
          const SizedBox(height: 20),
          Text(l.sellerMyBusiness, style: t.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: wholesalers.length <= 1
                ? ListTile(
                    leading: const Icon(Icons.store, size: 32),
                    title: Text(current?.name ?? ''),
                    subtitle: current?.status == 'pending' ? Text(l.sellerPending) : null,
                  )
                // 一个人可以是几家批发商的成员：选现在用哪一家
                : RadioGroup<String>(
                    groupValue: session.wholesalerId,
                    onChanged: (id) {
                      if (id != null) ref.read(sessionProvider).selectWholesaler(id);
                    },
                    child: Column(
                      children: [
                        for (final w in wholesalers)
                          RadioListTile<String>(
                            key: Key('seller-business-${w.id}'),
                            value: w.id,
                            title: Text(w.name),
                            subtitle: w.status == 'pending' ? Text(l.sellerPending) : null,
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Text(l.sellerNotifyTitle, style: t.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: AsyncView<WholesalerSettings>(
              value: settings,
              onRetry: () => ref.invalidate(wholesalerSettingsProvider),
              builder: (s) => current?.isOwner ?? false ? _channelPicker(s) : _channelReadOnly(s),
            ),
          ),
          const SizedBox(height: 20),
          Text(l.pushSettingsTitle, style: t.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: _pushStatus()),
          ),
          const SizedBox(height: 28),
          const LogoutButton(),
        ],
      ),
    );
  }

  Widget _channelPicker(WholesalerSettings s) {
    final l = context.l10n;
    final number = s.whatsappNumber;
    final channel = _savingChannel ?? s.notifyChannel;
    // 「自动」时没装 App 才用 WhatsApp：要另外同意。选「WhatsApp」本身就是同意
    final showOptIn =
        number != null && (channel == NotifyChannel.auto || !s.whatsappOptedIn) && channel != NotifyChannel.push;
    return RadioGroup<NotifyChannel>(
      groupValue: channel,
      onChanged: (c) {
        if (c != null && !_saving && c != s.notifyChannel) {
          _save((a) => a.setNotifyChannel(c), channel: c);
        }
      },
      child: Column(
        children: [
          RadioListTile<NotifyChannel>(
            key: const Key('notify-auto'),
            value: NotifyChannel.auto,
            title: Text(l.sellerNotifyAuto),
            subtitle: Text(l.sellerNotifyAutoHint),
          ),
          RadioListTile<NotifyChannel>(
            key: const Key('notify-push'),
            value: NotifyChannel.push,
            title: Text(l.sellerNotifyPush),
          ),
          RadioListTile<NotifyChannel>(
            key: const Key('notify-whatsapp'),
            value: NotifyChannel.whatsapp,
            enabled: number != null,
            title: Text(l.sellerNotifyWhatsapp),
            subtitle: Text(
              number != null ? l.sellerNotifyWhatsappTo(formatMalaysianMobile(number)) : l.sellerNotifyNoWhatsapp,
            ),
          ),
          if (showOptIn) ...[
            const Divider(),
            SwitchListTile(
              key: const Key('whatsapp-opt-in'),
              value: s.whatsappOptedIn,
              onChanged: _saving ? null : (v) => _save((a) => a.setWhatsappOptIn(v)),
              title: Text(l.sellerWhatsappOptIn),
              subtitle: Text(l.sellerWhatsappOptInHint),
            ),
          ],
        ],
      ),
    );
  }

  /// 员工：只显示现在用哪一种
  Widget _channelReadOnly(WholesalerSettings s) {
    final l = context.l10n;
    return ListTile(
      key: const Key('notify-read-only'),
      leading: const Icon(Icons.notifications, size: 32),
      title: Text(l.notifyChannel(s.notifyChannel)),
      subtitle: Text(l.sellerNotifyOwnerOnly),
    );
  }

  Widget _pushStatus() {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final push = ref.watch(pushServiceProvider);
    if (!push.isEnabled) {
      return InfoLine(icon: Icons.notifications_off, text: l.pushNotSupported);
    }
    return AsyncView<PushPermission>(
      value: ref.watch(pushPermissionProvider),
      onRetry: () => ref.invalidate(pushPermissionProvider),
      builder: (p) {
        if (p == PushPermission.granted) {
          return InfoLine(
            key: const Key('push-on'),
            icon: Icons.notifications_active,
            text: l.pushStatusOn,
            color: AppTheme.confirm,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoLine(
              key: const Key('push-off'),
              icon: Icons.notifications_off,
              text: l.pushStatusOff,
              color: AppTheme.problem,
            ),
            if (p == PushPermission.denied) ...[
              const SizedBox(height: 4),
              Text(l.pushDenied, style: t.bodyMedium?.copyWith(color: Colors.black54)),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('push-enable'),
              icon: const Icon(Icons.notifications_active),
              onPressed: _enablePush,
              label: Text(l.pushAskAllow),
            ),
          ],
        );
      },
    );
  }
}
