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
