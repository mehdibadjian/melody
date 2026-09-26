import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:test/test.dart';

void main() {
  group('PlayerProgress.clone (immutable state emission)', () {
    test('clone produces a distinct instance with equal serialized state', () {
      final original = PlayerProgress.initial();
      original.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: const RewardPayout(stars: 3, noteCurrency: 5),
        accuracy: 1.0,
      );
      original.recordPracticeDay(DateTime.utc(2026, 9, 20));

      final copy = original.clone();

      expect(copy, isNot(same(original)));
      expect(copy.toJson(), original.toJson());
    });

    test('mutating a clone does not affect the original', () {
      final original = PlayerProgress.initial();
      final copy = original.clone();

      copy.applyLevelCompletion(
        levelId: 'level-002-a',
        payout: const RewardPayout(stars: 2, noteCurrency: 4),
        accuracy: 1.0,
      );
      copy.recordNoteMastery('C4', hit: true);

      expect(original.stars, 0);
      expect(original.noteCurrency, 0);
      expect(original.completedLevelIds, isEmpty);
      expect(original.masteryHits('C4'), 0);
    });

    test('clone preserves streaks, chest claims, and cosmetics', () {
      final original = PlayerProgress.initial();
      original.recordPracticeDay(DateTime.utc(2026, 9, 20));
      original.recordPracticeDay(DateTime.utc(2026, 9, 21));
      original.claimDailyChest(DateTime.utc(2026, 9, 21));
      original.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: const RewardPayout(stars: 3, noteCurrency: 5),
        accuracy: 1.0,
      );
      original.purchaseCosmetic('hat-party', costNoteCurrency: 2);

      final copy = original.clone();

      expect(copy.currentStreak, 2);
      expect(copy.dailyChestStreak, 1);
      expect(copy.canClaimDailyChest(DateTime.utc(2026, 9, 21)), isFalse);
      expect(copy.canClaimDailyChest(DateTime.utc(2026, 9, 22)), isTrue);
      expect(copy.ownedCosmeticIds, {'hat-party'});
      // 2 (chest) + 5 (level) − 2 (cosmetic) = 5
      expect(copy.noteCurrency, 5);
    });
  });
}
