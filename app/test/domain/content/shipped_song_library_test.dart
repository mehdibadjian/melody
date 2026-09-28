import 'dart:io';

import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_parser.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:test/test.dart';

/// Guards the REAL shipped song library (`assets/content/lessons.json`).
///
/// Content authors edit JSON, not code, so this is the safety net that turns a
/// bad song file into a failing CI run instead of a broken lesson at runtime
/// (PRD §4.1: "invalid content fails loudly at parse time"). It also keeps the
/// library playable on the v1 hardware: a 61-key board, a bundled WAV per note,
/// and a recognisable range.
void main() {
  final raw = File('assets/content/lessons.json').readAsStringSync();
  final doc = ContentParser.parseDocument(raw);
  final board = KeyboardLayout.sixtyOne;

  /// Note names that have a bundled WAV in assets/audio/notes/, decoded through
  /// [NoteAsset] so `fs4.wav` reads back as `F#4` rather than `FS4`.
  final playableAudio = Directory('assets/audio/notes')
      .listSync()
      .map((f) => f.path.split(Platform.pathSeparator).last)
      .where((n) => n.endsWith('.wav'))
      .map(NoteAsset.noteNameFromFile)
      .toSet();

  test('shipped library parses as schema v2 with multiple songs', () {
    expect(doc.schemaVersion, 2);
    expect(doc.lessons.length, greaterThanOrEqualTo(8));
  });

  test('every song has unique lesson and level ids', () {
    final lessonIds = doc.lessons.map((l) => l.id);
    expect(lessonIds.toSet().length, lessonIds.length,
        reason: 'duplicate lesson id');
    for (final lesson in doc.lessons) {
      final levelIds = lesson.levels.map((l) => l.id);
      expect(levelIds.toSet().length, levelIds.length,
          reason: 'duplicate level id in ${lesson.id}');
    }
  });

  test('songs span multiple genres', () {
    final genres = doc.lessons.map((l) => l.genre).where((g) => g.isNotEmpty);
    expect(genres.toSet().length, greaterThanOrEqualTo(4),
        reason: 'library should cover several genres, not just one');
  });

  test('every note is a real key on the 61-key board', () {
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        for (final note in level.requiredNotes) {
          expect(board.containsNote(note), isTrue,
              reason: '$note (${lesson.id}) is off the 61-key board');
        }
      }
    }
  });

  test('every note has bundled audio (demo playback stays silent-free)', () {
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        for (final note in level.requiredNotes) {
          expect(playableAudio, contains(note),
              reason: '$note (${lesson.id}) has no WAV in assets/audio/notes/');
        }
      }
    }
  });

  test('every song is recognisable length (>= 4 notes) and non-punitive', () {
    // Checks every arrangement, not just the first: the library gained a
    // multi-level song, so a levels.first-only guard would leave the later
    // arrangements unverified.
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        expect(level.requiredNotes.length, greaterThanOrEqualTo(4),
            reason: '${level.id} is too short to be a recognisable phrase');
        // minNotesHit must be achievable (never above the note count).
        expect(level.successThreshold.minNotesHit,
            lessThanOrEqualTo(level.requiredNotes.length),
            reason: '${level.id} asks for more hits than it has notes');
        expect(level.successThreshold.minAccuracy, inInclusiveRange(0.0, 1.0));
      }
    }
  });

  test('the entry arrangement sits inside a comfortable 1.5-octave span', () {
    // Only the first level is beginner-gated: it is what the app selects for a
    // fresh player. Later arrangements may widen on purpose, but they still
    // have to fit the guide keyboard, which shows a C-to-C window.
    for (final lesson in doc.lessons) {
      final range = lesson.levels.first.noteRange;
      expect(range.isEmpty, isFalse,
          reason: '${lesson.id} has no parseable notes');
      final span = midiFromNote(range.high!)! - midiFromNote(range.low!)!;
      expect(span, lessThanOrEqualTo(18),
          reason: '${lesson.id} spans $span semitones — too wide for a '
              'beginner, and it is the arrangement the app opens with');
    }
  });

  test('a song arranged slower than the recording says how fast it is', () {
    // The demo is what a child uses to learn a tune's rhythm, so a practice
    // tempo has to be labelled as one. `songTempoBpm` is only meaningful next
    // to a real recording; if it is ever authored equal to the arrangement's
    // own tempo it is a leftover that makes the UI claim "practice speed" for a
    // tempo that is not slower, so it must not be in the file at all.
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        final song = level.songTempoBpm;
        if (song == null) continue;
        expect(song, isNot(level.tempoBpm),
            reason: '${level.id} sets songTempoBpm to its own tempo; drop the '
                'field instead');
      }
    }
  });

  test('GOLDEN is authored in the song\u0027s real 12/8 pulse', () {
    // The tune is a 12/8 anthem: four dotted-crotchet beats to a bar, three
    // eighths to each. Written as plain 4/4 with one note per beat, the demo
    // plays it at a third of the real speed and the child learns a limping
    // version of a song they recognise. This is the one shipped arrangement
    // where the meter is not decoration, so it is pinned here.
    final golden = doc.lessons.singleWhere((l) => l.id == 'song-golden');
    for (final level in golden.levels) {
      expect(level.meter.notation, '12/8', reason: level.id);
      expect(level.meter.notesPerBeat, 3, reason: level.id);
      expect(level.meter.beatName, 'dotted quarter', reason: level.id);
    }
  });

  test('no arrangement demos faster than the song it comes from', () {
    // A practice arrangement may be slower than the recording; that is the
    // point of three of them. Faster would mean the child hears a version of
    // the tune that does not exist, and the demo stops being reference audio.
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        final song = level.songTempoBpm;
        if (song == null) continue;
        expect(level.tempoBpm, lessThanOrEqualTo(song),
            reason: '${level.id} is faster than its own recording');
      }
    }
  });

  test('an authored rhythm totals whole beats, so the click grid stays in time',
      () {
    // A fractional beat count would leave the last click landing between the
    // melody's end and the bar line, which is the one thing a metronome must
    // never do.
    //
    // `golden-hard` is grandfathered: 85 notes at three to the beat is 28 1/3
    // beats, and that predates authored durations — the level is a note-count
    // challenge in the song's real 12/8 pulse, not a phrase that ends on a bar
    // line. Named here so the allowance cannot quietly grow.
    const grandfathered = {'golden-hard'};
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        if (grandfathered.contains(level.id)) continue;
        final beats = level.totalNoteUnits / level.meter.notesPerBeat;
        expect(beats, closeTo(beats.roundToDouble(), 1e-9),
            reason: '${level.id} lasts $beats beats');
      }
    }
  });

  test('most of the library has an authored rhythm, not a march of equal notes',
      () {
    // The schema could always express durations; this pins that the public
    // domain tunes actually use it. Without a rhythm every song demos as
    // evenly spaced notes, which is why none of them sounded like the tune.
    // GOLDEN is excluded on purpose: its rhythm belongs to whoever clears the
    // rights, not to a guess written into the library.
    final authored = <String>[];
    for (final lesson in doc.lessons) {
      if (lesson.id == 'song-golden') continue;
      for (final level in lesson.levels) {
        if (level.durations != null) authored.add(level.id);
      }
    }
    expect(authored.length, greaterThanOrEqualTo(10),
        reason: 'only ${authored.length} levels carry an authored rhythm');
  });

  test('an authored rhythm actually holds notes, rather than restating 1,1,1', () {
    // A `durations` array of all ones is the same as none at all, and would
    // pass every length check while changing nothing a child can hear.
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        final d = level.durations;
        if (d == null) continue;
        expect(d.any((v) => v != 1.0), isTrue,
            reason: '${level.id} authors a flat rhythm; drop the field instead');
      }
    }
  });

  test('every public-domain tune ends on a held note, like the song does', () {
    // The cadence is the single most recognisable part of a nursery rhyme or
    // hymn: the last note is long. An arrangement that ends on a short note
    // stops sounding finished, so this is checked per tune rather than left to
    // the author's ear.
    for (final lesson in doc.lessons) {
      if (lesson.id == 'song-golden') continue;
      for (final level in lesson.levels) {
        final d = level.durations;
        if (d == null) continue;
        expect(d.last, greaterThan(1.0),
            reason: '${level.id} ends on a short note');
      }
    }
  });
}
