# Melody v1 Implementation Plan

Derived from PRD (Revised Specification, `docs/planning/prd.md`). Scope for
this milestone: shippable core
of the keyboard training app with content-driven architecture, fully TDD.

## In scope
1. **Content schema** (PRD §4) — lessons, levels, boss battles as data:
   required notes, tempo, success thresholds, reward payout. JSON documents
   validated by a schema + Dart parser.
2. **Instrument Engine** (PRD §3) — abstract `InstrumentInput` interface
   (pitch/timing events in, correctness out). Concrete `KeyboardInstrument`
   (on-screen virtual keys, note matching) as v1.
3. **Gamification Engine** (PRD §6) — progress tracking (notes mastered,
   accuracy, streaks), reward economy (stars earned, spent on cosmetics only),
   daily chest logic. Non-punitive (no fail states that remove progress).
4. **Analytics event schema** (PRD §4, §7) — practice time, accuracy, session
   frequency events defined up front so the parental dashboard has a real
   source of truth.

## Out of scope (explicitly deferred per PRD)
- Microphone acoustic pitch detection (Phase 0 feasibility gate — open decision §9.2)
- MIDI input (separate workstream, §6)
- Backend sync + entitlement/IAP (§4, §8 Phase 1.3 — interfaces stubbed but not implemented)
- Parental gate UI + dashboard screens (§7 — event schema delivered; UI later)
- Art/assets, narrative theme (Phase 1.1)

## Architecture
```
app/
  lib/
    domain/            # pure Dart, no Flutter imports — fully unit-testable
      content/         # content schema models + JSON parsing + validation
      instrument/      # InstrumentInput interface, NoteEvent, evaluation
      keyboard/        # KeyboardInstrument (concrete), note matching
      gamification/    # progress, streaks, reward economy
      analytics/       # event schema, event logger
      session/         # lesson session orchestration (ties modules together)
  assets/content/      # lesson data (JSON) authored against schema
  test/                # unit tests (domain) + widget tests
```

Key decision: domain layer is pure Dart with no Flutter dependencies so all
core logic (note matching, evaluation, rewards, streaks) runs as fast unit
tests — end-to-end TDD per the PDLC loop.

## TDD approach
Each module: write failing tests capturing PRD acceptance criteria →
implement → refactor. Tests define behavior: multi-touch input handling,
accuracy calculation, threshold-based level completion, star payout,
streak counting, daily chest claim rules, event schema conformance.