import 'dart:async';

import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/instrument/instrument_engine.dart';
import 'package:melody_app/domain/instrument/note_event.dart';

/// Chromatic notes per octave, scientific pitch notation.
const chromaticNotes = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B'
];

/// On-screen virtual keyboard — first concrete [InstrumentInput] (PRD §6).
///
/// Supports multi-touch (multiple simultaneously pressed keys) and evaluates
/// note events with a timing tolerance that scales with tempo.
class KeyboardInstrument implements InstrumentInput {
  KeyboardInstrument(
      {this.octaves = 2, int? timingToleranceMs, int tempoBpm = 90, AudioEngine? audio})
      : _fixedToleranceMs = timingToleranceMs,
        _tempoBpm = tempoBpm,
        _audio = audio {
    for (var octave = 0; octave < octaves; octave++) {
      for (final name in chromaticNotes) {
        _keys.add(KeyboardKey(note: '$name${4 + octave}'));
      }
    }
  }

  final int octaves;
  final int _tempoBpm;
  final int? _fixedToleranceMs;
  final AudioEngine? _audio;
  final List<KeyboardKey> _keys = [];
  final Set<String> _pressed = {};
  final _controller = StreamController<NoteEvent>.broadcast();
  String _currentTarget = 'C4';
  int _targetSinceMs = 0;

  List<KeyboardKey> get keys => List.unmodifiable(_keys);
  int get keyCount => _keys.length;
  Set<String> get pressedNotes => Set.unmodifiable(_pressed);

  /// Timing tolerance in ms: fixed when explicitly provided, otherwise half a
  /// beat at the current tempo (a note within an eighth of a beat window counts).
  int get timingToleranceMs =>
      _fixedToleranceMs ?? (60000 / _tempoBpm / 2).round();

  @override
  Stream<NoteEvent> get noteStream => _controller.stream;

  /// Presses a key (multi-touch safe: several keys may be down at once).
  void press(String note) {
    _pressed.add(note);
    _controller.add(NoteEvent(note: note, timestampMs: _nowMs()));
    _audio?.playNote(note);
  }

  /// Releases a pressed key.
  void release(String note) => _pressed.remove(note);

  @override
  EvaluationResult evaluate(NoteEvent event) {
    final pitchOk = event.note == _currentTarget;
    if (!pitchOk) {
      return EvaluationResult(
        correct: false,
        expectedNote: _currentTarget,
        missReason: EvaluationMissReason.pitch,
      );
    }
    final timingOk =
        (event.timestampMs - _targetSinceMs).abs() <= timingToleranceMs;
    if (!timingOk) {
      return EvaluationResult(
        correct: false,
        expectedNote: _currentTarget,
        missReason: EvaluationMissReason.timing,
      );
    }
    return EvaluationResult(correct: true, expectedNote: _currentTarget);
  }

  /// Sets the note the player is expected to play next, from a level's
  /// required sequence.
  @override
  void setTarget(String note, {int sinceMs = 0}) {
    _currentTarget = note;
    _targetSinceMs = sinceMs;
  }

  @override
  LessonSession startSession(List<String> expectedNotes) {
    return LessonSession(
      expectedNotes: expectedNotes,
      timingToleranceMs: () => timingToleranceMs,
    );
  }

  void dispose() => _controller.close();

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}

/// A single playable key on the virtual keyboard.
class KeyboardKey {
  const KeyboardKey({required this.note});

  final String note;
}
