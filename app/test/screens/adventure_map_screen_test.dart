import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/screens/adventure_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
