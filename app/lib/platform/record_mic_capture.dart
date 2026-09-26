import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/mic_capture.dart';
import 'package:record/record.dart';

/// [MicCapture] backed by the `record` plugin — the only device-specific piece
/// of the acoustic stack.
///
/// It streams raw 16-bit little-endian **mono** PCM at [sampleRate], which is
/// exactly what [PcmDecoder]/[MicAnalyzer] expect. Kept deliberately thin: all
/// DSP and coaching logic lives in pure-Dart, CI-tested layers above it.
class RecordMicCapture implements MicCapture {
  RecordMicCapture({this.sampleRate = 22050});

  /// Capture sample rate. 22050 Hz halves the data rate vs 44100 while staying
  /// well above the Nyquist limit for a child keyboard's fundamentals (≤ ~1 kHz).
  final int sampleRate;

  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() {
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1, // mono: pitch detection only needs one channel
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
