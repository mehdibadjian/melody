# Epic 2 · Story 4 — Content Schema v2 (Song Metadata + Note Range)

**Status:** done
**Commit:** `3e43c94` — `feat(content): schema v2 — song metadata + derived note range`
**PRD ref:** §4.1 (content schema, lessons as data)
**Story key:** `epic-2/content-schema-v2`

## User story

As a content author, I want lessons to carry **song metadata** (title, genre,
attribution) and an automatically derived **note range**, so real recognizable
songs can be tagged by genre and validated to fit a given keyboard — without
breaking the existing v1 content.

## Acceptance criteria

- [x] Schema bumps to version **2**, still accepting version **1** (backward
      compatible: `supportedSchemaVersions = {1, 2}`).
- [x] `Lesson` gains optional `songTitle` (falls back to `title`), `genre`
      (default `''`), `attribution` (default `''`); `toJson` includes them only
      when present.
- [x] `NoteRange {low, high}` + `Level.noteRange` derive the lowest/highest
      MIDI from `requiredNotes`, ignoring unparseable entries; `isEmpty` when
      no notes parse.
- [x] Parser rejects an unsupported `schemaVersion` and a present-but-empty
      `genre` (loud failure at parse time, per §4.1).

## Technical notes

- `lib/domain/content/content_models.dart` — `Lesson` ctor uses a private
  backing field (`String? songTitle) : _songTitle = songTitle;`) so `songTitle`
  can fall back to `title`; new `NoteRange`; `Level.noteRange` getter (imports
  `piano_layout` for `midiFromNote`).
- `lib/domain/content/content_parser.dart` — `supportedSchemaVersion = 2`,
  version-set check, `_optionalString(json, key, {allowEmpty})`.

## Tests

`test/domain/content/content_song_metadata_test.dart` (10) — v2 round-trip,
v1 still parses, genre/attribution handling, note-range derivation, rejection
of bad version and empty genre.

## Definition of Done

Schema v2 parses and round-trips losslessly; v1 content keeps working; note
range is available for keyboard-fit validation (used by story 5).
