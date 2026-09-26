import 'dart:math' as math;
import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/acoustic_instrument.dart';
import 'package:melody_app/domain/acoustic/mic_analyzer.dart';
import 'package:melody_app/domain/acoustic/pitch_detector.dart';
import 'package:test/test.dart';

const sr = 22050;

/// 16-bit little-endian mono PCM bytes for a harmonic tone of [freq],
/// [seconds] long — the signal an electric keyboard makes through a mic.
Uint8List pcmTone(double freq, {double seconds = 0.4, double amp = 0.8}) {
  final n = (seconds * sr).round();
  final bytes = Uint8List(n * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final s = math.sin(2 * math.pi * freq * t) +
        0.5 * math.sin(2 * math.pi * 2 * freq * t) +
        0.3 * math.sin(2 * math.pi * 3 * freq * t);
    final v = ((s * amp).clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(i * 2, v, Endian.little);
  }
  return bytes;
}

Uint8List pcmSilence({double seconds = 0.4}) {
  final n = (seconds * sr).round();
  return Uint8List(n * 2);
}

void main() {
  group('MicAnalyzer (PCM -> stable detected note)', () {
    test('detects the played note from synthetic keyboard audio', () async {
      final stable = <String?>[];
      final analyzer = MicAnalyzer(
        detector: PitchDetector(sampleRate: sr),
        acoustic: AcousticInstrument(),
        sampleRate: sr,
        frameSize: 2048,
        onStableNote: stable.add,
      );

      // A4 = 440 Hz.
      analyzer.feed(pcmTone(440));
      await Future<void>.delayed(Duration.zero);

      expect(stable, contains('A4'));
      analyzer.dispose();
    });

    test('detects a second, different note after the first', () async {
      final stable = <String?>[];
      final analyzer = MicAnalyzer(
        detector: PitchDetector(sampleRate: sr),
        acoustic: AcousticInstrument(),
        sampleRate: sr,
        frameSize: 2048,
        onStableNote: stable.add,
      );

      analyzer.feed(pcmTone(261.63)); // C4
      await Future<void>.delayed(Duration.zero);
      analyzer.feed(pcmTone(392.00)); // G4
      await Future<void>.delayed(Duration.zero);

      expect(stable, contains('C4'));
      expect(stable, contains('G4'));
      analyzer.dispose();
    });

    test('silence produces no stable note', () async {
      final stable = <String?>[];
      final analyzer = MicAnalyzer(
        detector: PitchDetector(sampleRate: sr),
        acoustic: AcousticInstrument(),
        sampleRate: sr,
        frameSize: 2048,
        onStableNote: stable.add,
      );

      analyzer.feed(pcmSilence());
      await Future<void>.delayed(Duration.zero);

      expect(stable.where((n) => n != null), isEmpty);
      analyzer.dispose();
    });

    test('does not emit a frame until enough samples are buffered', () {
      final stable = <String?>[];
      final analyzer = MicAnalyzer(
        detector: PitchDetector(sampleRate: sr),
        acoustic: AcousticInstrument(),
        sampleRate: sr,
        frameSize: 2048,
        onStableNote: stable.add,
      );

      // Only 512 samples (~1024 bytes) — well short of one 2048 frame.
      analyzer.feed(Uint8List(1024));
      expect(analyzer.bufferedSamples, lessThan(2048));
      expect(stable, isEmpty);
      analyzer.dispose();
    });

    test('processes multiple frames from one large chunk', () async {
      var frames = 0;
      final analyzer = MicAnalyzer(
        detector: PitchDetector(sampleRate: sr),
        acoustic: AcousticInstrument(),
        sampleRate: sr,
        frameSize: 2048,
        hopSize: 2048,
        onStableNote: (_) {},
        onFrame: () => frames++,
      );

      // 0.5s of tone = ~11025 samples = 5 full frames of 2048.
      analyzer.feed(pcmTone(440, seconds: 0.5));
      await Future<void>.delayed(Duration.zero);

      expect(frames, greaterThanOrEqualTo(5));
      analyzer.dispose();
    });

    test('reset clears the sample buffer', () {
      final analyzer = MicAnalyzer(
        detector: PitchDetector(sampleRate: sr),
        acoustic: AcousticInstrument(),
        sampleRate: sr,
        frameSize: 2048,
        onStableNote: (_) {},
      );
      analyzer.feed(Uint8List(1024)); // 512 samples buffered
      expect(analyzer.bufferedSamples, greaterThan(0));
      analyzer.reset();
      expect(analyzer.bufferedSamples, 0);
      analyzer.dispose();
    });
  });
}
