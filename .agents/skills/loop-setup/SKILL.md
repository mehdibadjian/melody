---
name: 'loop-setup'
description: Sets up the myloop automation module in a project. Use when the user requests to 'install myloop module', 'configure myloop', or 'setup the myloop loop'.
---

# Module Setup

## Overview

Installs, configures, **and upgrades** the myloop module in a project.

This module is unusual: alongside its automation skills it relies on the **myloop orchestrator** — a pure-Rust binary, no runtime dependency (no Node, no `uv`) — built from the same repository's `engine-rust/` subdirectory. The skills do nothing on their own.

There is no separate package-manager install step for the skills themselves: a project typically gets them (this skill included) via `myloop init`'s own bundling (see step 2 below), or by vendoring [myLoop](https://github.com/mehdibadjian/myLoop) directly (e.g. as a git submodule). Either way, this skill's job is:

1. Build **or rebuild** the orchestrator binary.
2. Run `myloop init` to register hooks, lay down the bundled skills, and write `.myloop-runtime/policy.toml` + gitignore entries.
3. Preflight with `myloop validate`.

Module identity (name, code, version) comes from `./assets/module.yaml`.

`{project-root}` is a **literal token** in config _values_ — never substitute it there. **This does not apply to the filesystem path _arguments_ in the commands below**: those are real paths, so resolve `{project-root}` to the actual project root before running.

## On Activation

1. Read `./assets/module.yaml` for module metadata (the `code` field is the module identifier).
2. Check whether `{project-root}/.myloop-config/` exists — this project's own config (see the [myLoop README](https://github.com/mehdibadjian/myLoop) for its layout). If it does not, say so, and note that the automation skills expect one; setup can still build/locate the orchestrator binary.

**Decide fresh-install vs upgrade.** This drives whether the per-project skills are refreshed. Treat it as an **upgrade** when either holds:

- The user asked for one in their arguments — `upgrade`, `update`, `upgrade tool and skills`, or similar.
- A `myloop` binary is already reachable (on PATH, or already built at `{project-root}/.myloop/engine-rust/target/release/myloop` for a submodule checkout).

Otherwise it is a **fresh install**. State the decision to the user before proceeding — e.g. "Detected an existing myloop install — running an upgrade: rebuild + refresh skills" or "No existing install detected — running a fresh setup".

If the user provides arguments (e.g. `accept all defaults`, `--headless`, `upgrade`), use them and skip interactive prompting. Still display the full confirmation summary at the end.

## Build the Orchestrator Binary

The orchestrator is what spawns fresh `claude` sessions to invoke `build-auto` (the upstream dev primitive) for the dev pass — then re-invokes it on the `done` spec for the follow-up review pass — and `loop-sweep`, watches their hook signals, and verifies their artifacts. Building it is therefore part of setup, not an optional extra. It's a single static binary with no runtime dependency (no Node, no `uv` — just `cargo`).

> **Why a build step, not a package install?** A project vendoring myLoop's skills only carries the `skills/` directory — the orchestrator is a separate Cargo crate, published from the same repo's `engine-rust/` subdirectory so both stay versioned together. There's no published binary release to fetch; building from source is the only path today. (The reverse holds, though: the built binary **bundles** `loop-resolve`/`loop-sweep`/`loop-setup`, so `myloop init` lays them down into a project's skill tree on its own — see step 2.)

Unless the user explicitly asked to skip it (e.g. `skills only` / `--no-tool`), build **or rebuild** and bootstrap now. Resolve `{project-root}` to the real project path before running.

1. **Check what's already on PATH or built.** Try `myloop --version`. If that fails, look for a submodule checkout at `{project-root}/.myloop/engine-rust` (or wherever this pack is vendored) and build it:

   ```bash
   cd {project-root}/.myloop/engine-rust && cargo build --release
   ```

   The binary lands at `{project-root}/.myloop/engine-rust/target/release/myloop`; put it on `PATH` or reference it by that path for the remaining steps.

2. **Upgrade** (rebuild after pulling a newer submodule commit):

   1. Record the current version first so you can report the delta: `myloop --version`.
   2. Pull the submodule to the commit/tag you want (`git -C {project-root}/.myloop fetch && git -C {project-root}/.myloop checkout <ref>`), then rebuild: `cargo build --release` in `engine-rust/`.
   3. Re-run `myloop --version` and note the before → after for the confirmation step.

3. **Bootstrap the project** — register the `claude` hooks, install the bundled `myloop-*` skills, write the `.myloop-runtime/policy.toml` template, and the gitignore entry (idempotent). **On an upgrade, add `--force-skills`** so the per-project skill copies are actually refreshed — without it `init` skips every existing skill dir and the project keeps stale skills against the upgraded binary. On a fresh install, omit it.

   ```bash
   # fresh install
   myloop init --project "{project-root}"

   # upgrade — refresh the bundled skills in place
   myloop init --project "{project-root}" --force-skills
   ```

   `init` prints a one-time first-run note: start `claude` once in the project and accept the workspace-trust + hooks-approval dialogs before `myloop run` — spawned sessions can't answer first-run dialogs. Relay that note to the user.

   **Skills are installed automatically:** `init` lays the bundled `myloop-*` skills into `.claude/skills/`. On a fresh install, existing skill dirs are left untouched; on an upgrade, `--force-skills` overwrites them with the bundled copies from the upgraded binary.

   > **Note:** `--force-skills` also overwrites `loop-setup` itself (it ships in the same bundle). That's expected and safe — the freshly laid-down setup skill takes effect on the **next** invocation, and your `.myloop-config/custom/*.toml` overrides (keyed by skill directory name) are untouched.

4. **Preflight** — verify config, sprint-status, git, and hook registration:

   ```bash
   myloop validate --project "{project-root}"
   ```

   `validate` exits non-zero when the project isn't fully ready (e.g. no `sprint-status.yaml` yet, or `sprint-planning` hasn't run). On a fresh project that is **expected** — report its findings to the user as a readiness checklist, not as an install failure.

5. **Note the adapter limit.** `{project-root}/.myloop-runtime/policy.toml` (written by `init`) has an `[adapter]` table with optional per-stage `[adapter.dev]`/`[adapter.review]`/`[adapter.triage]` overrides, but today `myloop run` only ever drives `claude` regardless of what's configured there — the other CLI dialects (codex, gemini, copilot, antigravity) aren't wired up yet (see `engine-rust/README.md`'s "Not built yet" section for current status). Leave `policy.toml`'s adapter table at its default; don't promise the user a mixed-CLI setup works today.

## Confirm

Report:

- **Fresh install:** the built `myloop --version`, that `myloop init` registered `claude` hooks, installed the `myloop-*` skills, and wrote policy/gitignore.
- **Upgrade:** the before → after `myloop --version` (e.g. "upgraded 0.3.1 → 0.3.2", or "already current at 0.3.2"), and that the `myloop-*` skills were **refreshed** (not skipped) with `--force-skills`.

Also report:

- The `myloop validate` preflight result (pass, or the readiness checklist of what's still missing).

Then display the `module_greeting` from `./assets/module.yaml` to the user.

## Outcome

Use the user's configured name and language for the remainder of the session. Read them from this project's central config via its own resolver (four-layer TOML merge):

```bash
myloop config resolve --project-root "{project-root}" --key core
```

Take `user_name` and `communication_language` from the `core` table. If this fails, fall back to addressing the user neutrally in English — do not write or repair any config file.
