import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/theme/tama_theme.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';

void main() {
  // An explicit one-octave window C4..B4: 7 white + 5 black = 12 consecutive
  // keys (built directly so the assertion set is deterministic).
  final window = [
    for (var midi = midiFromNote('C4')!; midi <= midiFromNote('B4')!; midi++)
      noteFromMidi(midi)
  ];

  Widget build({
    void Function(String note)? onNote,
    required String targetNote,
    String? detectedNote,
    String? arrow,
    double width = 700,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(
          body: IllustratedKeyboard(
            windowNotes: window,
            targetNote: targetNote,
            detectedNote: detectedNote,
            arrow: arrow,
            onNote: onNote,
            height: 260,
          ),
        ),
      ),
    );
  }

  testWidgets('renders every white key in the window', (tester) async {
    await tester.pumpWidget(build(targetNote: 'C4'));
    for (final n in ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4']) {
      expect(find.byKey(Key('key-$n')), findsOneWidget, reason: 'white $n');
    }
  });

  testWidgets('renders the black keys (sharps) of the window', (tester) async {
    await tester.pumpWidget(build(targetNote: 'C4'));
    for (final n in ['C#4', 'D#4', 'F#4', 'G#4', 'A#4']) {
      expect(find.byKey(Key('key-$n')), findsOneWidget, reason: 'black $n');
    }
  });

  testWidgets('renders exactly the window keys, no more', (tester) async {
    await tester.pumpWidget(build(targetNote: 'C4'));
    expect(find.byType(IllustratedKeyboard), findsOneWidget);
    // 12 keys total (7 white + 5 black) from the window.
    expect(find.byKey(const Key('keys-layer')), findsOneWidget);
  });

  testWidgets('highlights the target key distinctly', (tester) async {
    await tester.pumpWidget(build(targetNote: 'E4'));
    expect(find.byKey(const Key('target-glow')), findsOneWidget);
    final target = tester.widget<Container>(find.byKey(const Key('key-E4')));
    expect(target.decoration, isNotNull);
  });

  testWidgets('shows the detected-note marker when a wrong note is heard',
      (tester) async {
    await tester.pumpWidget(build(targetNote: 'C4', detectedNote: 'G4'));
    expect(find.byKey(const Key('detected-marker')), findsOneWidget);
    expect(find.byKey(const Key('key-G4')), findsOneWidget);
  });

  testWidgets('no detected marker when nothing is heard yet', (tester) async {
    await tester.pumpWidget(build(targetNote: 'C4'));
    expect(find.byKey(const Key('detected-marker')), findsNothing);
  });

  testWidgets('renders the directional arrow when provided', (tester) async {
    await tester
        .pumpWidget(build(targetNote: 'C4', detectedNote: 'G4', arrow: '▼'));
    expect(find.text('▼'), findsOneWidget);
  });

  testWidgets('tapping a white key fires onNote with its name', (tester) async {
    String? tapped;
    await tester.pumpWidget(build(targetNote: 'C4', onNote: (n) => tapped = n));
    await tester.tap(find.byKey(const Key('key-F4')));
    await tester.pump();
    expect(tapped, 'F4');
  });

  testWidgets('tapping a black key fires onNote with its sharp name',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(build(targetNote: 'C4', onNote: (n) => tapped = n));
    await tester.tap(find.byKey(const Key('key-C#4')));
    await tester.pump();
    expect(tapped, 'C#4');
  });

  testWidgets('read-only guide mode (null onNote) still renders keys',
      (tester) async {
    await tester.pumpWidget(build(targetNote: 'C4', onNote: null));
    expect(find.byKey(const Key('key-C4')), findsOneWidget);
  });
  group('pitch-class colouring', () {
    // The regression: colours were `index % 7` over the white keys, so two C's
    // in different octaves of the same window got different colours. Colour is
    // the main "which key is this" cue the guide teaches with, so it must be a
    // function of the pitch class only.
    test('the same pitch class is the same colour in every octave', () {
      for (var octave = 2; octave <= 6; octave++) {
        expect(
          IllustratedKeyboard.colorForNote('C$octave'),
          IllustratedKeyboard.colorForNote('C4'),
          reason: 'C$octave',
        );
        expect(
          IllustratedKeyboard.colorForNote('F#4'),
          IllustratedKeyboard.colorForNote('F#${octave + 1}'),
          reason: 'F#${octave + 1}',
        );
      }
    });

    test('different pitch classes do not share a colour', () {
      final seen = <Color, String>{};
      for (final note in [
        'C4',
        'C#4',
        'D4',
        'D#4',
        'E4',
        'F4',
        'F#4',
        'G4',
        'G#4',
        'A4',
        'A#4',
        'B4'
      ]) {
        final color = IllustratedKeyboard.colorForNote(note);
        expect(seen.containsKey(color), isFalse,
            reason: '$note reuses the colour of ${seen[color]}');
        seen[color] = note;
      }
    });

    test('an unparseable note falls back instead of throwing', () {
      expect(IllustratedKeyboard.colorForNote('nope'), TamaColors.ink);
    });

    testWidgets('a white key border is coloured by its own pitch class',
        (tester) async {
      await tester.pumpWidget(build(targetNote: 'A4'));
      final key = tester.widget<Container>(find.byKey(const Key('key-G4')));
      final border = key.decoration! as BoxDecoration;
      expect(border.border!.top.color, IllustratedKeyboard.colorForNote('G4'));
    });
  });

  group('wide windows', () {
    final wide = KeyboardLayout.sixtyOne.octaveAlignedWindow('C4', octaves: 4);

    test('renders a board that starts and ends on a C', () {
      expect(wide.first, 'C2');
      expect(wide.last, 'C6');
      expect(wide, hasLength(49));
    });

    testWidgets('drops note names on keys too narrow for them', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: IllustratedKeyboard(
            windowNotes: wide,
            targetNote: 'C4',
            height: 200,
          ),
        ),
      ));
      // 4 octaves on an 800 px surface is ~28 px per white key.
      expect(find.text('D4'), findsNothing);
      // The octave anchor survives, so the child can still locate themselves.
      expect(find.text('C'), findsWidgets);
      expect(find.byKey(const Key('key-D4')), findsOneWidget);
    });

    testWidgets('keeps names when keys are wide enough', (tester) async {
      await tester.pumpWidget(build(targetNote: 'C4', width: 900));
      expect(find.text('D4'), findsOneWidget);
      expect(find.text('F#4'), findsOneWidget);
    });

    testWidgets('never overflows a phone-width board', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: IllustratedKeyboard(
              windowNotes: wide,
              targetNote: 'C4',
              height: 180,
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('black key geometry', () {
    testWidgets('a black key straddles the seam of its two white neighbours',
        (tester) async {
      await tester.pumpWidget(build(targetNote: 'C4', width: 700));
      final white = tester.getRect(find.byKey(const Key('key-C4')));
      final next = tester.getRect(find.byKey(const Key('key-D4')));
      final black = tester.getRect(find.byKey(const Key('key-C#4')));
      // Centred on the C/D seam.
      expect(black.center.dx, closeTo(white.right, 0.6));
      expect(black.left, greaterThan(white.left));
      expect(black.right, lessThan(next.right));
    });

    testWidgets('E and B have no black key above their right edge',
        (tester) async {
      await tester.pumpWidget(build(targetNote: 'C4', width: 700));
      // E-F and B-C are the two natural half-steps; no key may be drawn there.
      final eRight = tester.getRect(find.byKey(const Key('key-E4'))).right;
      final fLeft = tester.getRect(find.byKey(const Key('key-F4'))).left;
      final seam = (eRight + fLeft) / 2;
      // No black key may sit on the E/F seam.
      for (final n in ['C#4', 'D#4', 'F#4', 'G#4', 'A#4']) {
        final r = tester.getRect(find.byKey(Key('key-$n')));
        expect((r.center.dx - seam).abs(), greaterThan(10),
            reason: '$n must not overlap the E-F seam');
      }
    });
  });
}
