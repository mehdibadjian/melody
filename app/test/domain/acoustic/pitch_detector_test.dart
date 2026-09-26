import 'dart:math' as math;

import 'package:melody_app/domain/acoustic/pitch_detector.dart';
import 'package:test/test.dart';

/// Synthetic-signal helpers. A real microphone is not available in CI, so the
/// detector is validated against mathematically generated waveforms — the
/// clean, in-tune fundamentals an electric keyboard produces.
const sr = 22050;
const n = 2048;

List<double> sine(double freq, {double amp = 1.0}) => List<double>.generate(
      n,
      (i) => amp * math.sin(2 * math.pi * freq * i / sr),
    );

/// Harmonic-rich tone approximating an electric-piano timbre.
List<double> harmonics(double freq) => List<double>.generate(n, (i) {
      final t = i / sr;
      return math.sin(2 * math.pi * freq * t) +
          0.5 * math.sin(2 * math.pi * 2 * freq * t) +
          0.3 * math.sin(2 * math.pi * 3 * freq * t) +
          0.15 * math.sin(2 * math.pi * 4 * freq * t);
    });

List<double> noise({double amp = 0.05, int seed = 42}) {
  final rnd = math.Random(seed);
  return List<double>.generate(n, (_) => (rnd.nextDouble() * 2 - 1) * amp);
}

void main() {
  late PitchDetector detector;

  setUp(() {
    detector = PitchDetector(sampleRate: sr);
  });

  group('PitchDetector — fundamental frequency', () {
    test('detects A4 = 440 Hz from a clean sine', () {
      final est = detector.detect(sine(440));
      expect(est, isNotNull);
      expect(est!.frequencyHz, closeTo(440, 2));
      expect(est.clarity, greaterThan(0.9));
    });

    test('detects C4 = 261.63 Hz', () {
      final est = detector.detect(sine(261.63))!;
      expect(est.frequencyHz, closeTo(261.63, 3));
    });

    test('detects the fundamental, not a harmonic, for a rich waveform', () {
      // E4 with strong harmonics — must not lock onto E3/E5.
      final est = detector.detect(harmonics(329.63))!;
      expect(est.frequencyHz, closeTo(329.63, 5));
      expect(noteFromFrequency(est.frequencyHz)!.note, 'E4');
    });

    test('returns null for silence', () {
      expect(detector.detect(List<double>.filled(n, 0)), isNull);
    });

    test('returns null for low-level noise (no stable pitch)', () {
      final est = detector.detect(noise());
      // Either no estimate, or one below the clarity gate.
      expect(est == null || est.clarity < 0.7, isTrue);
    });

    test('returns null for an empty buffer', () {
      expect(detector.detect(const []), isNull);
    });
  });

  group('PitchDetector — children\'s keyboard range', () {
    test('identifies every note C4..C5 within ±25 cents', () {
      const semitonesFromA4 = {
        'C4': -9,
        'C#4': -8,
        'D4': -7,
        'D#4': -6,
        'E4': -5,
        'F4': -4,
        'F#4': -3,
        'G4': -2,
        'G#4': -1,
        'A4': 0,
        'A#4': 1,
        'B4': 2,
        'C5': 3,
      };
      var maxCents = 0;
      final errors = <String>[];
      semitonesFromA4.forEach((name, semi) {
        final freq = 440 * math.pow(2, semi / 12).toDouble();
        final est = detector.detect(harmonics(freq));
        if (est == null) {
          errors.add('$name: no detection');
          return;
        }
        final note = noteFromFrequency(est.frequencyHz)!;
        if (note.note != name || note.cents.abs() > 25) {
          errors.add('$name: got ${note.note} ${note.cents}c');
        }
        maxCents = math.max(maxCents, note.cents.abs());
      });
      // ignore: avoid_print
      print('range test: max |cents| error = $maxCents; failures = $errors');
      expect(errors, isEmpty, reason: 'note mis-detections: $errors');
      expect(maxCents, lessThanOrEqualTo(25));
    });
  });

  group('PitchDetector — noise robustness (real mic is never clean)', () {
    test('still identifies the note through moderate background noise', () {
      // ~20 dB SNR: tone amplitude 1.0, noise amplitude 0.1.
      final tone = harmonics(293.66); // D4
      final noisy =
          List<double>.generate(n, (i) => tone[i] + noise(amp: 0.1)[i]);
      final est = detector.detect(noisy);
      expect(est, isNotNull);
      expect(noteFromFrequency(est!.frequencyHz)!.note, 'D4');
    });

    test('identifies notes across a realistic child-keyboard octave', () {
      // C3 (130.81) up to B4 (493.88) — common practice range.
      final freqs = {
        'C3': 130.81,
        'G3': 196.00,
        'C4': 261.63,
        'E4': 329.63,
        'G4': 392.00,
        'B4': 493.88,
      };
      final errors = <String>[];
      freqs.forEach((name, freq) {
        final est = detector.detect(harmonics(freq));
        if (est == null || noteFromFrequency(est.frequencyHz)!.note != name) {
          errors.add(
              '$name: ${est == null ? "null" : noteFromFrequency(est.frequencyHz)!.note}');
        }
      });
      expect(errors, isEmpty, reason: 'octave-range failures: $errors');
    });
  });

  group('noteFromFrequency', () {
    test('maps 440 Hz to A4 with zero cents', () {
      final note = noteFromFrequency(440)!;
      expect(note.note, 'A4');
      expect(note.cents, 0);
    });

    test('maps 261.63 Hz to C4', () {
      expect(noteFromFrequency(261.63)!.note, 'C4');
    });

    test('maps 523.25 Hz to C5', () {
      expect(noteFromFrequency(523.25)!.note, 'C5');
    });

    test('reports cents deviation for a sharp note', () {
      // A4 + 30 cents (~447.7 Hz) rounds to A4 with +30 cents (unambiguous;
      // +50 sits exactly on the A4/A#4 boundary).
      final note = noteFromFrequency(440 * math.pow(2, 0.30 / 12).toDouble())!;
      expect(note.note, 'A4');
      expect(note.cents, closeTo(30, 1));
    });

    test('returns null for non-positive frequency', () {
      expect(noteFromFrequency(0), isNull);
      expect(noteFromFrequency(-1), isNull);
    });
  });
}
