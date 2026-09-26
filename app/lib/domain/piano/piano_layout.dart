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
}
