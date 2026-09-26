/// Content schema models (PRD §4): lessons, levels, boss battles as data.
///
/// Authored as JSON in `assets/content/` — never hardcoded per-level logic.
library;

/// Difficulty tiers for lessons.
enum Difficulty { beginner, intermediate, advanced }

/// Level kind: standard practice level or boss battle.
enum LevelType { standard, bossBattle }

/// A lesson in the adventure map.
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.levels,
  });

  final String id;
  final String title;
  final Difficulty difficulty;
  final List<Level> levels;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'difficulty': difficulty.name,
        'levels': levels.map((l) => l.toJson()).toList(),
      };
}

/// A playable level within a lesson.
class Level {
  const Level({
    required this.id,
    required this.name,
    required this.type,
    required this.requiredNotes,
    required this.tempoBpm,
    required this.successThreshold,
    required this.rewardPayout,
  });

  final String id;
  final String name;
  final LevelType type;
  final List<String> requiredNotes;
  final int tempoBpm;
  final SuccessThreshold successThreshold;
  final RewardPayout rewardPayout;

  bool get isBossBattle => type == LevelType.bossBattle;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type == LevelType.bossBattle ? 'boss_battle' : 'standard',
        'requiredNotes': requiredNotes,
        'tempoBpm': tempoBpm,
        'successThreshold': successThreshold.toJson(),
        'rewardPayout': rewardPayout.toJson(),
      };
}

/// What a player must achieve to complete a level.
class SuccessThreshold {
  const SuccessThreshold({
    required this.minAccuracy,
    required this.minNotesHit,
  });

  /// Fraction (0.0–1.0) of notes that must be hit correctly.
  final double minAccuracy;

  /// Absolute minimum number of correct notes.
  final int minNotesHit;

  Map<String, dynamic> toJson() => {
        'minAccuracy': minAccuracy,
        'minNotesHit': minNotesHit,
      };
}

/// Rewards granted on level completion. Spendable on cosmetics only.
class RewardPayout {
  const RewardPayout({required this.stars, required this.noteCurrency});

  final int stars;
  final int noteCurrency;

  Map<String, dynamic> toJson() => {
        'stars': stars,
        'noteCurrency': noteCurrency,
      };
}

/// Root of an authored content document.
class ContentDocument {
  const ContentDocument({required this.schemaVersion, required this.lessons});

  final int schemaVersion;
  final List<Lesson> lessons;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'lessons': lessons.map((l) => l.toJson()).toList(),
      };
}
