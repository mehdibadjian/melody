# Epic 2 · Story 13 — Android Release-Build Fix

**Status:** done
**Commit:** `caa2c15` — `fix(android): build release APK on Flutter 3.24.3 (pin record_android 1.3.3, minSdk 23)`
**PR:** [#30](https://github.com/mehdibadjian/melody/pull/30) → released **v1.6.1**
**Story key:** `epic-2/android-release-build-fix`

## Why this story exists

Merging the acoustic feature (PR #28) cut release **v1.6.0**, whose
`publish.yml` → `build-android` job **failed** at `flutter build apk
--release` — so v1.6.0 shipped with **no APK**. The feature looked green in CI
because `ci.yml` runs `flutter test`, which **never invokes Gradle**; only
`publish.yml` builds an APK. This story fixes the release build so a testable
artifact exists (a prerequisite for story 12).

The failure:

```
A problem occurred evaluating project ':record_android'.
> Could not get unknown property 'flutter' for extension 'android'
```

## Root cause

`record_android ≥1.4.0` declares `compileSdk = flutter.compileSdkVersion`. That
`flutter` extension is injected into **plugin** subprojects only from Flutter
**3.27+**. This repo is pinned to Flutter **3.24.3**, so the property is null
and Gradle cannot evaluate the plugin module. A second, latent failure sat
behind it: `record_android` requires `minSdk 23`, but the app used Flutter's
default `minSdk 21` → manifest merge would fail next.

Only the newly added `record` plugin used the 3.27-only syntax; audioplayers
(`compileSdk 35`), shared_preferences (`34`) and path_provider (`34`) all use
literals — which is why every prior release built an APK fine.

## Fix

1. **Pin `record_android` to `1.3.3`** via `dependency_overrides` in
   `pubspec.yaml` — the last version using a literal `compileSdk = 34`.
   `record_android` is **native-only** (no Dart), so the only contract is the
   method channel; verified 1.3.3's native handler covers every method
   `record_platform_interface` 1.6.0 invokes (`create` / `start` /
   `startStream` / `stop` / `hasPermission` / …) with matching arg keys, so
   `record` 6.2.1 and the Dart adapter (`RecordMicCapture`) are unchanged.
   Remove the override once the toolchain moves to Flutter 3.27+.
2. **`minSdk = 23`** in `android/app/build.gradle` (was `flutter.minSdkVersion`
   = 21).

## Acceptance criteria

- [x] `flutter build apk --release` succeeds on the pinned Flutter 3.24.3.
- [x] No `record_android` / "unknown property 'flutter'" Gradle errors.
- [x] Dart side unchanged: `dart format` clean · `flutter analyze
      --fatal-infos` clean · 217 tests pass.
- [x] A release-signed APK is produced and attached to the GitHub release.

## Verification

- **Local repro of the exact failing command:** provisioned Java 17 + Android
  SDK 34 and ran `flutter build apk --release` → `✓ Built app-release.apk
  (44.5MB)`, zero `record_android` errors.
- **Real CI:** merging PR #30 cut **v1.6.1**; `publish.yml` `build-android`
  → success (Build release APK · Verify APK signature · Upload · Attach all
  green). Release v1.6.1 carries `melody-v1.6.1.apk` (44.5 MB, release-signed).

## Lesson (carried into AGENTS.md)

`ci.yml` does not build an APK, so Android-only breakages (Gradle plugin
compatibility, minSdk/manifest merge, signing) are invisible until
`publish.yml` runs at release time. Android build config changes need a real
`flutter build apk --release` check, not just `flutter test`.
