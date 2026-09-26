import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> makeContainer() async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  }

  group('PlayerProgressNotifier state emission', () {
    test('applyLevelCompletion emits a NEW state instance', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      final before = container.read(playerProgressProvider);
      final emitted = <PlayerProgress>[];
      final sub = container.listen(
          playerProgressProvider, (_, next) => emitted.add(next));
      addTearDown(sub.close);

      container.read(playerProgressProvider.notifier).applyLevelCompletion(
            levelId: 'level-001-a',
            payout: const RewardPayout(stars: 3, noteCurrency: 5),
            accuracy: 1.0,
          );

      final after = container.read(playerProgressProvider);

      expect(after, isNot(same(before)));
      expect(emitted, isNotEmpty);
      expect(emitted.last, same(after));
      expect(after.stars, 3);
      expect(after.noteCurrency, 5);
    });

    test('claimDailyChest emits a NEW state instance and grants currency',
        () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      final before = container.read(playerProgressProvider);
      final emitted = <PlayerProgress>[];
      final sub = container.listen(
          playerProgressProvider, (_, next) => emitted.add(next));
      addTearDown(sub.close);

      container
          .read(playerProgressProvider.notifier)
          .claimDailyChest(DateTime.utc(2026, 9, 21));

      final after = container.read(playerProgressProvider);

      expect(after, isNot(same(before)));
      expect(emitted, isNotEmpty);
      expect(after.dailyChestStreak, 1);
      expect(after.noteCurrency, 2);
      expect(before.noteCurrency, 0);
    });

    test('commitSessionProgress adopts session mutations as new state',
        () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      final before = container.read(playerProgressProvider);
      final sessionCopy = before.clone();
      sessionCopy.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: const RewardPayout(stars: 3, noteCurrency: 5),
        accuracy: 1.0,
      );
      sessionCopy.recordPracticeDay(DateTime.utc(2026, 9, 20));
      sessionCopy.recordNoteMastery('C4', hit: true);

      final emitted = <PlayerProgress>[];
      final sub = container.listen(
          playerProgressProvider, (_, next) => emitted.add(next));
      addTearDown(sub.close);

      container
          .read(playerProgressProvider.notifier)
          .commitSessionProgress(sessionCopy);

      final after = container.read(playerProgressProvider);

      expect(after, isNot(same(before)));
      expect(after, isNot(same(sessionCopy)));
      expect(emitted, isNotEmpty);
      expect(after.stars, 3);
      expect(after.noteCurrency, 5);
      expect(after.currentStreak, 1);
      expect(after.masteryHits('C4'), 1);
    });
  });
}
