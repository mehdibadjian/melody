import 'dart:io';

import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/content/content_parser.dart';
import 'package:melody_app/domain/instrument/instrument_engine.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:melody_app/widgets/piano_keyboard.dart';
import 'package:test/test.dart';

/// What the on-screen keyboard can and cannot play.
///
/// [PianoKeyboard] draws white keys only and shows one octave below 900 dp,
/// while the acoustic path accepts the full 61-key board. The gap predates this
/// test — measuring it for GOLDEN found *Amazing Grace* was already unwinnable
/// on a phone-width board in a shipped release — but nothing anywhere stated
/// which levels the tap path could not serve.
///
/// Two distinct facts, because they fail differently:
///
///  * **Unwinnable** — tapping every reachable key still misses the success
///    threshold. The child cannot finish the level by tapping at all.
///  * **Skips notes** — the level can be won, but some required notes have no
///    key, so it completes while silently stepping over them.
///
/// The second is the easier one to miss, so both are pinned to exact sets.
/// Widen the board or re-arrange a song and this test tells you which entries
/// to delete; quietly break one and it tells you that too.
void main() {
  final doc = ContentParser.parseDocument(
    File('assets/content/lessons.json').readAsStringSync(),
  );

  const phoneWidth = 400.0; // <= 900 dp: naturals C4-B4, seven keys
  const wideWidth = 1000.0; // > 900 dp: naturals C4-B5, fourteen keys

  /// Notes this board cannot emit for [level].
  Set<String> missingFrom(Level level, Set<String> board) =>
      level.requiredNotes.where((n) => !board.contains(n)).toSet();

  /// Whether a run that plays every reachable note correctly and mashes a
  /// reachable key for the rest still clears the threshold. Uses the real
  /// [LessonSession] instead of restating its rule, so this cannot drift from
  /// how the app actually scores a run.
  bool winnableByTapping(Level level, Set<String> board) {
    final session = LessonSession(expectedNotes: level.requiredNotes);
    // The mash key must be a *wrong* answer for every unreachable note, or the
    // simulation would over-report hits. Asserted below, not assumed.
    final mash = board.first;
    for (var i = 0; i < level.requiredNotes.length; i++) {
      final expected = level.requiredNotes[i];
      session.submit(
        NoteEvent(
          note: board.contains(expected) ? expected : mash,
          timestampMs: i * 500,
        ),
      );
    }
    expect(session.complete, isTrue, reason: '${level.id} did not run to end');
    return session.passes(level.successThreshold);
  }

  /// Levels whose notes the phone board cannot all emit.
  const phoneMissing = {
    'when-saints-phrase': {'C5'},
    'amazing-grace-phrase': {'C5', 'D5', 'E5'},
    'golden-beginner': {'C5', 'D5'},
    'golden-medium': {'C5', 'D5', 'E5', 'G5', 'A5', 'B5'},
    'golden-hard': {'F#4', 'C5', 'D5', 'E5', 'G5', 'A5', 'B5', 'D6'},
  };

  /// Levels that cannot be *won* by tapping a phone board at all. Amazing
  /// Grace shipped this way before this test existed; the two GOLDEN
  /// arrangements sit deliberately above the phone's single octave and are
  /// meant for the acoustic path.
  const phoneUnwinnable = {
    'amazing-grace-phrase',
    'golden-medium',
    'golden-hard',
  };

  const wideMissing = {
    'golden-hard': {'F#4', 'D6'},
  };

  const wideUnwinnable = <String>{};

  void describe({
    required double width,
    required Map<String, Set<String>> expectedMissing,
    required Set<String> expectedUnwinnable,
    required String label,
  }) {
    final board = PianoKeyboard.playableNotes(screenWidth: width);
    final gaps = <String, Set<String>>{};
    final unwinnable = <String>{};
    for (final lesson in doc.lessons) {
      for (final level in lesson.levels) {
        final gap = missingFrom(level, board);
        if (gap.isNotEmpty) gaps[level.id] = gap;
        if (!winnableByTapping(level, board)) {
          unwinnable.add(level.id);
          // Unwinnable must be caused by an unreachable key. A level with every
          // note on the board that still cannot pass is a different bug and
          // needs naming.
          expect(gap, isNotEmpty,
              reason: '${level.id} cannot be won on $label even though every '
                  'note is tappable - the level itself is broken');
        }
      }
    }
    expect(gaps, expectedMissing, reason: '$label missing-note map drifted');
    expect(unwinnable, expectedUnwinnable,
        reason: '$label unwinnable set drifted. A new entry means a child '
            'cannot finish that level by tapping; a removed one means the '
            'board or arrangement changed.');
  }

  group('on-screen keyboard coverage', () {
    test('phone board: which levels skip notes and which are unwinnable', () {
      describe(
        width: phoneWidth,
        expectedMissing: phoneMissing,
        expectedUnwinnable: phoneUnwinnable,
        label: 'phone board',
      );
    });

    test('wide board: which levels skip notes and which are unwinnable', () {
      describe(
        width: wideWidth,
        expectedMissing: wideMissing,
        expectedUnwinnable: wideUnwinnable,
        label: 'wide board',
      );
    });

    test('every unwinnable level is also missing notes', () {
      // Guards the two sets stay consistent rather than drifting independently.
      for (final entry in phoneUnwinnable) {
        expect(phoneMissing.keys, contains(entry), reason: '$entry on phone');
      }
      for (final entry in wideUnwinnable) {
        expect(wideMissing.keys, contains(entry), reason: '$entry on wide');
      }
    });

    test('the board has no black keys and one octave on a phone', () {
      // Gaining sharps or a second phone octave makes entries above stale, and
      // these assertions are what say so.
      final phone = PianoKeyboard.playableNotes(screenWidth: phoneWidth);
      expect(phone.where((n) => n.contains('#')), isEmpty);
      expect(phone, hasLength(7));
      expect(
          PianoKeyboard.playableNotes(screenWidth: wideWidth), hasLength(14));
    });

    test('the mash key can never accidentally match a required note', () {
      // winnableByTapping counts an unreachable note as a hit if the mash key
      // equals it, which would hide an unwinnable level.
      for (final width in [phoneWidth, wideWidth]) {
        final board = PianoKeyboard.playableNotes(screenWidth: width);
        expect(board.first, 'C4');
        for (final lesson in doc.lessons) {
          for (final level in lesson.levels) {
            for (final note in missingFrom(level, board)) {
              expect(note, isNot('C4'), reason: level.id);
            }
          }
        }
      }
    });
  });
}
