# Epic 2 · Story 12 — On-Device Live-Mic Validation

**Status:** backlog (open release gate)
**Commit:** — (not started; requires a physical device + real keyboard)
**PRD ref:** §9.2 (feasibility on real hardware), §7 (privacy)
**Story key:** `epic-2/on-device-validation`

## Why this story exists

CI proves the **algorithm** and the **full pipeline** (listen → decode → detect
→ debounce → coach) using synthetic PCM through a fake mic. What CI **cannot**
prove is that a real microphone, in a real room, hearing a real electric
keyboard, produces a signal the detector locks onto. This is the one remaining
risk and the gate before treating the acoustic feature as production-ready
rather than alpha.

## User story

As the team, we need to confirm on a physical device that the app genuinely
hears a child's real keyboard and coaches correctly in normal room conditions —
so we never ship an app that "looks like it listens but doesn't."

## Acceptance criteria

- [ ] On a real device + electric piano, the app detects the correct note for
      every note in at least one shipped song (e.g. Mary Had a Little Lamb),
      in a normal room (no special acoustic treatment).
- [ ] Latency from key press to on-screen coaching feels immediate to a child
      (target: well under ~250 ms end to end).
- [ ] Repeated notes (e.g. "E4 E4 E4") each register when the child lifts and
      re-presses; the debounce re-arms reliably on real note gaps.
- [ ] Wrong-note directional coaching matches the actual pitch error on a real
      instrument (not just synthetic tones).
- [ ] `stableFramesRequired` and `clarityThreshold` are **calibrated** against
      real key-attack transients and room noise, and the chosen values are
      recorded here.
- [ ] Android runtime permission flow works end to end (grant, deny, retry).
- [ ] Privacy check: no audio is persisted or transmitted; only derived pitch is
      used (PRD §7, COPPA/GDPR-K) — verified by inspection on device.

## Suggested approach

1. Build a release/debug APK (`flutter build apk`) and sideload to an Android
   device; pair with a real electric keyboard.
2. Start with the simplest song; log per-frame detections (`MicAnalyzer.onFrame`)
   to see raw vs debounced behaviour.
3. Tune `clarityThreshold` (default 0.7) and `stableFramesRequired` (default 3)
   until detections are stable without lag; capture the chosen values.
4. Re-run the CI suite to confirm defaults/tests still hold after any tuning.
5. If iOS is in scope, add `NSMicrophoneUsageDescription` to `Info.plist` and
   repeat.

## Follow-ups unlocked by this story

- Flip PR #28 / the merged feature from alpha to a publishing release once the
  gate passes.
- Decide whether to render 76/88-key boards (layouts already defined).
- iOS microphone permission string (out of scope until iOS testing begins).

## Definition of Done

A real child (or tester) can play a shipped song on a physical keyboard, the app
coaches accurately and promptly, and the calibrated detection parameters are
recorded in this file. Until then the feature stays **alpha-test only**.
