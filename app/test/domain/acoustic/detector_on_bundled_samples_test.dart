import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/pitch_detector.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:test/test.dart';

// Drives the REAL PitchDetector over the REAL bundled note samples.
//
// The demo samples and the microphone are two different sources of "a note",
// but both end at the same vocabulary of note names. Nothing else in the suite
// connects them: the acoustic tests feed synthetic sine PCM, and the audio
// tests never call the detector. So a regeneration of the note assets could
// move them outside what the acoustic path can hear and every test would still
// pass.
//
// This matters more for struck-string samples than for the two-partial tones
// they replaced, and that is a genuine risk rather than a hypothetical one:
// NSDF can lock onto a sub-octave when a harmonic is strong, and these samples
// carry H3..Hn that the old ones did not. A richer timbre can fool a pitch
// detector even while sounding better.
//
// Keys above the detector's maxFrequencyHz are expected to yield no detection
// rather than a wrong one — GOLDEN's hardest arrangement reaches D6 (1174.7 Hz)
// against a 1200 Hz ceiling, and the board runs to C7. Those keys are
// documented as out of acoustic range; this test pins that boundary so it
// cannot drift unnoticed.
void main() {
  /// The sustained body of a bundled sample, as a detector frame: 2048 samples
  /// taken well past the hammer transient, which is broadband by design and
  /// would be the one place a false detection is legitimate.
  List<double> sustainedFrame(String note) {
    final bytes = File('assets/audio/notes/${NoteAsset.fileBaseFor(note)}.wav')
        .readAsBytesSync();
    // Locate the data chunk rather than assuming offset 44.
    var i = 12;
    Uint8List? pcm;
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size =
          ByteData.sublistView(bytes, i + 4, i + 8).getUint32(0, Endian.little);
      final body = i + 8;
      if (id == 'data') pcm = Uint8List.sublistView(bytes, body, body + size);
      i = body + size + (size.isOdd ? 1 : 0);
    }
    final data = pcm!;
    final total = data.length ~/ 2;
    // Start at a quarter of the way in: past the attack, still loud.
    final start = math.min(total - 2048, total ~/ 4);
    final frame = List<double>.filled(2048, 0);
    for (var n = 0; n < 2048; n++) {
      frame[n] =
          ByteData.sublistView(data, (start + n) * 2, (start + n) * 2 + 2)
                  .getInt16(0, Endian.little) /
              32768.0;
    }
    return frame;
  }

  group('the acoustic detector can still hear the bundled samples', () {
    test('every key inside the detector band is recognized, at the right pitch',
        () {
      // The band is 80..1200 Hz. A4=440, so MIDI 43 (G2, 98 Hz) to MIDI 86
      // (D6, 1174.7 Hz) is what the detector was built to cover.
      final detector = PitchDetector();
      final inBand = NoteFrequency.playableNotes
          .where(
              (n) => NoteFrequency.of(n)! >= 85 && NoteFrequency.of(n)! <= 1150)
          .toList();
      expect(inBand, isNotEmpty, reason: 'sanity: the band covers real keys');

      final wrong = <String>[];
      final missed = <String>[];
      for (final note in inBand) {
        final est = detector.detect(sustainedFrame(note));
        if (est == null) {
          missed.add(
              '$note (silent, expected ${NoteFrequency.of(note)!.round()} Hz)');
          continue;
        }
        final heard = noteFromFrequency(est.frequencyHz)?.note;
        if (heard != note) {
          wrong.add('$note heard as $heard '
              '(${est.frequencyHz.toStringAsFixed(1)} Hz vs '
              '${NoteFrequency.of(note)!.toStringAsFixed(1)} Hz)');
        }
      }
      expect(wrong, isEmpty, reason: 'detector locked onto the wrong pitch');
      expect(missed, isEmpty, reason: 'detector heard nothing');
    });

    test('the richest timbres are not mistaken for a sub-octave', () {
      // The specific failure a harmonic-heavy sample can cause: NSDF peaks at
      // twice the true period and the app hears C3 when C4 was played. Checked
      // on the keys with the most upper partials — the mid and upper treble,
      // where the synthesis model stacks three detuned strings.
      final detector = PitchDetector();
      for (final note in const [
        'C4',
        'E4',
        'A4',
        'C5',
        'E5',
        'A5',
        'C6',
        'F#4'
      ]) {
        final est = detector.detect(sustainedFrame(note));
        expect(est, isNotNull, reason: '$note produced no detection');
        final expected = NoteFrequency.of(note)!;
        final ratio = expected / est!.frequencyHz;
        expect(ratio, lessThan(1.2),
            reason: '$note detected an octave or more too low (ratio '
                '${ratio.toStringAsFixed(2)})');
        expect(ratio, greaterThan(0.83),
            reason:
                '$note detected too high (ratio ${ratio.toStringAsFixed(2)})');
      }
    });

    test('detections land within a few cents, so coaching hints stay honest',
        () {
      // coach() turns (detected, target) into "move a few keys lower". A sample
      // that detects 30 cents off would make the app tell a child to move when
      // they are already right.
      final detector = PitchDetector();
      for (final note in const ['C4', 'A4', 'E5', 'G4', 'D5']) {
        final est = detector.detect(sustainedFrame(note));
        expect(est, isNotNull, reason: note);
        final named = noteFromFrequency(est!.frequencyHz);
        expect(named?.note, note, reason: '$note mapped to ${named?.note}');
        expect(named!.cents.abs(), lessThanOrEqualTo(15),
            reason: '$note detected ${named.cents} cents off');
      }
    });

    test('clarity stays above the shipped threshold', () {
      // clarityThreshold defaults to 0.7. A sample below it is dropped as
      // unvoiced, which on a real keyboard presents as the app not hearing the
      // child at all — the exact failure epic-2/on-device-validation exists to
      // prevent. Measured on the bundled samples so a regeneration cannot drop
      // them under the gate.
      final detector = PitchDetector();
      final weak = <String>[];
      for (final note in NoteFrequency.playableNotes) {
        final hz = NoteFrequency.of(note)!;
        if (hz < 85 || hz > 1150) continue; // outside the detector band
        final est = detector.detect(sustainedFrame(note));
        if (est == null) {
          weak.add('$note (no detection)');
        } else if (est.clarity < 0.7) {
          weak.add('$note clarity ${est.clarity.toStringAsFixed(2)}');
        }
      }
      expect(weak, isEmpty, reason: 'samples below the clarity gate');
    });

    test(
        'the detector band stops below the top of the board, and that is stated',
        () {
      // Pins the documented limit rather than pretending the whole board is
      // audible in acoustic mode: C7 (2093 Hz) is above maxFrequencyHz (1200).
      final detector = PitchDetector();
      expect(detector.maxFrequencyHz, lessThan(NoteFrequency.of('C7')!));
      expect(detector.maxFrequencyHz, greaterThan(NoteFrequency.of('D6')!),
          reason: 'GOLDEN hard reaches D6 and must stay inside the band');
    });
  });
}
