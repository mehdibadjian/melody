import 'package:flutter/material.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';

/// Illustrates a slice of a real keyboard so the child can see *which physical
/// key* to press while they play their actual electric piano and the app
/// listens through the mic (PRD §3 connected-instrument guidance).
///
/// It renders [windowNotes] — a consecutive run of notes from a
/// [KeyboardLayout.visibleWindow] — with proper white/black key geometry. The
/// target note gets a glowing highlight ("press this one"); when the mic hears
/// a different note, [detectedNote] is marked and an [arrow] shows which way to
/// move. In acoustic mode [onNote] is null (the keys are a picture, not an
/// input); on-screen practice still passes a callback so keys are tappable.
class IllustratedKeyboard extends StatelessWidget {
  const IllustratedKeyboard({
    super.key,
    required this.windowNotes,
    required this.targetNote,
    required this.height,
    this.detectedNote,
    this.arrow,
    this.onNote,
  });

  /// Consecutive note names to draw, e.g. `['C4','C#4','D4', ...]`.
  final List<String> windowNotes;

  /// The note the child should play next (glowing highlight).
  final String targetNote;

  /// The note the mic thinks the child just played (null = nothing heard).
  final String? detectedNote;

  /// Directional cue from coaching, e.g. `▲`/`▼` (null on match/unknown).
  final String? arrow;

  /// Tap handler; null makes this a read-only illustration.
  final void Function(String note)? onNote;

  final double height;

  static const _whiteKeyColors = [
    Color(0xFFEF5350),
    Color(0xFFFFCA28),
    Color(0xFF66BB6A),
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
    Color(0xFF26C6DA),
  ];

  @override
  Widget build(BuildContext context) {
    final whiteKeys =
        windowNotes.where((n) => !isBlackKeyMidi(midiFromNote(n)!)).toList();
    final whiteCount = whiteKeys.length;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final whiteWidth = whiteCount == 0
              ? constraints.maxWidth
              : constraints.maxWidth / whiteCount;
          final blackWidth = whiteWidth * 0.62;
          final blackHeight = height * 0.62;

          return Stack(
            key: const Key('keys-layer'),
            children: [
              // White keys.
              Row(
                children: [
                  for (var i = 0; i < whiteKeys.length; i++)
                    Expanded(child: _whiteKey(whiteKeys[i], i)),
                ],
              ),
              // Black keys, positioned over the seam after their white neighbour.
              for (final note in windowNotes)
                if (isBlackKeyMidi(midiFromNote(note)!))
                  Positioned(
                    left: _blackKeyLeft(note, whiteKeys, whiteWidth, blackWidth,
                        constraints.maxWidth),
                    top: 0,
                    child: _blackKey(note, blackWidth, blackHeight),
                  ),
              // Target glow overlay (ignores taps so keys stay pressable).
              if (windowNotes.contains(targetNote))
                _overlayMarker(
                  key: const Key('target-glow'),
                  left: _keyLeft(targetNote, whiteKeys, whiteWidth, blackWidth,
                      constraints.maxWidth),
                  isBlack: isBlackKeyMidi(midiFromNote(targetNote)!),
                  color: const Color(0xFF00E676),
                  width: isBlackKeyMidi(midiFromNote(targetNote)!)
                      ? blackWidth
                      : whiteWidth,
                  child: arrow == null
                      ? null
                      : Text(
                          arrow!,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white),
                        ),
                ),
              // Detected-note marker (what the mic heard).
              if (detectedNote != null && windowNotes.contains(detectedNote!))
                _overlayMarker(
                  key: const Key('detected-marker'),
                  left: _keyLeft(detectedNote!, whiteKeys, whiteWidth,
                      blackWidth, constraints.maxWidth),
                  isBlack: isBlackKeyMidi(midiFromNote(detectedNote!)!),
                  color: Colors.deepOrange,
                  width: isBlackKeyMidi(midiFromNote(detectedNote!)!)
                      ? blackWidth
                      : whiteWidth,
                  child: null,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _whiteKey(String note, int index) {
    final isTarget = note == targetNote;
    final base = _whiteKeyColors[index % _whiteKeyColors.length];
    return Container(
      key: Key('key-$note'),
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: isTarget ? const Color(0xFF00E676) : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: isTarget ? Colors.green : base, width: 3),
      ),
      child: _tapTarget(
        note,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              note,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isTarget ? Colors.white : Colors.black54,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blackKey(String note, double width, double keyHeight) {
    final isTarget = note == targetNote;
    return Container(
      key: Key('key-$note'),
      width: width,
      height: keyHeight,
      decoration: BoxDecoration(
        color: isTarget ? const Color(0xFF00E676) : const Color(0xFF212121),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
        border:
            Border.all(color: isTarget ? Colors.green : Colors.black, width: 2),
      ),
      child: _tapTarget(
        note,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              note,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tapTarget(String note, {required Widget child}) {
    final cb = onNote;
    if (cb == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: () => cb(note), child: child),
    );
  }

  Widget _overlayMarker({
    required Key key,
    required double left,
    required bool isBlack,
    required Color color,
    required double width,
    required Widget? child,
  }) {
    return Positioned(
      left: left,
      top: 0,
      bottom: isBlack ? height * 0.30 : 0,
      width: width,
      child: IgnorePointer(
        child: Container(
          key: key,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 4),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.7), blurRadius: 12),
            ],
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }

  /// Horizontal pixel offset of [note]'s left edge within the window.
  double _keyLeft(
    String note,
    List<String> whiteKeys,
    double whiteWidth,
    double blackWidth,
    double totalWidth,
  ) {
    if (!isBlackKeyMidi(midiFromNote(note)!)) {
      final i = whiteKeys.indexOf(note);
      return i * whiteWidth;
    }
    return _blackKeyLeft(note, whiteKeys, whiteWidth, blackWidth, totalWidth);
  }

  /// Black keys sit centred on the seam after the white key one semitone below.
  double _blackKeyLeft(
    String note,
    List<String> whiteKeys,
    double whiteWidth,
    double blackWidth,
    double totalWidth,
  ) {
    final midi = midiFromNote(note)!;
    final precedingWhiteIndex =
        whiteKeys.indexWhere((w) => midiFromNote(w)! == midi - 1);
    // Clamp the centre so a window starting/ending mid-semitone still renders.
    final centre =
        precedingWhiteIndex >= 0 ? (precedingWhiteIndex + 1) * whiteWidth : 0.0;
    final left = centre - blackWidth / 2;
    return left.clamp(0.0, (totalWidth - blackWidth).clamp(0.0, totalWidth));
  }
}
