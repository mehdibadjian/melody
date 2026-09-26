---
title: Melody
created: 2026-09-26
updated: 2026-09-26
---

# PRD: Melody (Revised Specification)

## 0. Document Purpose

This PRD is the source of truth for the Melody children's music-learning app.
It is written for PMs, engineers, and downstream workflow owners (myLoop
stories, implementation plan). Section numbers are load-bearing: code, tests,
and `docs/implementation/implementation-plan.md` reference this document by
section (§3, §4, §6, §7, §8, §9). Vocabulary follows the Glossary (§10)
exactly. Assumptions are tagged inline `[ASSUMPTION: ...]` and indexed in §11.

This revision reflects the decision to reject Kotlin Multiplatform in favor of
Flutter (single codebase, iOS + Android + desktop for development), and calls
out the analytics schema (§4.2) and content schema (§4.1) as their own
workstreams.

## 1. Vision

Melody teaches children ages 6–10 to play real melodies through guided,
game-like practice. The child taps along on an on-screen keyboard (v1) or a
connected instrument (later phases), following a content-driven adventure map
of lessons and boss battles. Every session produces practice data that feeds a
parental dashboard, so parents see real progress — time practiced, accuracy,
consistency — not vanity metrics.

The product is strictly non-punitive: mistakes never remove progress, never
end a session early, and never produce fail states that reset a child's
streaks or rewards. Motivation comes from earned stars, note currency, and
cosmetics — never from loss or pressure.

Privacy is a first-class constraint. The audience is children, so the app is
designed for COPPA and GDPR-K compliance from the schema level: analytics
payloads use whitelisted keys only, with no free-text fields and no PII.

## 2. Target User

### 2.1 Jobs To Be Done

- **Child (6–10):** "I want to play songs I recognize and feel like I'm
  getting better, in short sessions, with rewards I can see."
- **Parent:** "I want to know my child is practicing, improving, and safe —
  without watching over their shoulder."
- **Content author (internal):** "I want to ship new lessons as data, not app
  releases."

### 2.2 Non-Users (v1)

- Children under 6 (reading-level and motor-skill assumptions).
- Advanced musicians; Melody v1 covers beginner note reading and simple
  melodies only.
- Schools/institutional deployments (no multi-classroom tooling in v1).

### 2.3 Key User Journeys

- **UJ-1. Mia clears her first lesson.** Mia (7) opens the adventure map,
  picks "First Notes," taps the highlighted keys C4–D4–E4 in time, hears each
  note, and finishes above the accuracy threshold. She earns 3 stars and 5
  note currency with a celebration, then sees the next level unlocked.
- **UJ-2. Leo loses to a boss — and keeps his progress.** Leo (9) attempts
  "The Guardian" boss battle and misses the 85% accuracy threshold. The app
  shows an encouraging "try again" state; his notes mastered, stars, and
  streak are untouched. He replays immediately.
- **UJ-3. Parent checks the dashboard.** A parent opens the parental area
  (behind a parent gate) and sees practice time, accuracy trend, and session
  frequency for the week, sourced from the analytics event stream (§4.2).

## 3. Core Gameplay: Instrument Engine

The Instrument Engine is the instrument-agnostic contract at the heart of
gameplay.

- **`InstrumentInput` interface** — abstract input source emitting
  pitch/timing events (`NoteEvent`: pitch, onset time, optional duration).
  All gameplay evaluation consumes this interface, never a concrete device.
- **`KeyboardInstrument` (v1 concrete implementation)** — on-screen virtual
  piano keyboard. Emits a `NoteEvent` per key press, supports multi-touch
  (simultaneous presses are independent events), and highlights the target
  note visually. Keyboard spans one octave on phone widths, two octaves on
  tablet widths.
- **Note matching / evaluation** — a session presents the level's
  `requiredNotes` in order. Evaluation in v1 is **pitch-only**: a press is a
  hit when its pitch matches the current required note. Timing is recorded
  (for analytics and future rhythm scoring) but does not affect correctness
  in v1. `[ASSUMPTION: rhythm scoring deferred until content includes note
  durations — §9.4]`
- **Non-punitive semantics (hard requirement):**
  - Misses never end a session; the session advances past missed notes.
  - Accuracy with zero attempts defaults to 1.0 (never a division-by-zero
    fail state).
  - Streaks reset to 1, never below; no streak ever reaches 0.
- **MIDI input** is a separate workstream (see §6.3), consuming the same
  `InstrumentInput` interface. `[NON-GOAL for MVP]`

## 4. Content and Data Schemas

Content and analytics are each their own workstream with versioned schemas.

### 4.1 Content schema (lessons as data)

Lessons, levels, and boss battles are authored as JSON against schema
version 1 (`app/assets/content/lessons.json`), parsed and validated by
`ContentParser`. Invalid content fails loudly at parse time, never silently
at gameplay time.

- **Lesson** — `id`, `title`, `difficulty` (beginner/intermediate/advanced),
  ordered `levels`.
- **Level** — `id`, `name`, `type` (`standard` | `boss_battle`),
  `requiredNotes` (ordered pitch names, e.g. `C4`), `tempoBpm`,
  `successThreshold`, `rewardPayout`.
- **SuccessThreshold** — `minAccuracy` (0..1) and `minNotesHit`. A level is
  passed when both are met. Boss battles use stricter thresholds
  (e.g. 0.85).
- **RewardPayout** — `stars` and `noteCurrency` awarded on **first
  completion only**. Replays never re-pay. Currency is earned-only: there is
  no purchase path for currency (no pay-to-win).

### 4.2 Analytics event schema

Defined up front so the parental dashboard (§7) queries a real schema, not
ad-hoc per-screen data. Events carry a schema version, a type, a
`childProfileId`, a UTC timestamp, and a **whitelisted-key payload** — no
free-text fields, no PII (COPPA/GDPR-K).

Event types (v1):

- `session_start` — payload: `platform`. (Session frequency source.)
- `practice_session` — payload: `levelId`, `practicedSeconds`, `accuracy`
  (validated 0..1 at construction), `notesHit`, `notesAttempted`.
  (Practice time and accuracy source.)
- `level_completed` — payload: `levelId`, `isBossBattle`, `starsAwarded`,
  `noteCurrencyAwarded`.

Events round-trip through JSON losslessly for future backend sync (§8,
Phase 1.3).

## 5. Screens and Navigation (v1)

- **Adventure Map** — lesson list with difficulty labels and boss icons;
  loading and error states surface content-load failures to the user.
- **Level Play** — piano keyboard, target-note highlight, live feedback,
  result celebration or encouraging retry.
- **State management** — Riverpod; persistence via `SharedPreferences`
  (player progress, reward balances, streaks, daily chest claim).
- **Parental gate + dashboard UI** — `[NON-GOAL for MVP]`; the event schema
  (§4.2) is delivered so the UI can be built later against real data.

## 6. Gamification Engine

### 6.1 Progress tracking

Notes mastered (per note, across sessions), per-level accuracy history, and
practice streaks (consecutive days). All progress persists locally; progress
is never removed by any gameplay outcome (non-punitive guarantee, §3).

### 6.2 Reward economy

- **Stars** — awarded per level on first completion only, per the level's
  `RewardPayout`.
- **Note currency** — awarded alongside stars, first completion only.
  Spent on **cosmetics only** (key skins, map themes). No gameplay advantage
  is ever purchasable.
- **Daily chest** — claimable once per calendar day per profile; claim state
  persists locally. Contents are cosmetics and/or note currency.

### 6.3 MIDI input workstream

MIDI instruments implement `InstrumentInput` and are tracked as a separate
workstream from the keyboard. `[NON-GOAL for MVP]`

## 7. Parental Dashboard and Privacy

- Dashboard shows practice time, accuracy, and session frequency per child
  profile, queried from the analytics event stream (§4.2).
- Access is behind a **parental gate** (adult-verification step).
  `[NON-GOAL for MVP — schema delivered, UI later]`
- **Privacy (hard constraints):** COPPA/GDPR-K. No PII in analytics;
  payload keys whitelisted at the schema level; no third-party ad SDKs; no
  social features; no free-text input from children anywhere in the event
  pipeline.

## 8. Delivery Phases

- **Phase 0 — Feasibility gate:** microphone acoustic pitch detection
  spike. Open decision (§9.2): gate whether acoustic input is viable for the
  target age group and device spread before committing.
- **Phase 1.1 — Shippable core (this milestone):** content schema, keyboard
  instrument, gamification engine, analytics schema, screens, widget tests.
  Art/assets and narrative theme land in this phase but are tracked
  separately.
- **Phase 1.3 — Backend sync + entitlement/IAP:** interfaces stubbed in
  Phase 1.1 but not implemented. Sync of progress and analytics events;
  store entitlements. `[NON-GOAL for MVP]`
- **Phase 2+ —** MIDI workstream (§6.3), acoustic input (pending §9.2),
  expanded content library.

## 9. Open Questions

1. **9.1 Content authoring tooling** — do we need a validator/editor beyond
   schema tests before external authors touch lessons.json?
2. **9.2 Microphone acoustic pitch detection** — feasibility gate (Phase 0).
   Decision open: accuracy on small speakers/inexpensive instruments, and
   whether latency is acceptable for a rhythm-adjacent game for 6-year-olds.
3. **9.3 Cosmetic catalog** — which cosmetics ship at launch; who authors
   them.
4. **9.4 Rhythm scoring** — when note durations enter the content schema,
   timing evaluation (§3) graduates from recorded-only to scored.

## 10. Glossary

- **Lesson** — a titled, difficulty-tagged collection of ordered Levels.
- **Level** — a playable unit: ordered RequiredNotes, tempo, SuccessThreshold,
  RewardPayout. Type is `standard` or `boss_battle`.
- **Boss battle** — a Level with stricter thresholds and higher payouts;
  loss is non-punitive (§3).
- **RequiredNotes** — the ordered pitch sequence a Level presents.
- **SuccessThreshold** — `minAccuracy` + `minNotesHit`; both must be met to
  pass.
- **RewardPayout** — stars and note currency, first-completion-only.
- **Note currency** — earned-only cosmetic currency. Never purchasable.
- **InstrumentInput** — abstract input contract (pitch/timing events in).
- **KeyboardInstrument** — v1 concrete InstrumentInput (on-screen keys).
- **NoteEvent** — pitch + onset time (+ optional duration) from an
  InstrumentInput.
- **Streak** — consecutive days practiced; minimum value 1, never 0.
- **Daily chest** — once-per-day claimable reward; contents cosmetic or
  currency.
- **Child profile** — local identity a child plays under; the
  `childProfileId` on analytics events. Not PII.
- **Analytics event** — whitelisted-key record (§4.2) feeding the dashboard.

## 11. Assumptions Index

- §3 — Timing is recorded but unscored in v1; rhythm scoring deferred until
  content includes durations (§9.4).
- §4.1 — Schema version 1 content is bundled as an app asset; remote content
  delivery arrives with backend sync (Phase 1.3).
- §6.2 — Daily chest contents are defined by the cosmetics catalog (§9.3),
  not by this PRD.
- §7 — Parental gate mechanism (e.g. arithmetic challenge) is a UX decision
  made when the dashboard UI ships.
