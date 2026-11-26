import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/providers.dart';
import 'common.dart';

/// 读现在这一家公司的 get_company_context，读到了才画页面（换公司会重读）
class CompanyScope extends ConsumerWidget {
  const CompanyScope({super.key, required this.builder});

  final Widget Function(BuildContext context, CompanyContext company) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(currentCompanyIdProvider);
    if (id == null) return const SizedBox.shrink();
    return AsyncBody(
      value: ref.watch(companyContextProvider(id)),
      onRetry: () => ref.invalidate(companyContextProvider(id)),
      builder: (c) => builder(context, c),
    );
  }
}

/// 改了公司的东西：重读公司首页的资料和「我是谁」（分店名字、角色可能变了）
void refreshCompany(WidgetRef ref, String companyId) {
  ref.invalidate(companyContextProvider(companyId));
  ref.invalidate(membersProvider(companyId));
  ref.invalidate(billingProvider(companyId));
  ref.read(sessionProvider).refresh();
}
