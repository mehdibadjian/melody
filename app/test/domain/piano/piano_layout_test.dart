import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:test/test.dart';

void main() {
  group('note name <-> midi', () {
    test('parses scientific pitch notation to midi numbers', () {
      expect(midiFromNote('A4'), 69);
      expect(midiFromNote('C4'), 60);
      expect(midiFromNote('C5'), 72);
      expect(midiFromNote('C2'), 36);
      expect(midiFromNote('C7'), 96);
    });

    test('accepts sharps, flats, and lowercase letters', () {
      expect(midiFromNote('C#4'), 61);
      expect(midiFromNote('Db4'), 61);
      expect(midiFromNote('a4'), 69);
      expect(midiFromNote('bb4'), 70);
    });

    test('rejects malformed note names', () {
      expect(midiFromNote(''), isNull);
      expect(midiFromNote('H4'), isNull);
      expect(midiFromNote('C'), isNull);
      expect(midiFromNote('C9x'), isNull);
    });

    test('converts midi back to a sharp note name', () {
      expect(noteFromMidi(60), 'C4');
      expect(noteFromMidi(61), 'C#4');
      expect(noteFromMidi(69), 'A4');
      expect(noteFromMidi(96), 'C7');
    });

    test('classifies black keys correctly', () {
      expect(isBlackKeyMidi(60), isFalse); // C
      expect(isBlackKeyMidi(61), isTrue); // C#
      expect(isBlackKeyMidi(64), isFalse); // E
      expect(isBlackKeyMidi(66), isTrue); // F#
    });

    test('round-trips note -> midi -> note', () {
      for (final note in ['C4', 'C#4', 'E4', 'F#5', 'B5', 'A4']) {
        expect(noteFromMidi(midiFromNote(note)!), note);
      }
    });
  });

  group('KeyboardLayout', () {
    test('61-key layout is C2..C7 with 36 white and 25 black keys', () {
      final layout = KeyboardLayout.sixtyOne;
      expect(layout.keyCount, 61);
      expect(layout.lowestNote, 'C2');
      expect(layout.highestNote, 'C7');
      expect(layout.notes, hasLength(61));
      expect(layout.whiteKeyCount, 36);
      expect(layout.blackKeyCount, 25);
    });

    test('76-key layout has 45 white and 31 black keys', () {
      final layout = KeyboardLayout.seventySix;
      expect(layout.keyCount, 76);
      expect(layout.whiteKeyCount, 45);
      expect(layout.blackKeyCount, 31);
      expect(layout.lowestNote, 'E1');
      expect(layout.highestNote, 'G7');
    });

    test('88-key layout is A0..C8 with 52 white and 36 black keys', () {
      final layout = KeyboardLayout.eightyEight;
      expect(layout.keyCount, 88);
      expect(layout.whiteKeyCount, 52);
      expect(layout.blackKeyCount, 36);
      expect(layout.lowestNote, 'A0');
      expect(layout.highestNote, 'C8');
    });

    test('every note in a layout parses to an in-range midi number', () {
      final layout = KeyboardLayout.sixtyOne;
      for (final note in layout.notes) {
        final midi = midiFromNote(note);
        expect(midi, isNotNull, reason: 'unparseable note $note');
        expect(midi, greaterThanOrEqualTo(layout.lowestMidi));
        expect(midi, lessThanOrEqualTo(layout.highestMidi));
      }
    });

    test('contains middle C and typical song notes', () {
      final notes = KeyboardLayout.sixtyOne.notes;
      expect(notes, contains('C4'));
      expect(notes, contains('G4'));
      expect(notes, contains('C5'));
    });

    test('containsNote is bounds-aware', () {
      final layout = KeyboardLayout.sixtyOne;
      expect(layout.containsNote('C4'), isTrue);
      expect(layout.containsNote('C1'), isFalse); // below range
      expect(layout.containsNote('C9'), isFalse); // above range
      expect(layout.containsNote('nope'), isFalse);
    });
  });

  group('visibleWindow', () {
    test('returns a centred slice of the requested size', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.visibleWindow('C4', size: 25);
      expect(window, hasLength(25));
      expect(window, contains('C4'));
    });

    test('clamps to the board start when the target is low', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.visibleWindow('C2', size: 25);
      expect(window.first, 'C2');
      expect(window, hasLength(25));
    });

    test('clamps to the board end when the target is high', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.visibleWindow('C7', size: 25);
      expect(window.last, 'C7');
      expect(window, hasLength(25));
    });

    test('never exceeds the board length', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.visibleWindow('C4', size: 200);
      expect(window, hasLength(61));
    });

    test('falls back to the board centre for an unknown target', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.visibleWindow('nope', size: 25);
      expect(window, hasLength(25));
    });
  });
}
