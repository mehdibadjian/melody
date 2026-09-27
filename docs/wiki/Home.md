# Tama Melody Wiki

Home for the **melody** codebase: a children's music-learning app (ages 6–10)
that teaches a real electric piano by listening through the microphone. The
user-facing product name is **Tama Melody**; the repo and package identifiers
are still `melody` / `melody_app`.

- Repo: `mehdibadjian/melody` · default branch `main` · app version `1.6.3+13`
- Stack: Flutter `3.24.3` stable / Dart `^3.5.3`, Riverpod, SharedPreferences
- Source of truth for *what to build*: [`docs/planning/prd.md`](../planning/prd.md)
- Source of truth for *how it works today*: this wiki + [`AGENTS.md`](../../AGENTS.md)

## Pages

| Page | What it covers |
| --- | --- |
| [Architecture](Architecture.md) | Layering, the `InstrumentInput` contract, request/data flow, state management |
| [Acoustic coaching pipeline](Acoustic-coaching-pipeline.md) | Mic → PCM → pitch → debounce → coach → UI, with every tuning constant |
| [Content, gamification, analytics](Content-gamification-analytics.md) | Lessons-as-data schema v2, reward economy, event schema, privacy constraints |
| [CI, release cascade, device build](CI-release-and-build.md) | The `feat:` → tag → APK chain, its known stall, and Android/iOS build facts |

## The app in one screen

```
AdventureMapScreen  (lesson list + daily chest)
      └─ bottom-sheet "How do you want to play?"
           ├─ PlayMode.onScreen     → LevelPlayScreen        → PianoKeyboard (tappable)
           └─ PlayMode.realKeyboard → AcousticPracticeScreen → IllustratedKeyboard (a picture)
                                          ▲                          ▲
                        AcousticPracticeController ─── SongCoach ────┘
                                          ▲
              MicCapture ─▶ MicAnalyzer ─▶ PitchDetector ─▶ AcousticInstrument
```

`PianoKeyboard` is not a second keyboard — it is `IllustratedKeyboard` rendering
a window onto the same 61-key board, so both modes ask for the same keys. Both
modes also funnel into the same pure-Dart session/reward/analytics stack, so
adding a guitar or MIDI input means one new `InstrumentInput` impl — no rewrite.

## Size and shape of the code

| Area | Files | Lines | Notes |
| --- | --- | --- | --- |
| `app/lib/domain/` | 21 | 2,390 | Game logic in pure Dart — no Flutter or plugin imports |
| `app/lib/screens` + `widgets` | 6 | 1,934 | Flutter UI |
| `app/lib/` (`main`, `providers`) | 2 | 130 | Composition root |
| `app/lib/theme/` | 1 | 69 | Tama palette + `ThemeData` |
| `app/lib/platform/` | 1 | 44 | The only device-specific code in the repo |
| `app/test/` | 30 | 5,169 | Mirrors the `lib/` tree; tests are larger than the code |
| `app/assets/audio/notes/` | 61 WAVs | ~1 MB | One sample per key of the 61-key board |

Repo layout, myLoop submodule, and agent workflow live in
[`AGENTS.md`](../../AGENTS.md). Story-level history lives in
[`docs/stories/sprint-status.yaml`](../stories/sprint-status.yaml).

## Quickstart

```bash
cd app
flutter pub get
flutter test              # or: flutter test --coverage
flutter analyze           # CI uses --fatal-infos
dart format --output=none --set-exit-if-changed .
```

Acoustic mode needs a real device with a microphone. In CI and on a simulator
the mic is faked (`test/support/fake_mic.dart`) with synthetic PCM, so the whole
listen-and-coach loop is verified without hardware.

## Status

Epic 1 (shippable on-screen core) is done and merged. Epic 2 (acoustic
real-keyboard coaching) is merged and code-complete — 12 of 13 stories `done` —
with exactly one open gate: `epic-2/on-device-validation`, live-mic validation
plus calibration of `stableFramesRequired` / `clarityThreshold`. Until that
passes, treat acoustic mode as alpha-test only. See
[CI, release cascade, device build](CI-release-and-build.md) for what ships
where.
