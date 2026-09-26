# Epic 2 · Story 7 — SongCoach Note-by-Note State Machine

**Status:** done
**Commit:** `2cd1829` — `feat(coaching): SongCoach state machine for acoustic play`
**PRD ref:** §3 (non-punitive gameplay)
**Story key:** `epic-2/song-coach`

## User story

As a child, I want the app to walk me through a song **one note at a time**:
advance when I get it right, and stay put (with guidance) when I don't — never
failing me — until I finish the whole song.

## Acceptance criteria

- [x] `SongCoach` holds an ordered note list and a current `index`; a correct
      detected note advances, a wrong one holds the index and records
      `CoachingFeedback`.
- [x] `SongCoachState` exposes `notes`, `index`, `correctHits`,
      `wrongAttempts`, `feedback`, `detectedNote`, and derived `isComplete`,
      `targetNote`, `attempts`, `accuracy`.
- [x] `onDetectedNote(String?)` is the single input; null/empty is ignored
      (still notifies state so the UI can refresh).
- [x] `onComplete` fires exactly once (guarded by a `_completed` flag);
      `onStateChanged` notifies listeners on every input.
- [x] Non-punitive accuracy: zero attempts default to 1.0 (no divide-by-zero).

## Technical notes

- `lib/domain/coaching/song_coach.dart` — `SongCoach({required notes,
  onComplete})`; `onComplete` and `onStateChanged` are settable callbacks
  (the controller wires them, story 9).

## Tests

`test/domain/coaching/song_coach_test.dart` (14) — advance on match, hold on
mismatch with directional feedback, repeated notes, completion fires once,
accuracy/attempts math, null-input handling.

## Definition of Done

The state machine is pure-Dart and green in CI; it is the gameplay core that
`AcousticPracticeController` (story 9) drives from detected notes.
