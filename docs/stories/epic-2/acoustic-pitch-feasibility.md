# Epic 2 · Story 1 — Acoustic Pitch Detection Feasibility Gate

**Status:** done
**Commit:** `eb2ae50` — `test: acoustic pitch detection feasibility (synthetic waveforms)`
**PRD ref:** §9.2 (Phase 0 feasibility gate)
**Story key:** `epic-2/acoustic-pitch-feasibility`

## User story

As the team, we need to know whether microphone-based acoustic pitch detection
is accurate and fast enough for a 6-year-old at a real keyboard **before** we
commit to building it, so we don't ship an app that "looks like it listens but
doesn't."

## Acceptance criteria

- [x] A prototype detector identifies the correct note from synthetic
      waveforms (no microphone, no device) across a full octave.
- [x] Quantified accuracy (cents error), noise tolerance (SNR), and per-frame
      latency are recorded as evidence for the §9.2 decision.
- [x] Runs as pure-Dart tests in CI (no plugin, no permission, no audio I/O).

## Technical notes

Feasibility spike only — proves the algorithm, not the product. Established
the time-domain **NSDF** approach (de Cheveigné & Kawahara 2002) as viable and
the measurement methodology reused by later stories.

**Results (synthetic signals):**
- Accuracy: 0-cent error identifying every note C4..C5; correct note across
  C3..B4.
- Noise: still identifies the note through ~20 dB SNR background noise.
- Latency: ~197 µs per 30 ms frame ≈ 167× real-time — a non-issue on clean
  signals.

## Tests

Feasibility assertions lived in the spike test scaffold and were carried into
story 2's `pitch_detector_test.dart` (14 tests).

## Decision

§9.2 gate: **GREEN** on the detection algorithm. Proceeded to build the engine
(story 2). The remaining risk is real-world acoustics, which can only be
settled on a device (story 12).
