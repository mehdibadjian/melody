# Epic 2 · Story 8 — PCM Decode + Live Analysis Pipeline

**Status:** done
**Commit:** `d93964a` — `feat(acoustic): PCM decode + live-analysis pipeline (pure Dart)`
**PRD ref:** §9.2 (acoustic input)
**Story key:** `epic-2/pcm-decode-live-pipeline`

## User story

As the app, I need to turn a raw stream of microphone bytes into detected
notes: decode 16-bit PCM to samples, slice them into frames, run pitch
detection on each frame, and debounce the result into clean note events — all
without touching the device so it can be tested in CI.

## Acceptance criteria

- [x] `PcmDecoder` converts 16-bit little-endian PCM byte chunks to float
      samples in [-1, 1], carrying an odd trailing byte across chunk boundaries.
- [x] `MicAnalyzer` buffers decoded samples and drains fixed frames
      (frameSize 2048, hopSize 1024) through `PitchDetector.detect` →
      `noteFromFrequency` → `AcousticInstrument.onDetectedNote`.
- [x] Stable (debounced) notes are forwarded to an `onStableNote` callback;
      optional `onFrame` exposes raw per-frame detection.
- [x] `feed(Uint8List)` is the only input; `reset()` and `dispose()` clean up;
      `bufferedSamples` reports backlog.
- [x] Pure Dart — no plugin, fully unit-testable.

## Technical notes

- `lib/domain/acoustic/pcm_decoder.dart` — `PcmDecoder { Uint8List? _carry;
  List<double> push(chunk); reset() }`; divides int16 by 32768.
- `lib/domain/acoustic/mic_analyzer.dart` — `MicAnalyzer({detector, acoustic,
  onStableNote, sampleRate=22050, frameSize=2048, hopSize=1024, onFrame})`;
  `_drain()` slices frames and subscribes to the debouncer's `NoteEvent`
  stream (`StreamSubscription<NoteEvent>`).
- `app/pubspec.yaml` adds `record: ^6.1.2` (resolves 6.2.1) — pinned to match
  Flutter 3.24.3 / Dart 3.5.3; the plugin itself is wired in story 9.

## Tests

`test/domain/acoustic/pcm_decoder_test.dart` (8) — value mapping, odd-byte
carry across chunks, reset.
`test/domain/acoustic/mic_analyzer_test.dart` (6) — frame slicing, detection →
debounce → `onStableNote`, dispose.

## Definition of Done

A synthetic PCM byte stream fed to `MicAnalyzer` produces the expected stable
notes in CI, with no device dependency.
