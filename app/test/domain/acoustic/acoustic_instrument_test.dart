import 'package:melody_app/domain/acoustic/acoustic_instrument.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:test/test.dart';

void main() {
  // Frames are fed as already-detected stable note labels by the test double;
  // the instrument's job is debounce + event emission + evaluation, all pure.
  group('AcousticInstrument — note stability (debounce)', () {
    test('a single transient frame does not emit a note', () async {
      final instrument = AcousticInstrument(stableFramesRequired: 3);
      final emitted = <NoteEvent>[];
      final sub = instrument.noteStream.listen(emitted.add);

      instrument.onDetectedNote('C4');
      instrument.onDetectedNote(null); // flicker away

      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);
      await sub.cancel();
      instrument.dispose();
    });

    test('a note held for stableFramesRequired consecutive frames emits once',
        () async {
      final instrument = AcousticInstrument(stableFramesRequired: 3);
      final emitted = <NoteEvent>[];
      final sub = instrument.noteStream.listen(emitted.add);

      instrument.onDetectedNote('C4');
      instrument.onDetectedNote('C4');
      instrument.onDetectedNote('C4');

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.single.note, 'C4');
      await sub.cancel();
      instrument.dispose();
    });

    test('holding the same note does not re-emit until it changes', () async {
      final instrument = AcousticInstrument(stableFramesRequired: 2);
      final emitted = <NoteEvent>[];
      final sub = instrument.noteStream.listen(emitted.add);

      for (var i = 0; i < 10; i++) {
        instrument.onDetectedNote('E4');
      }

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1)); // one press, not ten
      await sub.cancel();
      instrument.dispose();
    });

    test('a gap (null) between notes lets the same note fire again', () async {
      final instrument = AcousticInstrument(stableFramesRequired: 2);
      final emitted = <NoteEvent>[];
      final sub = instrument.noteStream.listen(emitted.add);

      instrument.onDetectedNote('C4');
      instrument.onDetectedNote('C4');
      instrument.onDetectedNote(null); // release
      instrument.onDetectedNote('C4');
      instrument.onDetectedNote('C4');

      await Future<void>.delayed(Duration.zero);
      expect(emitted.map((e) => e.note), ['C4', 'C4']);
      await sub.cancel();
      instrument.dispose();
    });
  });

  group('AcousticInstrument — InstrumentInput contract', () {
    test('evaluate matches the current target note', () {
      final instrument = AcousticInstrument();
      instrument.setTarget('D4');

      expect(
        instrument
            .evaluate(const NoteEvent(note: 'D4', timestampMs: 0))
            .correct,
        isTrue,
      );
      final miss =
          instrument.evaluate(const NoteEvent(note: 'F4', timestampMs: 0));
      expect(miss.correct, isFalse);
      expect(miss.expectedNote, 'D4');
      instrument.dispose();
    });

    test('startSession returns a session over the expected notes', () {
      final instrument = AcousticInstrument();
      final session = instrument.startSession(['C4', 'D4', 'E4']);
      expect(session.complete, isFalse);
      session.submit(const NoteEvent(note: 'C4', timestampMs: 0));
      session.submit(const NoteEvent(note: 'D4', timestampMs: 0));
      session.submit(const NoteEvent(note: 'E4', timestampMs: 0));
      expect(session.complete, isTrue);
      expect(session.hits, 3);
      instrument.dispose();
    });
  });
}
