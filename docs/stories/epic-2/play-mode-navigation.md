# Epic 2 · Story 11 — Play-Mode Navigation

**Status:** done
**Commit:** `14b0c4d` — `feat(nav): route lessons to real-keyboard or on-screen play mode`
**PRD ref:** §5 (screens and navigation)
**Story key:** `epic-2/play-mode-navigation`

## User story

As a child opening a song, I want to **choose how to play it**: on my own real
keyboard (Melody listens and coaches) or on the on-screen keys — so the new
acoustic experience is actually reachable from the adventure map.

## Acceptance criteria

- [x] Tapping a lesson opens a play-mode chooser (bottom sheet) with two
      options: "My real keyboard" and "On-screen keys".
- [x] "My real keyboard" routes to `AcousticPracticeScreen`; "On-screen keys"
      routes to `LevelPlayScreen` (the existing on-screen flow, unchanged).
- [x] Dismissing the sheet navigates nowhere; a stale `BuildContext` after the
      async gap is guarded (`context.mounted`).
- [x] The chooser is covered by navigation tests using fakes (no device mic or
      audio output).

## Technical notes

- `lib/screens/adventure_map_screen.dart` — new `PlayMode {realKeyboard,
  onScreen}` enum + `_choosePlayMode(context, lesson)` showing
  `showModalBottomSheet<PlayMode>` with keys `play-mode-real-keyboard` /
  `play-mode-on-screen`; routes via a `switch` expression on the chosen mode.
  The lesson `ListTile.onTap` now calls `_choosePlayMode` instead of pushing
  `LevelPlayScreen` directly.
- This closes the gap where `AcousticPracticeScreen` (story 10) existed but had
  **no entry point** from the app.

## Tests

`test/screens/adventure_map_screen_test.dart` (+3, total 7) — the chooser shows
both modes; real-keyboard opens `AcousticPracticeScreen` (asserts
`start-listening`); on-screen opens `LevelPlayScreen`. The container overrides
`audioEngineProvider` (synth) and `micCaptureProvider` (fake) so routing is
CI-verified end to end. `adventure_map_screen.dart` coverage 51/51 (100%).

## Definition of Done

The acoustic coaching screen is reachable from the adventure map; both play
modes route correctly and are covered in CI.
