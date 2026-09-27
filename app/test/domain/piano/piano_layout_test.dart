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

  group('octaveAlignedWindow', () {
    test('starts on a C, and ends on one wherever a full octave fits', () {
      final layout = KeyboardLayout.sixtyOne;
      for (final target in layout.notes) {
        final window = layout.octaveAlignedWindow(target);
        expect(midiFromNote(window.first)! % 12, 0,
            reason: 'window for $target starts on ${window.first}');
        // The 61-key board spans 5 whole octaves, so every default-width window
        // can end on a C. Boards with a partial top octave are covered below.
        expect(midiFromNote(window.last)! % 12, 0,
            reason: 'window for $target ends on ${window.last}');
      }
    });

    test('contains the target for every key on the board', () {
      final layout = KeyboardLayout.sixtyOne;
      for (final target in layout.notes) {
        expect(layout.octaveAlignedWindow(target), contains(target),
            reason: 'target $target must be on screen');
      }
    });

    test('is exactly two octaves of keys wide', () {
      final layout = KeyboardLayout.sixtyOne;
      // C4 is mid-board, so no clamping applies.
      final window = layout.octaveAlignedWindow('C4');
      expect(window, hasLength(25));
      expect(window.first, 'C3');
      expect(window.last, 'C5');
    });

    test('never renders a phantom black-key group', () {
      // The concrete bug: a centred 15-key window starting on E has no black key
      // between its first two white keys, so the 2-and-3 black-key pattern that
      // tells a child where C is repeats one white key early and drifts off the
      // highlighted note. A C-anchored window cannot produce that shape.
      final layout = KeyboardLayout.sixtyOne;
      for (final target in layout.notes) {
        final window = layout.octaveAlignedWindow(target);
        final whites =
            window.where((n) => !isBlackKeyMidi(midiFromNote(n)!)).toList();
        // Every white key except the final C must be followed by a black key,
        // and the only unpaired ones are E and B.
        for (var i = 0; i < whites.length - 1; i++) {
          final pc = midiFromNote(whites[i])! % 12;
          final paired = isBlackKeyMidi(midiFromNote(whites[i])! + 1);
          expect(paired, pc != 4 && pc != 11,
              reason: '${whites[i]} in window for $target');
        }
      }
    });

    test('clamps to the top of the board for a high target', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.octaveAlignedWindow('C7');
      expect(window.last, 'C7');
      expect(window.first, 'C5');
      expect(window, contains('C7'));
    });

    test('clamps to the bottom of the board for a low target', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.octaveAlignedWindow('C2');
      expect(window.first, 'C2');
      expect(window.last, 'C4');
    });

    test('honours the requested octave count', () {
      final layout = KeyboardLayout.sixtyOne;
      expect(layout.octaveAlignedWindow('C4', octaves: 1), hasLength(13));
      expect(layout.octaveAlignedWindow('C4', octaves: 4), hasLength(49));
    });

    test('clamps a nonsense octave count', () {
      final layout = KeyboardLayout.sixtyOne;
      expect(layout.octaveAlignedWindow('C4', octaves: 0), hasLength(13));
      // Wider than the board: the window stops at the board edges.
      expect(layout.octaveAlignedWindow('C4', octaves: 8), hasLength(61));
    });

    test('handles an unparseable target without dropping keys', () {
      final layout = KeyboardLayout.sixtyOne;
      final window = layout.octaveAlignedWindow('nope');
      expect(window, isNotEmpty);
      expect(window.first, startsWith('C'));
    });

    test('works on the 88-key board', () {
      final layout = KeyboardLayout.eightyEight;
      for (final target in ['C4', 'A4', 'B7', 'C8']) {
        final window = layout.octaveAlignedWindow(target);
        expect(window, contains(target), reason: 'target $target');
        expect(midiFromNote(window.first)! % 12, 0);
        expect(layout.containsNote(window.last), isTrue);
      }
    });

    test('holds an upper-octave target in a narrow one-octave window', () {
      // A note from C# up to F is the awkward band: centring a one-octave window
      // on the C below it ends the window short of the note, so the child's own
      // target would be off screen. The anchor moves up to that note's octave.
      final layout = KeyboardLayout.sixtyOne;
      for (final target in ['C#4', 'D4', 'D#4', 'E4', 'F4']) {
        final window = layout.octaveAlignedWindow(target, octaves: 1);
        expect(window, contains(target), reason: target);
        expect(midiFromNote(window.first)! % 12, 0);
        expect(window, hasLength(13));
      }
    });

    test('keeps a target in a board with a partial top octave', () {
      // A 76-key board tops out at G7, so no C-anchored two-octave window
      // reaches it. The window gives up its C end rather than drop the note.
      final layout = KeyboardLayout.seventySix;
      final window = layout.octaveAlignedWindow('G7', octaves: 2);
      expect(window, contains('G7'));
      expect(midiFromNote(window.first)! % 12, 0);
      expect(window.last, 'G7');
      expect(layout.containsNote(window.last), isTrue);
    });

    test('clamps a target below the board\'s first C up to it', () {
      // A C-anchored window cannot start on an 88-key board's partial bottom
      // octave, so A0 and B0 render as the C1 window they belong to.
      final layout = KeyboardLayout.eightyEight;
      final window = layout.octaveAlignedWindow('A0');
      expect(window.first, 'C1');
      expect(window, isNot(contains('A0')));
    });
  });
}
