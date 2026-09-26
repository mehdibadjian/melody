import 'dart:async';
import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/acoustic_instrument.dart';
import 'package:melody_app/domain/acoustic/pcm_decoder.dart';
import 'package:melody_app/domain/acoustic/pitch_detector.dart';
import 'package:melody_app/domain/instrument/note_event.dart';

/// The live-analysis pipeline that turns raw microphone PCM into stable,
/// debounced note events — the bridge between the platform capture layer and
/// the pure-Dart coaching stack.
///
///   mic bytes ─▶ [PcmDecoder] ─▶ ring buffer ─▶ frame ─▶ [PitchDetector]
///             ─▶ [AcousticInstrument] (note-stability debounce) ─▶ onStableNote
///
/// Everything here is pure Dart and unit-testable with synthetic PCM; only the
/// thin capture adapter that supplies the bytes is platform code. [frameSize]
/// (~93 ms at 22 kHz) is the analysis window; [hopSize] advances it so frames
/// can overlap for smoother tracking.
class MicAnalyzer {
  MicAnalyzer({
    required PitchDetector detector,
    required AcousticInstrument acoustic,
    required this.onStableNote,
    this.sampleRate = 22050,
    this.frameSize = 2048,
    this.hopSize = 1024,
    this.onFrame,
  })  : _detector = detector,
        _acoustic = acoustic {
    // Forward the debouncer's confirmed presses to the caller.
    _sub = _acoustic.noteStream.listen((e) => onStableNote(e.note));
  }

  final int sampleRate;
  final int frameSize;
  final int hopSize;

  /// Called with each confirmed (stable) note the debouncer accepts.
  final void Function(String note) onStableNote;

  /// Optional per-frame hook (used by tests / latency instrumentation).
  final void Function()? onFrame;

  final PitchDetector _detector;
  final AcousticInstrument _acoustic;
  final PcmDecoder _decoder = PcmDecoder();

  /// Growable sample buffer; the head is dropped by [hopSize] after each frame.
  final List<double> _buffer = [];

  late final StreamSubscription<NoteEvent> _sub;

  /// Samples currently held in the analysis buffer (not yet consumed).
  int get bufferedSamples => _buffer.length;

  /// Feeds one raw PCM chunk from the capture plugin and processes every
  /// complete frame it yields.
  void feed(Uint8List pcmChunk) {
    _buffer.addAll(_decoder.push(pcmChunk));
    _drain();
  }

  void _drain() {
    while (_buffer.length >= frameSize) {
      final frame = _buffer.sublist(0, frameSize);
      final estimate = _detector.detect(frame);
      final note = estimate == null
          ? null
          : noteFromFrequency(estimate.frequencyHz)?.note;
      _acoustic.onDetectedNote(note);
      onFrame?.call();
      _buffer.removeRange(0, hopSize > frameSize ? frameSize : hopSize);
    }
  }

  /// Clears buffered audio (e.g. between songs or after a pause) without
  /// tearing down the subscription.
  void reset() {
    _buffer.clear();
    _decoder.reset();
    _acoustic.onDetectedNote(null);
  }

  Future<void> dispose() async {
    await _sub.cancel();
  }
}
