import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:melody_app/domain/analytics/analytics_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AnalyticsStore> makeStore() async {
    final prefs = await SharedPreferences.getInstance();
    return AnalyticsStore(prefs);
  }

  AnalyticsEvent sampleEvent({String levelId = 'level-001-a'}) {
    return AnalyticsEvent.levelCompleted(
      childProfileId: 'child-local',
      levelId: levelId,
      isBossBattle: false,
      starsAwarded: 3,
      noteCurrencyAwarded: 5,
    );
  }

  group('AnalyticsStore (event sink)', () {
    test('load returns empty list when nothing was persisted', () async {
      final store = await makeStore();
      expect(store.load(), isEmpty);
    });

    test('append persists the event as JSON and load round-trips it',
        () async {
      final store = await makeStore();
      final event = sampleEvent();

      await store.append(event);

      final loaded = store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.type, AnalyticsEventType.levelCompleted);
      expect(loaded.single.childProfileId, 'child-local');
      expect(loaded.single.payload['levelId'], 'level-001-a');
      expect(loaded.single.payload['starsAwarded'], 3);
    });

    test('appends accumulate in order', () async {
      final store = await makeStore();

      await store.append(sampleEvent(levelId: 'level-001-a'));
      await store.append(AnalyticsEvent.sessionStart(
        childProfileId: 'child-local',
        platform: 'test',
      ));
      await store.append(sampleEvent(levelId: 'level-002-b'));

      final loaded = store.load();
      expect(loaded, hasLength(3));
      expect(loaded[0].payload['levelId'], 'level-001-a');
      expect(loaded[1].type, AnalyticsEventType.sessionStart);
      expect(loaded[2].payload['levelId'], 'level-002-b');
    });

    test('load survives app restarts (fresh store over same prefs)',
        () async {
      final store = await makeStore();
      await store.append(sampleEvent());

      final reopened = await makeStore();
      expect(reopened.load(), hasLength(1));
      expect(reopened.load().single.payload['levelId'], 'level-001-a');
    });

    test('corrupt persisted data returns empty and is repairable', () async {
      SharedPreferences.setMockInitialValues({
        'analytics_events_v1': 'not-json{{{',
      });
      final store = await makeStore();

      expect(store.load(), isEmpty);

      await store.append(sampleEvent());
      expect(store.load(), hasLength(1));
    });

    test('a single corrupt entry is skipped without losing valid entries',
        () async {
      SharedPreferences.setMockInitialValues({
        'analytics_events_v1':
            '[{"schemaVersion":1,"type":"level_completed","childProfileId":"child-local","occurredAt":"2026-09-20T10:00:00.000Z","levelId":"ok","isBossBattle":false,"starsAwarded":1,"noteCurrencyAwarded":1},"garbage-entry"]',
      });
      final store = await makeStore();

      final loaded = store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.payload['levelId'], 'ok');
    });

    test('clear removes all persisted events', () async {
      final store = await makeStore();
      await store.append(sampleEvent());

      await store.clear();

      expect(store.load(), isEmpty);
    });
  });
}
