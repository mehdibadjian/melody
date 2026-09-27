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
}
