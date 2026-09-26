# Epic 2 · Story 6 — Illustrated Real-Keyboard Widget

**Status:** done
**Commit:** `8824756` — `feat(ui): illustrated real-keyboard guide widget`
**PRD ref:** §5 (screens), §9.2
**Story key:** `epic-2/illustrated-keyboard`

## User story

As a child, I want to **see a picture of a real keyboard** with the key I should
press highlighted, and the key I just played marked, so I know exactly which
physical key to hit — and whether I was too high or too low.

## Acceptance criteria

- [x] `IllustratedKeyboard` renders white keys in a row with black keys
      positioned over the gaps (correct physical layout, not a flat strip).
- [x] A target-key **glow** overlay marks the note to play; a separate
      **detected** marker shows what the mic just heard.
- [x] Overlays are tap-through (`IgnorePointer`) so an interactive board stays
      pressable; `onNote == null` makes it a read-only illustration.
- [x] Each overlay carries **per-note keys** (`target-<note>`,
      `detected-<note>`) so widget tests can assert the right key is marked.
- [x] Renders only a `windowNotes` slice (from `visibleWindow`) so a phone
      shows a readable region, not all 61 keys at once.

## Technical notes

- `lib/widgets/illustrated_keyboard.dart` — `IllustratedKeyboard({windowNotes,
  targetNote, height, detectedNote, arrow, onNote})`; `_blackKeyLeft` computes
  black-key x-offset; `_overlayMarker({markerKey, noteKey, left, isBlack, color,
  width, child})` = `Positioned(key: noteKey)` → `IgnorePointer` →
  `Container(key: markerKey)`. Uses `withOpacity` (Flutter 3.24.3 has no
  `withValues`).

## Tests

`test/widgets/illustrated_keyboard_test.dart` (10) — white/black key counts,
target glow and detected marker land on the correct per-note keys, read-only vs
interactive (`onNote`) modes, window slicing.

## Definition of Done

The widget renders a physically-correct keyboard with testable target/detected
overlays; reused by `AcousticPracticeScreen` (story 10) in read-only mode.
