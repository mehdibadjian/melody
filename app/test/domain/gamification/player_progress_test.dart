import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:test/test.dart';

void main() {
  const payout = RewardPayout(stars: 3, noteCurrency: 5);

  group('PlayerProgress — reward economy (PRD §6: cosmetics only)', () {
    test('level completion awards stars and note currency', () {
      final progress = PlayerProgress.initial();
      progress.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      expect(progress.stars, 3);
      expect(progress.noteCurrency, 5);
      expect(progress.completedLevelIds, contains('level-001-a'));
    });

    test(
        'completing a level twice does not double-award (first completion only)',
        () {
      final progress = PlayerProgress.initial();
      progress.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      progress.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 1.0,
      );
      expect(progress.stars, 3);
      expect(progress.noteCurrency, 5);
    });

    test('cosmetic purchase spends note currency', () {
      final progress = PlayerProgress.initial();
      progress.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      progress.purchaseCosmetic('mascot-hat-blue', costNoteCurrency: 4);
      expect(progress.noteCurrency, 1);
      expect(progress.ownedCosmeticIds, contains('mascot-hat-blue'));
    });

    test('purchase fails without sufficient currency (no pay-to-win)', () {
      final progress = PlayerProgress.initial();
      expect(
        () => progress.purchaseCosmetic('mascot-hat-gold', costNoteCurrency: 4),
        throwsA(isA<InsufficientCurrencyException>()),
      );
      expect(progress.ownedCosmeticIds, isEmpty);
    });

    test('cannot purchase the same cosmetic twice', () {
      final progress = PlayerProgress.initial();
      progress.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      progress.purchaseCosmetic('mascot-hat-blue', costNoteCurrency: 1);
      expect(
        () => progress.purchaseCosmetic('mascot-hat-blue', costNoteCurrency: 1),
        throwsA(isA<AlreadyOwnedException>()),
      );
    });
  });

  group('PlayerProgress — notes mastered', () {
    test('records mastered notes as hit counts accumulate', () {
      final progress = PlayerProgress.initial();
      progress.recordNoteMastery('C4', hit: true);
      progress.recordNoteMastery('C4', hit: true);
      progress.recordNoteMastery('C4', hit: false);
      expect(progress.masteryHits('C4'), 2);
      expect(progress.masteryMisses('C4'), 1);
      expect(progress.notesMastered, isEmpty);
    });

    test('a note is mastered at 5 successful hits', () {
      final progress = PlayerProgress.initial();
      for (var i = 0; i < 4; i++) {
        progress.recordNoteMastery('D4', hit: true);
      }
      expect(progress.notesMastered, isEmpty);
      progress.recordNoteMastery('D4', hit: true);
      expect(progress.notesMastered, contains('D4'));
    });
  });

  group('PlayerProgress — streaks & daily chest (low-pressure, PRD §6)', () {
    test('streak increments when practicing on consecutive days', () {
      final progress = PlayerProgress.initial();
      progress.recordPracticeDay(DateTime.utc(2026, 9, 20));
      progress.recordPracticeDay(DateTime.utc(2026, 9, 21));
      expect(progress.currentStreak, 2);
    });

    test('streak resets after a skipped day', () {
      final progress = PlayerProgress.initial();
      progress.recordPracticeDay(DateTime.utc(2026, 9, 20));
      progress.recordPracticeDay(DateTime.utc(2026, 9, 22));
      expect(progress.currentStreak, 1);
    });

    test('practicing twice the same day does not inflate streak', () {
      final progress = PlayerProgress.initial();
      progress.recordPracticeDay(DateTime.utc(2026, 9, 20));
      progress.recordPracticeDay(DateTime.utc(2026, 9, 20));
      expect(progress.currentStreak, 1);
    });

    test('daily chest claimable once per day', () {
      final progress = PlayerProgress.initial();
      final day = DateTime.utc(2026, 9, 21);
      expect(progress.canClaimDailyChest(day), isTrue);
      progress.claimDailyChest(day);
      expect(progress.canClaimDailyChest(day), isFalse);
      expect(progress.canClaimDailyChest(DateTime.utc(2026, 9, 22)), isTrue);
    });

    test('daily chest grants reward and resets if a day is skipped', () {
      final progress = PlayerProgress.initial();
      final day = DateTime.utc(2026, 9, 21);
      progress.claimDailyChest(day);
      expect(progress.dailyChestStreak, 1);
      progress.claimDailyChest(DateTime.utc(2026, 9, 25));
      expect(progress.dailyChestStreak, 1);
    });
  });
}
