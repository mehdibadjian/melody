import 'dart:convert';

import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:test/test.dart';

void main() {
  const payout = RewardPayout(stars: 3, noteCurrency: 5);

  group('PlayerProgress — serialization round-trip', () {
    test('initial progress serializes and deserializes cleanly', () {
      final original = PlayerProgress.initial(profileId: 'test-child');
      final json = original.toJson();
      final restored = PlayerProgress.fromJson(json);

      expect(restored.profileId, 'test-child');
      expect(restored.stars, 0);
      expect(restored.noteCurrency, 0);
      expect(restored.currentStreak, 0);
      expect(restored.completedLevelIds, isEmpty);
      expect(restored.ownedCosmeticIds, isEmpty);
      expect(restored.notesMastered, isEmpty);
    });

    test('full state survives JSON round-trip', () {
      final original = PlayerProgress.initial(profileId: 'child-42');
      original.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      original.purchaseCosmetic('mascot-hat-blue', costNoteCurrency: 2);
      for (var i = 0; i < 5; i++) {
        original.recordNoteMastery('C4', hit: true);
      }
      original.recordNoteMastery('D4', hit: false);
      original.recordPracticeDay(DateTime.utc(2026, 9, 20));
      original.recordPracticeDay(DateTime.utc(2026, 9, 21));
      original.claimDailyChest(DateTime.utc(2026, 9, 21));

      final json = original.toJson();
      final restored = PlayerProgress.fromJson(json);

      expect(restored.profileId, 'child-42');
      expect(restored.stars, 3);
      expect(restored.noteCurrency, 5); // 5 earned - 2 spent + 2 daily chest
      expect(restored.currentStreak, 2);
      expect(restored.completedLevelIds, contains('level-001-a'));
      expect(restored.ownedCosmeticIds, contains('mascot-hat-blue'));
      expect(restored.notesMastered, contains('C4'));
      expect(restored.masteryMisses('D4'), 1);
      expect(restored.dailyChestStreak, 1);
    });

    test('toJson produces valid JSON string via jsonEncode', () {
      final progress = PlayerProgress.initial();
      progress.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      final encoded = jsonEncode(progress.toJson());
      expect(encoded, isA<String>());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['profileId'], 'child-local');
    });

    test('fromJson handles missing optional fields gracefully', () {
      final minimal = <String, dynamic>{
        'profileId': 'minimal-child',
      };
      final restored = PlayerProgress.fromJson(minimal);
      expect(restored.profileId, 'minimal-child');
      expect(restored.stars, 0);
      expect(restored.completedLevelIds, isEmpty);
    });

    test('non-punitive semantics preserved after restore', () {
      final original = PlayerProgress.initial();
      original.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 0.9,
      );
      final restored = PlayerProgress.fromJson(original.toJson());
      restored.applyLevelCompletion(
        levelId: 'level-001-a',
        payout: payout,
        accuracy: 1.0,
      );
      expect(restored.stars, 3);
    });
  });
}
