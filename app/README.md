# melody_app

The Flutter application for **Tama Melody** — a children's piano-learning app
(ages 6–10). Kids learn real melodies through guided, game-like practice, on an
on-screen keyboard or a real electric piano that the app listens to through the
microphone.

For the product overview, downloads, and repo map, see the
[root README](../README.md). This document is for working on the app itself.

## Requirements

- Flutter `3.24.3` stable
- Dart SDK `^3.5.3`
- Android: `minSdk 23`, build-tools 34, JDK 17 (Gradle wrapper 8.3 does not run
  on Java 21). iOS microphone usage string is not yet added.

The Flutter SDK is not assumed to be preinstalled in CI sandboxes; see
[`AGENTS.md`](../AGENTS.md) for the exact install step used by the agent
workflow.

## Getting started

```bash
flutter pub get
flutter run
```

Run the full CI gate locally before pushing (this is what `.github/workflows/ci.yml` runs on `app/**`):

```bash
flutter pub get
dart format --set-exit-if-changed --output=none .
flutter analyze --fatal-infos
flutter test --coverage   # CI enforces an 80% line-coverage floor
```

> CI runs `flutter test`, which never invokes Gradle — so Android-only
> breakage (plugin compatibility, minSdk, signing) is invisible until the
> release build. If you touch Android build config or add a plugin, verify with
> a real `flutter build apk --release`.

## Architecture

One narrow contract shapes everything: `InstrumentInput`
(`lib/domain/instrument/instrument_engine.dart`). Two ways to play a level
implement it and produce identical downstream behaviour (scoring, rewards,
analytics):

| Impl | Input |
| --- | --- |
| `KeyboardInstrument` | taps on the on-screen keyboard |
| `AcousticInstrument` | debounced pitch detections from the mic |

The layering, from `docs/wiki/Architecture.md`:

```
presentation   screens/ · widgets/ · theme/
composition    providers.dart (Riverpod) · main.dart
application    session/LevelSessionFlow · coaching/AcousticPracticeController
domain         pure Dart — instrument · keyboard · acoustic · coaching · piano ·
               content · gamification · analytics · audio   (no Flutter imports)
platform       record_mic_capture.dart — the only device-specific code
```

**The purity rule:** game logic under `lib/domain/` imports no Flutter. Only
three domain files touch any package — `content/content_repository.dart`
(`rootBundle`), `audio/audio_engine.dart` (`audioplayers`), and the two
`*Store` adapters (`shared_preferences`). Everything else is pure Dart, which
is why `test/domain/` mirrors `lib/domain/` file for file and CI needs no
device. Preserve this on every new file.

### Source layout

| Path | Purpose |
| --- | --- |
| `lib/domain/` | Pure-Dart game logic (instrument, acoustic, coaching, content, gamification, analytics, audio, piano, session, rhythm) |
| `lib/screens/` | Flutter screens (adventure map, level play, acoustic practice) |
| `lib/widgets/` | Reusable UI (piano keyboard, illustrated keyboard, lesson tiles) |
| `lib/theme/` | Shared Tama palette and `ThemeData` |
| `lib/providers.dart` | The whole Riverpod container (eight providers, no codegen) |
| `lib/platform/` | `MicCapture` device implementation (the `record` plugin) |
| `assets/content/lessons.json` | Lesson content (schema v2) — add songs here, no code |
| `assets/audio/notes/` | 61 WAVs, one per key of the 61-key board — struck-string samples (regenerate: `tools/generate_note_samples.py`) |
| `tools/` | Deterministic asset generators (note samples) |
| `test/` | Mirrors the `lib/` tree; larger than the code under test |

### Acoustic pipeline

```
MicCapture ─▶ MicAnalyzer ─▶ PitchDetector (NSDF) ─▶ AcousticInstrument (debounce)
                                                          ─▶ SongCoach ─▶ UI
```

The device mic is isolated behind the injectable `MicCapture` interface. Tests
inject `FakeMicCapture` (`test/support/fake_mic.dart`), which emits **synthetic
PCM bytes** — not notes — so the real decode → detect → debounce → coach loop
runs in CI without hardware. Tuning constants (`stableFramesRequired`,
`clarityThreshold`) are documented in
[`docs/wiki/Acoustic-coaching-pipeline.md`](../docs/wiki/Acoustic-coaching-pipeline.md).

Acoustic mode is **alpha-test only** until on-device live-mic validation and
calibration pass (`epic-2/on-device-validation`).

## Key conventions

- **Non-punitive semantics.** A miss holds the player on the current note
  (counts as an attempt, does not advance), so a level ends when the song is
  played through — never when taps run out. Runs fail on accuracy. Accuracy
  defaults to `1.0` at zero attempts; streaks reset to `1`, never below.
- **Reward economy.** First-completion-only payouts; currency is earned-only
  (no pay-to-win).
- **Privacy (COPPA / GDPR-K).** Analytics payloads use whitelisted keys only —
  no free text, no PII. Microphone audio is analysed on-device for pitch only;
  it is never stored or transmitted.
- **Persistence.** One bounded `SharedPreferences` blob per concern
  (`player_progress_v1`, `analytics_events_v1`, capped at 500 events). Both
  decode defensively: a corrupt blob yields fresh state rather than throwing.
- **Riverpod gotcha.** `PlayerProgress` is mutable but `StateNotifier` only
  notifies on identity change — always `clone()` → mutate → commit a fresh
  instance, or the UI silently won't rebuild.

## Dependencies of note

- `record ^6.1.2` (resolves 6.2.1), pinned to match Flutter 3.24.3.
- `record_android` is pinned to **1.3.3** via `dependency_overrides` — 1.4.0+
  needs Flutter 3.27+ and breaks the release APK build on 3.24.3. The override
  comment in `pubspec.yaml` explains when it can be removed.
- `Color.withValues` does **not** exist on Flutter 3.24.3 — use `withOpacity`.

## Testing

- `test/domain/**` — pure-Dart unit tests (the bulk of the suite; `package:test`).
- `test/screens/**`, `test/widgets/**` — `flutter_test` widget tests keyed off
  declared `Key(...)` values (e.g. `play-mode-real-keyboard`, `start-listening`).
- `test/support/fake_mic.dart` — synthetic PCM source for CI.
- `test/domain/content/shipped_song_library_test.dart` — content linter: fails
  CI if a song goes off the 61-key board or needs a note with no bundled WAV.

Known trap: broadcast streams deliver asynchronously, so after `press()` a
multi-touch test must `await Future.delayed(Duration.zero)` before asserting.

## Branding

Brand colors and the app icon come from Tama-Tama — see
[`docs/brand/README.md`](../docs/brand/README.md).

## Further reading

- [Wiki home](../docs/wiki/Home.md) — the app in one screen
- [Architecture](../docs/wiki/Architecture.md)
- [Acoustic coaching pipeline](../docs/wiki/Acoustic-coaching-pipeline.md)
- [Content, gamification, analytics](../docs/wiki/Content-gamification-analytics.md)
- [CI, release cascade, device build](../docs/wiki/CI-release-and-build.md)
- [`AGENTS.md`](../AGENTS.md) — repo conventions and the release cascade
