import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'voice_recorder.dart';

/// 语音下单的按钮：按住说话、放开就送出。AI 做好草稿后打开「确认语音订单」页（不会自己下单）。
/// 首页是快捷动作卡片，购物车是一条细的按钮（compact）。
class MicButton extends ConsumerStatefulWidget {
  const MicButton({super.key, this.compact = false});

  final bool compact;

  /// 最多录多久（到了自己停、送出）
  static const maxDuration = Duration(seconds: 60);

  /// 太短的不送（手指不小心按到）
  static const minDuration = Duration(milliseconds: 800);

  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

enum _Phase { idle, starting, recording, sending }

class _MicButtonState extends ConsumerState<MicButton> {
  _Phase _phase = _Phase.idle;
  DateTime? _startedAt;
  Timer? _ticker;
  int _seconds = 0;

  /// 手指在录音开始之前就放开了
  bool _releasedEarly = false;

  VoiceRecorder get _recorder => ref.read(voiceRecorderProvider);

  @override
  void dispose() {
    _ticker?.cancel();
    if (_phase == _Phase.recording || _phase == _Phase.starting) _recorder.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_phase != _Phase.idle) return;
    final l = context.l10n;
    setState(() {
      _phase = _Phase.starting;
      _releasedEarly = false;
    });
    try {
      if (!await _recorder.ensurePermission()) {
        if (!mounted) return;
        setState(() => _phase = _Phase.idle);
        showMessage(context, l.voiceNoPermission, error: true);
        return;
      }
      await _recorder.start();
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      showMessage(context, l.voiceErrRecordAgain, error: true);
      return;
    }
    if (!mounted) return;
    _startedAt = DateTime.now();
    setState(() {
      _phase = _Phase.recording;
      _seconds = 0;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final s = DateTime.now().difference(_startedAt!);
      if (s >= MicButton.maxDuration) {
        _finish();
      } else if (mounted && s.inSeconds != _seconds) {
        setState(() => _seconds = s.inSeconds);
      }
    });
    if (_releasedEarly) await _finish();
  }

  Future<void> _finish() async {
    if (_phase == _Phase.starting) {
      _releasedEarly = true;
      return;
    }
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    final l = context.l10n;
    setState(() => _phase = _Phase.sending);
    final audio = await _recorder.stop().catchError((_) => null);
    if (!mounted) return;
    if (audio == null || audio.duration < MicButton.minDuration) {
      setState(() => _phase = _Phase.idle);
      showMessage(context, l.voiceTooShort, error: true);
      return;
    }
    try {
      final draft = await ref.read(apiProvider).submitVoiceOrder(ref.read(shopIdProvider), audio.wav);
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      context.push('/voice-draft/${draft.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      showMessage(context, l.error(e), error: true);
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    if (_phase == _Phase.recording || _phase == _Phase.starting) await _recorder.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final recording = _phase == _Phase.recording || _phase == _Phase.starting;
    final sending = _phase == _Phase.sending;
    // 录音中：红色（一定跟「正在录音 n 秒」的字一起出现）
    final accent = recording ? AppTheme.problem : scheme.primary;
    final label = sending
        ? l.voiceListening
        : recording
        ? l.voiceRecording(_seconds)
        : l.voiceHold;
    final icon = sending
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: accent, strokeWidth: 2))
        : Icon(recording ? Icons.graphic_eq : Icons.mic_none, size: 20, color: accent);
    final labelText = Text(
      label,
      key: const Key('voice-mic-label'),
      style: t.titleSmall?.copyWith(color: recording ? AppTheme.problem : scheme.onSurface),
    );
    final Widget content = widget.compact
        // 购物车：一条细的按钮
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [icon, const SizedBox(width: 8), Flexible(child: labelText)],
          )
        // 首页：跟「跟上次一样」一样大的卡片
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.mic_none,
                background: recording ? AppTheme.problem.withValues(alpha: 0.1) : null,
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(child: labelText),
            ],
          );
    return Semantics(
      button: true,
      label: l.voiceHold,
      hint: l.voiceHoldHint,
      child: GestureDetector(
        key: const Key('voice-mic'),
        behavior: HitTestBehavior.opaque,
        onTap: sending ? null : () => showMessage(context, l.voiceHoldHint),
        onLongPressStart: sending ? null : (_) => _start(),
        onLongPressEnd: sending ? null : (_) => _finish(),
        onLongPressCancel: _cancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: BoxConstraints(minHeight: widget.compact ? 48 : 72),
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
              : const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: recording ? const Color(0xFFFDF0EF) : Colors.white,
            borderRadius: BorderRadius.circular(widget.compact ? AppTheme.radius : AppTheme.cardRadius),
            border: Border.all(color: recording ? AppTheme.problem : (widget.compact ? AppTheme.borderStrong : AppTheme.border)),
          ),
          child: content,
        ),
      ),
    );
  }
}
