import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:melody_app/domain/session/level_session_flow.dart';
import 'package:melody_app/domain/keyboard/keyboard_instrument.dart';
import 'package:test/test.dart';

void main() {
  const level = Level(
    id: 'level-001-a',
    name: 'Three Friends',
    type: LevelType.standard,
    requiredNotes: ['C4', 'D4', 'E4'],
    tempoBpm: 80,
    successThreshold: SuccessThreshold(minAccuracy: 0.7, minNotesHit: 2),
    rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
  );

  group('LevelSessionFlow (orchestrates content → engine → progress)', () {
    test('plays required notes in order and passes the level', () {
      final instrument = KeyboardInstrument();
      final progress = PlayerProgress.initial();
      final events = <AnalyticsEvent>[];
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: progress,
        onAnalyticsEvent: events.add,
      );

      expect(flow.submit(const NoteEvent(note: 'C4', timestampMs: 0)), isTrue);
      expect(
          flow.submit(const NoteEvent(note: 'D4', timestampMs: 100)), isTrue);
      expect(
          flow.submit(const NoteEvent(note: 'E4', timestampMs: 200)), isTrue);
      expect(flow.isComplete, isTrue);
      expect(flow.result!.passed, isTrue);
      expect(progress.stars, 3);
      expect(progress.noteCurrency, 5);
    });

    test('missed notes hold the player and never end the run', () {
      // Rewritten for the hold rule. This test used to assert that three taps
      // (two of them wrong) ended a 3-note level; ending a level by running out
      // of taps is precisely the reported bug — the child got "Nice try" after
      // 6 presses whether or not they could play. A run now ends only when the
      // song has been played through.
      final instrument = KeyboardInstrument();
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: PlayerProgress.initial(),
      );
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 0));
      expect(flow.isComplete, isFalse);
      expect(flow.targetNote, 'C4', reason: 'a miss must not skip a note');
      flow.submit(const NoteEvent(note: 'D4', timestampMs: 100));
      expect(flow.targetNote, 'C4');
      flow.submit(const NoteEvent(note: 'Y4', timestampMs: 200));
      expect(flow.isComplete, isFalse);
      for (final note in ['C4', 'D4', 'E4']) {
        flow.submit(NoteEvent(note: note, timestampMs: 300));
      }
      expect(flow.isComplete, isTrue);
      // 3 hits in 6 taps: the run can now fail on accuracy, which is the only
      // honest way left to fail.
      expect(flow.result!.accuracy, closeTo(0.5, 0.001));
      expect(flow.result!.passed, isFalse);
    });

    test('passing level emits level_completed analytics event', () {
      final instrument = KeyboardInstrument();
      final progress = PlayerProgress.initial();
      final events = <AnalyticsEvent>[];
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: progress,
        onAnalyticsEvent: events.add,
      );
      flow.submit(const NoteEvent(note: 'C4', timestampMs: 0));
      flow.submit(const NoteEvent(note: 'D4', timestampMs: 100));
      flow.submit(const NoteEvent(note: 'E4', timestampMs: 200));
      final completed = events
          .where((e) => e.type == AnalyticsEventType.levelCompleted)
          .toList();
      expect(completed, hasLength(1));
      expect(completed.single.payload['levelId'], 'level-001-a');
      expect(completed.single.payload['starsAwarded'], 3);
    });

    test('failing level emits practice_session but no level_completed', () {
      final instrument = KeyboardInstrument();
      final events = <AnalyticsEvent>[];
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: PlayerProgress.initial(),
        onAnalyticsEvent: events.add,
      );
      // Play the song out with two fumbles: 3 hits in 5 taps is 0.6 accuracy,
      // below the 0.7 threshold, so this fails honestly rather than by running
      // out of notes.
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 0));
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 100));
      for (final note in ['C4', 'D4', 'E4']) {
        flow.submit(NoteEvent(note: note, timestampMs: 200));
      }
      expect(events.any((e) => e.type == AnalyticsEventType.practiceSession),
          isTrue);
      expect(events.any((e) => e.type == AnalyticsEventType.levelCompleted),
          isFalse);
      expect(flow.result!.starsAwarded, 0);
    });

    test('updates notes mastered in progress as notes are hit', () {
      final instrument = KeyboardInstrument();
      final progress = PlayerProgress.initial();
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: progress,
      );
      flow.submit(const NoteEvent(note: 'C4', timestampMs: 0));
      expect(progress.masteryHits('C4'), 1);
    });

    test('submits after completion are ignored', () {
      final instrument = KeyboardInstrument();
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: PlayerProgress.initial(),
      );
      for (final note in ['C4', 'D4', 'E4']) {
        flow.submit(NoteEvent(note: note, timestampMs: 0));
      }
      expect(
          flow.submit(const NoteEvent(note: 'C4', timestampMs: 100)), isFalse);
    });

    test('completing a level records the practice day (streak >= 1)', () {
      final instrument = KeyboardInstrument();
      final progress = PlayerProgress.initial();
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: progress,
        now: () => DateTime.utc(2026, 9, 20),
      );
      flow.submit(const NoteEvent(note: 'C4', timestampMs: 0));
      flow.submit(const NoteEvent(note: 'D4', timestampMs: 100));
      flow.submit(const NoteEvent(note: 'E4', timestampMs: 200));
      expect(flow.isComplete, isTrue);
      expect(progress.currentStreak, greaterThanOrEqualTo(1));
    });

    test('failing a level still records the practice day (non-punitive)', () {
      final instrument = KeyboardInstrument();
      final progress = PlayerProgress.initial();
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: progress,
        now: () => DateTime.utc(2026, 9, 20),
      );
      // Two fumbles then the song: 0.6 accuracy fails the threshold, and a
      // failed run still counts as practice.
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 0));
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 100));
      for (final note in ['C4', 'D4', 'E4']) {
        flow.submit(NoteEvent(note: note, timestampMs: 200));
      }
      expect(flow.isComplete, isTrue);
      expect(progress.currentStreak, 1);
    });

    test('completing a level twice in one day keeps streak at 1', () {
      final progress = PlayerProgress.initial();
      for (var i = 0; i < 2; i++) {
        final flow = LevelSessionFlow(
          level: level,
          instrument: KeyboardInstrument(),
          progress: progress,
          now: () => DateTime.utc(2026, 9, 20),
        );
        flow.submit(const NoteEvent(note: 'C4', timestampMs: 0));
        flow.submit(const NoteEvent(note: 'D4', timestampMs: 100));
        flow.submit(const NoteEvent(note: 'E4', timestampMs: 200));
      }
      expect(progress.currentStreak, 1);
    });

    test('consecutive practice days grow the streak', () {
      final progress = PlayerProgress.initial();
      for (final day in [
        DateTime.utc(2026, 9, 20),
        DateTime.utc(2026, 9, 21),
      ]) {
        final flow = LevelSessionFlow(
          level: level,
          instrument: KeyboardInstrument(),
          progress: progress,
          now: () => day,
        );
        flow.submit(const NoteEvent(note: 'C4', timestampMs: 0));
        flow.submit(const NoteEvent(note: 'D4', timestampMs: 100));
        flow.submit(const NoteEvent(note: 'E4', timestampMs: 200));
      }
      expect(progress.currentStreak, 2);
    });
  });
}
