import 'dart:async';
import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/acoustic_instrument.dart';
import 'package:melody_app/domain/acoustic/mic_analyzer.dart';
import 'package:melody_app/domain/acoustic/mic_capture.dart';
import 'package:melody_app/domain/acoustic/pitch_detector.dart';
import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:melody_app/domain/coaching/coaching.dart';
import 'package:melody_app/domain/coaching/song_coach.dart';
import 'package:melody_app/domain/content/content_models.dart';

/// Immutable view-model snapshot for the acoustic practice screen. The UI
/// rebuilds from this on every detected note; it never reaches into the
/// controller's internals.
class AcousticSnapshot {
  const AcousticSnapshot({
    required this.coach,
    required this.listening,
    required this.permissionDenied,
  });

  factory AcousticSnapshot.initial(List<String> notes) => AcousticSnapshot(
        coach: _initialCoach(notes),
        listening: false,
        permissionDenied: false,
      );

  static SongCoachState _initialCoach(List<String> notes) =>
      SongCoach(notes: notes).state;

  /// The coaching state machine (target, hits, feedback, detected note).
  final SongCoachState coach;

  /// True while the microphone is actively capturing.
  final bool listening;

  /// True when capture was refused (permission denied) — the UI shows a
  /// gentle "enable the mic" prompt rather than an error.
  final bool permissionDenied;

  CoachingFeedback? get feedback => coach.feedback;
  String? get detectedNote => coach.detectedNote;
  String? get targetNote => coach.targetNote;
  bool get complete => coach.isComplete;

  AcousticSnapshot copyWith({
    SongCoachState? coach,
    bool? listening,
    bool? permissionDenied,
  }) =>
      AcousticSnapshot(
        coach: coach ?? this.coach,
        listening: listening ?? this.listening,
        permissionDenied: permissionDenied ?? this.permissionDenied,
      );
}

/// Orchestrates one acoustic practice run end-to-end:
///
///   [MicCapture] ─▶ [MicAnalyzer] (decode+pitch+debounce) ─▶ [SongCoach]
///   (holds the child on a wrong note, coaches direction) ─▶ snapshot ─▶ UI
///
/// On completion it emits a practice-session analytics event and calls
/// [onComplete] once so the screen can commit progress and rewards. Everything
/// except [MicCapture] (injected, faked in tests) is pure Dart, so the whole
/// listen-and-coach loop is CI-tested without a microphone.
class AcousticPracticeController {
  AcousticPracticeController({
    required List<String> notes,
    required MicCapture mic,
    required this.level,
    this.childProfileId = 'child-local',
    this.sampleRate = 22050,
    this.onComplete,
    DateTime Function()? now,
  })  : _mic = mic,
        _now = now ?? (() => DateTime.now().toUtc()),
        _coach = SongCoach(notes: notes),
        _snapshot = AcousticSnapshot.initial(notes) {
    // Re-publish the snapshot whenever the coach advances; on completion,
    // emit analytics + reward exactly once.
    _coach.onStateChanged = _publish;
    _coach.onComplete = () => _onSongComplete(_coach.state);
  }

  final MicCapture _mic;
  final DateTime Function() _now;
  final SongCoach _coach;
  AcousticSnapshot _snapshot;
  DateTime? _startedAt;

  /// Set by the screen/provider: receives analytics events (the store sink).
  void Function(AnalyticsEvent event)? onAnalyticsEvent;

  /// Called once when the song is completed (commit progress + rewards).
  void Function(SongCoachState state)? onComplete;

  /// The current snapshot.
  AcousticSnapshot get snapshot => _snapshot;

  bool get listening => _snapshot.listening;

  final _listeners = <void Function(AcousticSnapshot)>[];

  void addListener(void Function(AcousticSnapshot) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(AcousticSnapshot) listener) {
    _listeners.remove(listener);
  }

  MicAnalyzer? _analyzer;
  StreamSubscription<Uint8List>? _pcmSub;

  /// Requests the mic permission and, if granted, starts capturing and
  /// analysing. Safe to call repeatedly (e.g. after the user enables the
  /// permission in settings): it re-checks each time.
  Future<void> start() async {
    if (listening) return;
    final granted = await _mic.hasPermission();
    if (!granted) {
      _snapshot = _snapshot.copyWith(listening: false, permissionDenied: true);
      _notify();
      return;
    }

    final acoustic = AcousticInstrument();
    _analyzer = MicAnalyzer(
      detector: PitchDetector(sampleRate: sampleRate),
      acoustic: acoustic,
      sampleRate: sampleRate,
      onStableNote: _coach.onDetectedNote,
    );
    _startedAt = _now();

    final stream = await _mic.start();
    _pcmSub = stream.listen((chunk) => _analyzer?.feed(chunk));
    _snapshot = _snapshot.copyWith(listening: true, permissionDenied: false);
    _notify();
  }

  /// Stops capture (keeps the current snapshot so the UI can show results).
  Future<void> stopListening() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _mic.stop();
    _snapshot = _snapshot.copyWith(listening: false);
    _notify();
  }

  void _onSongComplete(SongCoachState state) {
    final practicedSeconds =
        _startedAt == null ? 0 : _now().difference(_startedAt!).inSeconds;
    onAnalyticsEvent?.call(
      AnalyticsEvent.practiceSession(
        childProfileId: childProfileId,
        levelId: level.id,
        practicedSeconds: practicedSeconds,
        accuracy: state.accuracy,
        notesHit: state.correctHits,
        notesAttempted: state.attempts,
      ),
    );
    onComplete?.call(state);
  }

  void _publish() {
    _snapshot = _snapshot.copyWith(coach: _coach.state);
    _notify();
  }

  void _notify() {
    for (final l in _listeners) {
      l(_snapshot);
    }
  }

  /// Releases the mic, analyser, and subscriptions. Idempotent.
  Future<void> dispose() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _analyzer?.dispose();
    _analyzer = null;
    await _mic.stop();
    await _mic.dispose();
    _snapshot = _snapshot.copyWith(listening: false);
    _listeners.clear();
  }

  /// The level being practiced (for analytics + reward payout).
  final Level level;

  /// Profile id stamped on analytics events (not PII, PRD §4.2).
  final String childProfileId;

  /// Capture sample rate; must match the [MicCapture]/[PitchDetector] rate.
  final int sampleRate;
}
