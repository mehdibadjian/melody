import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/widgets/piano_keyboard.dart';

/// The tappable board is a window onto the same 61-key piano the acoustic guide
/// draws. It used to be its own 7-white-key row pinned to C4-B4, which is why
/// shipped songs were unwinnable on a phone; these tests are mostly about
/// proving that the board a child sees always contains the note being asked
/// for, at both widths, everywhere on the piano.
void main() {
  Widget buildKeyboard({
    required void Function(String note) onNote,
    String targetNote = 'C4',
    double width = 400,
    double height = 800,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: Material(
          child: PianoKeyboard(
            onNote: onNote,
            targetNote: targetNote,
            height: 240,
          ),
        ),
      ),
    );
  }

  group('window follows the target', () {
    test('a phone-width board shows one octave, a wide board two', () {
      expect(PianoKeyboard.octavesFor(400), 1);
      expect(PianoKeyboard.octavesFor(900), 1); // breakpoint is exclusive
      expect(PianoKeyboard.octavesFor(1000), 2);
    });

    test('the target is always on the board, for every key of the piano', () {
      // The bug this widget replaced: ask for a note the board has no key for.
      // Checked across the whole 61-key layout rather than sampled, because the
      // window slides and only certain positions were ever broken.
      for (final note in PianoKeyboard.board.notes) {
        for (final width in [400.0, 500.0, 900.0, 1000.0, 1600.0]) {
          final window = PianoKeyboard.windowFor(note, width);
          expect(window, contains(note),
              reason: 'target $note off the board at ${width}dp');
        }
      }
    });

    test('the window is anchored on a C so black keys match their names', () {
      // A slice starting mid-octave renders a keyboard that does not exist (see
      // KeyboardLayout.octaveAlignedWindow).
      for (final note in PianoKeyboard.board.notes) {
        final window = PianoKeyboard.windowFor(note, 400);
        expect(midiFromNote(window.first)! % 12, 0,
            reason: 'window for $note starts on ${window.first}');
      }
    });

    test('it renders black keys, which the old board had none of', () {
      // F#4 is a real note in shipped content (GOLDEN — Hard).
      expect(PianoKeyboard.windowFor('F#4', 400), contains('F#4'));
    });

    testWidgets('a phone-width octave renders 8 white and 5 black keys',
        (tester) async {
      await tester.pumpWidget(buildKeyboard(onNote: (_) {}));
      // C4..C5 inclusive.
      expect(find.byKey(const Key('key-C4')), findsOneWidget);
      expect(find.byKey(const Key('key-D4')), findsOneWidget);
      expect(find.byKey(const Key('key-B4')), findsOneWidget);
      expect(find.byKey(const Key('key-C5')), findsOneWidget);
      for (final sharp in ['C#4', 'D#4', 'F#4', 'G#4', 'A#4']) {
        expect(find.byKey(Key('key-$sharp')), findsOneWidget, reason: sharp);
      }
    });

    testWidgets('tapping any key reports that exact note', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(buildKeyboard(onNote: tapped.add));
      await tester.tap(find.byKey(const Key('key-E4')));
      await tester.tap(find.byKey(const Key('key-F#4')));
      await tester.pump();
      expect(tapped, ['E4', 'F#4']);
    });

    testWidgets('a sharp is reachable by tap, not just display',
        (tester) async {
      // The whole point of black keys: a song in G major needs F#4 to be
      // finishable on the screen.
      String? hit;
      await tester
          .pumpWidget(buildKeyboard(onNote: (n) => hit = n, targetNote: 'F#4'));
      await tester.tap(find.byKey(const Key('key-F#4')));
      await tester.pump();
      expect(hit, 'F#4');
    });

    testWidgets('the requested target key is the highlighted one',
        (tester) async {
      await tester.pumpWidget(buildKeyboard(onNote: (_) {}, targetNote: 'G4'));
      expect(find.byKey(const Key('target-glow')), findsOneWidget);
      expect(find.byKey(const Key('target-G4')), findsOneWidget);
    });
  });

  group('layout safety', () {
    test('every key of the board is renderable without dropping the target',
        () {
      // Window sizes are derived, never hardcoded, so assert the span the UI
      // commits to.
      for (final width in [400.0, 1000.0]) {
        for (final note in PianoKeyboard.board.notes) {
          final window = PianoKeyboard.windowFor(note, width);
          final octaves = PianoKeyboard.octavesFor(width);
          expect(window.length, lessThanOrEqualTo(octaves * 12 + 1),
              reason: '$note at ${width}dp shows ${window.length} keys');
          expect(
            window,
            everyElement(matches(RegExp(r'^[A-G]#?\d+$'))),
            reason: '$note at ${width}dp produced a bad key name',
          );
        }
      }
    });

    testWidgets('no overflow at the narrowest supported phone', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildKeyboard(onNote: (_) {}, width: 320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow in landscape (short height)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildKeyboard(onNote: (_) {}, width: 800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
