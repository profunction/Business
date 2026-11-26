import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';
import 'voice_recorder.dart';

/// 语音下单的大按钮：按住说话、放开就送出。AI 做好草稿后打开「确认语音订单」页（不会自己下单）。
/// 首页用大的，购物车用小的（compact）。
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
    final recording = _phase == _Phase.recording || _phase == _Phase.starting;
    final sending = _phase == _Phase.sending;
    final bg = recording ? const Color(0xFFC62828) : const Color(0xFF6A1B9A);
    final label = sending
        ? l.voiceListening
        : recording
        ? l.voiceRecording(_seconds)
        : l.voiceHold;
    final icon = sending
        ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 4))
        : Icon(recording ? Icons.graphic_eq : Icons.mic, size: widget.compact ? 34 : 48, color: Colors.white);
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
          constraints: BoxConstraints(minHeight: widget.compact ? 64 : 96),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: widget.compact ? 10 : 18),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      key: const Key('voice-mic-label'),
                      style: (widget.compact ? t.titleLarge : t.headlineSmall)?.copyWith(color: Colors.white),
                    ),
                    if (!widget.compact && !recording && !sending) ...[
                      const SizedBox(height: 4),
                      Text(l.voiceHoldHint, style: t.bodyMedium?.copyWith(color: Colors.white70)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
