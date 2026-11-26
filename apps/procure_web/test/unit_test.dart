import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_procure/app/l10n_x.dart';
import 'package:jb_procure/l10n/app_localizations.dart';
import 'package:wholesale_core/wholesale_core.dart';

void main() {
  test('三个语言的 ARB 键一样', () {
    Set<String> keys(String lang) =>
        (jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>).keys
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(keys('en'), keys('zh'));
    expect(keys('ms'), keys('zh'));
  });

  test('马来西亚时间', () {
    expect(fmtDateTime(DateTime.utc(2026, 11, 30, 17, 5)), '2026-12-01 01:05');
    expect(fmtDay(DateTime(2026, 12, 1)), '2026-12-01');
  });

  test('收件箱的文字（三种语言）、错误代码', () async {
    final page = InboxPage.fromJson(
      jsonDecode(File('../../packages/core/test/fixtures/procure_inbox.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final lang in ['zh', 'en', 'ms']) {
      final l = await L10n.delegate.load(Locale(lang));
      for (final i in page.items) {
        final t = l.inboxText(i);
        expect(t.title, isNot(l.inboxGeneric), reason: '${i.eventType} $lang');
        expect(t.body, isNotEmpty);
      }
      expect(l.error(const AppError('PLAN_LIMIT_SITES', detail: '3')), contains('3'));
      expect(l.error(const AppError('LAST_COMPANY_ADMIN')), l.errLastAdmin);
      expect(l.roles({CompanyRole.requester, CompanyRole.admin}), startsWith(l.roleAdmin));
    }
    final zh = await L10n.delegate.load(const Locale('zh'));
    expect(zh.inboxText(page.items.first).title, '方案账单 CI2611-0001');
  });
}
