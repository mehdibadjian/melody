/// A single pitch/timing event entering the instrument engine.
class NoteEvent {
  const NoteEvent({required this.note, required this.timestampMs});

  /// Pitch label in scientific pitch notation, e.g. `C4`, `F#5`.
  final String note;

  /// Monotonic timestamp of the event in milliseconds.
  final int timestampMs;
}