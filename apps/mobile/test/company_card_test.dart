// 第八步第 1 期：App 认得公司员工（只显示，没有新功能）。公司方案不在 App 卖：不叫人去哪里付钱。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jb_wholesale/l10n/app_localizations.dart';
import 'package:jb_wholesale/widgets/company_card.dart';
import 'package:wholesale_core/wholesale_core.dart';

void main() {
  final context = MyContext.fromJson(
    jsonDecode(File('../../packages/core/test/fixtures/procure_my_context.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  for (final lang in ['zh', 'en', 'ms']) {
    testWidgets('公司成员卡片（$lang，400 宽）', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: CompanyMembershipCard(companies: context.companies)),
        ),
      );
      await tester.pumpAndSettle();
      final l = lookupL10n(Locale(lang));
      expect(find.text('Grand Hotel Johor Bahru'), findsOneWidget);
      expect(find.textContaining(l.companyRoleFinance), findsOneWidget);
      expect(find.text(l.companyPlanManaged), findsOneWidget);
      final all = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
      expect(
        all,
        isNot(matches(RegExp(r'付款|网页|http|pay online|website|bayar dalam talian|laman web', caseSensitive: false))),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
