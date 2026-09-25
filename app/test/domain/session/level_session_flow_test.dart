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
      expect(flow.submit(const NoteEvent(note: 'D4', timestampMs: 100)), isTrue);
      expect(flow.submit(const NoteEvent(note: 'E4', timestampMs: 200)), isTrue);
      expect(flow.isComplete, isTrue);
      expect(flow.result!.passed, isTrue);
      expect(progress.stars, 3);
      expect(progress.noteCurrency, 5);
    });

    test('missed notes are non-punitive: session still completes', () {
      final instrument = KeyboardInstrument();
      final flow = LevelSessionFlow(
        level: level,
        instrument: instrument,
        progress: PlayerProgress.initial(),
      );
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 0));
      flow.submit(const NoteEvent(note: 'D4', timestampMs: 100));
      flow.submit(const NoteEvent(note: 'Y4', timestampMs: 200));
      expect(flow.isComplete, isTrue);
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
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 0));
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 100));
      flow.submit(const NoteEvent(note: 'X4', timestampMs: 200));
      expect(events.any((e) => e.type == AnalyticsEventType.practiceSession), isTrue);
      expect(events.any((e) => e.type == AnalyticsEventType.levelCompleted), isFalse);
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
      expect(flow.submit(const NoteEvent(note: 'C4', timestampMs: 100)), isFalse);
    });
  });
}