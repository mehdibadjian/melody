import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/screens/level_play_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testLevel = Level(
    id: 'level-001-a',
    name: 'Three Friends',
    type: LevelType.standard,
    requiredNotes: ['C4', 'D4', 'E4'],
    tempoBpm: 80,
    successThreshold: SuccessThreshold(minAccuracy: 0.7, minNotesHit: 2),
    rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
  );

  Future<ProviderContainer> makeContainer() async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioEngineProvider.overrideWith((ref) => SynthAudioEngine()),
      ],
    );
  }

  Widget buildScreen(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LevelPlayScreen(level: testLevel)),
    );
  }

  Future<void> playPerfectRun(WidgetTester tester) async {
    for (final note in ['C4', 'D4', 'E4']) {
      await tester.tap(find.text(note).last);
      await tester.pumpAndSettle();
    }
  }

  group('LevelPlayScreen progress HUD', () {
    testWidgets('shows stars and currency, updates after level completion',
        (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();

      expect(find.text('Stars 0'), findsOneWidget);
      expect(find.text('Notes 0'), findsOneWidget);

      await playPerfectRun(tester);

      // Result dialog appears; HUD must already reflect the payout.
      expect(find.text('You did it!'), findsOneWidget);
      expect(find.text('Stars 3'), findsOneWidget);
      expect(find.text('Notes 5'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Stars 3'), findsOneWidget);
    });
  });

  group('LevelPlayScreen analytics wiring', () {
    testWidgets('level run appends analytics events to the store',
        (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      await playPerfectRun(tester);

      final events = container.read(analyticsStoreProvider).load();
      expect(
        events.where((e) => e.type == AnalyticsEventType.practiceSession),
        hasLength(1),
      );
      expect(
        events.where((e) => e.type == AnalyticsEventType.levelCompleted),
        hasLength(1),
      );
    });
  });
}
