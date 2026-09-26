# Melody v1 Implementation Plan

Derived from PRD (Revised Specification, `docs/planning/prd.md`). Scope for
this milestone: shippable core
of the keyboard training app with content-driven architecture, fully TDD.

## In scope
1. **Content schema** (PRD §4) — lessons, levels, boss battles as data:
   required notes, tempo, success thresholds, reward payout. JSON documents
   validated by a schema + Dart parser.
2. **Instrument Engine** (PRD §3) — abstract `InstrumentInput` interface
   (pitch/timing events in, correctness out). Concrete `KeyboardInstrument`
   (on-screen virtual keys, note matching) as v1.
3. **Gamification Engine** (PRD §6) — progress tracking (notes mastered,
   accuracy, streaks), reward economy (stars earned, spent on cosmetics only),
   daily chest logic. Non-punitive (no fail states that remove progress).
4. **Analytics event schema** (PRD §4, §7) — practice time, accuracy, session
   frequency events defined up front so the parental dashboard has a real
   source of truth.

## Out of scope (explicitly deferred per PRD)
- Microphone acoustic pitch detection — **delivered in Epic 2** (see the
  Acoustic Implementation Plan below); it was the Phase 0 feasibility gate
  (§9.2) when this v1 plan was written.
- MIDI input (separate workstream, §6)
- Backend sync + entitlement/IAP (§4, §8 Phase 1.3 — interfaces stubbed but not implemented)
- Parental gate UI + dashboard screens (§7 — event schema delivered; UI later)
- Art/assets, narrative theme (Phase 1.1)

## Architecture
```
app/
  lib/
    domain/            # pure Dart, no Flutter imports — fully unit-testable
      content/         # content schema models + JSON parsing + validation
      instrument/      # InstrumentInput interface, NoteEvent, evaluation
      keyboard/        # KeyboardInstrument (concrete), note matching
      gamification/    # progress, streaks, reward economy
      analytics/       # event schema, event logger
      session/         # lesson session orchestration (ties modules together)
  assets/content/      # lesson data (JSON) authored against schema
  test/                # unit tests (domain) + widget tests
```

Key decision: domain layer is pure Dart with no Flutter dependencies so all
core logic (note matching, evaluation, rewards, streaks) runs as fast unit
tests — end-to-end TDD per the PDLC loop.

## TDD approach
Each module: write failing tests capturing PRD acceptance criteria →
implement → refactor. Tests define behavior: multi-touch input handling,
accuracy calculation, threshold-based level completion, star payout,
streak counting, daily chest claim rules, event schema conformance.

---

# Melody Epic 2 Implementation Plan — Acoustic Real-Keyboard Coaching

Derived from PRD §3 (Instrument Engine), §9.2 (acoustic feasibility gate) and
§8 (Phase 0 → Phase 2+). **Status:** built and merged to `main` (squash
`88e38e7`, PR #28); one open gate (on-device live-mic validation). Stories are
tracked in `docs/stories/epic-2.md` and `docs/stories/epic-2/`.

## Goal

Teach a child to play a **real electric-piano keyboard** by listening through
the microphone: show which physical key to press, correct wrong presses with
directional guidance, illustrate the keyboard, and use real public-domain songs
across multiple genres — all scalable as data.

## Guiding architecture decision: the CI-testability seam

The single most important decision in this epic. A microphone cannot run in CI,
so the device boundary is isolated behind one injectable interface and the rest
is pure Dart:

```
                 ┌───────────────── pure Dart (CI-tested) ─────────────────┐
device mic ──PCM──> MicCapture      PcmDecoder   MicAnalyzer   PitchDetector
(record plugin)     (interface)  ──────────────> frames ─────> NSDF + cents
   ▲                                                          │
   │ only device-only code                          noteFromFrequency
   │ (~44 lines, 0% cov by design)                            ▼
RecordMicCapture                                     AcousticInstrument
                                                     (note-stability debounce)
                                                              │ stable note
                                                              ▼
                                                         SongCoach ──> CoachingFeedback
                                                     (state machine)   (direction + msg)
                                                              │
                                                              ▼
                                              AcousticPracticeController ──> AcousticSnapshot
                                                              │
                                                              ▼
                                              AcousticPracticeScreen (IllustratedKeyboard)
```

`MicCapture` is the seam. In production it is `RecordMicCapture` (the `record`
plugin); in tests it is `FakeMicCapture` emitting **synthetic PCM** that flows
through the *real* decode → detect → debounce → coach pipeline. Result: the
entire loop is verified in CI; only the ~44-line plugin adapter is device-only.

## Layer map (new code)

```
app/lib/
  domain/
    acoustic/        pitch_detector, acoustic_instrument, pcm_decoder,
                     mic_analyzer, mic_capture (interface)   — pure Dart
    coaching/        coaching (directional feedback), song_coach (state
                     machine), acoustic_practice_controller    — pure Dart
    piano/           piano_layout (note↔midi, 61/76/88-key, visibleWindow)
    content/         content_models + content_parser bumped to schema v2
  platform/
    record_mic_capture.dart   — the ONLY device-specific code
  widgets/
    illustrated_keyboard.dart — physical-keyboard render + overlays
  screens/
    acoustic_practice_screen.dart — child-facing coaching UI
    adventure_map_screen.dart     — play-mode chooser (navigation)
  providers.dart     — micCaptureProvider (prod RecordMicCapture / test fake)
app/assets/content/lessons.json — schema v2, 11 public-domain songs
```

## Build order (as executed — fully CI-testable core first, then the live layer)

1. **Feasibility spike** (§9.2 gate) — prove NSDF on synthetic signals. *Story 1.*
2. **Detection engine + `AcousticInstrument`** — behind the existing
   `InstrumentInput` contract. *Story 2.*
3. **Piano layouts + directional coaching** — pure-Dart math the UI and coach
   both need. *Story 3.*
4. **Content schema v2** — song metadata + derived note range, v1-compatible.
   *Story 4.*
5. **Public-domain song library** — 11 real songs, validated to fit the board
   and bundled audio. *Story 5.*
6. **Illustrated keyboard widget** — physically-correct render with testable
   per-note overlays. *Story 6.*
7. **`SongCoach`** — note-by-note, non-punitive state machine. *Story 7.*
8. **PCM decode + live-analysis pipeline** — bytes → frames → notes, pure Dart.
   *Story 8.*
9. **Mic capture seam + practice controller** — permission, capture, wiring;
   the loop becomes CI-testable via the fake mic. *Story 9.*
10. **Acoustic practice screen** — the child-facing coaching UI. *Story 10.*
11. **Play-mode navigation** — make the screen reachable from the map. *Story 11.*
12. **On-device live-mic validation** — the open release gate. *Story 12.*

Each step landed as one Conventional Commit on `qoder/spike-acoustic-pitch`,
keeping `dart format` / `flutter analyze --fatal-infos` / `flutter test
--coverage` green at every commit (80% coverage floor).

## Scalability (per the explicit ask: "do not limit this")

- **More songs/genres:** edit `lessons.json` (data), guarded by
  `shipped_song_library_test.dart`. No code change.
- **More keyboard sizes:** `KeyboardLayout.seventySix` / `.eightyEight` are
  already defined; only the 61-key view renders today — adding a board is a UI
  change, not an engine change.
- **Other instruments:** everything keys off the `InstrumentInput` contract, so
  a future MIDI input (PRD §6.3) plugs in beside acoustic and on-screen.

## Privacy (PRD §7, COPPA/GDPR-K)

Audio is analysed **on-device for pitch only**; raw audio is never stored or
transmitted. Android declares `RECORD_AUDIO`. Analytics events keep the existing
whitelisted-key, no-PII payload.

## Verification at merge

`dart format` clean · `flutter analyze --fatal-infos` clean · **217 tests
passing** · coverage **1060/1112 = 95.32%** (floor 80%). `AcousticPracticeScreen`
100%, `AcousticPracticeController` 97%, `adventure_map_screen` 100%;
`RecordMicCapture` 0% (device-only by design). CI green on the merged commit.

> Caveat caught post-merge: CI (`ci.yml`) runs `flutter test` only and never
> builds an APK, so it did **not** catch that the new `record` plugin broke
> `flutter build apk --release` on Flutter 3.24.3 — the v1.6.0 publish produced
> no APK. Fixed in *Story 13* (`epic-2/android-release-build-fix`, PR #30 →
> v1.6.1): pin `record_android` to 1.3.3 + app `minSdk = 23`. Lesson: Android
> build-config changes need a real `flutter build apk --release`, not just
> `flutter test`.

## What is NOT done (open, needs hardware)

- **On-device live-mic validation + calibration** (`stableFramesRequired`,
  `clarityThreshold`) against a real keyboard in a real room — *Story 12*, the
  release gate.
- 76/88-key board UI (layouts defined; not rendered).
- iOS `NSMicrophoneUsageDescription` (Android permission in place).
- Rhythm/duration scoring (PRD §9.4) — timing recorded, not scored.

## Recommendation

The feature is complete, reachable, and CI-verified, but **alpha-test only**
until Story 12 passes on a physical device. Treat on-device validation as the
gate before promoting from alpha to a published release.