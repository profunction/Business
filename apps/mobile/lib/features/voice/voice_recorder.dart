import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// 录好的一段（WAV）
class RecordedAudio {
  const RecordedAudio(this.wav, this.duration);

  final Uint8List wav;
  final Duration duration;
}

/// 录音（测试换成假的）。录 16 kHz 单声道 PCM，停的时候包成 WAV（手机、网页都一样）
abstract class VoiceRecorder {
  /// 有没有麦克风权限（没有就问）
  Future<bool> ensurePermission();

  Future<void> start();

  /// 停下来，回传录到的；什么都没录到 → null
  Future<RecordedAudio?> stop();

  /// 不要了（手指滑出去 / 页面关掉）
  Future<void> cancel();
}

class PluginVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  final _pcm = BytesBuilder(copy: false);

  static const sampleRate = 16000;

  @override
  Future<bool> ensurePermission() async => (_rec ??= AudioRecorder()).hasPermission();

  @override
  Future<void> start() async {
    final rec = _rec ??= AudioRecorder();
    _pcm.clear();
    final stream = await rec.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1),
    );
    _sub = stream.listen(_pcm.add);
  }

  @override
  Future<RecordedAudio?> stop() async {
    await _rec?.stop();
    await _sub?.cancel();
    _sub = null;
    final pcm = _pcm.takeBytes();
    if (pcm.isEmpty) return null;
    return RecordedAudio(pcm16ToWav(pcm), pcm16Duration(pcm.length));
  }

  @override
  Future<void> cancel() async {
    await _rec?.cancel();
    await _sub?.cancel();
    _sub = null;
    _pcm.clear();
  }
}

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) => PluginVoiceRecorder());
