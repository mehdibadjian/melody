# Content, gamification, analytics

[← Home](Home.md)

PRD §4, §6 and §7 as they exist in code. The unifying rule: **lessons are data,
not logic** — nothing in `lib/` knows the name of a song.

## Content schema v2

`app/assets/content/lessons.json` is loaded by `ContentRepository` via
`rootBundle` and validated by `ContentParser.parseDocument()`
(`app/lib/domain/content/content_parser.dart:15`). An invalid file throws
`ContentValidationException` at load time — the Adventure Map shows an error
state rather than a half-broken lesson.

```jsonc
{
  "schemaVersion": 2,
  "lessons": [{
    "id": "song-twinkle",
    "title": "Twinkle Twinkle Little Star",
    "difficulty": "beginner",          // beginner | intermediate | advanced
    "songTitle": "…",                  // v2, optional → defaults to title
    "genre": "nursery",                // v2, optional, must not be blank if present
    "attribution": "Traditional, public domain",  // v2, optional
    "levels": [{
      "id": "twinkle-1",
      "name": "…",
      "type": "standard",              // standard | boss_battle
      "requiredNotes": ["C4","C4","G4","G4","A4","A4","G4"],
      "tempoBpm": 84,                  // 40–240, must be an int
      "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 10 },
      "rewardPayout":  { "stars": 4, "noteCurrency": 6 }
    }]
  }]
}
```

Validation, exactly as implemented:

| Rule | Enforcement |
| --- | --- |
| `schemaVersion` ∈ {1, 2} | v1 documents still parse — optional v2 fields default |
| non-empty `lessons`, non-empty `levels` per lesson | throws |
| unique `id` per lesson and per level | `_firstDuplicate` scan |
| `difficulty` / `type` from a fixed vocabulary | throws on typos |
| `requiredNotes` non-empty, all non-empty strings | throws; note *pitch* is not validated here |
| `tempoBpm` int in 40–240 | throws |
| `minAccuracy` num in 0–1, `minNotesHit` ≥ 0, `stars`/`noteCurrency` ≥ 0 ints | throws |
| `genre` present ⇒ non-empty; `songTitle`/`attribution` may be blank | `_optionalString` |

Derived, never authored: `Level.noteRange`
(`content_models.dart`) computes the lowest/highest MIDI across `requiredNotes`,
ignoring unparseable entries, so the illustrated keyboard can centre its window
on the song's real span.

### The shipped library (as of v1.6.3)

11 lessons, 11 levels — one level per song today — across 6 genres
(nursery, folk, classical, hymn, spiritual, holiday). Difficulty: 8 beginner,
2 intermediate, 1 advanced. Songs run 6–15 notes, 80–100 bpm, thresholds
0.70–0.80, payouts 3★+5n to 8★+12n.

`shipped_song_library_test.dart` is the real content gate. It asserts ≥ 8 songs,
unique ids, ≥ 4 genres, **every note is a real key on the 61-key board**, and
every note has a bundled WAV.

### What the content actually constrains

- `boss_battle` is a valid, parsed type and the map renders a 🔥 icon for it —
  but **0 boss levels ship**. The mechanic is schema, not gameplay, yet.
  (`LessonQuestTile` also draws a bolt on the badge and a diamond pip for a boss
  level; both are only exercised by tests until boss content ships.)
- Audio covers naturals C4–B5 only (`assets/audio/notes/`, 14 WAVs). No sharps
  or flats can be authored today: `AssetAudioEngine.playNote` silently returns
  for anything outside `NoteFrequency._frequencies`, so an accidental would
  produce a *silent* demo. The library test is what keeps authors honest.
- The on-screen `PianoKeyboard` renders 7 white keys (C4–B4) on a phone and 14
  (C4–B5) above 900 dp. Two shipped songs — *When the Saints* (C5) and *Amazing
  Grace* (C5–E5) — therefore contain notes a phone-sized on-screen board cannot
  display. Those songs are playable in acoustic mode, where the window slides
  freely. Worth knowing before adding content in that register.

## Gamification (`PlayerProgress`)

`app/lib/domain/gamification/player_progress.dart` — pure Dart, JSON
round-trippable, persisted under `player_progress_v1`.

| Mechanic | Implementation detail |
| --- | --- |
| Level completion | `applyLevelCompletion` — **first completion only**; re-playing is encouraged and never double-pays |
| Note mastery | `recordNoteMastery(note, hit:)`; a note is *mastered* at ≥ 5 hits (`masteryHitsRequired`) |
| Practice streak | `recordPracticeDay` — consecutive calendar days; a gap resets to **1**, never to 0 |
| Daily chest | `claimDailyChest` once per calendar day; pays 2 note currency and grows `dailyChestStreak` |
| Cosmetics | `purchaseCosmetic` throws `AlreadyOwnedException` / `InsufficientCurrencyException` |
| Reward economy | currency is **earned-only** — no purchase path exists anywhere (PRD §6: no pay-to-win) |

Design notes that matter when editing:

- `DateOnly` is a UTC calendar-date wrapper with `isSameDay` /
  `isConsecutiveDayAfter`. Streak logic is date-based, not duration-based, so it
  survives clock changes only insofar as UTC does.
- The class is mutable by design; `clone()` deep-copies all six collections
  because Riverpod needs a new instance to notify. See
  [Architecture](Architecture.md#state-management).
- Cosmetic **ids are free-form strings and nothing spends them yet** — there is
  no shop UI and no cosmetic catalogue. `ownedCosmetics` persists and is read by
  tests only.

## Analytics schema

PRD §7 wants a parental dashboard *later*, so the schema ships *now* and the UI
does not. Three event types, whitelisted keys, no free text:

| Type (`toJson`) | Payload keys |
| --- | --- |
| `session_start` | `platform` |
| `practice_session` | `levelId`, `practicedSeconds`, `accuracy`, `notesHit`, `notesAttempted` |
| `level_completed` | `levelId`, `isBossBattle`, `starsAwarded`, `noteCurrencyAwarded` |

Envelope on every event: `schemaVersion` (1), `type`, `childProfileId`,
`occurredAt` (ISO-8601 UTC). Factories validate: `_requireAccuracy` throws for
anything outside 0–1, so a bad metric cannot enter the store.

`AnalyticsStore.append()` re-reads, appends, trims to the most recent 500 events
(ring-buffer semantics, oldest evicted) and rewrites the whole blob. Bad JSON at
the top level yields `[]`; a bad entry inside a good list is skipped. Deliberate
choice: **never let telemetry break a child's lesson.**

Note that `session_start` has a factory and a type but **no call site** — app
launch does not emit it yet.

## Privacy constraints (hard requirements)

- COPPA / GDPR-K; the app stores no PII. `profileId` is the literal
  `'child-local'` until the backend-sync workstream replaces it.
- Microphone audio is analysed on-device for pitch only and is never stored or
  transmitted. `RECORD_AUDIO` is declared in `AndroidManifest.xml` with that
  exact justification in a comment.
- No third-party ad SDKs, no social features, no free-text input anywhere in
  the event pipeline. Payload keys are whitelisted *by construction* — the only
  way to add one is to add a factory.

## Not built yet

| Gap | PRD | Where it would land |
| --- | --- | --- |
| Parental gate + dashboard UI | §5, §7 (explicit MVP non-goal) | new screen reading `AnalyticsStore.load()` |
| Backend sync / progress + event upload | §8 phase 1.3 | behind `ProgressStore` / `AnalyticsStore` |
| Cosmetics catalogue, shop, key skins | §6.2 | content + a shop screen |
| MIDI input | §6.3 (non-goal) | a third `InstrumentInput` impl |
| Multi-level lessons / boss battles | §4 | content only, once a boss mechanic is specified |
| iOS mic | — | add `NSMicrophoneUsageDescription` |
