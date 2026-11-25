import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 输入 6 位验证码。登录成功后 router 会自动带去下一页。
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
    setState(() => _resendIn = 30);
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
    if (_code.text.trim().length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).verifyOtp(widget.phone, _code.text);
      // 成功：SessionController 收到登录事件，router 会跳去下一页
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(apiProvider).sendOtp(widget.phone, locale: ref.read(sessionProvider).localeCode);
      _startTimer();
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.otpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.otpSentTo(formatMalaysianMobile(widget.phone)), style: t.titleMedium),
            const SizedBox(height: 24),
            TextField(
              key: const Key('otp-field'),
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofillHints: const [AutofillHints.oneTimeCode],
              style: t.headlineMedium?.copyWith(letterSpacing: 12),
              decoration: InputDecoration(counterText: '', hintText: '••••••', errorText: _error, errorMaxLines: 3),
              onChanged: (v) {
                if (v.length == 6) _verify();
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.changePhone)),
                TextButton(
                  onPressed: _resendIn > 0 ? null : _resend,
                  child: Text(_resendIn > 0 ? l.otpResendIn(_resendIn) : l.otpResend),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: BusyButton(key: const Key('verify-code'), label: l.otpLogin, busy: _busy, onPressed: _verify),
      ),
    );
  }
}
