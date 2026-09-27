import 'package:flutter/material.dart';

class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({
    super.key,
    required this.onNote,
    required this.targetNote,
    required this.height,
  });

  final void Function(String note) onNote;
  final String targetNote;
  final double height;

  static const _whiteKeys = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  static const _whiteKeyColors = [
    Color(0xFFEF5350),
    Color(0xFFFFCA28),
    Color(0xFF66BB6A),
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
    Color(0xFF26C6DA),
  ];

  /// The notes this board renders, left to right, at [screenWidth].
  ///
  /// The single definition of what the tap path can play. [build] draws from it
  /// and `piano_keyboard_winnability_test.dart` reasons about content from it,
  /// so the two cannot drift apart — a guard that measures a board the widget no
  /// longer renders is worse than no guard, because it looks like coverage.
  ///
  /// Note how small this is next to the acoustic path's 61 keys: white keys
  /// only, and one octave below 900 dp. Songs that need a sharp or a note above
  /// B4 are not playable here even though they are valid content.
  static List<String> noteNamesFor(double screenWidth) {
    final octaves = screenWidth > 900 ? const [4, 5] : const [4];
    return [
      for (final o in octaves)
        for (final k in _whiteKeys) '$k$o'
    ];
  }

  /// The notes reachable by tapping at [screenWidth].
  static Set<String> playableNotes({required double screenWidth}) =>
      noteNamesFor(screenWidth).toSet();

  @override
  Widget build(BuildContext context) {
    final notes = noteNamesFor(MediaQuery.of(context).size.width);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < notes.length; i++)
            Expanded(
              child: Material(
                color: _whiteKeyColors[i % _whiteKeyColors.length],
                child: InkWell(
                  onTap: () => onNote(notes[i]),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: notes[i] == targetNote
                            ? Colors.white
                            : Colors.transparent,
                        width: 4,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        notes[i],
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
