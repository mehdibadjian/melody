import 'package:flutter/material.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';

/// The tappable on-screen keyboard.
///
/// It is deliberately the *same* widget the acoustic guide draws: a slice of a
/// real [KeyboardLayout.sixtyOne] rendered by [IllustratedKeyboard], with black
/// keys and a window that follows the note the child is asked for. Previously
/// this was a separate 7-white-key row pinned to C4–B4, which meant the two
/// play modes disagreed about what a song even is — a tune reaching above B4 or
/// needing a sharp was playable on the child's real piano and literally
/// unfinishable on the screen, because the keys it asked for did not exist.
/// One renderer, one board, so that class of bug cannot come back.
///
/// The window is C-anchored (see [KeyboardLayout.octaveAlignedWindow]) so the
/// black-key pattern always matches the note names, and the number of octaves
/// shown is chosen by width: one octave keeps white keys near a 48 dp tap
/// target on a phone, which matters more for a 6-year-old's accuracy than
/// showing more of the piano at once.
class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({
    super.key,
    required this.onNote,
    required this.targetNote,
    this.height = 160,
  });

  /// Called with the note name of the key the child tapped.
  final void Function(String note) onNote;

  /// The key to light up.
  final String targetNote;

  final double height;

  /// The board this keyboard is a window onto.
  static final KeyboardLayout board = KeyboardLayout.sixtyOne;

  /// Widths above this get a second octave; below it, tap targets get too
  /// narrow to hit accurately on a phone held by a child.
  static const double twoOctaveBreakpoint = 900;

  /// Octaves shown at [screenWidth].
  static int octavesFor(double screenWidth) =>
      screenWidth > twoOctaveBreakpoint ? 2 : 1;

  /// The notes rendered at [screenWidth] while [targetNote] is the goal.
  ///
  /// Always contains [targetNote] — asserted across the whole board by
  /// `piano_keyboard_test.dart`, because a window that could drop the target
  /// would re-create the exact bug this widget replaced.
  static List<String> windowFor(String targetNote, double screenWidth) =>
      board.octaveAlignedWindow(targetNote, octaves: octavesFor(screenWidth));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => IllustratedKeyboard(
          windowNotes: windowFor(targetNote, width),
          targetNote: targetNote,
          onNote: onNote,
          height: constraints.maxHeight,
        ),
      ),
    );
  }
}
