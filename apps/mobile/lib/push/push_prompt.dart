import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/l10n_x.dart';
import '../app/providers.dart';
import '../widgets/common.dart';
import 'push_service.dart';

const _kAsked = 'push_permission_asked';

/// 在适当的时候（批发商第一次打开首页、买家第一次下单后）问一次要不要打开通知：
/// 先用 App 自己的话说明为什么，按「打开通知」才跳出系统的询问。只问一次；拒绝了 App 照样能用。
Future<void> askForPushOnce(BuildContext context, WidgetRef ref, {required bool seller}) async {
  final push = ref.read(pushServiceProvider);
  if (!push.isEnabled) return;
  final prefs = ref.read(sessionProvider).prefs;
  if (prefs.getBool(_kAsked) ?? false) return;
  final PushPermission status;
  try {
    status = await push.permissionStatus();
  } catch (_) {
    return;
  }
  if (status != PushPermission.notDetermined) {
    await prefs.setBool(_kAsked, true); // 已经允许了，或者在系统设定里关掉了：不再问
    return;
  }
  if (!context.mounted) return;
  unawaited(prefs.setBool(_kAsked, true));
  final l = context.l10n;
  final yes = await confirmDialog(
    context,
    title: l.pushAskTitle,
    confirmLabel: l.pushAskAllow,
    cancelLabel: l.pushAskLater,
    content: Text(seller ? l.pushAskSellerBody : l.pushAskBuyerBody, style: Theme.of(context).textTheme.bodyLarge),
  );
  if (!yes) return;
  PushPermission result;
  try {
    result = await push.requestPermission();
  } catch (_) {
    result = PushPermission.denied;
  }
  if (result != PushPermission.granted && context.mounted) showMessage(context, l.pushDenied);
}
