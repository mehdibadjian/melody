# Architecture

[← Home](Home.md)

## The one idea that shapes everything

There are two ways a child can play a level — tap the glass, or play a **real**
electric piano while the app listens. Both must produce the same downstream
behaviour (scoring, rewards, analytics), and only one of them can be tested
without hardware.

The answer is a single narrow contract, `InstrumentInput`
(`app/lib/domain/instrument/instrument_engine.dart:7`):

```dart
abstract interface class InstrumentInput {
  Stream<NoteEvent> get noteStream;
  EvaluationResult evaluate(NoteEvent event);
  LessonSession startSession(List<String> expectedNotes);
  void setTarget(String note, {int sinceMs});
}
```

Two implementations exist today:

| Impl | Input | File |
| --- | --- | --- |
| `KeyboardInstrument` | taps on the on-screen keyboard | `app/lib/domain/keyboard/keyboard_instrument.dart:27` |
| `AcousticInstrument` | debounced pitch detections from the mic | `app/lib/domain/acoustic/acoustic_instrument.dart:22` |

A third (MIDI, PRD §6.3) is deferred, not missing: adding it means one new class
that implements this interface. Nothing above it changes.

## Layering

```
┌─ presentation ──────────────────────────────────────────────────────┐
│ screens/  adventure_map · level_play · acoustic_practice            │
│ widgets/  piano_keyboard · illustrated_keyboard · lesson_quest_tile │
│ theme/    tama_theme — the shared Tama palette + ThemeData          │
├─ composition ───────────────────────────────────────────────────────┤
│ providers.dart   Riverpod providers        main.dart  app bootstrap │
├─ application ───────────────────────────────────────────────────────┤
│ session/    LevelSessionFlow  (drives one on-screen level run)      │
│ coaching/   AcousticPracticeController (drives one listening run)   │
├─ domain (pure Dart, no Flutter) ────────────────────────────────────┤
│ instrument/  InstrumentInput · LessonSession · NoteEvent            │
│ keyboard/    KeyboardInstrument   acoustic/  detector·debounce·pcm  │
│ coaching/    coach() · SongCoach  piano/     note↔MIDI · layouts     │
│ content/     models · parser · repository                           │
│ gamification/ player_progress · progress_store                     │
│ analytics/    analytics_event · analytics_store                     │
│ audio/        AudioEngine (asset + test synth)                      │
├─ platform ──────────────────────────────────────────────────────────┤
│ platform/record_mic_capture.dart   44 lines — the ONLY device code   │
└─────────────────────────────────────────────────────────────────────┘
```

The purity rule that keeps this honest: **the game logic under `domain/` imports
no Flutter.** Concretely, only three domain files touch any package at all —
`content/content_repository.dart` (`rootBundle`, to read the bundled JSON),
`audio/audio_engine.dart` (`audioplayers`), and the two `*Store` persistence
adapters (`shared_preferences`). Everything else — detection, coaching,
scoring, gamification, analytics, piano geometry — is pure Dart with no plugin
dependency, which is why `app/test/domain/` mirrors `app/lib/domain/` file for
file and why CI needs no device. The rule is worth preserving on every new file.

## Two runtimes, one outcome

**On-screen (`LevelPlayScreen`)** builds a `LevelSessionFlow`
(`app/lib/domain/session/level_session_flow.dart:10`). Each tap is pushed
through `submit()` (`:47`), which asks the session what note it is holding the
child on (`LessonSession.nextExpectedNote`), records per-note mastery for *that*
note, and moves the instrument's target to the next one. A miss does not advance,
so the run ends when the song has been played through, never when taps have run
out. Then `_finish()`: pass/fail against the level's `SuccessThreshold`, a
`practiceSession` analytics event always, a `levelCompleted` event plus payout
only on a pass.

**Acoustic (`AcousticPracticeScreen`)** builds an `AcousticPracticeController`
(`app/lib/domain/coaching/acoustic_practice_controller.dart:68`). It does *not*
use `LevelSessionFlow` — the two stacks are separate code — but the rule is now
the same on both paths: a wrong note **holds** the child where they are until
they land it. It used to be the one difference between the modes, which meant the
same mistake was forgiven in one and cost the rest of the song in the other.
Both end at the same place — `applyLevelCompletion` + `recordPracticeDay`
on a `PlayerProgress` clone, then `commitSessionProgress`.

The screen-level pattern is identical in both: `initState` clones progress out
of the provider, the run mutates the clone, `dispose`/completion writes it back
as a fresh instance.

## State management

`app/lib/providers.dart` is the whole container — eight providers, no codegen:

| Provider | Kind | Notes |
| --- | --- | --- |
| `sharedPreferencesProvider` | `Provider` | `throw UnimplementedError` — must be overridden in `main()` |
| `progressStoreProvider` / `analyticsStoreProvider` | `Provider` | thin prefs wrappers |
| `playerProgressProvider` | `StateNotifierProvider` | see below |
| `contentRepositoryProvider` / `lessonsProvider` | `Provider` / `FutureProvider` | JSON loaded once, `AsyncValue` in the UI |
| `audioEngineProvider` | `Provider` | `AssetAudioEngine`, initialized off the sync path |
| `micCaptureProvider` | `Provider` | the seam tests override with `FakeMicCapture` |

Two gotchas worth knowing before you touch this file:

1. **`PlayerProgress` is mutable, Riverpod is not.** `StateNotifier` only
   notifies when the instance identity changes, so every mutation path goes
   through `clone()` → mutate → `_commit(next)` (`providers.dart:31`). Adding a
   setter that mutates in place will silently fail to rebuild the UI.
2. **Audio must never crash the app.** `engine.initialize()` is called with
   `.catchError((_) {})` off the synchronous path (`providers.dart:86`), because
   `audioplayers` needs a platform channel that does not exist under
   `flutter test`. On failure the engine stays uninitialized and `playNote`
   becomes a safe no-op. The same reasoning applies to `onDispose`.

## Persistence

Everything is one `SharedPreferences` blob per concern, no database:

| Key | Content | Owner |
| --- | --- | --- |
| `player_progress_v1` | JSON `PlayerProgress` | `gamification/progress_store.dart` |
| `analytics_events_v1` | JSON list, capped at 500 events | `analytics/analytics_store.dart` |

Both decode defensively: a corrupt blob yields a fresh initial state (or an
empty list) rather than an exception, so a bad write can never soft-brick a
child's app. The analytics buffer is deliberately bounded — prefs loads the
entire blob into memory on every launch, so an unbounded list would slowly
degrade startup (that was the v1.5.2 fix).

## Testing strategy

- `test/domain/**` — pure-Dart unit tests, the bulk of the suite.
- `test/screens/**`, `test/widgets/**` — `flutter_test` widget tests, keyed off
  `Key('...')` values the screens declare on purpose (`daily-chest-button`,
  `play-mode-real-keyboard`, `start-listening`, `result-toast`).
- `test/support/fake_mic.dart` — emits **synthetic PCM bytes**, not notes, so
  the real decoder, detector, and debounce layers all execute in CI.
- `test/domain/content/shipped_song_library_test.dart` — reads the actual
  `assets/content/lessons.json` and fails CI if a song goes off the 61-key board
  or asks for a note with no bundled WAV. Content is authored by hand, so this
  is the content linter.
- `test/domain/audio/note_sample_quality_test.dart` — decodes the bundled WAVs
  and fails if they are not piano-like: no harmonics above the second, one fixed
  envelope for every pitch, or no decay. The first 61 samples were two-partial
  sine tones that were perfectly in tune and passed every test that existed, so
  this measures the audio rather than trusting that a file is present.
- `test/domain/audio/sustain_fills_held_slots_test.dart` — ties the authored
  `durations` to the sample decay. The demo engine is monophonic and never
  re-triggers a held note, so a note written to last four beats only sounds for
  four beats if its WAV is audible that long. Onsets and pitch were both correct
  while every held cadence note still went silent mid-slot — the two halves pass
  in isolation and only fail together, which is what this test exists to catch.
- `test/domain/acoustic/detector_on_bundled_samples_test.dart` — runs the real
  `PitchDetector` over the real note samples, the only place those two meet. A
  richer timbre can fool an NSDF detector into a sub-octave error even while
  sounding better, so this pins detection, cents error, and clarity headroom.

Known trap: broadcast streams deliver asynchronously, so a multi-touch test must
`await Future.delayed(Duration.zero)` after `press()` before asserting.

## Where to make a change

| Want to… | Touch |
| --- | --- |
| Add a song | `app/assets/content/lessons.json` only — no code |
| Add an instrument (MIDI, guitar) | new `InstrumentInput` impl + tests |
| Change coaching wording | `domain/coaching/coaching.dart` (`_distanceHint`, messages) |
| Change pitch-tracking feel | tuning constants — see [Acoustic pipeline](Acoustic-coaching-pipeline.md) |
| Add a reward rule | `domain/gamification/player_progress.dart` + its serialization tests |
| Add a screen | file in `lib/screens/`, wire through `_choosePlayMode` in `adventure_map_screen.dart` |
| Add persisted state | new prefs key; keep it bounded |
