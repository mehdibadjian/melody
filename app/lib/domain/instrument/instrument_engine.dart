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
/// Scoring is pitch-only (non-punitive, PRD §3): the session advances through
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

  /// How many notes of the song have been landed (not taps made).
  int get position => _position;

  /// The note the player must land next, or null once the song is complete.
  ///
  /// The session owns this so a caller cannot derive it from [totalAttempts]:
  /// taps and progress are different numbers the moment a miss holds the
  /// player on the same note, and an index built from taps points at a slot the
  /// child never reached.
  String? get nextExpectedNote => complete ? null : _expected[_position];

  /// Fraction of attempted notes that were hit. Defined as 1.0 when nothing
  /// has been attempted yet (non-punitive default per PRD §3).
  double get accuracy => _attempts == 0 ? 1.0 : _hits / _attempts;

  /// True when every expected note has been evaluated.
  bool get complete => _position >= _expected.length;

  /// Submits a note event for evaluation against the next expected note.
  ///
  /// Judged on pitch only: the session never penalizes late/early arrival, so
  /// normal beat spacing and first-note gaps don't count as misses (PRD §3).
  ///
  /// **A miss does not advance.** The session holds on the current note until
  /// the child lands it, so a fumble costs one tap rather than the rest of the
  /// song. This is what `SongCoach` has always done on the acoustic path
  /// ("wrong: ... stays on the same note"); the tap path used to step past a
  /// miss instead, which meant one early slip shifted every later note against
  /// a position the child had already slid away from and scored a correctly
  /// played song as 0%. Two modes, one mistake, opposite verdicts.
  ///
  /// Because attempts still count the misses, [accuracy] stays exactly what it
  /// always claimed to be — the fraction of notes played that were right — and
  /// needs no new formula.
  void submit(NoteEvent event) {
    if (complete) return;
    final expected = _expected[_position];
    final correct = event.note == expected;
    _attempts++;
    if (correct) {
      _hits++;
      _position++;
    }
  }

  /// Whether the session result satisfies the level's success threshold.
  bool passes(SuccessThreshold threshold) {
    return accuracy >= threshold.minAccuracy && hits >= threshold.minNotesHit;
  }
}
