import 'dart:io';

import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/content/content_parser.dart';
import 'package:melody_app/domain/instrument/instrument_engine.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:melody_app/widgets/piano_keyboard.dart';
import 'package:test/test.dart';

/// Every shipped song must be finishable by tapping the screen.
///
/// This file used to document the opposite: a pinned list of levels the
/// on-screen board could not serve, because it drew seven white keys pinned to
/// C4-B4 while the songs reached higher and used sharps. *Amazing Grace*
/// shipped in that state — its melody is C5-E5, none of it tappable, best
/// achievable accuracy 0.14 against a threshold of 0.8.
///
/// The escape hatch was to fix the board rather than curate the exception list,
/// so the guard is now a promise instead of a confession: for every note of
/// every level, at every supported width, the key exists and the level can be
/// completed. If a future arrangement goes off the 61-key piano, or the window
/// stops following the target, this fails — which is the outcome that should
/// make someone change content, because an exception list here would just be a
/// way to ship an unfinishable song knowingly.
void main() {
  final doc = ContentParser.parseDocument(
    File('assets/content/lessons.json').readAsStringSync(),
  );

  final levels = [
    for (final lesson in doc.lessons)
      for (final level in lesson.levels) level
  ];

  const phoneWidth = 400.0;
  const wideWidth = 1000.0;

  /// Play the song the way a child who is being shown the target would: tap
  /// exactly the note on screen, every time.
  ///
  /// Drives the real [LessonSession] rather than restating its rule, so this
  /// cannot drift from how the app actually scores a run.
  LessonSession playPerfectly(Level level) {
    final session = LessonSession(expectedNotes: level.requiredNotes);
    while (!session.complete) {
      session.submit(
        NoteEvent(
          note: session.nextExpectedNote!,
          timestampMs: session.totalAttempts * 500,
        ),
      );
    }
    return session;
  }

  group('shipped songs are finishable on the tap board', () {
    test('the library actually has levels to check', () {
      // Guards against this file passing because `levels` went empty.
      expect(levels, isNotEmpty);
      expect(levels.length, greaterThanOrEqualTo(14));
    });

    test('every required note is a key on the board', () {
      for (final level in levels) {
        for (final note in level.requiredNotes) {
          expect(PianoKeyboard.board.containsNote(note), isTrue,
              reason: '${level.id} asks for $note, which is not on the '
                  '${PianoKeyboard.board.name} board');
        }
      }
    });

    test('at phone width, the shown window contains every note it asks for',
        () {
      // The window slides per target, so this is checked note by note rather
      // than against one static set: a song whose notes are individually
      // reachable can still be unfinishable if the board ever fails to show one.
      for (final level in levels) {
        for (final note in level.requiredNotes) {
          expect(PianoKeyboard.windowFor(note, phoneWidth), contains(note),
              reason: '${level.id} needs $note, off screen at ${phoneWidth}dp');
        }
      }
    });

    test('at wide width, the shown window contains every note it asks for', () {
      for (final level in levels) {
        for (final note in level.requiredNotes) {
          expect(PianoKeyboard.windowFor(note, wideWidth), contains(note),
              reason: '${level.id} needs $note, off screen at ${wideWidth}dp');
        }
      }
    });

    test('playing what is shown completes the song and passes', () {
      for (final level in levels) {
        final session = playPerfectly(level);
        expect(session.totalAttempts, level.requiredNotes.length,
            reason: '${level.id} took more taps than it has notes: a correct '
                'tap must never cost the child a second attempt');
        expect(session.hits, level.requiredNotes.length);
        expect(session.accuracy, 1.0);
        expect(session.passes(level.successThreshold), isTrue,
            reason: '${level.id} cannot be passed by playing every note '
                'correctly — the thresholds themselves are unreachable');
      }
    });

    test('an unreachable-threshold level is a content bug, not an exception',
        () {
      // minNotesHit above the note count makes a level mathematically
      // unpassable no matter how the board is drawn.
      for (final level in levels) {
        expect(level.successThreshold.minNotesHit,
            lessThanOrEqualTo(level.requiredNotes.length),
            reason: '${level.id} demands more hits than it has notes');
        expect(level.successThreshold.minAccuracy, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('fumbling cannot cost the rest of the song', () {
    test('wrong taps hold the child on the note instead of ending the run', () {
      // The reported bug: after a few presses the level was simply over, with a
      // score that ignored how well the child actually played. A level now ends
      // by finishing the song, so a fumble is one wasted tap, not a lost run.
      for (final level in levels) {
        final session = LessonSession(expectedNotes: level.requiredNotes);
        var taps = 0;
        while (!session.complete && taps < level.requiredNotes.length * 3) {
          final target = session.nextExpectedNote!;
          // Alternate: fumble once onto a different board key, then land it.
          final wrong = PianoKeyboard.board.notes.firstWhere(
              (n) => n != target && !level.requiredNotes.contains(n));
          session.submit(NoteEvent(note: wrong, timestampMs: taps * 100));
          taps++;
          if (session.complete) break;
          session.submit(NoteEvent(
              note: session.nextExpectedNote!, timestampMs: taps * 100));
          taps++;
        }
        expect(session.complete, isTrue,
            reason: '${level.id} not finished after $taps taps with a '
                'hit-every-other-tap player');
        expect(session.hits, level.requiredNotes.length,
            reason: '${level.id}: a child who landed every note should not be '
                'missing some');
      }
    });

    test('one wrong tap per note fails every level, so thresholds still bite',
        () {
      // The other side of the hold rule: misses still count against accuracy, so
      // making the board finishable did not make it free. A child who fumbles
      // once before every single note lands all of them and still scores 0.5,
      // under every threshold in the library (0.70-0.80).
      for (final level in levels) {
        final session = LessonSession(expectedNotes: level.requiredNotes);
        for (final note in level.requiredNotes) {
          session.submit(const NoteEvent(note: 'C1', timestampMs: 0));
          session.submit(NoteEvent(note: note, timestampMs: 0));
        }
        expect(session.hits, level.requiredNotes.length);
        expect(session.accuracy, closeTo(0.5, 0.001));
        expect(session.passes(level.successThreshold), isFalse,
            reason: '${level.id} passes at 50% accuracy, so its threshold is '
                'looser than the library intends');
      }
    });

    test('nextExpectedNote is null exactly when the song is over', () {
      final level = levels.first;
      final session = LessonSession(expectedNotes: level.requiredNotes);
      expect(session.nextExpectedNote, level.requiredNotes.first);
      for (var i = 0; i < level.requiredNotes.length; i++) {
        session.submit(
            NoteEvent(note: session.nextExpectedNote!, timestampMs: i * 100));
      }
      expect(session.complete, isTrue);
      expect(session.nextExpectedNote, isNull);
      // Further taps change nothing.
      final before = session.totalAttempts;
      session.submit(const NoteEvent(note: 'C4', timestampMs: 9999));
      expect(session.totalAttempts, before);
    });
  });
}
