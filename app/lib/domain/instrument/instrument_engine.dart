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
///
/// Scoring is pitch-only (non-punitive, PRD §5): the session advances through
/// the expected note sequence counting hits. Real-time timing feedback is the
/// instrument's concern via [InstrumentInput.evaluate]; the session never
/// penalizes late/early arrival so normal beat spacing and first-note gaps
/// don't count as misses.
class LessonSession {
  LessonSession({required List<String> expectedNotes})
      : _expected = List.of(expectedNotes),
        _position = 0,
        _hits = 0,
        _attempts = 0;

  final List<String> _expected;
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
  /// Judged on pitch/sequence only: the session moves through the expected
  /// sequence and counts hits, while live timing correctness is the
  /// instrument's concern ([InstrumentInput.evaluate] checks arrival against
  /// the target window). Gap-based timing here would punish normal beat
  /// spacing and penalize the first note (non-punitive, PRD §5).
  ///
  /// Position advances past misses too: the session moves on to the next
  /// expected note regardless of outcome.
  void submit(NoteEvent event) {
    if (complete) return;
    final expected = _expected[_position];
    final correct = event.note == expected;
    _attempts++;
    if (correct) _hits++;
    _position++;
  }

  /// Whether the session result satisfies the level's success threshold.
  bool passes(SuccessThreshold threshold) {
    return accuracy >= threshold.minAccuracy && hits >= threshold.minNotesHit;
  }
}
