# AGENTS.md

Agent context for the **melody** repository.

## Repository

- **Working directory:** `/workspace/project/melody`
- **Remote:** `https://github.com/mehdibadjian/melody.git` (origin)
- **Default branch:** `main`
- **GitHub CLI is NOT installed** — use `git` and the GitHub REST API via `curl` with `$GITHUB_TOKEN`.

## Project

A children's music-learning app (ages 6–10) specified via a PRD
(`docs/planning/prd.md`). The Flutter app is implemented under `app/`:
- **Epic 1** (shippable core, `main`) — content schema, on-screen
  `KeyboardInstrument`, gamification, analytics, screens, widget tests.
- **Epic 2** (acoustic real-keyboard coaching, merged `88e38e7`) — the app
  listens through the microphone and coaches a child on a *real* electric
  piano. Tracked in `docs/stories/epic-2.md`; one open gate: on-device
  live-mic validation (`epic-2/on-device-validation`).

## Repository layout

- `.claude/` — Claude Code config:
  - `settings.json` — includes myloop hooks
  - `skills/` — skills: `loop-sweep`, `loop-resolve`, `loop-setup`,
    `create-prd`, `validate-prd`, `advanced-elicitation`, `agent-ux-designer`,
    `checkpoint-preview`, `documentation`
- `.myloop/` — dev-loop engine git submodule (`https://github.com/mehdibadjian/myLoop`) with pure Rust orchestrator binary at `.myloop/engine-rust/target/release/myloop`
- `.myloop-config/` — myLoop project configuration and artifact path mappings
  (`planning_artifacts` → `docs/planning`, `implementation_artifacts` →
  `docs/stories`, `project_knowledge` → `AGENTS.md`).
- `docs/` — planning and implementation artifacts:
  - `docs/planning/prd.md` — the PRD (source of truth for §refs).
  - `docs/implementation/implementation-plan.md` — v1 core + Epic 2 acoustic plan.
  - `docs/stories/sprint-status.yaml` — the tracking ledger (`epic-N/slug` keys,
    `tracking_system: file-system`).
  - `docs/stories/epic-2.md` + `docs/stories/epic-2/*.md` — Epic 2 stories
    (epic-1 predates story files; it is ledger-only).
- `app/` — the Flutter application (`melody_app`). See "Melody app build" below.
- `.gitignore` — ignores runtime state, caches, and OS metadata
- `AGENTS.md` — this file

## Conventions and workflow

- **Git history is linear; commit messages use Conventional Commits**
  (e.g. `chore:`, `feat:`, `docs:`).
- The user has approved direct pushes to `main` **only when explicitly stated**;
  otherwise use: build → push feature branch → PR → verify → merge.
- Never push directly to `main` unless the user explicitly asks.
- Use `git` (not `gh` — the GitHub CLI is not installed) for VCS operations;
  `git --no-pager` **works** in this environment (an earlier note claimed
  otherwise — that was wrong). For PR/issue operations use the GitHub REST API
  via `curl` with `$GITHUB_TOKEN` (read *and* write both work — see below).
- **Merging to `main` triggers a release cascade:** `release-please.yml`
  (`on: push: main`) reads Conventional Commit types and, on a `feat:`/`fix:`,
  cuts a version, opens/auto-merges a release PR, then dispatches `publish.yml`
  to build + attach a signed APK. The repo squash-merges, so the **squash
  commit title** is what release-please sees: a `feat:` title cuts a release; a
  `spike:`/`chore:` title does not. Choose the merge title deliberately.
- Draft PRs cannot be merged; un-draft via the GraphQL
  `markPullRequestReadyForReview` mutation before merging.

## Agent notes / learnings

- `git switch -c <branch>` for new branches; the repo tracks `origin/main` as HEAD.
- PRD revisions for this project reject Kotlin Multiplatform in favor of an
  alternative cross-platform approach; analytics schema and content-schema
  ownership are called out as their own workstreams.

## Melody app build (2026-09-25)

- Flutter app lives at `app/` (project `melody_app`, Flutter 3.24.3 stable,
  Dart ^3.5.3). Domain layer under `app/lib/domain/` is pure Dart (no Flutter
  imports) so all core logic is unit-testable; tests mirror the tree under
  `app/test/domain/`.
- Run tests: `cd app && flutter test`. Analyzer must stay clean (`flutter analyze`).
- Dev deps note: `flutter test` requires `test` package in dev_dependencies
  (scaffold only ships `flutter_test`; pure-Dart tests import `package:test`).
- Architecture decisions (PRD-mapped): `InstrumentInput` interface is the
  instrument-agnostic contract; `KeyboardInstrument` (on-screen) and
  `AcousticInstrument` (real keyboard via mic) are the concrete impls.
  Lesson content is data in `app/assets/content/lessons.json` validated by
  `ContentParser` (schema v2; still accepts v1). Analytics events have a
  whitelisted-key payload (COPPA/GDPR-K). Reward economy:
  first-completion-only payouts, currency earned-only (no pay-to-win).
- Non-punitive semantics: LessonSession advances past misses; accuracy
  defaults to 1.0 with zero attempts; streaks reset to 1 (never below).
- Multi-touch test gotcha: broadcast streams need `await Future.delayed(Duration.zero)` after `press()` before asserting.
- Remote operations WORK with the sandbox `GITHUB_TOKEN`: `git push` to a
  feature branch, the REST `pulls/<n>/merge` endpoint (squash), and GraphQL
  mutations (e.g. un-draft) all succeeded for PR #28 (merged `88e38e7`). An
  earlier note claimed the token lacked Contents:write and that push/PR creation
  returned 403 — that is no longer true. `origin` uses
  `https://x-access-token@github.com/...`; never log or echo the token.
- CI gate (`.github/workflows/ci.yml`, runs on `app/**`): `flutter pub get` →
  `dart format --set-exit-if-changed --output=none .` → `flutter analyze
  --fatal-infos` → `flutter test --coverage` → an 80% line-coverage floor
  (parsed from `coverage/lcov.info` LF/LH). Match this exactly before pushing;
  docs-only changes outside `app/**` do not trigger CI.
- **CI does NOT build an APK** (`ci.yml` runs `flutter test`, which never
  invokes Gradle). Android-only breakages — Gradle plugin compatibility,
  minSdk/manifest merge, signing — are invisible until `publish.yml` runs at
  release time. When you touch Android build config or add an Android plugin,
  verify with a real `flutter build apk --release` (the v1.6.0 publish failed
  this way; see `epic-2/android-release-build-fix`). Local repro: install Java
  17 + Android SDK 34 (Gradle wrapper 8.3 does not run on Java 21), then
  `flutter config --android-sdk <path> --jdk-dir <jdk17>` and build.
- Flutter SDK is at `/opt/flutter` in the sandbox (3.24.3 stable / Dart 3.5.3);
  add `/opt/flutter/bin` to `PATH`. `Color.withValues` does NOT exist on this
  version — use `withOpacity`.

## Epic 2 — acoustic real-keyboard coaching (2026-09-26)

- The app listens through the mic and coaches a child on a *real* keyboard.
  Architecture + stories: `docs/implementation/implementation-plan.md`
  ("Epic 2" section) and `docs/stories/epic-2.md`.
- **CI-testability seam:** the device mic is isolated behind the injectable
  `MicCapture` interface (`lib/domain/acoustic/mic_capture.dart`). Prod impl is
  `lib/platform/record_mic_capture.dart` (the `record` plugin — the *only*
  device-specific code, ~44 lines, intentionally 0% covered). Tests inject
  `FakeMicCapture` (`test/support/fake_mic.dart`) emitting **synthetic PCM**
  that flows through the real decode→detect→debounce→coach pipeline, so the
  whole loop is CI-verified without hardware.
- New domain areas (all pure Dart): `acoustic/` (pitch_detector NSDF,
  acoustic_instrument debounce, pcm_decoder, mic_analyzer), `coaching/`
  (coaching directional feedback, song_coach state machine,
  acoustic_practice_controller), `piano/piano_layout.dart` (note↔midi,
  61/76/88-key — only 61 renders today). UI: `widgets/illustrated_keyboard.dart`,
  `screens/acoustic_practice_screen.dart`; navigation via a play-mode chooser in
  `screens/adventure_map_screen.dart` (`PlayMode.realKeyboard` / `.onScreen`).
  `providers.dart` exposes `micCaptureProvider`.
- Content is schema **v2** (`ContentParser` still accepts v1): `Lesson` carries
  optional `songTitle`/`genre`/`attribution`; `Level.noteRange` derives the
  MIDI span. `assets/content/lessons.json` ships 11 public-domain songs across
  6 genres; `shipped_song_library_test.dart` guards board-fit + bundled audio.
- `record` is pinned to `^6.1.2` (resolves 6.2.1) to match Flutter 3.24.3 /
  Dart 3.5.3; 7.x requires a newer toolchain. `record_android` is additionally
  pinned to **1.3.3** via `dependency_overrides` — 1.4.0+ needs Flutter 3.27+
  (`compileSdk = flutter.compileSdkVersion`), which breaks the release APK build
  on 3.24.3. Android declares `RECORD_AUDIO`; app `minSdk = 23` (record needs
  it). iOS `NSMicrophoneUsageDescription` not yet added. See
  `epic-2/android-release-build-fix`.
- Released **v1.6.1** (PR #30) — the first release carrying a working APK for
  the acoustic feature (`melody-v1.6.1.apk`). v1.6.0 (the feature merge) built
  no APK due to the Android break above.
- Privacy (PRD §7): audio analysed on-device for pitch only; never stored or
  transmitted.
- **Open release gate:** on-device live-mic validation + calibration of
  `stableFramesRequired` / `clarityThreshold` (`epic-2/on-device-validation`).
  Until it passes, treat acoustic as alpha-test only.
