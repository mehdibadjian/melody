import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_repository.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/gamification/progress_store.dart';
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

  Future<void> save() async {
    await _store.save(state);
  }

  void applyLevelCompletion({
    required String levelId,
    required dynamic payout,
    required double accuracy,
  }) {
    state.applyLevelCompletion(
      levelId: levelId,
      payout: payout,
      accuracy: accuracy,
    );
    save();
  }
}

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  return const ContentRepository();
});

final lessonsProvider = FutureProvider((ref) {
  return ref.watch(contentRepositoryProvider).loadLessons();
});

final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = SynthAudioEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});
