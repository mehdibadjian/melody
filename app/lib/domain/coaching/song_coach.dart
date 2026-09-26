/// Song-level coaching state machine for the acoustic (real-keyboard) mode.
///
/// This is what makes the app a teacher, not a tap-the-screen game: the child
/// plays a physical electric piano, the mic feeds detected notes here, and the
/// coach holds them on the current note until they play it right — telling them
/// *which way to move* when they don't (PRD §3, non-punitive). A wrong note
/// never advances the song and never fails the child; it just guides.
///
/// Pure Dart and fully unit-testable. The live-mic capture layer calls
/// [onDetectedNote] with each stable detected note; a [SongCoach] is typically
/// owned by a Riverpod notifier so the UI rebuilds on every [state] change.
library;

import 'package:melody_app/domain/coaching/coaching.dart';

/// Immutable snapshot of coaching progress, emitted on every detected note.
class SongCoachState {
  const SongCoachState({
    required this.notes,
    required this.index,
    required this.correctHits,
    required this.wrongAttempts,
    this.feedback,
    this.detectedNote,
  });

  /// The full expected note sequence for the song.
  final List<String> notes;

  /// Index of the note the child is on. Equals [notes].length when complete.
  final int index;

  /// Correct notes landed so far.
  final int correctHits;

  /// Wrong (but detected) attempts so far — coaching opportunities, not fails.
  final int wrongAttempts;

  /// The most recent coaching verdict (null before the first detection).
  final CoachingFeedback? feedback;

  /// The note the mic last heard (null on silence) — drives the UI marker.
  final String? detectedNote;

  /// True when every note in the song has been played correctly.
  bool get isComplete => index >= notes.length;

  /// The note to play next, or null once the song is complete.
  String? get targetNote => isComplete ? null : notes[index];

  /// Total detections that were judged (correct + wrong). Null/silence frames
  /// are not counted.
  int get attempts => correctHits + wrongAttempts;

  /// Fraction of judged detections that were correct. 1.0 when nothing has
  /// been attempted (non-punitive default, mirrors LessonSession).
  double get accuracy => attempts == 0 ? 1.0 : correctHits / attempts;
}

/// Drives one run through a song's note sequence from acoustic detections.
class SongCoach {
  SongCoach({required List<String> notes, this.onComplete})
      : _state = SongCoachState(
            notes: List.of(notes), index: 0, correctHits: 0, wrongAttempts: 0);

  /// Called once when the song is completed (fires exactly once).
  final void Function()? onComplete;

  SongCoachState _state;

  /// The current snapshot.
  SongCoachState get state => _state;

  bool _completed = false;

  /// Feeds one detected note (or null for silence) from the mic layer.
  ///
  /// - null/empty: ignored — silence never advances or penalises.
  /// - matches the target: counts a hit and advances to the next note.
  /// - wrong: records [CoachingFeedback] guidance and stays on the same note.
  void onDetectedNote(String? note) {
    if (_state.isComplete) return;
    if (note == null || note.isEmpty) {
      _state = SongCoachState(
        notes: _state.notes,
        index: _state.index,
        correctHits: _state.correctHits,
        wrongAttempts: _state.wrongAttempts,
        feedback: _state.feedback,
        detectedNote: null,
      );
      return;
    }

    final target = _state.targetNote!;
    final feedback = coach(detected: note, target: target);
    final advanced = feedback.isCorrect;
    final nextIndex = advanced ? _state.index + 1 : _state.index;

    _state = SongCoachState(
      notes: _state.notes,
      index: nextIndex,
      correctHits: _state.correctHits + (advanced ? 1 : 0),
      wrongAttempts: _state.wrongAttempts + (advanced ? 0 : 1),
      feedback: feedback,
      detectedNote: note,
    );

    if (_state.isComplete && !_completed) {
      _completed = true;
      onComplete?.call();
    }
  }
}
