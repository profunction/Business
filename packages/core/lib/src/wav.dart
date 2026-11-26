import 'dart:typed_data';

/// 录音（PCM 16-bit little-endian）包成 WAV 档：语音转文字服务收 WAV，所有平台（手机、网页）都录得出 PCM。
/// 16 kHz 单声道 60 秒大约 1.9 MB（voice-orders 上限 3 MB）。
Uint8List pcm16ToWav(Uint8List pcm, {int sampleRate = 16000, int channels = 1}) {
  final data = pcm.length.isOdd ? pcm.sublist(0, pcm.length - 1) : pcm;
  final out = ByteData(44 + data.length);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk 长度
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * 2, Endian.little); // 每秒几个字节
  out.setUint16(32, channels * 2, Endian.little);
  out.setUint16(34, 16, Endian.little); // 16 bit
  ascii(36, 'data');
  out.setUint32(40, data.length, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(44, 44 + data.length, data);
  return bytes;
}

/// 这段 PCM 有几秒
Duration pcm16Duration(int byteLength, {int sampleRate = 16000, int channels = 1}) =>
    Duration(milliseconds: byteLength * 1000 ~/ (sampleRate * channels * 2));
