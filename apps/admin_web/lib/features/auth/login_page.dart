import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';

/// 登录页的外框：中间一张卡片（电脑、平板都好看）
class _AuthCard extends ConsumerWidget {
  const _AuthCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: l.language,
            icon: const Icon(Icons.translate),
            onSelected: (code) => ref.read(sessionProvider).setLocale(code),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'zh', child: Text('华文')),
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
            ],
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机号 → 发验证码（跟手机 App 一样的 Supabase 手机号登录）
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
    return _AuthCard(
      title: l.loginTitle,
      children: [
        Text(l.loginSubtitle),
        const SizedBox(height: 16),
        TextField(
          key: const Key('phone-field'),
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
          decoration: InputDecoration(
            labelText: l.phoneLabel,
            hintText: '012-345 6789',
            prefixIcon: const Icon(Icons.phone_android),
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('send-code'),
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.sendCode),
        ),
      ],
    );
  }
}

class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({super.key, required this.phone});

  /// '+60123456789'
  final String phone;

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _resendIn = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).verifyOtp(widget.phone, _code.text);
      // 成功：AdminSession 收到登录事件，router 会跳去下一页
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(apiProvider).sendOtp(widget.phone, locale: ref.read(sessionProvider).localeCode);
      setState(_startTimer);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _AuthCard(
      title: l.otpTitle,
      children: [
        Text(l.otpSentTo(formatMalaysianMobile(widget.phone))),
        const SizedBox(height: 16),
        TextField(
          key: const Key('otp-field'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 10),
          decoration: InputDecoration(counterText: '', hintText: '••••••', errorText: _error, errorMaxLines: 3),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: () => context.pop(), child: Text(l.changePhone)),
            TextButton(
              onPressed: _resendIn > 0 ? null : _resend,
              child: Text(_resendIn > 0 ? l.otpResendIn(_resendIn) : l.otpResend),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('verify-code'),
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.otpLogin),
        ),
      ],
    );
  }
}
