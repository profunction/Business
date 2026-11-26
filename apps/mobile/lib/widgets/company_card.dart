import 'package:flutter/material.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../app/l10n_x.dart';
import '../l10n/app_localizations.dart';

String companyRoleLabel(L10n l, CompanyRole r) => switch (r) {
  CompanyRole.admin => l.companyRoleAdmin,
  CompanyRole.approver => l.companyRoleApprover,
  CompanyRole.finance => l.companyRoleFinance,
  CompanyRole.requester => l.companyRoleRequester,
};

/// 我是哪几家公司的成员（第八步第 1 期：只显示，没有新功能）。
/// 公司方案在网页付；App 里只说「方案由贵公司管理」，不放付款按钮、不放去网页付款的连结或文字（docs/08-procurement-spec.md 第 11 节）
class CompanyMembershipCard extends StatelessWidget {
  const CompanyMembershipCard({super.key, required this.companies});

  final List<MyCompany> companies;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Card(
      key: const Key('company-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in companies) ...[
              Row(
                children: [
                  const Icon(Icons.apartment, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.name, style: t.titleMedium)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l.companyMemberOf(
                  CompanyRole.values
                      .where(c.roles.contains)
                      .map((r) => companyRoleLabel(l, r))
                      .join(l.localeName == 'zh' ? '、' : ', '),
                ),
                style: t.bodyLarge,
              ),
              if (c.status == CompanyStatus.suspended) Text(l.companySuspended, style: t.bodyLarge),
              Text(l.companyPlanManaged, style: t.bodyMedium),
              const SizedBox(height: 12),
            ],
            Text(l.companyComingSoon, style: t.bodyMedium),
          ],
        ),
      ),
    );
  }
}
