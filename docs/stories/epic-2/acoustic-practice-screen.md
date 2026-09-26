# Epic 2 · Story 10 — Acoustic Practice Screen

**Status:** done
**Commit:** `d369303` — `feat(acoustic): child-facing practice screen that listens and coaches`
**PRD ref:** §3, §5, §7
**Story key:** `epic-2/acoustic-practice-screen`

## User story

As a child playing my own keyboard, I want a screen that shows me the song's
progress, the **big note to play next**, an **illustrated keyboard** pointing at
the right physical key, and — when I get it wrong — a clear **directional
message** on how to fix it. A wrong note should encourage me, never fail me.

## Acceptance criteria

- [x] `AcousticPracticeScreen` renders a progress strip ("n / total"), a large
      target-note readout, the coaching message, and the illustrated keyboard
      (read-only — input comes from the real keyboard, not the screen).
- [x] The target key glows and the detected key is marked; a directional arrow
      accompanies the message.
- [x] A "Start listening" button begins capture; a listening indicator shows
      while active; permission-denied shows a gentle retry prompt (not a crash).
- [x] Completing the song celebrates and commits progress + rewards via the
      existing gamification flow; the mic stops so the recording light goes off.
- [x] The board window recentres on the current target (61-key layout,
      window size 15).
- [x] `micCaptureProvider` added to `providers.dart` (prod = `RecordMicCapture`,
      tests = fake).

## Technical notes

- `lib/screens/acoustic_practice_screen.dart` — `ConsumerStatefulWidget`; builds
  an `AcousticPracticeController` in `initState` from `widget.level.requiredNotes`
  + `ref.read(micCaptureProvider)`, listens for snapshots → `setState`.
  `_onSongComplete` checks the pass threshold, then `applyLevelCompletion` +
  `recordPracticeDay` + `commitSessionProgress` + `stopListening`. Sub-widgets:
  `_SongProgress`, `_CoachingPanel`, `_ListeningIndicator`, `_PermissionDenied`,
  `_KeyboardGuide` — each carries stable keys for tests.
- `lib/providers.dart` — `micCaptureProvider` with `ref.onDispose(dispose)`.
- The screen clones progress and commits on completion, matching
  `LevelPlayScreen`'s on-screen flow.

## Tests

`test/screens/acoustic_practice_screen_test.dart` (7) — title/start prompt,
listening indicator, permission-denied, correct-note advance, wrong-note
directional coaching ("too high"), whole-song completion, progress strip. Driven
by `FakeMicCapture` + `pcmToneFor` (synthetic PCM through the real pipeline);
a 0.15 s silence gap between notes models a child lifting their finger so
repeated pitches re-arm the debouncer. Coverage: screen 118/118 (100%),
controller 69/71 (97%).

## Definition of Done

The child-facing coaching UI is built, reachable in tests, and 100% covered;
wired to navigation in story 11.
