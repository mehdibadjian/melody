import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/screens/acoustic_practice_screen.dart';
import 'package:melody_app/screens/adventure_map_screen.dart';
import 'package:melody_app/screens/level_play_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_mic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildApp({required ProviderContainer container}) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AdventureMapScreen()),
    );
  }

  Future<ProviderContainer> makeContainer({
    Future<ContentDocument>? lessonsFuture,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Both play screens need these; provide fakes so navigation tests
        // exercise the real routing without a device mic or audio output.
        audioEngineProvider.overrideWith((ref) => SynthAudioEngine()),
        micCaptureProvider.overrideWithValue(FakeMicCapture()),
        if (lessonsFuture != null)
          lessonsProvider.overrideWith((ref) => lessonsFuture),
      ],
    );
  }

  const testDoc = ContentDocument(
    schemaVersion: 1,
    lessons: [
      Lesson(
        id: 'lesson-001',
        title: 'First Notes',
        difficulty: Difficulty.beginner,
        levels: [
          Level(
            id: 'level-001-a',
            name: 'Three Friends',
            type: LevelType.standard,
            requiredNotes: ['C4', 'D4', 'E4'],
            tempoBpm: 80,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.7, minNotesHit: 2),
            rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
          ),
        ],
      ),
    ],
  );

  testWidgets('shows loading indicator while content loads', (tester) async {
    final completer = Completer<ContentDocument>();
    final container = await makeContainer(lessonsFuture: completer.future);

    addTearDown(container.dispose);
    await tester.pumpWidget(buildApp(container: container));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('First Notes'), findsNothing);

    completer.complete(testDoc);
  });

  testWidgets('displays lesson list when content loads successfully',
      (tester) async {
    final container = await makeContainer(
      lessonsFuture: Future<ContentDocument>.value(testDoc),
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(buildApp(container: container));
    await tester.pumpAndSettle();

    expect(find.text('First Notes'), findsOneWidget);
    expect(find.text('beginner'), findsOneWidget);
    // AppBar HUD also uses a music_note icon; the lesson tile's is size 36.
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.music_note && w.size == 36,
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows error message when content fails to load', (tester) async {
    final completer = Completer<ContentDocument>();
    final container = await makeContainer(lessonsFuture: completer.future);

    addTearDown(container.dispose);
    await tester.pumpWidget(buildApp(container: container));

    completer.completeError(Exception('boom'), StackTrace.empty);
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load lessons:'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('daily chest button claims once and updates currency',
      (tester) async {
    final container = await makeContainer(
      lessonsFuture: Future<ContentDocument>.value(testDoc),
    );

    addTearDown(container.dispose);
    await tester.pumpWidget(buildApp(container: container));
    await tester.pumpAndSettle();

    expect(find.text('Notes 0'), findsOneWidget);
    expect(find.byKey(const Key('daily-chest-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('daily-chest-button')));
    await tester.pumpAndSettle();

    expect(find.text('Notes 2'), findsOneWidget);
  });

  group('lesson play-mode chooser', () {
    Future<void> openChooser(
        WidgetTester tester, ProviderContainer container) async {
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First Notes'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a lesson offers both play modes', (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(testDoc),
      );
      await openChooser(tester, container);

      expect(find.byKey(const Key('play-mode-real-keyboard')), findsOneWidget);
      expect(find.byKey(const Key('play-mode-on-screen')), findsOneWidget);
    });

    testWidgets('real-keyboard mode opens the acoustic practice screen',
        (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(testDoc),
      );
      await openChooser(tester, container);

      await tester.tap(find.byKey(const Key('play-mode-real-keyboard')));
      await tester.pumpAndSettle();

      expect(find.byType(AcousticPracticeScreen), findsOneWidget);
      expect(find.byKey(const Key('start-listening')), findsOneWidget);
    });

    testWidgets('on-screen mode opens the level play screen', (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(testDoc),
      );
      await openChooser(tester, container);

      await tester.tap(find.byKey(const Key('play-mode-on-screen')));
      await tester.pumpAndSettle();

      expect(find.byType(LevelPlayScreen), findsOneWidget);
    });
  });
}
