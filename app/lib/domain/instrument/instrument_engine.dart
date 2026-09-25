import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/instrument/note_event.dart';

/// Instrument-agnostic input contract (PRD §3): pitch/timing events in,
/// correctness out. Keyboard is the first concrete implementation; guitar,
/// ukulele, or voice register as new implementations without a rewrite.
abstract interface class InstrumentInput {
  /// Live note stream from the input source (touch, MIDI, mic).
  Stream<NoteEvent> get noteStream;

  /// Evaluates a single incoming note event against the current expectation.
  EvaluationResult evaluate(NoteEvent event);

  /// Starts a scored session over the given expected note sequence.
  LessonSession startSession(List<String> expectedNotes);

  /// Sets the note the player is expected to play next, so adaptive UIs and
  /// future instruments (mic pitch detection, MIDI) can guide the player.
  void setTarget(String note, {int sinceMs});
}

/// Why an evaluated note missed.
enum EvaluationMissReason { pitch, timing, none }

/// Result of evaluating one note event.
class EvaluationResult {
  const EvaluationResult({
    required this.correct,
    required this.expectedNote,
    this.missReason = EvaluationMissReason.none,
  });

  final bool correct;
  final String expectedNote;
  final EvaluationMissReason missReason;
}

/// Stateful evaluator for one run of a level.
class LessonSession {
  LessonSession({
    required List<String> expectedNotes,
    required int Function() timingToleranceMs,
  })  : _expected = List.of(expectedNotes),
        _toleranceMs = timingToleranceMs,
        _position = 0,
        _hits = 0,
        _attempts = 0;

  final List<String> _expected;
  final int Function() _toleranceMs;
  int _position;
  int _hits;
  int _attempts;

  int get hits => _hits;
  int get totalAttempts => _attempts;

  /// Fraction of attempted notes that were hit. Defined as 1.0 when nothing
  /// has been attempted yet (non-punitive default per PRD §5).
  double get accuracy => _attempts == 0 ? 1.0 : _hits / _attempts;

  /// True when every expected note has been evaluated.
  bool get complete => _position >= _expected.length;

  /// Submits a note event for evaluation against the next expected note.
  ///
  /// Position advances past misses too: the session moves on to the next
  /// expected note regardless of outcome (non-punitive, PRD §5).
  void submit(NoteEvent event) {
    if (complete) return;
    final expected = _expected[_position];
    final correct = event.note == expected &&
        (event.timestampMs - _lastAcceptedTimestampMs).abs() <= _toleranceMs();
    _lastAcceptedTimestampMs = event.timestampMs;
    _attempts++;
    if (correct) _hits++;
    _position++;
  }

  int _lastAcceptedTimestampMs = 0;

  /// Whether the session result satisfies the level's success threshold.
  bool passes(SuccessThreshold threshold) {
    return accuracy >= threshold.minAccuracy && hits >= threshold.minNotesHit;
  }
}
