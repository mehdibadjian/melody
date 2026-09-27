import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/instrument/instrument_engine.dart';
import 'package:melody_app/domain/instrument/note_event.dart';

/// Orchestrates one level run: drives note events through the instrument
/// engine, applies results to player progress, and emits analytics events.
/// Data-driven from a [Level] — no per-level hardcoded logic (PRD §4).
class LevelSessionFlow {
  LevelSessionFlow({
    required this.level,
    required InstrumentInput instrument,
    required this.progress,
    this.onAnalyticsEvent,
    DateTime Function()? now,
  })  : _instrument = instrument,
        _now = now ?? (() => DateTime.now().toUtc()),
        _session = instrument.startSession(level.requiredNotes) {
    _instrument.setTarget(level.requiredNotes.first);
  }

  final Level level;
  final PlayerProgress progress;
  final void Function(AnalyticsEvent event)? onAnalyticsEvent;
  final InstrumentInput _instrument;
  final LessonSession _session;
  final DateTime Function() _now;
  late final DateTime _startedAt = _now();
  bool _finished = false;

  bool get isComplete => _finished;

  /// The note the child is being asked for right now, or null once the run has
  /// ended. Read from the session rather than indexed by tap count — see
  /// [LessonSession.nextExpectedNote].
  String? get targetNote => _session.nextExpectedNote;

  /// Notes of the song landed so far, for a "3 of 12" progress readout.
  int get notesCleared => _session.position;

  /// Total taps made, including ones that held the child on the same note.
  int get taps => _session.totalAttempts;

  /// Submits a note event. Returns true when the note was hit.
  /// Ignored after the level run has completed.
  bool submit(NoteEvent event) {
    if (_finished) return false;
    // Ask the session for the expectation *before* submitting. A miss now holds
    // the position, so indexing `requiredNotes` by tap count would judge (and
    // record mastery for) a note the child was never asked to play.
    final expected = _session.nextExpectedNote;
    if (expected == null) return false;
    final correct = event.note == expected;
    progress.recordNoteMastery(expected, hit: correct);
    _session.submit(event);
    if (_session.complete) {
      _finish();
      return correct;
    }
    _instrument.setTarget(_session.nextExpectedNote!);
    return correct;
  }

  /// Terminal state of the level run.
  LevelRunResult? get result => _result;
  LevelRunResult? _result;

  void _finish() {
    if (_finished) return;
    _finished = true;
    final passed = _session.passes(level.successThreshold);
    final accuracy = _session.accuracy;
    final durationSeconds = _now().difference(_startedAt).inSeconds;
    // Any completed run counts as practice (non-punitive — streak never lost
    // for a failed level).
    progress.recordPracticeDay(_now());
    onAnalyticsEvent?.call(
      AnalyticsEvent.practiceSession(
        childProfileId: progress.profileId,
        levelId: level.id,
        practicedSeconds: durationSeconds,
        accuracy: accuracy,
        notesHit: _session.hits,
        notesAttempted: _session.totalAttempts,
      ),
    );
    int stars = 0;
    int noteCurrency = 0;
    if (passed) {
      progress.applyLevelCompletion(
        levelId: level.id,
        payout: level.rewardPayout,
        accuracy: accuracy,
      );
      stars = level.rewardPayout.stars;
      noteCurrency = level.rewardPayout.noteCurrency;
      onAnalyticsEvent?.call(
        AnalyticsEvent.levelCompleted(
          childProfileId: progress.profileId,
          levelId: level.id,
          isBossBattle: level.isBossBattle,
          starsAwarded: stars,
          noteCurrencyAwarded: noteCurrency,
        ),
      );
    }
    _result = LevelRunResult(
      passed: passed,
      accuracy: accuracy,
      notesLanded: _session.position,
      starsAwarded: stars,
      noteCurrencyAwarded: noteCurrency,
    );
  }
}

/// Outcome of a completed level run.
class LevelRunResult {
  const LevelRunResult({
    required this.passed,
    required this.accuracy,
    required this.notesLanded,
    required this.starsAwarded,
    required this.noteCurrencyAwarded,
  });

  final bool passed;
  final double accuracy;

  /// How many of the song's notes the child actually landed.
  ///
  /// Carried explicitly because "notes played" and "accuracy" answer different
  /// questions once a run ends by finishing the song rather than by running out
  /// of taps: `3 of 12 notes` reads to a child, `25% accuracy` does not.
  final int notesLanded;

  final int starsAwarded;
  final int noteCurrencyAwarded;
}
