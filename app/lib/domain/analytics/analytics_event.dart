/// Analytics event types feeding the parental dashboard (PRD §7).
enum AnalyticsEventType {
  sessionStart,
  practiceSession,
  levelCompleted,
}

/// Analytics event schema (PRD §4): practice time, accuracy, session
/// frequency — defined up front so the parental dashboard queries a real
/// schema, not ad-hoc per-screen data.
///
/// COPPA/GDPR-K: payload keys are whitelisted; no free-text or PII fields.
class AnalyticsEvent {
  AnalyticsEvent._({
    required this.type,
    required this.childProfileId,
    required this.occurredAt,
    required this.payload,
  });

  final AnalyticsEventType type;
  final String childProfileId;
  final DateTime occurredAt;
  final Map<String, Object?> payload;

  static const schemaVersion = 1;

  factory AnalyticsEvent.sessionStart({
    required String childProfileId,
    required String platform,
  }) {
    return AnalyticsEvent._(
      type: AnalyticsEventType.sessionStart,
      childProfileId: childProfileId,
      occurredAt: DateTime.now().toUtc(),
      payload: {'platform': platform},
    );
  }

  factory AnalyticsEvent.practiceSession({
    required String childProfileId,
    required String levelId,
    required int practicedSeconds,
    required double accuracy,
    required int notesHit,
    required int notesAttempted,
  }) {
    _requireAccuracy(accuracy);
    return AnalyticsEvent._(
      type: AnalyticsEventType.practiceSession,
      childProfileId: childProfileId,
      occurredAt: DateTime.now().toUtc(),
      payload: {
        'levelId': levelId,
        'practicedSeconds': practicedSeconds,
        'accuracy': accuracy,
        'notesHit': notesHit,
        'notesAttempted': notesAttempted,
      },
    );
  }

  factory AnalyticsEvent.levelCompleted({
    required String childProfileId,
    required String levelId,
    required bool isBossBattle,
    required int starsAwarded,
    required int noteCurrencyAwarded,
  }) {
    return AnalyticsEvent._(
      type: AnalyticsEventType.levelCompleted,
      childProfileId: childProfileId,
      occurredAt: DateTime.now().toUtc(),
      payload: {
        'levelId': levelId,
        'isBossBattle': isBossBattle,
        'starsAwarded': starsAwarded,
        'noteCurrencyAwarded': noteCurrencyAwarded,
      },
    );
  }

  static void _requireAccuracy(double accuracy) {
    if (accuracy < 0 || accuracy > 1 || accuracy.isNaN) {
      throw ArgumentError.value(accuracy, 'accuracy', 'must be within 0..1');
    }
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'type': _typeNames[type],
        'childProfileId': childProfileId,
        'occurredAt': occurredAt.toIso8601String(),
        ...payload,
      };

  factory AnalyticsEvent.fromJson(Map<String, Object?> json) {
    final typeName = json['type'] as String;
    final type = _typeNames.entries
        .singleWhere((e) => e.value == typeName,
            orElse: () => throw ArgumentError('unknown event type: $typeName'))
        .key;
    final occurredAt = DateTime.parse(json['occurredAt'] as String);
    final payload = Map<String, Object?>.of(json)
      ..remove('schemaVersion')
      ..remove('type')
      ..remove('childProfileId')
      ..remove('occurredAt');
    return AnalyticsEvent._(
      type: type,
      childProfileId: json['childProfileId'] as String,
      occurredAt: occurredAt,
      payload: payload,
    );
  }

  static const _typeNames = {
    AnalyticsEventType.sessionStart: 'session_start',
    AnalyticsEventType.practiceSession: 'practice_session',
    AnalyticsEventType.levelCompleted: 'level_completed',
  };
}
