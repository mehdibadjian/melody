import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/mic_capture.dart';

/// Test helpers for faking a microphone in CI: synthetic 16-bit little-endian
/// mono PCM that the real detection pipeline decodes, so screen/controller
/// tests exercise the full listen→detect→debounce→coach loop without a device.
const testSampleRate = 22050;

/// Frequency (Hz) table for the notes used in the shipped song library.
const _freqs = <String, double>{
  'C4': 261.63,
  'D4': 293.66,
  'E4': 329.63,
  'F4': 349.23,
  'G4': 392.00,
  'A4': 440.00,
  'B4': 493.88,
  'C5': 523.25,
  'D5': 587.33,
  'E5': 659.25,
};

/// Builds ~[seconds] of harmonic mono PCM for [note] — the signal an electric
/// keyboard makes through a microphone.
Uint8List pcmToneFor(String note, {double seconds = 0.5, double amp = 0.8}) {
  final freq = _freqs[note] ?? 440;
  final n = (seconds * testSampleRate).round();
  final bytes = Uint8List(n * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    final t = i / testSampleRate;
    final s = math.sin(2 * math.pi * freq * t) +
        0.5 * math.sin(2 * math.pi * 2 * freq * t) +
        0.3 * math.sin(2 * math.pi * 3 * freq * t);
    data.setInt16(
        i * 2, ((s * amp).clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return bytes;
}

/// [seconds] of digital silence (zeros).
Uint8List pcmSilenceFor({double seconds = 0.4}) =>
    Uint8List((seconds * testSampleRate).round() * 2);

/// A scriptable [MicCapture] stand-in. Push PCM via [emit]; flip [permission]
/// to exercise the denied path.
class FakeMicCapture implements MicCapture {
  FakeMicCapture({this.permission = true});

  bool permission;
  final controller = StreamController<Uint8List>.broadcast();
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> dispose() async => disposed = true;

  void emit(Uint8List chunk) => controller.add(chunk);

  /// Emits a [note] tone then flushes stream delivery + debounce.
  Future<void> play(String note) async {
    emit(pcmToneFor(note));
    await Future<void>.delayed(Duration.zero);
  }
}
