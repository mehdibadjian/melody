import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/instrument/instrument_engine.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:melody_app/domain/keyboard/keyboard_instrument.dart';
import 'package:test/test.dart';

void main() {
  group('InstrumentEngine contract', () {
    test('KeyboardInstrument implements InstrumentInput', () {
      final InstrumentInput instrument = KeyboardInstrument();
      expect(instrument, isA<InstrumentInput>());
    });

    test('keyboard exposes 2 octaves of keys (adaptive layout basis)', () {
      final instrument = KeyboardInstrument(octaves: 2);
      expect(instrument.keyCount, 24);
      expect(instrument.keys.first.note, 'C4');
      expect(instrument.keys.last.note, 'B5');
    });

    test('multi-touch: accepts multiple simultaneous key presses', () async {
      final instrument = KeyboardInstrument();
      final events = <NoteEvent>[];
      final subscription = instrument.noteStream.listen(events.add);
      instrument.press('C4');
      instrument.press('E4');
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.note), ['C4', 'E4']);
      expect(instrument.pressedNotes, unorderedEquals(['C4', 'E4']));
      await subscription.cancel();
    });

    test('release removes a note from pressed set', () {
      final instrument = KeyboardInstrument();
      instrument.press('C4');
      instrument.release('C4');
      expect(instrument.pressedNotes, isEmpty);
    });
  });

  group('Note matching (pitch/timing events in, correctness out)', () {
    late KeyboardInstrument instrument;
    setUp(() => instrument = KeyboardInstrument());

    test('correct note passes', () {
      final result =
          instrument.evaluate(const NoteEvent(note: 'C4', timestampMs: 0));
      expect(result.correct, isTrue);
      expect(result.expectedNote, 'C4');
    });

    test('wrong note fails', () {
      final result =
          instrument.evaluate(const NoteEvent(note: 'D4', timestampMs: 0));
      expect(result.correct, isFalse);
    });

    test('timing tolerance: on-beat note within tolerance is hit', () {
      final result =
          instrument.evaluate(const NoteEvent(note: 'C4', timestampMs: 80));
      expect(result.correct, isTrue);
    });

    test('timing outside tolerance is a miss even with correct pitch', () {
      final result =
          instrument.evaluate(const NoteEvent(note: 'C4', timestampMs: 1000));
      expect(result.correct, isFalse);
      expect(result.missReason, EvaluationMissReason.timing);
    });

    test('wrong pitch reports pitch miss reason', () {
      final result =
          instrument.evaluate(const NoteEvent(note: 'F4', timestampMs: 0));
      expect(result.correct, isFalse);
      expect(result.missReason, EvaluationMissReason.pitch);
    });
  });

  group('LessonSession evaluation (correctness out)', () {
    test('first note is never a timing miss (no previous-note baseline)', () {
      final instrument = KeyboardInstrument();
      final session = instrument.startSession(['C4', 'D4']);
      session.submit(const NoteEvent(note: 'C4', timestampMs: 9000));
      expect(session.hits, 1);
    });

    test('normal beat spacing between notes is not a timing miss', () {
      final instrument = KeyboardInstrument(tempoBpm: 60);
      final session = instrument.startSession(['C4', 'D4', 'E4']);
      // Beats 1s apart at 60bpm; per-note tolerance is 500ms, so gap-based
      // timing checks would wrongly fail every note after the first.
      session.submit(const NoteEvent(note: 'C4', timestampMs: 1000));
      session.submit(const NoteEvent(note: 'D4', timestampMs: 2000));
      session.submit(const NoteEvent(note: 'E4', timestampMs: 3000));
      expect(session.hits, 3);
      expect(session.accuracy, 1.0);
    });

    test('computes accuracy across a sequence of note events', () {
      final instrument = KeyboardInstrument();
      final session = instrument.startSession(['C4', 'D4', 'E4', 'F4']);
      session.submit(const NoteEvent(note: 'C4', timestampMs: 0)); // hit
      session.submit(const NoteEvent(note: 'D4', timestampMs: 100)); // hit
      session
          .submit(const NoteEvent(note: 'X4', timestampMs: 200)); // pitch miss
      session.submit(const NoteEvent(note: 'F4', timestampMs: 350)); // hit
      expect(session.hits, 3);
      expect(session.totalAttempts, 4);
      expect(session.accuracy, closeTo(0.75, 0.001));
      expect(session.complete, isTrue);
    });

    test('session passes when thresholds met (PRD: success thresholds)', () {
      final instrument = KeyboardInstrument();
      final session = instrument.startSession(['C4', 'D4']);
      session.submit(const NoteEvent(note: 'C4', timestampMs: 0));
      session.submit(const NoteEvent(note: 'D4', timestampMs: 100));
      expect(
        session.passes(const SuccessThreshold(
          minAccuracy: 0.7,
          minNotesHit: 2,
        )),
        isTrue,
      );
    });

    test('session fails when accuracy below threshold', () {
      final instrument = KeyboardInstrument();
      final session = instrument.startSession(['C4', 'D4', 'E4']);
      session.submit(const NoteEvent(note: 'C4', timestampMs: 0));
      session.submit(const NoteEvent(note: 'X4', timestampMs: 100));
      expect(
        session.passes(const SuccessThreshold(
          minAccuracy: 0.7,
          minNotesHit: 1,
        )),
        isFalse,
      );
    });

    test('tolerance window scales with tempo (slower tempo = wider window)',
        () {
      final slow = KeyboardInstrument(timingToleranceMs: null, tempoBpm: 60);
      final fast = KeyboardInstrument(timingToleranceMs: null, tempoBpm: 180);
      expect(slow.timingToleranceMs, greaterThan(fast.timingToleranceMs));
    });

    test(
        'session scoring is pitch-only; instrument timing is separate feedback',
        () {
      final instrument = KeyboardInstrument(tempoBpm: 60);
      final session = instrument.startSession(['C4', 'D4']);

      // Instrument-level evaluate checks timing
      final lateResult = instrument.evaluate(
        const NoteEvent(note: 'C4', timestampMs: 5000),
      );
      expect(lateResult.correct, isFalse);
      expect(lateResult.missReason, EvaluationMissReason.timing);

      // Session-level submit ignores timing — only pitch matters
      session.submit(const NoteEvent(note: 'C4', timestampMs: 5000));
      session.submit(const NoteEvent(note: 'D4', timestampMs: 10000));
      expect(session.hits, 2);
      expect(session.accuracy, 1.0);
    });
  });
}
