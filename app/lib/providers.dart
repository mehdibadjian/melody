import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/acoustic/mic_capture.dart';
import 'package:melody_app/domain/analytics/analytics_store.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/content/content_repository.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/gamification/progress_store.dart';
import 'package:melody_app/platform/record_mic_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('override in ProviderScope');
});

final progressStoreProvider = Provider<ProgressStore>((ref) {
  return ProgressStore(ref.watch(sharedPreferencesProvider));
});

final playerProgressProvider =
    StateNotifierProvider<PlayerProgressNotifier, PlayerProgress>((ref) {
  final store = ref.watch(progressStoreProvider);
  return PlayerProgressNotifier(store);
});

class PlayerProgressNotifier extends StateNotifier<PlayerProgress> {
  PlayerProgressNotifier(this._store) : super(_store.load());

  final ProgressStore _store;

  Future<void> _commit(PlayerProgress next) async {
    state = next;
    await _store.save(next);
  }

  Future<void> save() async {
    await _store.save(state);
  }

  void applyLevelCompletion({
    required String levelId,
    required RewardPayout payout,
    required double accuracy,
  }) {
    final next = state.clone();
    next.applyLevelCompletion(
      levelId: levelId,
      payout: payout,
      accuracy: accuracy,
    );
    _commit(next);
  }

  void claimDailyChest(DateTime day) {
    final next = state.clone();
    next.claimDailyChest(day);
    _commit(next);
  }

  /// Adopts a progress object mutated during a play session (e.g. by
  /// LevelSessionFlow) by re-emitting it as a fresh state instance.
  void commitSessionProgress(PlayerProgress sessionProgress) {
    _commit(sessionProgress.clone());
  }
}

final analyticsStoreProvider = Provider<AnalyticsStore>((ref) {
  return AnalyticsStore(ref.watch(sharedPreferencesProvider));
});

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  return const ContentRepository();
});

final lessonsProvider = FutureProvider((ref) {
  return ref.watch(contentRepositoryProvider).loadLessons();
});

final audioEngineProvider = Provider<AudioEngine>((ref) {
  // Real playback uses the bundled per-note WAVs (AssetAudioEngine); the
  // SynthAudioEngine double is test-only and silent in a shipped build.
  final engine = AssetAudioEngine();
  // Initialize off the synchronous path: audioplayers needs a platform
  // channel that is absent in tests, and audio must never crash the app.
  // On failure the engine stays uninitialized, so playNote is a safe no-op.
  engine.initialize().catchError((_) {});
  ref.onDispose(() => engine.dispose().catchError((_) {}));
  return engine;
});

/// Microphone capture for acoustic coaching. Overridden in tests with a fake
/// so the listen→detect→coach loop is CI-verified without a device mic.
final micCaptureProvider = Provider<MicCapture>((ref) {
  final capture = RecordMicCapture();
  ref.onDispose(() => capture.dispose());
  return capture;
});
