# Epic 2 · Story 5 — Public-Domain Song Library Across Genres

**Status:** done
**Commit:** `6d0d018` — `feat(content): real public-domain song library across genres`
**PRD ref:** §4.1 (content as data), §8 (Phase 2+ expanded content library)
**Story key:** `epic-2/public-domain-song-library`

## User story

As a child, I want to learn **real songs I recognize**, across **different kinds
of music**, so practicing feels like playing actual music — and as the team we
want the library to be **data**, so adding more songs/genres never touches code.

## Acceptance criteria

- [x] Replace the note-reading drills with **11 recognizable public-domain
      songs** spanning **6 genres**.
- [x] Every note in every song is playable on the **61-key board** and has a
      **bundled reference audio** clip (C4–G5 natural notes).
- [x] Each song is a sensible length (≥4 notes) and a comfortable range
      (≤18-semitone span) for a young beginner.
- [x] Authored as `schemaVersion: 2` JSON with `genre` tags — scalable by
      editing data only.

## Technical notes

`app/assets/content/lessons.json` (rewritten, schema v2). Genres and songs:

- **nursery:** Hot Cross Buns · Mary Had a Little Lamb · Twinkle Twinkle Little Star
- **folk:** Au Clair de la Lune · Frère Jacques · Row, Row, Row Your Boat ·
  London Bridge Is Falling Down
- **holiday:** Jingle Bells
- **classical:** Ode to Joy
- **spiritual:** When the Saints Go Marching In
- **hymn:** Amazing Grace

All are traditional/public-domain; melodies verified note-by-note.

## Tests

`test/domain/content/shipped_song_library_test.dart` (7) — asserts every
shipped song: notes fit the 61-key layout, has a bundled WAV, length ≥ 4 notes,
and span ≤ 18 semitones. This is the "real hardware constraint" guard so the
library can't silently drift out of range.

## Definition of Done

The shipped `lessons.json` is all real songs, validated against physical-board
and audio-asset constraints in CI.
