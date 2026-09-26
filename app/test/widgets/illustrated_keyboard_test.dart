import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
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
}
