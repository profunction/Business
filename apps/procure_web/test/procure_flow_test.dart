// 用示范模式（本机数据库导出的真实样本，不连服务器）把公司采购网页点一遍：登录、注册公司、换公司、首页、比价、分店、
// 成员和邀请、方案和付款、收件箱、公司资料；不同角色看到的东西；电脑（1280）和手机（400）宽度都不能 overflow。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _co = 'Grand Hotel Johor Bahru';

void main() {
  testWidgets('手机号 + 验证码登录 → 首页', (tester) async {
    final r = await pumpProcure(tester, loggedIn: false);
    expect(find.text('公司采购登录'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone-field')), '12345');
    await tester.tap(find.byKey(const Key('send-code')));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入马来西亚手机号'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone-field')), '012-000 0005');
    await tester.tap(find.byKey(const Key('send-code')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('sendOtp +60120000005'));
    await tester.enterText(find.byKey(const Key('otp-field')), '111111');
    await tester.tap(find.byKey(const Key('verify-code')));
    await tester.pumpAndSettle();
    expect(find.textContaining('验证码不对'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.tap(find.byKey(const Key('verify-code')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-banner')), findsOneWidget);
    expect(find.text(_co), findsWidgets);
    expect(find.textContaining('试用中，到'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('公司采购登录'), findsOneWidget);
  });

  testWidgets('批发商账号进不来', (tester) async {
    await pumpProcure(tester, seller: true);
    expect(find.text('这个账号是批发商'), findsOneWidget);
    await tester.tap(find.byKey(const Key('denied-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('公司采购登录'), findsOneWidget);
  });

  for (final size in [desktop, phone]) {
    final w = size.width.toInt();
    testWidgets('每一页都打得开、不 overflow（$w 宽）', (tester) async {
      await pumpProcure(tester, size: size);
      for (final page in ['home', 'browse', 'sites', 'members', 'billing', 'inbox', 'company']) {
        await goTo(tester, page);
        expect(tester.takeException(), isNull, reason: page);
      }
      await goTo(tester, 'billing');
      expect(find.text('CI2611-0001'), findsOneWidget);
      await tester.tap(find.byKey(const Key('company-switcher')));
      await tester.pumpAndSettle();
      expect(find.text('注册另一家公司'), findsOneWidget);
      await tester.tap(find.byKey(const Key('switch-register')));
      await tester.pumpAndSettle();
      expect(find.text('注册公司'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('还没有公司 → 注册公司 → 首页（$w 宽）', (tester) async {
      final r = await pumpProcure(tester, size: size, noCompany: true);
      expect(find.textContaining('你还不是任何公司的成员'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reg-submit')));
      await tester.pumpAndSettle();
      expect(find.text('请填公司名字'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reg-name')), 'Kilang Maju Sdn Bhd');
      await tester.enterText(find.byKey(const Key('reg-site-name')), 'Kilang Senai');
      await tapKey(tester, 'reg-submit');
      expect(find.text('请选分店的送货区'), findsOneWidget);
      await tapKey(tester, 'reg-site-zone');
      await tester.tap(find.text('士古来').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'reg-submit');
      expect(r.api.calls, contains('registerCompany Kilang Maju Sdn Bhd'));
      expect(find.text('Kilang Maju Sdn Bhd'), findsWidgets);
      expect(find.textContaining('试用中'), findsOneWidget);
      expect(find.text('Kilang Senai'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('再注册一家公司 → 公司切换', (tester) async {
    final r = await pumpProcure(tester);
    await tester.tap(find.byKey(const Key('company-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-register')));
    await tester.pumpAndSettle();
    expect(find.textContaining('再注册一家公司'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reg-name')), 'Grand Resort Desaru');
    await tapKey(tester, 'reg-submit');
    expect(r.api.calls, contains('registerCompany Grand Resort Desaru'));
    expect(find.textContaining('方案停了'), findsOneWidget, reason: '同一个号码第二家：没有试用，要先付');
    await tester.tap(find.byKey(const Key('company-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-$_co')));
    await tester.pumpAndSettle();
    expect(find.textContaining('试用中，到'), findsOneWidget);
  });

  testWidgets('比价：选分店、同一样东西几家放一起、最便宜', (tester) async {
    final r = await pumpProcure(tester);
    await goTo(tester, 'browse');
    expect(r.api.calls, contains('getOffers'));
    expect(find.text('最便宜'), findsWidgets);
    expect(find.textContaining('仙'), findsWidgets);
    await tester.enterText(find.byKey(const Key('browse-search')), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('没有送到这个分店的商品'), findsOneWidget);
  });

  testWidgets('分店：加（上限 3 个）、改、封存', (tester) async {
    final r = await pumpProcure(tester);
    await goTo(tester, 'sites');
    expect(find.text('Grand Hotel 中央厨房'), findsOneWidget);
    expect(find.textContaining('（2 / 3 个）'), findsOneWidget);
    await tapKey(tester, 'site-add');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('请填分店名字、选送货区'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('site-name')), 'Grand Hotel 酒吧');
    await tester.tap(find.byKey(const Key('site-zone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('士古来').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('site-code')), 'BAR');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('addSite Grand Hotel 酒吧'));
    expect(find.text('分店加好了'), findsOneWidget);
    expect(find.text('BAR'), findsOneWidget);

    await scrollTop(tester);
    await tapKey(tester, 'site-add');
    await tester.enterText(find.byKey(const Key('site-name')), '第四个');
    await tester.tap(find.byKey(const Key('site-zone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('士古来').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('方案最多 3 个分店，请换方案'), findsOneWidget);

    await tapKey(tester, 'site-archive-Grand Hotel 酒吧');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('分店封存了'), findsOneWidget);
    expect(find.text('已封存'), findsOneWidget);

    await tapKey(tester, 'site-edit-Grand Hotel 宴会厅');
    await tester.enterText(find.byKey(const Key('site-name')), 'Grand Hotel 大宴会厅');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Grand Hotel 大宴会厅'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('成员：邀请（号码、角色、分店）、改角色、最后一个管理员、取消邀请', (tester) async {
    final r = await pumpProcure(tester);
    await goTo(tester, 'members');
    expect(find.text('林美玲'), findsOneWidget);
    expect(find.text('Aisyah'), findsOneWidget);
    expect(find.text('012-333 4444'), findsOneWidget);

    await tapKey(tester, 'member-invite');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入马来西亚手机号'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('member-phone')), '012-555 0001');
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('至少选一个角色'), findsOneWidget);
    await tester.tap(find.byKey(const Key('role-requester')));
    await tester.tap(find.byKey(const Key('member-all-sites')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('选他能管的分店'), findsOneWidget);
    await tester.tap(find.byKey(const Key('member-site-Grand Hotel 宴会厅')));
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('inviteMember +60125550001 requester'));
    expect(find.text('012-555 0001'), findsOneWidget);

    await tapKey(tester, 'member-edit-林美玲');
    await tester.tap(find.byKey(const Key('role-admin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('公司至少要有一个管理员'), findsOneWidget);

    await tapKey(tester, 'member-edit-Rajesh Kumar');
    await tester.tap(find.byKey(const Key('role-approver')));
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('setMember approver,finance true'));

    await tapKey(tester, 'invite-cancel-60123334444');
    expect(find.text('邀请取消了'), findsOneWidget);
    expect(find.text('012-333 4444'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('方案：换方案（账单照新方案重开）→ 付款开新分页；网关没设定 → 说清楚', (tester) async {
    final r = await pumpProcure(tester);
    await goTo(tester, 'billing');
    expect(find.text('下一期'), findsOneWidget, reason: '样本选了 Pro');
    await tapKey(tester, 'choose-co_starter');
    expect(find.textContaining('RM290.00 / 月'), findsWidgets);
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('changePlan co_starter monthly'));
    expect(find.text('作废'), findsOneWidget, reason: '旧的 Pro 账单作废');
    final pay = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('pay-CI'),
    );
    expect(pay, findsOneWidget);
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();
    expect(r.opener.opened.single, startsWith('https://'));
    expect(find.textContaining('金额 RM290.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pay-done')));
    await tester.pumpAndSettle();

    r.api.paymentError = 'PAYMENT_NOT_CONFIGURED';
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();
    expect(find.textContaining('网上付款还没开通'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收件箱：按一条 → 已读、去方案页；全部已读', (tester) async {
    final r = await pumpProcure(tester);
    expect(find.text('1'), findsWidgets, reason: '上面的收件箱有 1 条没看');
    await goTo(tester, 'inbox');
    expect(find.text('方案账单 CI2611-0001'), findsOneWidget);
    expect(find.text('没看'), findsOneWidget);
    await tester.tap(find.text('方案账单 CI2611-0001'));
    await tester.pumpAndSettle();
    expect(r.api.calls, contains('markInboxRead 1'));
    expect(find.text('CI2611-0001'), findsOneWidget, reason: '去了方案页');
    await goTo(tester, 'inbox');
    expect(find.text('没看'), findsNothing);
    expect(find.byKey(const Key('inbox-read-all')), findsNothing);
  });

  testWidgets('公司资料：管理员改', (tester) async {
    final r = await pumpProcure(tester, locale: 'en');
    await goTo(tester, 'company');
    expect(find.text('Company profile'), findsWidgets);
    await tester.enterText(find.byKey(const Key('company-sst_no')), 'W10-1234-56789012');
    await tapKey(tester, 'company-save');
    expect(r.api.calls, contains('updateCompany'));
    expect(find.text('Saved'), findsOneWidget);
  });

  for (final size in [desktop, phone]) {
    testWidgets('申请人：看不到成员、方案；只看到自己的分店（${size.width.toInt()} 宽，马来文）', (tester) async {
      await pumpProcure(tester, size: size, role: 'requester', locale: 'ms');
      expect(find.textContaining('Pelan diurus oleh pentadbir'), findsOneWidget);
      expect(find.byKey(const Key('quick-invite')), findsNothing);
      if (size == phone) {
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('nav-members')), findsNothing);
      expect(find.byKey(const Key('nav-billing')), findsNothing);
      await tester.tap(find.byKey(const Key('nav-sites')));
      await tester.pumpAndSettle();
      expect(find.text('Grand Hotel 宴会厅'), findsOneWidget);
      expect(find.text('Grand Hotel 中央厨房'), findsNothing);
      expect(find.byKey(const Key('site-add')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('财务：看得到方案和付款，不能换方案、不能邀请', (tester) async {
    await pumpProcure(tester, role: 'finance');
    await goTo(tester, 'billing');
    expect(find.byKey(const Key('choose-co_starter')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('pay-CI'),
      ),
      findsOneWidget,
    );
    await goTo(tester, 'members');
    expect(find.byKey(const Key('member-invite')), findsNothing);
  });
}
