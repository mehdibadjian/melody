/// Pure-Dart piano geometry: scientific-pitch note names ↔ MIDI numbers, and
/// the physical key layouts the app can illustrate (PRD §3 "connected
/// instrument").
///
/// The acoustic and coaching layers reason in MIDI semitones (direction and
/// distance), while content and the UI speak in note names (`C4`). This file is
/// the single source of truth for both directions so they can never drift.
library;

const _sharps = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B'
];

/// Semitone offsets of natural (white) letters within an octave.
const _letterSemitones = {
  'C': 0,
  'D': 2,
  'E': 4,
  'F': 5,
  'G': 7,
  'A': 9,
  'B': 11,
};

/// MIDI numbers that are black keys (C#, D#, F#, G#, A#).
const _blackPitchClasses = {1, 3, 6, 8, 10};

/// Parses a note name in scientific pitch notation (`C4`, `F#5`, `Db3`,
/// case-insensitive) to its MIDI number, or null if it is malformed.
int? midiFromNote(String note) {
  final match = RegExp(r'^([a-gA-G])([#b]?)(-?\d+)$').firstMatch(note.trim());
  if (match == null) return null;
  final letter = match.group(1)!.toUpperCase();
  final semitone = _letterSemitones[letter];
  if (semitone == null) return null;
  final octave = int.tryParse(match.group(3)!);
  if (octave == null) return null;
  final accidental = switch (match.group(2)) {
    '#' => 1,
    'b' || 'B' => -1,
    _ => 0,
  };
  return (octave + 1) * 12 + semitone + accidental;
}

/// Renders a MIDI number as a sharp-based scientific pitch note name.
String noteFromMidi(int midi) {
  final octave = (midi ~/ 12) - 1;
  final name = _sharps[((midi % 12) + 12) % 12];
  return '$name$octave';
}

/// True when [midi] is one of the five black keys of an octave.
bool isBlackKeyMidi(int midi) =>
    _blackPitchClasses.contains(((midi % 12) + 12) % 12);

/// A physical keyboard layout: an inclusive MIDI range that mirrors a real
/// instrument so the on-screen illustration matches what the child sees.
class KeyboardLayout {
  /// Builds a layout from an inclusive MIDI range. White/black counts and the
  /// note list are derived, so they can never disagree with the range.
  KeyboardLayout(
      {required this.name, required this.lowestMidi, required this.highestMidi})
      : assert(lowestMidi <= highestMidi),
        notes = [
          for (var m = lowestMidi; m <= highestMidi; m++) noteFromMidi(m),
        ];

  /// 61-key board (C2–C7): 36 white + 25 black keys. The v1 target device.
  static final KeyboardLayout sixtyOne =
      KeyboardLayout(name: '61 keys', lowestMidi: 36, highestMidi: 96);

  /// 76-key board (E1–G7): 45 white + 31 black keys.
  static final KeyboardLayout seventySix =
      KeyboardLayout(name: '76 keys', lowestMidi: 28, highestMidi: 103);

  /// 88-key piano (A0–C8): 52 white + 36 black keys.
  static final KeyboardLayout eightyEight =
      KeyboardLayout(name: '88 keys', lowestMidi: 21, highestMidi: 108);

  final String name;
  final int lowestMidi;
  final int highestMidi;

  /// All note names from lowest to highest, inclusive.
  final List<String> notes;

  int get keyCount => notes.length;
  String get lowestNote => notes.first;
  String get highestNote => notes.last;
  int get whiteKeyCount =>
      notes.where((n) => !isBlackKeyMidi(midiFromNote(n)!)).length;
  int get blackKeyCount =>
      notes.where((n) => isBlackKeyMidi(midiFromNote(n)!)).length;

  /// True when [note] is a real, in-range key on this board.
  bool containsNote(String note) {
    final midi = midiFromNote(note);
    if (midi == null) return false;
    return midi >= lowestMidi && midi <= highestMidi;
  }

  /// A readable slice of [size] consecutive notes centred on [target], clamped
  /// to the board. A full 61-key board does not fit on a phone, so the UI
  /// shows this sliding window that follows the note the child must play. An
  /// unknown target falls back to the middle of the board.
  List<String> visibleWindow(String target, {int size = 25}) {
    final span = (size < keyCount ? size : keyCount);
    final center = midiFromNote(target) ?? ((lowestMidi + highestMidi) ~/ 2);
    final start =
        (center - span ~/ 2).clamp(lowestMidi, highestMidi - span + 1);
    return [for (var m = start; m < start + span; m++) noteFromMidi(m)];
  }

  /// A C-to-C slice of [octaves] whole octaves that contains [target].
  ///
  /// [visibleWindow] centres the target, which reads well for coaching but is
  /// wrong as a *picture of a piano*: because it cuts the board mid-chord, the
  /// window's first two white keys are an E–F or B–C pair with no black key
  /// between them. The eye (and the colour code) then places the group of "two
  /// black keys" one white key early, and it keeps drifting by one per octave —
  /// so the highlight no longer sits on the key it names. Clipped edge keys make
  /// the window read as a full board that has been cut in half.
  ///
  /// Anchoring every window to a C keeps the grouping correct at any width. The
  /// window is then nudged so it really does hold [target]: centring can leave a
  /// note in the upper half of its octave outside a narrow window, and a board
  /// whose top octave is partial (a 76-key board's G7) has no C-anchored window
  /// that reaches it, so there the top edge stops at the board rather than at a
  /// C. Showing the note the child must play outranks ending on a C.
  List<String> octaveAlignedWindow(String target, {int octaves = 2}) {
    final whole = octaves.clamp(1, 8);
    // A window may not start on a board's partial bottom octave.
    final boardLowC = lowestMidi + ((12 - lowestMidi % 12) % 12);
    final span = whole * 12;
    final center = (midiFromNote(target) ?? ((lowestMidi + highestMidi) ~/ 2))
        .clamp(boardLowC, highestMidi);
    // Highest start that still keeps the whole window on the board, on the grid.
    final lastStart = _floorToC(highestMidi - span);
    var start = _floorToC(center - span ~/ 2);
    // A note in the top half of its octave falls outside a window centred on
    // the octave below it; re-anchor on the note's own octave instead.
    if (start + span < center) start = _floorToC(center);
    if (start < boardLowC) start = boardLowC;
    if (start > lastStart && lastStart >= boardLowC) start = lastStart;
    var end = start + span;
    if (end > highestMidi) end = highestMidi;
    if (end < center) end = center;
    return [for (var m = start; m <= end; m++) noteFromMidi(m)];
  }
}

/// The highest MIDI number at or below [midi] that is a C.
int _floorToC(int midi) => midi - ((midi % 12) + 12) % 12;
