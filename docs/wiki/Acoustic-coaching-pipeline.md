# Acoustic coaching pipeline

[← Home](Home.md)

How a child pressing a physical key becomes a green highlight and a compliment.

## End-to-end flow

```
 [device]  AudioRecorder (record plugin)      platform/record_mic_capture.dart
    │  Stream<Uint8List>  16-bit LE mono PCM @ 22 050 Hz
     ▼
 [seam]   MicCapture (interface)              domain/acoustic/mic_capture.dart
    │
     ▼  bytes
 [decode] PcmDecoder.push()                   domain/acoustic/pcm_decoder.dart
    │  List<double> in [-1, 1]  (odd trailing byte carried across chunks)
     ▼
 [frame]  MicAnalyzer.feed()                  domain/acoustic/mic_analyzer.dart
    │  ring buffer → 2048-sample frames, 1024 hop  (~93 ms window, ~46 ms step)
     ▼
 [pitch]  PitchDetector.detect()              domain/acoustic/pitch_detector.dart
    │  PitchEstimate{frequencyHz, clarity}  →  noteFromFrequency() → "C4"
     ▼
 [debounce] AcousticInstrument.onDetectedNote()   domain/acoustic/acoustic_instrument.dart
    │  a note must persist 3 consecutive frames; one emission per held note
     ▼
 [coach]  SongCoach.onDetectedNote()          domain/coaching/song_coach.dart
    │  correct → advance; wrong → hold + directional feedback
     ▼
 [ui]     AcousticSnapshot → setState         screens/acoustic_practice_screen.dart
```

`AcousticPracticeController.start()`
(`domain/coaching/acoustic_practice_controller.dart:121`) wires the whole chain
and is the only place that touches the mic permission.

## Tuning constants

Everything that controls how the app *feels* lives in four constructors. These
are the numbers `epic-2/on-device-validation` exists to calibrate on real
hardware in a real room.

| Constant | Default | File | Effect if raised |
| --- | --- | --- | --- |
| `sampleRate` | 22 050 Hz | `record_mic_capture.dart:15` | more data, more CPU; still ≫ Nyquist for ≤1 kHz fundamentals |
| `minFrequencyHz` | 80 | `pitch_detector.dart:70` | rejects room rumble / lowest keyboard note |
| `maxFrequencyHz` | 1200 | `pitch_detector.dart:71` | above ~D6; v1 content never goes there |
| `clarityThreshold` | 0.7 | `pitch_detector.dart:72` | fewer false detections, more dropped notes |
| `stableFramesRequired` | 3 | `acoustic_instrument.dart:23` | less flicker, slower response |
| `frameSize` / `hopSize` | 2048 / 1024 | `mic_analyzer.dart:26` | window resolution vs. latency |
| `_windowSize` | 15 notes | `acoustic_practice_screen.dart:43` | how much keyboard the child sees at once |

## Why NSDF, not autocorrelation

`PitchDetector` is a time-domain Normalized Square Difference Function
(de Cheveigné & Kawahara 2002):

```
NSDF(τ) = 1 − d(τ) / (Φ(τ) + Φ'(τ)),   d(τ) = Σ (x[j] − x[j+τ])²
```

Raw autocorrelation on a harmonic instrument peaks strongly at integer multiples
of the true period, which produces **sub-octave errors** — the app would hear
C3 when the child played C4. Normalizing by the two half-signals' energies
suppresses that. Two more details matter:

- The scan starts at the *smallest* τ (highest frequency) and takes the first
  peak above threshold, so it cannot lock onto a longer spurious period.
- The peak is refined by parabolic interpolation (`_parabolic`,
  `pitch_detector.dart`) for sub-sample period accuracy before
  `frequency = sampleRate / τ`.
- Buffers are reused across frames; this runs per frame on a phone.

`noteFromFrequency()` uses A4 = 440 Hz = MIDI 69 and returns a `NoteName` with a
signed cents offset. The cents value is available but the UI uses only the note
name — see [Known limits](#known-limits).

## Debounce: why a "held" note fires once

Per-frame pitch is jumpy: a sustain flickers between detected and silent, and
between neighbouring pitches. `AcousticInstrument` accepts a note only after it
survives `stableFramesRequired` consecutive frames, and remembers `_emitted` so a
held key does not re-trigger. A `null` (silence) frame resets the candidate, so
the same note can legitimately fire again later.

## Coaching is non-punitive by design

`coach()` (`domain/coaching/coaching.dart:65`) turns `(detected, target)` into
one of four directions:

| Case | Feedback |
| --- | --- |
| equal | `match` — "Perfect! That's C4" |
| detected above target | `tooHigh` + `▼` — "That's G4 — too high. Move a few keys lower to C4" |
| detected below target | `tooLow` + `▲` |
| silence / unparseable | `unknown` — plain "Play C4", **no penalty** |

Distance becomes child-language via `_distanceHint`: ≤2 semitones "just a
little", ≤6 "a few keys", ≤11 "quite a way", else "a long way".

`SongCoach` (`domain/coaching/song_coach.dart:61`) holds the position on a wrong
note. Consequences worth remembering:

- `index` never advances on a miss, so a song cannot be "failed" — only finished.
- `wrongAttempts` counts coaching opportunities, not errors; `accuracy` is
  `correctHits / attempts` and defaults to **1.0 with zero attempts**.
- A noisy mic inflates `attempts` and therefore lowers `accuracy`, which is what
  the level's `minAccuracy` gate is measured against. That is the practical risk
  the open validation gate is about.
- `onStateChanged` fires on every frame, and the screen rebuilds from an
  immutable `AcousticSnapshot` — the UI never reaches into controller internals.

## The keyboard the child looks at

`IllustratedKeyboard` (`widgets/illustrated_keyboard.dart`) is a **picture**, not
an input: in acoustic mode `onNote` is null. It renders a 15-note sliding window
from `KeyboardLayout.visibleWindow()` — a full 61-key board does not fit on a
phone — centred on the current target, with the target glowing, the detected
note marked in orange, and the `▲`/`▼` cue.

`KeyboardLayout` (`domain/piano/piano_layout.dart:70`) declares 61-, 76- and
88-key boards from an inclusive MIDI range; white/black counts and note lists are
derived so they cannot disagree with the range. **Only `sixtyOne` is used and
rendered today** — the other two are geometry that no code path selects yet.

## The testability seam

`MicCapture` (`domain/acoustic/mic_capture.dart`) exists so the entire chain
above it is CI-testable. `FakeMicCapture` (`test/support/fake_mic.dart`) emits
synthetic PCM **bytes**, not notes, so decode → detect → debounce → coach all
really execute in the tests. `RecordMicCapture` is the only device code and is
deliberately 44 lines with 0 % coverage — there is nothing in it worth testing
that a device won't catch.

`start()` re-checks permission on every call and never throws; denial sets
`permissionDenied`, and the UI shows a "enable the mic" prompt instead of an
error. Calling `start()` again after the user fixes the setting in system
preferences just works.

## Known limits

- **No timing judgement.** Scoring is pitch-only; tempo lives in content
  (`tempoBpm`) but nothing measures the child against it yet.
- **Single-note only.** The detector tracks one fundamental per frame, so
  chords and two-handed playing are not supported.
- **No intonation feedback.** Cents are computed and dropped; a child an octave
  off, or a piano badly out of tune, gets no distinct signal.
- **No input latency compensation.** Mic → UI lag is unmeasured on device, so
  the ~46 ms hop figure is a calculation, not an observation.
- **Untuned thresholds.** `0.7` clarity and `3` stable frames come from the
  feasibility spike against synthetic and file-based audio, not from a child's
  keyboard in a living room.
- **iOS is not ready.** `NSMicrophoneUsageDescription` is absent from
  `ios/Runner/Info.plist`; the mic would crash on launch there. Android-only
  until that lands.
