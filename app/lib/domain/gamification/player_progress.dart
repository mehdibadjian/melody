import 'package:melody_app/domain/content/content_models.dart';

/// Persistent child profile progress (PRD §4): notes mastered, streaks,
/// accuracy, reward economy. Pure Dart; serialization lands with the
/// backend-sync workstream.
class PlayerProgress {
  PlayerProgress.initial({this.profileId = 'child-local'})
      : _stars = 0,
        _noteCurrency = 0,
        _currentStreak = 0,
        _lastPracticeDay = null,
        _lastChestClaimDay = null,
        _dailyChestStreak = 0,
        _completedLevels = {},
        _ownedCosmetics = {},
        _masteryHits = {},
        _masteryMisses = {};

  PlayerProgress._({
    required this.profileId,
    required int stars,
    required int noteCurrency,
    required int currentStreak,
    required DateOnly? lastPracticeDay,
    required DateOnly? lastChestClaimDay,
    required int dailyChestStreak,
    required Set<String> completedLevels,
    required Set<String> ownedCosmetics,
    required Map<String, int> masteryHits,
    required Map<String, int> masteryMisses,
  })  : _stars = stars,
        _noteCurrency = noteCurrency,
        _currentStreak = currentStreak,
        _lastPracticeDay = lastPracticeDay,
        _lastChestClaimDay = lastChestClaimDay,
        _dailyChestStreak = dailyChestStreak,
        _completedLevels = completedLevels,
        _ownedCosmetics = ownedCosmetics,
        _masteryHits = masteryHits,
        _masteryMisses = masteryMisses;

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    return PlayerProgress._(
      profileId: json['profileId'] as String? ?? 'child-local',
      stars: json['stars'] as int? ?? 0,
      noteCurrency: json['noteCurrency'] as int? ?? 0,
      currentStreak: json['currentStreak'] as int? ?? 0,
      lastPracticeDay: json['lastPracticeDay'] != null
          ? DateOnly.fromString(json['lastPracticeDay'] as String)
          : null,
      lastChestClaimDay: json['lastChestClaimDay'] != null
          ? DateOnly.fromString(json['lastChestClaimDay'] as String)
          : null,
      dailyChestStreak: json['dailyChestStreak'] as int? ?? 0,
      completedLevels:
          (json['completedLevels'] as List<dynamic>?)?.cast<String>().toSet() ??
              {},
      ownedCosmetics:
          (json['ownedCosmetics'] as List<dynamic>?)?.cast<String>().toSet() ??
              {},
      masteryHits:
          (json['masteryHits'] as Map<String, dynamic>?)?.cast<String, int>() ??
              {},
      masteryMisses: (json['masteryMisses'] as Map<String, dynamic>?)
              ?.cast<String, int>() ??
          {},
    );
  }

  /// Child profile identifier; replaced by a server-synced id when the
  /// backend-sync workstream (PRD §4) lands.
  final String profileId;

  int _stars;
  int _noteCurrency;
  int _currentStreak;
  DateOnly? _lastPracticeDay;
  DateOnly? _lastChestClaimDay;
  int _dailyChestStreak;
  final Set<String> _completedLevels;
  final Set<String> _ownedCosmetics;
  final Map<String, int> _masteryHits;
  final Map<String, int> _masteryMisses;

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'stars': _stars,
        'noteCurrency': _noteCurrency,
        'currentStreak': _currentStreak,
        'lastPracticeDay': _lastPracticeDay?.toString(),
        'lastChestClaimDay': _lastChestClaimDay?.toString(),
        'dailyChestStreak': _dailyChestStreak,
        'completedLevels': _completedLevels.toList(),
        'ownedCosmetics': _ownedCosmetics.toList(),
        'masteryHits': Map<String, int>.from(_masteryHits),
        'masteryMisses': Map<String, int>.from(_masteryMisses),
      };

  static const masteryHitsRequired = 5;

  int get stars => _stars;
  int get noteCurrency => _noteCurrency;
  int get currentStreak => _currentStreak;
  int get dailyChestStreak => _dailyChestStreak;
  Set<String> get completedLevelIds => Set.unmodifiable(_completedLevels);
  Set<String> get ownedCosmeticIds => Set.unmodifiable(_ownedCosmetics);

  /// Notes the player has demonstrated mastery of (>= 5 hits each).
  Set<String> get notesMastered => Set.unmodifiable(
        _masteryHits.entries
            .where((e) => e.value >= masteryHitsRequired)
            .map((e) => e.key),
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
      _lastChestClaimDay == null ||
      !DateOnly(day).isSameDay(_lastChestClaimDay!);

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

  DateOnly._(this.year, this.month, this.day);

  factory DateOnly.fromString(String s) {
    final parts = s.split('-');
    return DateOnly._(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

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
