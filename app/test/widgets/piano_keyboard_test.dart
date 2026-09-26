import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/widgets/piano_keyboard.dart';

void main() {
  Widget buildKeyboard({
    required void Function(String note) onNote,
    String targetNote = 'C4',
    double width = 400,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
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

  testWidgets('renders correct number of keys for phone width', (tester) async {
    await tester.pumpWidget(buildKeyboard(onNote: (_) {}));

    expect(find.text('C4'), findsOneWidget);
    expect(find.text('D4'), findsOneWidget);
    expect(find.text('E4'), findsOneWidget);
    expect(find.text('F4'), findsOneWidget);
    expect(find.text('G4'), findsOneWidget);
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('B4'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(7));
  });

  testWidgets('calls onNote callback when key is tapped', (tester) async {
    String? tapped;
    await tester.pumpWidget(buildKeyboard(onNote: (note) => tapped = note));

    await tester.tap(find.text('E4'));
    await tester.pump();

    expect(tapped, 'E4');
  });

  testWidgets('renders two octaves for tablet width', (tester) async {
    await tester.pumpWidget(buildKeyboard(onNote: (_) {}, width: 1000));

    expect(find.byType(InkWell), findsNWidgets(14));
    expect(find.text('C5'), findsOneWidget);
    expect(find.text('B5'), findsOneWidget);
  });

  testWidgets('highlights the target note visually', (tester) async {
    await tester.pumpWidget(buildKeyboard(onNote: (_) {}, targetNote: 'E4'));

    final targetContainer = tester.widget<Container>(
      find
          .ancestor(of: find.text('E4'), matching: find.byType(Container))
          .first,
    );
    final decoration = targetContainer.decoration as BoxDecoration;
    final border = decoration.border as Border;

    expect(border.top.color, Colors.white);
    expect(border.top.width, 4);
  });
}
