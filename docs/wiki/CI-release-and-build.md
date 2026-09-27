# CI, release cascade, device build

[← Home](Home.md)

Three workflows live in `.github/workflows/` (`ci.yml`, `release-please.yml`,
`publish.yml`). The chain from a merged PR to a downloadable APK is the single
most confusing part of this repo, so it is documented end-to-end here — including
the failure mode that has already bitten twice.

## CI (`ci.yml`) — the gate

Triggers: `pull_request` and `push: main`, **only when `app/**` or `ci.yml`
itself change**. A docs-only PR (including this wiki) runs no CI.

```
flutter pub get
→ dart format --set-exit-if-changed --output=none .
→ flutter analyze --fatal-infos
→ flutter test --coverage
→ coverage floor: 80 % line coverage from coverage/lcov.info (LF/LH)
```

Flutter is pinned to **3.24.3** here and in `publish.yml`. The format step is
part of the contract: run `dart format .` before pushing or CI fails on
whitespace, not logic. Everything runs with `working-directory: app`.

## The release cascade

```
 feat:/fix: PR squash-merged to main
   → release-please.yml (on: push: main)
       ├─ cuts a version, opens a release PR  (chore(main): release X.Y.Z)
       ├─ "Auto-merge release PRs on green CI": native --auto, else poll
       │  check-runs for 15 min and squash-merge when all green
       └─ on app--release_created → repository_dispatch "publish-release" {tag}
   → publish.yml
       ├─ build-android: tests → keystore (or debug fallback) → flutter build apk
       │  → verify signature → upload artifact
       └─ attach-to-release: gh release upload melody-<TAG>.apk
```

Two hops, and they break differently:

| Hop | Mechanism | Known break |
| --- | --- | --- |
| merge → release-please runs | `on: push: main` | **Recursion guard** — a PR merged by the bot's `GITHUB_TOKEN` does not fire `push: main`, so no version is cut at all |
| release created → publish runs | `repository_dispatch` | previously read the *root* `release_created` output instead of the path-scoped `app--release_created`, so it stayed skipped (v1.5.0, v1.5.1) |

The second is fixed in the workflow. The first is not fixable in YAML — it is a
GitHub behaviour — and it is why v1.6.2 and v1.6.3 both needed manual recovery.

### Cascade stall: symptoms and fix

All four symptoms together mean it, and nothing else, is wrong:

1. the release PR is already merged but still labelled `autorelease: pending`;
2. the version bump (manifest + `pubspec.yaml` + CHANGELOG) is already on `main`;
3. no `vX.Y.Z` tag or GitHub Release exists;
4. a ~4-second / 0-job `CI` run shows `failure` on the release-please branch
   (orphaned when its head branch was deleted by the merge).

**Preferred fix — re-fire the cascade in one step.** Merge the *next* stuck
release PR yourself over REST with your own `$GITHUB_TOKEN`:

```bash
curl -s -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/OWNER/REPO/pulls/N/merge \
  -d '{"merge_method":"squash"}'
# then flip the label: autorelease: pending → autorelease: tagged
```

An external-token merge is not recursion-guarded, so `push: main` fires,
release-please runs, the tag lands, publish dispatches, the APK builds.

**Fallback, when the release PR is already merged and there is nothing left to
merge** (this is how v1.6.2 was recovered): create the annotated tag via
`git/tags` + `git/refs` at the release-merge commit, and create the `releases`
entry so the attach step has a target. Pushing that ref fires `publish.yml`
through its `on: push: tags` trigger.

**Do not try `workflow_dispatch`** on either workflow — it returns
`403 Resource not accessible by integration`; the token lacks `actions:write`.

### Choose merge titles deliberately

This repo squash-merges, so release-please reads the **squash commit title
only**:

| Title prefix | Effect |
| --- | --- |
| `feat:` / `fix:` | cuts a release (minor / patch) |
| `chore:` / `docs:` / `spike:` | no release |
| `BREAKING CHANGE:` in the body | major |

That means a `docs(agents):` PR is inert, and an urgent one-line `fix:` carries
whatever else was in the PR. Squash a stack of unrelated work into one release
deliberately, not accidentally.

## Building the Android APK locally

`flutter test` never invokes Gradle, so **CI cannot see Android breakage** —
Gradle plugin compatibility, manifest merges, minSdk conflicts, signing all
surface only when `publish.yml` runs. That is exactly how v1.6.0 shipped with no
APK at all (`epic-2/android-release-build-fix`).

If you touch Android build config or add an Android plugin, verify with a real
release build:

```bash
# Java 17 required: the Gradle wrapper (8.3) will not run on Java 21.
flutter config --android-sdk <sdk-path> --jdk-dir <jdk17-path>
cd app && flutter build apk --release
```

Build facts:

| Item | Value |
| --- | --- |
| `applicationId` | `dev.melody.melody_app` |
| `minSdk` | 23 — forced by `record_android`; Flutter's default 21 fails |
| `compileSdk` / `targetSdk` | `flutter.compileSdkVersion` (Flutter injects) |
| Signing | `android/key.properties` → release keystore; absent → **debug fallback** |
| Permission | `RECORD_AUDIO` in `AndroidManifest.xml` |
| APK output | `app/build/app/outputs/flutter-apk/`, renamed `melody-<TAG>.apk` |

`publish.yml` asserts the signature: if a keystore secret exists and
`apksigner` still reports "Android Debug", the job fails rather than shipping a
mis-signed build.

### The `record_android` pin — do not "clean up"

`pubspec.yaml` carries a `dependency_overrides` entry pinning `record_android`
to **1.3.3**, and `record` itself to `^6.1.2` (resolves 6.2.1).

1.4.0+ declares `compileSdk = flutter.compileSdkVersion`, a property Flutter
only injects into plugin subprojects from **3.27+**. On 3.24.3 that property is
null, Gradle fails to evaluate `:record_android`, and the release build dies.
The override is protocol-safe (1.3.3's native code implements every method
platform_interface 1.6.0 calls) and is removable **only** when the toolchain
moves to Flutter 3.27+. Note also that `Color.withValues` does not exist on
3.24.3 — use `withOpacity`.

## Versioning plumbing

- `.release-please-manifest.json` → `{"app": "1.6.3"}` is the released truth.
- `release-please-config.json` → package path `app`, `release-type: dart`,
  `component: melody-app`, `include-component-in-tag: false` — which is why tags
  are `v1.6.3`, not `melody-app-v1.6.3`. (`publish.yml` still accepts both tag
  patterns.)
- Because the package is at path `app`, action outputs are **path-scoped**:
  `app--release_created`, `app--tag_name`. Root-level names are empty. They
  contain `--`, so shell access needs brackets.
- `app/CHANGELOG.md` is generated. Never hand-edit it.
- `dependabot.yml` covers **`github-actions` only** — there is no automation
  watching the pub dependencies, so `pubspec.yaml` pins drift silently.

## Repo conventions that affect CI

- Git history is linear, Conventional Commits, direct pushes to `main` only when
  explicitly asked for.
- GitHub CLI is **not installed** in the sandbox; use `git` plus the REST API via
  `curl` with `$GITHUB_TOKEN` (read and write both work). Never echo the token —
  `origin` already embeds it.
- Draft PRs cannot be merged; un-draft via the GraphQL
  `markPullRequestReadyForReview` mutation first.

## Release readiness checklist

1. `cd app && dart format . && flutter analyze --fatal-infos && flutter test`
   — all green, coverage ≥ 80 %.
2. Touched Android config or an Android plugin? Run a real
   `flutter build apk --release`.
3. Added or edited a song? The library test must pass (61-key board + bundled
   WAV coverage).
4. Intentional release? Confirm the squash title starts with `feat:` or `fix:`.
5. After merge: watch for the four stall symptoms above. No tag within a few
   minutes means apply the one-command fix, don't re-diagnose.
6. Outstanding: `epic-2/on-device-validation` gates acoustic mode; iOS needs
   `NSMicrophoneUsageDescription` before any Apple build.
