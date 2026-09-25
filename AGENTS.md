# AGENTS.md

Agent context for the **melody** repository.

## Repository

- **Working directory:** `/workspace/project/melody`
- **Remote:** `https://github.com/mehdibadjian/melody.git` (origin)
- **Default branch:** `main`
- **GitHub CLI is NOT installed** — use `git` and the GitHub REST API via `curl` with `$GITHUB_TOKEN`.

## Project

A children's music-learning app (ages 6–10) specified via a PRD. No application
code exists yet — the repo currently contains only dev-loop tooling and settings.

## Repository layout

- `.claude/` — Claude Code config:
  - `settings.json` — includes myloop hooks
  - `skills/` — skills: `loop-sweep`, `loop-resolve`, `loop-setup`,
    `create-prd`, `validate-prd`, `advanced-elicitation`, `agent-ux-designer`,
    `checkpoint-preview`, `documentation`
- `.myloop/` — dev-loop engine git submodule (`https://github.com/mehdibadjian/myLoop`) with pure Rust orchestrator binary at `.myloop/engine-rust/target/release/myloop`
- `.myloop-config/` — myLoop project configuration and artifact path mappings
- `docs/` — planning and implementation artifacts (`docs/planning/`, `docs/stories/sprint-status.yaml`)
- `.gitignore` — ignores runtime state, caches, and OS metadata
- `AGENTS.md` — this file

## Conventions and workflow

- **Git history is linear; commit messages use Conventional Commits**
  (e.g. `chore:`, `feat:`, `docs:`).
- The user has approved direct pushes to `main` **only when explicitly stated**;
  otherwise use: build → push feature branch → PR → verify → merge.
- Never push directly to `main` unless the user explicitly asks.
- Use `git` (not `gh`) for VCS operations; `git --no-pager` is not supported in
  this environment — use plain `git` commands.

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
  instrument-agnostic contract; `KeyboardInstrument` is v1 concrete impl.
  Lesson content is data in `app/assets/content/lessons.json` validated by
  `ContentParser` (schema v1). Analytics events have a whitelisted-key
  payload (COPPA/GDPR-K). Reward economy: first-completion-only payouts,
  currency earned-only (no pay-to-win).
- Non-punitive semantics: LessonSession advances past misses; accuracy
  defaults to 1.0 with zero attempts; streaks reset to 1 (never below).
- Multi-touch test gotcha: broadcast streams need `await Future.delayed(Duration.zero)` after `press()` before asserting.
- `git --no-pager` unsupported claim in this env: actually `git --no-pager`
  works here; plain commands are fine.
- Push limitation: sandbox `GITHUB_TOKEN` is a GitHub App installation token
  without Contents:write on this repo — `git push` (403) and API branch/PR
  creation ("Resource not accessible by integration") both fail. Read-only
  API access works. A PAT with repo scope or App permission change is needed
  for remote operations.
