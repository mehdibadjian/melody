import 'dart:async';

import 'package:melody_app/domain/instrument/instrument_engine.dart';
import 'package:melody_app/domain/instrument/note_event.dart';

/// Acoustic instrument input: the child plays a **real** keyboard (electric
/// piano or similar) and the app listens through the microphone.
///
/// Raw per-frame pitch detection (see [PitchDetector]) is noisy — a held note
/// flickers between detected/silent and between neighbouring pitches. This
/// layer applies *note stability* (debounce): a detected note must persist for
/// [stableFramesRequired] consecutive frames before it is accepted as a real
/// key press, and a held note emits only once until it changes.
///
/// It implements the same [InstrumentInput] contract as the on-screen
/// [KeyboardInstrument], so the existing session/evaluation/gamification stack
/// works unchanged — the child can be coached on a physical keyboard.
///
/// Audio capture (microphone plugin, permissions, sample buffers) is the
/// platform layer that calls [onDetectedNote]; this class is pure Dart and
/// fully unit-testable.
class AcousticInstrument implements InstrumentInput {
  AcousticInstrument({this.stableFramesRequired = 3});

  /// Consecutive frames a detected note must persist to count as a real press.
  final int stableFramesRequired;

  final _controller = StreamController<NoteEvent>.broadcast();
  String _currentTarget = 'C4';

  String? _candidate;
  int _candidateFrames = 0;
  String? _emitted;

  @override
  Stream<NoteEvent> get noteStream => _controller.stream;

  /// Feeds one frame's detected note (or null when nothing voiced) into the
  /// debouncer. Emits a [NoteEvent] on [noteStream] when a stable press is
  /// confirmed.
  void onDetectedNote(String? note) {
    if (note == null || note.isEmpty) {
      // Gap: reset so the same note can fire again after it returns.
      _candidate = null;
      _candidateFrames = 0;
      _emitted = null;
      return;
    }
    if (note != _candidate) {
      _candidate = note;
      _candidateFrames = 1;
      _emitted = null;
    } else {
      _candidateFrames++;
    }
    if (_candidateFrames >= stableFramesRequired && _emitted != note) {
      _emitted = note;
      _controller.add(NoteEvent(note: note, timestampMs: _nowMs()));
    }
  }

  @override
  EvaluationResult evaluate(NoteEvent event) {
    final correct = event.note == _currentTarget;
    return EvaluationResult(
      correct: correct,
      expectedNote: _currentTarget,
      missReason:
          correct ? EvaluationMissReason.none : EvaluationMissReason.pitch,
    );
  }

  @override
  LessonSession startSession(List<String> expectedNotes) {
    return LessonSession(expectedNotes: expectedNotes);
  }

  @override
  void setTarget(String note, {int sinceMs = 0}) {
    _currentTarget = note;
  }

  void dispose() => _controller.close();

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}
