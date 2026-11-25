import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/router.dart';
import '../app/session.dart';
import 'push_routes.dart';

/// 点了通知 → 打开那一页。App 还在读登录资料（或刚被通知叫醒）时先记着，
/// 等到首页出现了再 push 上去，这样按「返回」会回到首页。
class PushNavigator {
  PushNavigator({required Stream<Map<String, String>> taps, required this.session, required this.router}) {
    _sub = taps.listen((data) {
      _pending = data;
      _flush();
    });
    session.addListener(_flush);
    router.routerDelegate.addListener(_flush);
  }

  final SessionController session;
  final GoRouter router;
  late final StreamSubscription<Map<String, String>> _sub;
  Map<String, String>? _pending;

  void _flush() {
    final data = _pending;
    if (data == null) return;
    final stage = session.stage;
    if (stage == SessionStage.admin) {
      _pending = null; // 客服用网页后台，App 里没有要打开的页面
      return;
    }
    final isSeller = stage == SessionStage.seller;
    if (!isSeller && stage != SessionStage.buyer) return; // 还没登录好
    final current = currentLocation(router);
    if (current.path.isEmpty || isTransientPage(current.path)) return; // 等首页
    if (isSeller != isSellerPath(current.path)) return; // 路由还没跳到这个角色的首页
    _pending = null;
    final location = pushRoute(data, isSeller: isSeller);
    if (location == null) return;
    // 通知是另一家批发商的（一个人可以是几家的成员；data.wholesaler_id）：先换到那一家，
    // 送货总结、订单列表才会读那一家的资料（不然会打开现在选的那一家）
    final switchTo = isSeller ? _otherWholesaler(data['wholesaler_id']) : null;
    if (switchTo == null && current.toString() == location) return;
    // 不在 listener 里面直接改路由
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (switchTo != null) await session.selectWholesaler(switchTo);
      if (currentLocation(router).toString() != location) router.push(location);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// 通知说的批发商：是我的另一家（不是现在选的）才回传，其他（没有、不认识、不是成员）→ null
  String? _otherWholesaler(String? id) {
    if (!isUuid(id) || id == session.wholesalerId) return null;
    final mine = session.context?.wholesalers ?? const [];
    return mine.any((w) => w.id == id) ? id : null;
  }

  void dispose() {
    _sub.cancel();
    session.removeListener(_flush);
    router.routerDelegate.removeListener(_flush);
  }
}
