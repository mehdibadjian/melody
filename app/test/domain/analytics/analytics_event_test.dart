import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:test/test.dart';

void main() {
  group('AnalyticsEvent schema (PRD §4/§7: dashboard source of truth)', () {
    test('practice session event carries time practiced and accuracy', () {
      final event = AnalyticsEvent.practiceSession(
        childProfileId: 'child-1',
        levelId: 'level-001-a',
        practicedSeconds: 420,
        accuracy: 0.8,
        notesHit: 8,
        notesAttempted: 10,
      );
      expect(event.type, AnalyticsEventType.practiceSession);
      expect(event.payload['practicedSeconds'], 420);
      expect(event.payload['accuracy'], 0.8);
    });

    test('level completed event carries level id and reward payout', () {
      final event = AnalyticsEvent.levelCompleted(
        childProfileId: 'child-1',
        levelId: 'level-001-a',
        isBossBattle: true,
        starsAwarded: 3,
        noteCurrencyAwarded: 5,
      );
      expect(event.type, AnalyticsEventType.levelCompleted);
      expect(event.payload['isBossBattle'], isTrue);
      expect(event.payload['starsAwarded'], 3);
    });

    test('session start event marks session frequency data', () {
      final event = AnalyticsEvent.sessionStart(
        childProfileId: 'child-1',
        platform: 'android',
      );
      expect(event.type, AnalyticsEventType.sessionStart);
      expect(event.payload['platform'], 'android');
    });

    test('event serializes to JSON with required envelope fields', () {
      final event = AnalyticsEvent.practiceSession(
        childProfileId: 'child-1',
        levelId: 'level-001-a',
        practicedSeconds: 60,
        accuracy: 1.0,
        notesHit: 5,
        notesAttempted: 5,
      );
      final json = event.toJson();
      expect(json, containsPair('type', 'practice_session'));
      expect(json, containsPair('childProfileId', 'child-1'));
      expect(json['occurredAt'], isNotNull);
      expect(json['schemaVersion'], 1);
    });

    test('event round-trips through JSON', () {
      final event = AnalyticsEvent.levelCompleted(
        childProfileId: 'child-2',
        levelId: 'level-002-boss',
        isBossBattle: true,
        starsAwarded: 8,
        noteCurrencyAwarded: 12,
      );
      final restored = AnalyticsEvent.fromJson(event.toJson());
      expect(restored.type, event.type);
      expect(restored.childProfileId, event.childProfileId);
      expect(restored.payload, event.payload);
    });

    test('accuracy outside 0..1 is rejected at event construction', () {
      expect(
        () => AnalyticsEvent.practiceSession(
          childProfileId: 'child-1',
          levelId: 'level-001-a',
          practicedSeconds: 60,
          accuracy: 1.5,
          notesHit: 5,
          notesAttempted: 5,
        ),
        throwsArgumentError,
      );
    });

    test('no PII: payload contains only whitelisted keys (COPPA/GDPR-K)', () {
      final event = AnalyticsEvent.practiceSession(
        childProfileId: 'child-1',
        levelId: 'level-001-a',
        practicedSeconds: 60,
        accuracy: 1.0,
        notesHit: 5,
        notesAttempted: 5,
      );
      final allowedKeys = {
        'childProfileId',
        'levelId',
        'practicedSeconds',
        'accuracy',
        'notesHit',
        'notesAttempted',
        'isBossBattle',
      };
      expect(event.payload.keys.toSet().difference(allowedKeys), isEmpty);
    });
  });
}