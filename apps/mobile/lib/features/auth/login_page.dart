import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 输入手机号 -> 发验证码。只有一个输入框、一个按钮。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = context.l10n;
    final phone = normalizeMalaysianMobile(_phone.text);
    if (phone == null) {
      setState(() => _error = l.phoneInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).sendOtp(phone, locale: ref.read(sessionProvider).localeCode);
      if (mounted) context.push(Uri(path: '/login/otp', queryParameters: {'phone': phone}).toString());
    } catch (e) {
      if (mounted) setState(() => _error = l.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            tooltip: l.language,
            icon: const Icon(Icons.translate),
            onPressed: () => ref.read(sessionProvider).setLocale(switch (l.lang) {
              'zh' => 'en',
              'en' => 'ms',
              _ => 'zh',
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.loginTitle, style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(l.loginSubtitle, style: t.bodyLarge),
            const SizedBox(height: 32),
            TextField(
              key: const Key('phone-field'),
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
              style: t.headlineSmall,
              decoration: InputDecoration(
                labelText: l.phoneLabel,
                hintText: '012-345 6789',
                prefixIcon: const Icon(Icons.phone_android, size: 30),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: BusyButton(key: const Key('send-code'), label: l.sendCode, busy: _busy, onPressed: _send),
      ),
    );
  }
}
