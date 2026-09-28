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
      "durations": [1, 1, 1, 1, 1, 1, 2],  // optional: base notes per entry
      "tempoBpm": 84,                  // 40–240, must be an int
      "meter": {                       // optional, defaults to simple 4/4
        "beatsPerMeasure": 4, "beatUnit": 4,
        "dotted": true, "notesPerBeat": 3    // → 12/8
      },
      "songTempoBpm": 123,             // optional: the recording's real tempo
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
| `durations` absent ⇒ one base note per note; else a list of numbers, one per `requiredNotes` entry, each in (0, 8] | throws on length mismatch, non-numeric, zero/negative, or > `ContentParser.maxNoteDurationNotes` |
| `tempoBpm` int in 40–240 | throws |
| `songTempoBpm` absent, or int in 40–240 | throws |
| `meter` absent ⇒ simple 4/4; else a Map with int `beatsPerMeasure`/`beatUnit`/`notesPerBeat` in 1–16 and bool `dotted` | throws |
| `dotted` only with `beatUnit` 4 or 8 | throws (a dotted half/quarter divides into three; a dotted whole does not fit a beat) |
| `minAccuracy` num in 0–1, `minNotesHit` ≥ 0, `stars`/`noteCurrency` ≥ 0 ints | throws |
| `genre` present ⇒ non-empty; `songTitle`/`attribution` may be blank | `_optionalString` |

Derived, never authored: `Level.noteRange`
(`content_models.dart`) computes the lowest/highest MIDI across `requiredNotes`,
ignoring unparseable entries, so the illustrated keyboard can centre its window
on the song's real span. `Level.durationNotesAt(i)` and `Level.totalNoteUnits`
read the rhythm, defaulting to one base note per note when `durations` is
absent.

### What `durations` is for

`requiredNotes` says *which* keys a song uses; on its own it cannot say how long
each is held, so the demo rendered every tune as a march of equal-length notes —
the pitches of "Row Row Row Your Boat" with none of its dotted lilt. `durations`
is an optional parallel array, one entry per note, in **base-note units** (the
same unit `SongMeter.noteMs` measures, so `1.0` is one step of the demo grid and
`4.0` a whole note in 4/4). `DemoTimeline.plan` walks a running offset instead of
`i * noteMs`, so a held note pushes everything after it later, and the metronome
clicks now sit on the beat grid rather than being attached to a note, which keeps
them in time while a note rings across several beats.

Scoring is untouched: `LessonSession` still walks `requiredNotes` and matches on
pitch only. `durations` changes what the child *hears*, not what they are graded
on. `toJson` omits the field when it is absent or all-ones, so documents
round-trip unchanged. Eleven public-domain levels carry an authored rhythm;
GOLDEN's three do not, because transcribing a copyrighted contemporary
arrangement's rhythm is a rights decision, not something to guess at here.

### What `meter` is for

`tempoBpm` alone does not define a speed, because it does not say *which note
value gets the beat*. GOLDEN's printed arrangements carry both `half note = 90`
and `dotted quarter = 123`, which are the same real pulse about 2.5 % apart; as a
bare number, `120` could mean four crotchets or three quarters of a bar.
`SongMeter` (`domain/rhythm/song_meter.dart`) closes that gap: the beat's note
value, whether it is dotted, and how many melody notes fill it. GOLDEN is
authored as four dotted-quarter beats of three eighths — `12/8` — so its
`92 / 108 / 120` are progressive *practice* tempos for that beat, and
`songTempoBpm: 123` states the recording's real tempo beside them.

Only the listen-first demo (`domain/rhythm/song_demo.dart`,
`widgets/song_demo_dialog.dart`) consumes `meter`, to space its notes, count-in
bar and metronome clicks; scoring stays pitch-only, and every song without a
`meter` keeps the simple 4/4 default. `toJson` omits `meter` when it is the
default, so documents round-trip unchanged.

### The shipped library (as of v1.7.1 + GOLDEN)

12 lessons, 14 levels — all single-level except *GOLDEN*, which ships three
arrangements — across 7 genres (nursery, folk, classical, hymn, spiritual,
holiday, pop). Difficulty: 9 beginner, 2 intermediate, 1 advanced. Levels run
6–85 notes, 80–120 bpm, thresholds 0.70–0.80, payouts 3★+5n to 8★+12n. Eleven
of the levels carry an authored `durations` rhythm; the three GOLDEN
arrangements deliberately do not.

`shipped_song_library_test.dart` is the real content gate. It asserts ≥ 8 songs,
unique ids, ≥ 4 genres, **every note is a real key on the 61-key board**, and
every note has a bundled WAV. Length/threshold checks run over **every** level,
not just the first; the 18-semitone span cap applies to `levels.first` only,
because that is the arrangement a fresh player is dropped into. It also lints the
authored rhythms: every level totals a whole number of beats (`golden-hard`
grandfathered, named so the allowance cannot quietly grow), ≥ 10 non-GOLDEN
levels carry a `durations` array, none of them is a flat all-ones list, and each
ends on a held note.

### What the content actually constrains

- `boss_battle` is a valid, parsed type and the map renders a 🔥 icon for it.
  Exactly **one** boss level ships: *GOLDEN — Hard*. `LessonQuestTile` also draws
  a bolt on the badge and a diamond pip for a boss level, so those affordances
  are no longer test-only. Nothing gates on it — no unlock requirement, no
  different reward path; it is presentation plus one analytics tag.
- Audio covers the **whole 61-key board**: `NoteFrequency` is generated from
  `KeyboardLayout.sixtyOne` and equal temperament at A4=440, and each of those
  61 notes has a WAV in `assets/audio/notes/`. It used to be a hand-typed list
  of 16. `AssetAudioEngine.playNote` still returns silently for a name with no
  entry, which is why `audio_engine_test.dart` checks the table and the bundle
  agree in **both** directions: table-without-file and file-without-table are
  both a dead key, not an error.
- Sharps are stored on disk with `s`, not `#` (`fs4.wav` for `F#4`), and
  `NoteAsset` is the only place that spells it. See its doc comment: `#` is a
  URL fragment delimiter and `playNote` swallows a failed source, so a `#` file
  name risks a key that does nothing rather than one that errors.
- The on-screen `PianoKeyboard` is a **window onto the same 61-key board the
  acoustic guide draws**, rendered by `IllustratedKeyboard`: black keys included,
  one octave on a phone and two above 900 dp, sliding to stay centred on the
  note the child is asked for. It used to be its own seven-white-key row pinned
  to C4–B4, which made several shipped songs literally unfinishable by tapping —
  *Amazing Grace* (melody C5–E5) could reach at best 0.14 accuracy against a 0.8
  threshold, and *GOLDEN — Medium/Hard* likewise.
  `piano_keyboard_playability_test.dart` now asserts the opposite of that: for
  every note of every level, at both widths, the key is on screen and the song
  can be completed. Keep content inside `KeyboardLayout.sixtyOne` and that stays
  true; step outside it and the guard fails rather than shipping a dead key.
- Accuracy means **correct taps / total taps**, on both paths, and a wrong tap
  *holds* the child on the current note instead of consuming it. So a level ends
  by the song being played through, never by running out of taps; a run can
  still fail, but only on accuracy. One wrong tap before every note scores 0.5,
  below every threshold in the library (0.70–0.80), which is what keeps the
  thresholds meaningful now that reaching the end is always possible.
- Because the acoustic coach cannot complete without landing every note,
  `AcousticPracticeScreen` awards the payout on completion rather than
  re-testing the threshold itself. It used to re-test it, which silently denied
  the reward to a child who fumbled a lot and still finished the song.

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
