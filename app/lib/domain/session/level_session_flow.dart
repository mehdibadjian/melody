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
  })  : _instrument = instrument,
        _session = instrument.startSession(level.requiredNotes) {
    _instrument.setTarget(level.requiredNotes.first);
  }

  final Level level;
  final PlayerProgress progress;
  final void Function(AnalyticsEvent event)? onAnalyticsEvent;
  final InstrumentInput _instrument;
  final LessonSession _session;
  final DateTime _startedAt = DateTime.now().toUtc();
  bool _finished = false;

  bool get isComplete => _finished;

  /// Submits a note event. Returns true when the note was hit.
  /// Ignored after the level run has completed.
  bool submit(NoteEvent event) {
    if (_finished) return false;
    final expected = level.requiredNotes[_session.totalAttempts];
    final correct = event.note == expected;
    progress.recordNoteMastery(expected, hit: correct);
    _session.submit(event);
    _advanceTarget();
    if (_session.complete) {
      _finish();
      return correct;
    }
    return correct;
  }

  void _advanceTarget() {
    if (_session.complete) return;
    _instrument.setTarget(level.requiredNotes[_session.totalAttempts]);
  }

  /// Terminal state of the level run.
  LevelRunResult? get result => _result;
  LevelRunResult? _result;

  void _finish() {
    if (_finished) return;
    _finished = true;
    final passed = _session.passes(level.successThreshold);
    final accuracy = _session.accuracy;
    final durationSeconds =
        DateTime.now().toUtc().difference(_startedAt).inSeconds;
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
    required this.starsAwarded,
    required this.noteCurrencyAwarded,
  });

  final bool passed;
  final double accuracy;
  final int starsAwarded;
  final int noteCurrencyAwarded;
}