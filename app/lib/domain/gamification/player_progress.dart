import 'package:melody_app/domain/content/content_models.dart';

/// Persistent child profile progress (PRD §4): notes mastered, streaks,
/// accuracy, reward economy. Pure Dart; serialization lands with the
/// backend-sync workstream.
class PlayerProgress {
  PlayerProgress.initial({this.profileId = 'child-local'});

  /// Child profile identifier; replaced by a server-synced id when the
  /// backend-sync workstream (PRD §4) lands.
  final String profileId;

  int _stars = 0;
  int _noteCurrency = 0;
  int _currentStreak = 0;
  DateOnly? _lastPracticeDay;
  DateOnly? _lastChestClaimDay;
  int _dailyChestStreak = 0;
  final Set<String> _completedLevels = {};
  final Set<String> _ownedCosmetics = {};
  final Map<String, int> _masteryHits = {};
  final Map<String, int> _masteryMisses = {};

  static const masteryHitsRequired = 5;

  int get stars => _stars;
  int get noteCurrency => _noteCurrency;
  int get currentStreak => _currentStreak;
  int get dailyChestStreak => _dailyChestStreak;
  Set<String> get completedLevelIds => Set.unmodifiable(_completedLevels);
  Set<String> get ownedCosmeticIds => Set.unmodifiable(_ownedCosmetics);

  /// Notes the player has demonstrated mastery of (>= 5 hits each).
  Set<String> get notesMastered => Set.unmodifiable(
        _masteryHits.entries.where((e) => e.value >= masteryHitsRequired).map((e) => e.key),
      );

  int masteryHits(String note) => _masteryHits[note] ?? 0;
  int masteryMisses(String note) => _masteryMisses[note] ?? 0;

  /// Awards a level completion. Re-completing a level is encouraged but never
  /// double-awards (first completion sets the payout).
  void applyLevelCompletion({
    required String levelId,
    required RewardPayout payout,
    required double accuracy,
  }) {
    if (_completedLevels.contains(levelId)) return;
    _completedLevels.add(levelId);
    _stars += payout.stars;
    _noteCurrency += payout.noteCurrency;
  }

  /// Spends note currency on a cosmetic. Currency can never be bought,
  /// only earned (PRD §6: no pay-to-win).
  void purchaseCosmetic(String cosmeticId, {required int costNoteCurrency}) {
    if (_ownedCosmetics.contains(cosmeticId)) {
      throw AlreadyOwnedException(cosmeticId);
    }
    if (_noteCurrency < costNoteCurrency) {
      throw InsufficientCurrencyException(costNoteCurrency, _noteCurrency);
    }
    _noteCurrency -= costNoteCurrency;
    _ownedCosmetics.add(cosmeticId);
  }

  void recordNoteMastery(String note, {required bool hit}) {
    if (hit) {
      _masteryHits[note] = (_masteryHits[note] ?? 0) + 1;
    } else {
      _masteryMisses[note] = (_masteryMisses[note] ?? 0) + 1;
    }
  }

  /// Records a practice session on [day]. Streak counts consecutive calendar
  /// days; a skipped day resets it to 1 (no anxiety mechanics — never drops
  /// below 1 once practice is recorded).
  void recordPracticeDay(DateTime day) {
    final date = DateOnly(day);
    final last = _lastPracticeDay;
    _lastPracticeDay = date;
    if (last == null) {
      _currentStreak = 1;
    } else if (date.isSameDay(last)) {
      return;
    } else if (date.isConsecutiveDayAfter(last)) {
      _currentStreak++;
    } else {
      _currentStreak = 1;
    }
  }

  /// Daily chest is claimable at most once per calendar day.
  bool canClaimDailyChest(DateTime day) =>
      _lastChestClaimDay == null || !DateOnly(day).isSameDay(_lastChestClaimDay!);

  void claimDailyChest(DateTime day) {
    if (!canClaimDailyChest(day)) return;
    final date = DateOnly(day);
    final last = _lastChestClaimDay;
    _lastChestClaimDay = date;
    if (last != null && date.isConsecutiveDayAfter(last)) {
      _dailyChestStreak++;
    } else {
      _dailyChestStreak = 1;
    }
    _noteCurrency += 2;
  }
}

/// Calendar-date wrapper for day-level comparisons in UTC.
class DateOnly {
  DateOnly(DateTime dt)
      : year = dt.year,
        month = dt.month,
        day = dt.day;

  final int year;
  final int month;
  final int day;

  bool isSameDay(DateOnly other) =>
      year == other.year && month == other.month && day == other.day;

  bool isConsecutiveDayAfter(DateOnly previous) {
    final a = DateTime.utc(year, month, day);
    final b = DateTime.utc(previous.year, previous.month, previous.day);
    return a.difference(b).inDays == 1;
  }
}

class InsufficientCurrencyException implements Exception {
  InsufficientCurrencyException(this.required, this.available);
  final int required;
  final int available;

  @override
  String toString() =>
      'InsufficientCurrencyException: need $required, have $available';
}

class AlreadyOwnedException implements Exception {
  AlreadyOwnedException(this.cosmeticId);
  final String cosmeticId;

  @override
  String toString() => 'AlreadyOwnedException: $cosmeticId already owned';
}