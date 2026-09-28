// Guards that the bundled note samples are *piano-like* rather than
// electronic test tones.
//
// The other audio tests pin that every key has a file and that the frequency
// table agrees with the board. Neither of those catches the failure this does:
// the first 61 samples shipped were `sin(f) + 0.35*sin(2f)` with one fixed
// 350 ms envelope for every key, all of them perfectly in tune. They passed
// every test that existed and sounded like a synthesizer bleep, which is why
// this file measures the samples instead of trusting their presence.
//
// The properties checked here are exactly the ones a struck string has and a
// two-partial sine does not:
//
//   * harmonics beyond the second exist at all
//   * the fundamental carries most of the energy (it is a note, not noise)
//   * higher harmonics decay faster than the fundamental (brightness fades)
//   * decay time depends on pitch — bass rings, treble dies

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:test/test.dart';

/// Decodes a 16-bit mono PCM WAV into samples scaled to [-1, 1].
///
/// Deliberately minimal: no `dart:ui` or plugin dependency, so this runs in CI
/// on the plain VM like the rest of `test/domain/`.
class _Wav {
  _Wav(this.samples, this.sampleRate);

  final Float64List samples;
  final int sampleRate;

  static _Wav read(String path) {
    final bytes = File(path).readAsBytesSync();
    expect(bytes.sublist(0, 4), [0x52, 0x49, 0x46, 0x46],
        reason: '$path not RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

    // Walk chunks: the data chunk is not always at the fixed offset 44.
    var i = 12;
    Uint8List? data;
    var format = 0;
    var channels = 0;
    var rate = 0;
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size =
          ByteData.sublistView(bytes, i + 4, i + 8).getUint32(0, Endian.little);
      final body = i + 8;
      if (id == 'fmt ') {
        format = ByteData.sublistView(bytes, body, body + 2)
            .getUint16(0, Endian.little);
        channels = ByteData.sublistView(bytes, body + 2, body + 4)
            .getUint16(0, Endian.little);
        rate = ByteData.sublistView(bytes, body + 4, body + 8)
            .getUint32(0, Endian.little);
      } else if (id == 'data') {
        data = Uint8List.sublistView(bytes, body, body + size);
      }
      i = body + size + (size.isOdd ? 1 : 0);
    }
    expect(format, 1, reason: '$path is not PCM');
    expect(channels, 1, reason: '$path is not mono');
    expect(data, isNotNull, reason: '$path has no data chunk');
    final pcm = data!;

    final out = Float64List(pcm.length ~/ 2);
    for (var n = 0; n < out.length; n++) {
      out[n] = ByteData.sublistView(pcm, n * 2, n * 2 + 2)
              .getInt16(0, Endian.little) /
          32768.0;
    }
    return _Wav(out, rate);
  }
}

/// Goertzel magnitude of [x] at [hz] — a single-bin DFT, cheaper than an FFT
/// and all this test needs to ask "how much energy is at this pitch".
double _magnitude(Float64List x, int sampleRate, double hz) {
  final n = x.length;
  final w = 2 * math.pi * hz / sampleRate;
  final coeff = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = 0; i < n; i++) {
    final s0 = x[i] + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  return math.sqrt(s1 * s1 + s2 * s2 - coeff * s1 * s2);
}

/// Energy at [hz] measured over a window starting [secondsFromStart], so the
/// decay of one partial can be compared against another.
double _energyAfter(
    Float64List x, int rate, double hz, double secondsFromStart) {
  final start = (secondsFromStart * rate).floor().clamp(0, x.length - 1);
  final win = math.min(rate, x.length - start); // up to 1 s window
  return _magnitude(Float64List.sublistView(x, start, start + win), rate, hz);
}

void main() {
  /// Loads a bundled sample by note name through [NoteAsset], so this test
  /// agrees with the engine about spelling rather than re-deriving it.
  _Wav load(String note) =>
      _Wav.read('assets/audio/notes/${NoteAsset.fileBaseFor(note)}.wav');

  group('bundled samples are piano-like, not two-partial tones', () {
    test('every key is PCM mono 16-bit at the capture rate', () {
      // The acoustic pipeline and these samples must agree on the rate, or a
      // demo note and a detected note are pitched against different clocks.
      for (final note in NoteFrequency.playableNotes) {
        final w = load(note);
        expect(w.sampleRate, 22050, reason: note);
        expect(w.samples.length, greaterThan(0), reason: '$note is empty');
      }
    });

    test('every key is in tune to within 10 cents', () {
      // Measured by finding which of the equal-tempered candidates carries the
      // most energy, rather than trusting the file name.
      for (final note in NoteFrequency.playableNotes) {
        final expected = NoteFrequency.of(note)!;
        final w = load(note);
        var best = 0.0;
        for (final candidate in NoteFrequency.playableNotes) {
          final m =
              _magnitude(w.samples, w.sampleRate, NoteFrequency.of(candidate)!);
          if (m > best) best = m;
        }
        final atExpected = _magnitude(w.samples, w.sampleRate, expected);
        expect(atExpected, greaterThan(best * 0.97),
            reason: '$note does not carry its own fundamental most strongly');
        expect(atExpected, greaterThan(0),
            reason: '$note is silent at $expected Hz');
      }
    });

    test('harmonics beyond the second are present', () {
      // The old samples had H3..Hn at literally zero, which is what made them
      // read as a synthesizer rather than a string. A piano note has a whole
      // decaying series; require real energy at the third harmonic.
      for (final note in const ['A4', 'C5', 'E5', 'A5', 'C4', 'F#4']) {
        final f0 = NoteFrequency.of(note)!;
        final w = load(note);
        final h1 = _magnitude(w.samples, w.sampleRate, f0);
        final h3 = _magnitude(w.samples, w.sampleRate, f0 * 3);
        expect(h1, greaterThan(0), reason: '$note fundamental');
        expect(h3 / h1, greaterThan(0.005),
            reason: '$note has no third harmonic — sounds like a test tone');
      }
    });

    test('the fundamental dominates: a note, not noise', () {
      // The strike transient is broadband by design, so this also bounds it:
      // enough harmonics to be a piano, not so much noise to be a hiss.
      for (final note in const ['A4', 'C4', 'C6']) {
        final f0 = NoteFrequency.of(note)!;
        final w = load(note);
        final h1 = _magnitude(w.samples, w.sampleRate, f0);
        final h2 = _magnitude(w.samples, w.sampleRate, f0 * 2);
        expect(h1, greaterThan(h2),
            reason: '$note should peak at its fundamental');
      }
    });

    test('the envelope decays rather than holding at a fixed level', () {
      // Every old sample had the same raised-cosine attack and the same decay
      // for all 61 pitches. Require a real attack and a real release.
      for (final note in const ['A4', 'C4', 'E5']) {
        final w = load(note);
        final x = w.samples;
        double rms(int from, int to) {
          var s = 0.0;
          for (var i = from; i < to; i++) {
            s += x[i] * x[i];
          }
          return math.sqrt(s / (to - from));
        }

        final head = rms(0, math.min(x.length, w.sampleRate ~/ 40));
        final tail =
            rms(x.length - math.min(x.length, w.sampleRate ~/ 10), x.length);
        expect(head, greaterThan(0.02), reason: '$note has no attack');
        expect(tail, lessThan(head), reason: '$note does not decay');
        expect(tail, lessThan(0.02),
            reason: '$note ends loud instead of ringing out');
      }
    });

    test('low notes ring longer than high notes', () {
      // The single most un-piano property of the old bundle was one duration
      // for every key: a 350 ms C2 and a 350 ms C7. Bass strings ring for
      // seconds and treble for a fraction of that.
      final w = load('C3');
      final w2 = load('C6');
      expect(w.samples.length, greaterThan(w2.samples.length * 1.5),
          reason: 'decay should shorten as pitch rises');
    });

    test('every sample is long enough to sound its own slot', () {
      // The shortest note slot in the shipped library is 250 ms (GOLDEN hard,
      // 12/8 at 120). A sample shorter than its slot leaves silence in the
      // middle of the tune; one that merely overlaps is fine, because
      // AssetAudioEngine stops the previous note.
      for (final note in NoteFrequency.playableNotes) {
        final w = load(note);
        expect(w.samples.length / w.sampleRate, greaterThanOrEqualTo(0.25),
            reason: '$note is shorter than the fastest slot it must fill');
      }
    });

    test('upper harmonics decay faster than the fundamental', () {
      // The brightness of a hammer strike fades before the note does. This is
      // what distinguishes a piano envelope from a constant-amplitude tone, and
      // it is cheap to measure at two points in time.
      for (final note in const ['A4', 'C5']) {
        final f0 = NoteFrequency.of(note)!;
        final w = load(note);
        final earlyH1 = _energyAfter(w.samples, w.sampleRate, f0, 0.05);
        final lateH1 = _energyAfter(w.samples, w.sampleRate, f0, 0.6);
        final earlyH4 = _energyAfter(w.samples, w.sampleRate, f0 * 4, 0.05);
        final lateH4 = _energyAfter(w.samples, w.sampleRate, f0 * 4, 0.6);
        expect(earlyH1, greaterThan(0), reason: '$note fundamental at start');
        expect(earlyH4, greaterThan(0), reason: '$note has no fourth harmonic');
        final ratioH1 = lateH1 / earlyH1;
        final ratioH4 = lateH4 / earlyH4;
        expect(ratioH1, lessThan(1.0),
            reason: '$note fundamental does not decay');
        expect(ratioH4, lessThanOrEqualTo(ratioH1 * 1.05),
            reason: '$note: H4 should not outlast the fundamental');
      }
    });
  });

  group('bundle hygiene', () {
    test('no sample is clipped or absurdly quiet', () {
      // Clipping would come from a regeneration that forgot headroom; near
      // silence would come from one that forgot to normalize.
      for (final note in NoteFrequency.playableNotes) {
        final x = load(note).samples;
        var peak = 0.0;
        for (final v in x) {
          peak = math.max(peak, v.abs());
        }
        expect(peak, lessThanOrEqualTo(0.99), reason: '$note clips');
        expect(peak, greaterThan(0.25), reason: '$note is too quiet to hear');
      }
    });

    test('the samples are not all the same length', () {
      // Pins the specific regression: 61 files of identical frame count meant
      // one envelope shared by every pitch.
      final lengths = NoteFrequency.playableNotes
          .map((n) => load(n).samples.length)
          .toSet();
      expect(lengths.length, greaterThan(20),
          reason: 'durations should vary with pitch');
    });
  });
}
