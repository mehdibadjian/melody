# Epic 2 · Story 2 — Pitch Detection Engine + AcousticInstrument

**Status:** done
**Commit:** `b0963c5` — `feat: acoustic pitch detection engine + AcousticInstrument input`
**PRD ref:** §3 (Instrument Engine — `InstrumentInput` contract)
**Story key:** `epic-2/pitch-detection-engine`

## User story

As a child playing a real keyboard, the app must reliably turn what it hears
into a clean, named note (e.g. `E4`) so the rest of the game can evaluate my
press — without flickering between pitches on a held note.

## Acceptance criteria

- [x] `PitchDetector` estimates a frame's fundamental frequency with NSDF +
      parabolic sub-sample interpolation and a clarity gate.
- [x] `noteFromFrequency` maps Hz → scientific pitch notation + signed cents.
- [x] `AcousticInstrument` implements `InstrumentInput` (the same contract as
      `KeyboardInstrument`) and emits `NoteEvent`s on a broadcast stream.
- [x] Note-stability **debounce**: a detected note must persist
      `stableFramesRequired` (default 3) consecutive frames before it fires,
      and a held note emits only once until it changes; a silence gap re-arms
      it so repeated pitches each register.
- [x] Pure Dart, no Flutter/plugin imports — fully unit-testable in CI.

## Technical notes

- `lib/domain/acoustic/pitch_detector.dart` — `PitchEstimate`, `NoteName`,
  `noteFromFrequency`, `PitchDetector` (sampleRate 22050, 80–1200 Hz band,
  `clarityThreshold` 0.7). NSDF chosen over raw autocorrelation because
  normalization suppresses sub-octave errors on harmonic (musical) signals.
- `lib/domain/acoustic/acoustic_instrument.dart` — `AcousticInstrument`
  implements `InstrumentInput` (`noteStream`, `evaluate`, `startSession`,
  `setTarget`) plus `onDetectedNote(String?)` as the debounce entry point.

## Tests

`test/domain/acoustic/pitch_detector_test.dart` (14) ·
`test/domain/acoustic/acoustic_instrument_test.dart` (6).

## Definition of Done

Detection + debounce are green in CI on synthetic input; the engine plugs into
the existing `InstrumentInput` consumers unchanged.
