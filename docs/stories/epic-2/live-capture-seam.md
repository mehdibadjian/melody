# Epic 2 · Story 9 — Live Mic Capture Seam + Practice Controller

**Status:** done
**Commit:** `df8a73f` — `feat(acoustic): live capture seam + practice controller (CI-tested loop)`
**PRD ref:** §3, §7 (privacy), §9.2
**Story key:** `epic-2/live-capture-seam`

## User story

As a child, I want to tap "start", have the app ask for (and handle) microphone
permission, and then listen to my real keyboard and coach me — and as the team
we want the entire listen→detect→debounce→coach loop **tested in CI** even
though a real mic can't run there.

## Acceptance criteria

- [x] `MicCapture` is an injectable interface (`hasPermission`, `start` →
      `Stream<Uint8List>`, `stop`, `dispose`) so a fake can replace the device.
- [x] `RecordMicCapture` is the **only** device-specific code: wraps the
      `record` plugin (`startStream` with pcm16bits, 22050 Hz, mono).
- [x] `AcousticPracticeController` wires permission → capture → `MicAnalyzer`
      → `SongCoach`, publishing an `AcousticSnapshot` and emitting analytics.
- [x] Permission-denied is a first-class state (no crash, retryable).
- [x] Audio is analysed on-device for pitch only; never stored or transmitted
      (PRD §7, COPPA/GDPR-K).
- [x] `AndroidManifest.xml` declares `RECORD_AUDIO` with a COPPA comment.

## Technical notes

- `lib/domain/acoustic/mic_capture.dart` — `abstract interface class MicCapture`.
- `lib/platform/record_mic_capture.dart` — `RecordMicCapture` (device-only;
  0/12 coverage **by design**).
- `lib/domain/coaching/acoustic_practice_controller.dart` —
  `AcousticSnapshot {coach, listening, permissionDenied, …}` +
  `AcousticPracticeController({notes, mic, level, childProfileId, sampleRate,
  onComplete, onAnalyticsEvent, now})`. Wires `_coach.onStateChanged =
  _publish` and `_coach.onComplete = () => _onSongComplete(_coach.state)`.
  `start()` checks permission, builds `AcousticInstrument` + `MicAnalyzer`
  (`onStableNote: _coach.onDetectedNote`), subscribes to the mic stream.
  `dispose()` cancels the subscription, disposes the analyzer, and **stops but
  does not dispose** the `MicCapture` (lifecycle owned by the provider so it can
  be reused across runs).

## Tests

`test/domain/coaching/acoustic_practice_controller_test.dart` (10) + a fake mic
(`FakeMicCapture`) emitting synthetic PCM drive the real pipeline: permission
granted/denied, correct/wrong notes, completion + analytics, dispose semantics.

## Definition of Done

The whole acoustic loop is CI-verified through a fake mic; only the ~44-line
plugin adapter is device-only and unexercised in CI.
