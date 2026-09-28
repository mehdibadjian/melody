// Ties two things that only meet at runtime: the authored `durations` in the
// real content, and the decay of the real bundled samples.
//
// The demo engine (`AssetAudioEngine`) is monophonic — it calls `stop()` before
// each note and a held note is never re-triggered. So a note authored to last
// four beats only *sounds* for four beats if its WAV is still audible that long.
// Nothing in the pure-Dart tests checks that link, and the failure mode is the
// one a parent reports: "the music doesn't sound right, it keeps pausing." Both
// earlier passes of this bug slipped through because each half looked fine alone
// — onsets correct, samples in tune — and only their product went silent.
//
// This walks the shipped library, and for every note held longer than one base
// note it asserts the sample sustains through that slot rather than dropping to
// silence mid-phrase.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_parser.dart';
import 'package:test/test.dart';

void main() {
  final doc = ContentParser.parseDocument(
      File('assets/content/lessons.json').readAsStringSync());
  final levels = doc.lessons.expand((l) => l.levels).toList();

  /// Audible length of a bundled sample, in ms: from the strike until the
  /// envelope falls below [floor] of its own peak. 2 % is roughly where a piano
  /// note stops being clearly heard under a metronome click.
  double audibleMs(String note, {double floor = 0.02}) {
    final w =
        _Wav.read('assets/audio/notes/${NoteAsset.fileBaseFor(note)}.wav');
    final x = w.samples;
    var peak = 0.0;
    for (final v in x) {
      peak = math.max(peak, v.abs());
    }
    final threshold = floor * peak;
    var last = 0;
    for (var i = x.length - 1; i >= 0; i--) {
      if (x[i].abs() > threshold) {
        last = i;
        break;
      }
    }
    return (last + 1) / w.sampleRate * 1000.0;
  }

  /// The longest slot a note is held for *before another note follows*, in ms.
  /// Only these create an audible pause: a terminal held note is the last thing
  /// in the tune and legitimately rings out and fades, so its decay is a note
  /// release, not a gap. This is the number the sample has to keep sounding.
  double longestHeldMs(String note) {
    var best = 0.0;
    for (final level in levels) {
      final d = level.durations;
      if (d == null) continue;
      final noteMs = level.meter.noteMs(level.tempoBpm);
      for (var i = 0; i < level.requiredNotes.length - 1; i++) {
        if (level.requiredNotes[i] == note) {
          best = math.max(best, d[i] * noteMs);
        }
      }
    }
    return best;
  }

  group('a held demo note sustains through its own slot', () {
    final heldNotes = <String>{
      for (final level in levels)
        ...?level.durations
            ?.asMap()
            .entries
            .where((e) => e.value > 1.0)
            .map((e) => level.requiredNotes[e.key]),
    };

    test('the library actually holds some notes open', () {
      // If this set is empty the test below is vacuous, which is how the first
      // version of this check would have passed on nothing.
      expect(heldNotes, isNotEmpty);
      expect(longestHeldMs('C4'), greaterThan(1000),
          reason: 'expected a mid-tune note held longer than a second');
    });

    for (final note in [
      // The widest held register in the library: the three-second cadence
      // notes and the two-second halves that lead into them.
      'C4', 'E4', 'C5', 'D5', 'G4', 'A4', 'D4',
    ]) {
      test('$note keeps ringing as long as any tune holds it', () {
        final held = longestHeldMs(note);
        if (held == 0) return; // not held anywhere in the library
        final rings = audibleMs(note);
        // 120 ms is below what reads as a gap; the holes that shipped were
        // 1400–2400 ms, so this catches the real bug without being brittle.
        expect(rings, greaterThanOrEqualTo(held - 120),
            reason: '$note is held for ${held.round()}ms but its sample is '
                'inaudible after ${rings.round()}ms — that silence is the '
                '"pause between notes" a child hears');
      });
    }
  });

  group('a full playthrough has no inter-note silence', () {
    test('no level goes dead between one note ending and the next beginning',
        () {
      // The strict, product-level version of the check above: replay each
      // level exactly as the engine would (each note cut short by the next
      // onset) and total the silence left inside held notes.
      for (final level in levels) {
        final d = level.durations;
        if (d == null) continue;
        final noteMs = level.meter.noteMs(level.tempoBpm);
        var deadMs = 0.0;
        for (var i = 0; i < level.requiredNotes.length - 1; i++) {
          final slot = d[i] * noteMs;
          final ring = math.min(audibleMs(level.requiredNotes[i]), slot);
          if (ring < slot - 120) deadMs += slot - ring;
        }
        expect(deadMs, lessThan(500),
            reason: '${level.id} leaves ${deadMs.round()}ms of dead air '
                'between notes');
      }
    });
  });
}

/// Minimal 16-bit mono PCM WAV reader, matching the one in the quality test so
/// this file stays pure-Dart and runs on the plain VM.
class _Wav {
  _Wav(this.samples, this.sampleRate);

  final Float64List samples;
  final int sampleRate;

  static _Wav read(String path) {
    final bytes = File(path).readAsBytesSync();
    var i = 12;
    Uint8List? data;
    var rate = 0;
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size =
          ByteData.sublistView(bytes, i + 4, i + 8).getUint32(0, Endian.little);
      final body = i + 8;
      if (id == 'fmt ') {
        rate = ByteData.sublistView(bytes, body + 4, body + 8)
            .getUint32(0, Endian.little);
      } else if (id == 'data') {
        data = Uint8List.sublistView(bytes, body, body + size);
      }
      i = body + size + (size.isOdd ? 1 : 0);
    }
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
