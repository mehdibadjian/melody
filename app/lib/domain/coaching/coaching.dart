/// Directional coaching: turns "detected note vs. target note" into
/// child-friendly guidance — match, or which way to move on the keyboard.
///
/// This is the heart of the real-keyboard experience the app is built for: the
/// child plays a physical electric piano, the app listens through the mic, and
/// when the wrong key is pressed it says *how* to fix it ("that's G4 — go lower
/// to C4"). Pure Dart and non-punitive (PRD §3): a wrong or missing note never
/// fails the child, it just guides.
library;

import 'package:melody_app/domain/piano/piano_layout.dart';

/// Which way the child must move to reach the target.
enum PitchDirection {
  /// Detected note equals the target.
  match,

  /// Detected note is above the target: move down/left.
  tooHigh,

  /// Detected note is below the target: move up/right.
  tooLow,

  /// Nothing usable was detected yet (silence, noise, or first note).
  unknown,
}

/// One coaching verdict for a detected note against the current target.
class CoachingFeedback {
  const CoachingFeedback({
    required this.detectedNote,
    required this.targetNote,
    required this.direction,
    required this.semitonesFromTarget,
    required this.message,
    this.arrow,
  });

  /// The note the app thinks the child played (null when nothing was detected).
  final String? detectedNote;

  /// The note the child is supposed to play next.
  final String targetNote;

  final PitchDirection direction;

  /// Signed semitone distance from target (positive = detected is too high).
  /// Null when there was no usable detection.
  final int? semitonesFromTarget;

  /// Child-friendly spoken/display text.
  final String message;

  /// Optional directional glyph for the UI (▲/▼). Null on match/unknown.
  final String? arrow;

  bool get isCorrect => direction == PitchDirection.match;
}

/// Produces [CoachingFeedback] for [detected] against [target].
///
/// [detected] may be null (silence) or an unparseable label; both degrade to a
/// gentle [PitchDirection.unknown] prompt rather than an error, so a noisy mic
/// frame never punishes the child.
CoachingFeedback coach({required String? detected, required String target}) {
  if (detected == null || detected.isEmpty) {
    return CoachingFeedback(
      detectedNote: null,
      targetNote: target,
      direction: PitchDirection.unknown,
      semitonesFromTarget: null,
      message: 'Play $target',
    );
  }

  final detectedMidi = midiFromNote(detected);
  final targetMidi = midiFromNote(target);
  if (detectedMidi == null || targetMidi == null) {
    return CoachingFeedback(
      detectedNote: detected,
      targetNote: target,
      direction: PitchDirection.unknown,
      semitonesFromTarget: null,
      message: 'Play $target',
    );
  }

  final delta = detectedMidi - targetMidi; // >0 means detected is too high.
  if (delta == 0) {
    return CoachingFeedback(
      detectedNote: detected,
      targetNote: target,
      direction: PitchDirection.match,
      semitonesFromTarget: 0,
      message: 'Perfect! That\'s $target',
    );
  }

  final tooHigh = delta > 0;
  final steps = delta.abs();
  final hint = _distanceHint(steps);
  final way = tooHigh ? 'lower' : 'higher';
  return CoachingFeedback(
    detectedNote: detected,
    targetNote: target,
    direction: tooHigh ? PitchDirection.tooHigh : PitchDirection.tooLow,
    semitonesFromTarget: delta,
    arrow: tooHigh ? '▼' : '▲',
    message: 'That\'s $detected — too ${tooHigh ? 'high' : 'low'}. '
        'Move $hint $way to $target',
  );
}

/// Turns a semitone distance into words a 6-year-old can act on.
String _distanceHint(int steps) {
  if (steps <= 2) return 'just a little';
  if (steps <= 6) return 'a few keys';
  if (steps <= 11) return 'quite a way';
  return 'a long way';
}
