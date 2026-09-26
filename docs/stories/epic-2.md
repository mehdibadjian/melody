# Epic 2 — Acoustic Real-Keyboard Coaching

**Status:** in-progress (built, merged to `main`, pending on-device validation)
**PRD refs:** §3 (Instrument Engine), §9.2 (microphone acoustic pitch detection
feasibility gate), §8 (Phase 0 → Phase 2+ acoustic input)
**Branch:** `qoder/spike-acoustic-pitch` → squash-merged to `main` as `88e38e7`
**PR:** [#28](https://github.com/mehdibadjian/melody/pull/28)
**Tracking:** `file-system` (stories under `docs/stories/epic-2/`)

## Goal

Let a child learn on a **real electric-piano keyboard** while the app listens
through the microphone and coaches them note by note: show *which physical key*
to press on an illustrated keyboard, and on a wrong note tell them *how to
correct it* (which direction to move). The music is **real, recognizable,
public-domain songs across multiple genres**, authored as data so it scales to
more songs and instruments without code changes.

This epic resolves PRD open question **§9.2** ("is microphone acoustic pitch
detection viable for a child at a real keyboard?") and takes it all the way
from a feasibility spike to a reachable, child-facing screen.

## Why this shape

The app's input layer is already an abstract `InstrumentInput` (PRD §3). This
epic adds a **new implementation** (`AcousticInstrument`) plus a pure-Dart
detection engine layered behind it. The existing session / evaluation /
gamification / analytics / content stack is unchanged — a real keyboard heard
through the mic plugs in beside the on-screen keyboard. That is what makes the
acoustic path testable in CI: only the ~44-line `record` plugin adapter is
device-specific.

## Scope

**In scope (delivered):**
- Acoustic pitch detection (NSDF) + note-stability debounce as an
  `InstrumentInput`.
- Live microphone capture seam, PCM decode, and per-frame analysis pipeline.
- Physical keyboard layouts (61-key built; 76/88-key plan-only) + directional
  coaching engine.
- Note-by-note `SongCoach` state machine and `AcousticPracticeController`.
- Illustrated real-keyboard widget + child-facing `AcousticPracticeScreen`.
- Content schema v2 (song metadata + derived note range) and an 11-song
  public-domain library across 6 genres.
- Play-mode navigation (real keyboard ⇄ on-screen).

**Out of scope (deferred):**
- On-device live-mic calibration against a physical keyboard — **the one true
  release blocker**; tracked as `epic-2/on-device-validation` (story 12).
- 76/88-key board UI (layouts defined; only the 61-key view ships).
- iOS `NSMicrophoneUsageDescription` (Android `RECORD_AUDIO` is in place).
- Rhythm/duration scoring (PRD §9.4) — timing recorded, not scored.
- MIDI input (PRD §6.3, separate workstream).

## Stories

| # | Story | Status | Commit |
|---|-------|--------|--------|
| 1 | [Acoustic pitch feasibility gate](epic-2/acoustic-pitch-feasibility.md) | done | `eb2ae50` |
| 2 | [Pitch detection engine + AcousticInstrument](epic-2/pitch-detection-engine.md) | done | `b0963c5` |
| 3 | [Piano key layouts + directional coaching](epic-2/piano-layout-coaching.md) | done | `c5f58ff` |
| 4 | [Content schema v2 — song metadata + note range](epic-2/content-schema-v2.md) | done | `3e43c94` |
| 5 | [Public-domain song library across genres](epic-2/public-domain-song-library.md) | done | `6d0d018` |
| 6 | [Illustrated real-keyboard widget](epic-2/illustrated-keyboard.md) | done | `8824756` |
| 7 | [SongCoach note-by-note state machine](epic-2/song-coach.md) | done | `2cd1829` |
| 8 | [PCM decode + live analysis pipeline](epic-2/pcm-decode-live-pipeline.md) | done | `d93964a` |
| 9 | [Live mic capture seam + practice controller](epic-2/live-capture-seam.md) | done | `df8a73f` |
| 10 | [Acoustic practice screen](epic-2/acoustic-practice-screen.md) | done | `d369303` |
| 11 | [Play-mode navigation](epic-2/play-mode-navigation.md) | done | `14b0c4d` |
| 12 | [On-device live-mic validation](epic-2/on-device-validation.md) | backlog | — |

## Definition of Done (epic)

- [x] Detection engine identifies notes on synthetic signals with 0-cent error
      across C4..C5 (CI-verified).
- [x] Full listen → decode → detect → debounce → coach loop runs in CI through
      a fake mic emitting synthetic PCM.
- [x] Wrong notes guide directionally and never fail the child (PRD §3).
- [x] 11 recognizable public-domain songs ship across ≥3 genres, all playable
      on a 61-key board with bundled reference audio.
- [x] The acoustic screen is reachable from the adventure map.
- [x] `dart format` clean · `flutter analyze --fatal-infos` clean · 217 tests
      passing · coverage ≥ 80% floor (95.32% at merge).
- [x] Merged to `main` (squash `88e38e7`); CI green.
- [ ] **On-device live-mic validation** (story 12) — confirm it genuinely hears
      a physical keyboard in a real room, and calibrate `stableFramesRequired`
      / `clarityThreshold`. Until this passes, the release stays non-publishing
      in spirit (alpha-test only).
