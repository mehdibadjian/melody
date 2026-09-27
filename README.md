# Tama Melody

A children's piano-learning app (ages 6–10) built with Flutter. Kids learn real
melodies through guided, game-like practice — either on the **on-screen
keyboard** or on a **real electric piano**, where the app listens through the
microphone and coaches every note.

The user-facing product name is **Tama Melody**; the repo and package
identifiers are `melody` / `melody_app`.

## Download

Get the latest signed Android APK from the
[releases page](https://github.com/mehdibadjian/melody/releases).

## What it does

- **Adventure map of lessons** — 12 songs across 7 genres, shipped as data
  (`app/assets/content/lessons.json`, content schema v2), so new songs do not
  require app releases.
- **Two play modes, one keyboard** — tap along on screen, or play a real
  keyboard while the app listens: mic → PCM → pitch detection (NSDF) →
  debounce → coaching feedback. Both modes render a window onto the same
  61-key board and share the same session/reward/analytics stack.
- **"Hear it" demo player** — a listen-first playback with metronome,
  available mid-run on both play screens.
- **Strictly non-punitive gamification** — a miss holds you on the current
  note; runs end on accuracy, never on running out of taps. Stars, note
  currency and cosmetics are earned-only (first-completion payouts, no
  pay-to-win).
- **Privacy by design (COPPA / GDPR-K)** — analytics payloads use whitelisted
  keys only, no free text, no PII. Microphone audio is analysed on-device for
  pitch only; it is never stored or transmitted.

## Status

Epic 1 (on-screen core) is shipped. Epic 2 (acoustic real-keyboard coaching)
is merged and code-complete, with one open gate: on-device live-mic validation
and calibration (`epic-2/on-device-validation`). Until that passes, treat
acoustic mode as **alpha-test only**.

## Repository layout

| Path | What lives there |
| --- | --- |
| `app/` | The Flutter application (`melody_app`) — see [`app/README.md`](app/README.md) |
| `docs/planning/prd.md` | The PRD — source of truth for *what to build* |
| `docs/wiki/` | Codebase wiki — source of truth for *how it works today* |
| `docs/implementation/` | Implementation plan (v1 core + Epic 2 acoustic) |
| `docs/stories/` | Epic/story files and the sprint-status ledger |
| `docs/brand/` | Tama brand colors, icon, and the mascot SVG |
| `AGENTS.md` | Agent context: conventions, release cascade, build notes |

## Development

Requires Flutter `3.24.3` stable (Dart `^3.5.3`).

```bash
cd app
flutter pub get
flutter test
flutter analyze
```

Acoustic mode needs a real device with a microphone; in CI and on simulators
the mic is faked with synthetic PCM, so the full listen-and-coach loop is
verified without hardware. Full details in [`app/README.md`](app/README.md)
and the [wiki](docs/wiki/Home.md).

## Releases

Releases are automated: a `feat:`/`fix:` squash-merge to `main` triggers
[release-please](https://github.com/googleapis/release-please), which cuts a
`vX.Y.Z` tag, and the publish workflow builds, signs, and attaches the Android
APK to the GitHub release. See
[docs/wiki/CI-release-and-build.md](docs/wiki/CI-release-and-build.md) for the
full chain and its known stall mode.

## Documentation

- [Wiki home](docs/wiki/Home.md) — the app in one screen
- [Architecture](docs/wiki/Architecture.md) — layering and the `InstrumentInput` contract
- [Acoustic coaching pipeline](docs/wiki/Acoustic-coaching-pipeline.md) — mic to UI, with tuning constants
- [Content, gamification, analytics](docs/wiki/Content-gamification-analytics.md)
