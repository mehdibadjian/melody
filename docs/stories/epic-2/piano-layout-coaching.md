# Epic 2 · Story 3 — Piano Key Layouts + Directional Coaching

**Status:** done
**Commit:** `c5f58ff` — `feat: piano key layouts + directional coaching engine`
**PRD ref:** §3 (non-punitive gameplay), §9.2
**Story key:** `epic-2/piano-layout-coaching`

## User story

As a child at a real keyboard, when I press the wrong key I want to be told
**which direction to move** (and roughly how far), and I want the app to know
the **physical layout** of my keyboard so it can point at the right key — for a
61-key board now, with 76/88-key planned.

## Acceptance criteria

- [x] Note ↔ MIDI conversion both ways (`midiFromNote`, `noteFromMidi`),
      sharp-based naming, correct black/white classification.
- [x] `KeyboardLayout` derives `notes`, `keyCount`, `whiteKeyCount`,
      `blackKeyCount` from a low/high MIDI range.
- [x] Three layouts: `sixtyOne` (built, MIDI 36–96 = C2–C7, 36 white + 25
      black), `seventySix` (plan-only), `eightyEight` (plan-only).
- [x] `visibleWindow(target, size:)` returns a centred, clamped slice of notes
      around the target so the UI can show a readable region.
- [x] `coach({detected, target})` returns a `CoachingFeedback` with a
      `PitchDirection` (match / tooHigh / tooLow / unknown), semitone delta,
      an arrow (▲/▼), and a plain-language message with a distance hint.
- [x] Non-punitive: a wrong note never fails the child; null/unknown detection
      just re-prompts "Play <target>".

## Technical notes

- `lib/domain/piano/piano_layout.dart` — note↔midi (regex
  `^([a-gA-G])([#b]?)(-?\d+)$`), `isBlackKeyMidi` (pitch classes {1,3,6,8,10}),
  `KeyboardLayout` + statics, `containsNote`, `visibleWindow`.
- `lib/domain/coaching/coaching.dart` — `PitchDirection`, `CoachingFeedback`
  (`isCorrect` getter), `coach()`, `_distanceHint` (≤2 "just a little", ≤6 "a
  few keys", ≤11 "quite a way", else "a long way").

## Tests

`test/domain/piano/piano_layout_test.dart` (17) ·
`test/domain/coaching/coaching_test.dart` (8).

## Definition of Done

Layout math and directional coaching are pure-Dart and green in CI; the 61-key
board is the shipped target, 76/88-key are defined but not yet rendered.
