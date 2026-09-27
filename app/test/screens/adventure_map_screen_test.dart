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
import 'package:melody_app/widgets/song_demo_dialog.dart';
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

  /// A song with three arrangements, which is what the picker exists for. Kept
  /// as a local fixture rather than read from `lessons.json` so the routing
  /// assertions do not silently change when an author edits content.
  const songDoc = ContentDocument(
    schemaVersion: 2,
    lessons: [
      Lesson(
        id: 'song-golden',
        title: 'GOLDEN',
        difficulty: Difficulty.beginner,
        songTitle: 'GOLDEN',
        genre: 'pop',
        levels: [
          Level(
            id: 'golden-beginner',
            name: 'Beginner - right-hand melody',
            type: LevelType.standard,
            requiredNotes: ['G4', 'A4', 'B4'],
            tempoBpm: 92,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.7, minNotesHit: 2),
            rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
          ),
          Level(
            id: 'golden-medium',
            name: 'Medium - chorus lift',
            type: LevelType.standard,
            requiredNotes: ['D5', 'E5', 'G5'],
            tempoBpm: 108,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.75, minNotesHit: 2),
            rewardPayout: RewardPayout(stars: 4, noteCurrency: 6),
          ),
          Level(
            id: 'golden-hard',
            name: 'Hard - the full anthem',
            type: LevelType.bossBattle,
            requiredNotes: ['F#4', 'D6'],
            tempoBpm: 120,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.75, minNotesHit: 1),
            rewardPayout: RewardPayout(stars: 6, noteCurrency: 9),
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
    // The tile is a quest card, not a plain ListTile: it renders the lesson's
    // own difficulty badge and the reward it is worth before the tap.
    expect(find.byKey(const Key('quest-badge-lesson-001')), findsOneWidget);
    expect(find.byKey(const Key('lesson-tile-lesson-001')), findsOneWidget);
    // 3 stars and 5 notes from the single level's payout.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // No level cleared yet, so the progress ring is absent.
    expect(find.byType(CircularProgressIndicator), findsNothing);
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

  /// The sheet is scrollable, so on a short viewport a mode row can sit below
  /// the fold; scroll it into view rather than tapping blind.
  Future<void> tapMode(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

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

    testWidgets('hearing the tune is on the play screens, not a third mode',
        (tester) async {
      // It was offered here first, as a sibling of the two play modes. That
      // asked a child to decide how they want to play *before* they could hear
      // the song, and left the real-keyboard and on-screen screens with no way
      // to listen once they were already in.
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(testDoc),
      );
      await openChooser(tester, container);

      expect(find.byKey(const Key('play-mode-demo')), findsNothing);
      expect(find.byType(SongDemoDialog), findsNothing);

      await tapMode(tester, const Key('play-mode-on-screen'));
      expect(find.byKey(const Key('hear-it')), findsOneWidget);

      await tester.tap(find.byKey(const Key('hear-it')));
      await tester.pumpAndSettle();
      // A dialog over the board, not a pushed route: the run the child was
      // about to take is still there when this closes.
      expect(find.byType(SongDemoDialog), findsOneWidget);
      expect(find.byKey(const Key('demo-play')), findsOneWidget);

      await tester.tap(find.byKey(const Key('demo-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SongDemoDialog), findsNothing);
      expect(find.byType(LevelPlayScreen), findsOneWidget);
    });

    testWidgets('the demo is the arrangement that was selected, not the first',
        (tester) async {
      // GOLDEN has three arrangements at three tempos. A demo that always played
      // levels.first would show the wrong speed for the one the child picked.
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(songDoc),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GOLDEN'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('level-choice-golden-hard')));
      await tester.pumpAndSettle();
      await tapMode(tester, const Key('play-mode-on-screen'));
      await tester.tap(find.byKey(const Key('hear-it')));
      await tester.pumpAndSettle();

      // The screen behind also names the arrangement in its app bar, so assert
      // the dialog's own title rather than a substring on the whole tree.
      expect(find.text('Listen to Hard - the full anthem'), findsOneWidget);
      // The hard arrangement's own tempo, not the beginner one's 92. The meter
      // rendering itself is covered by song_demo_dialog_test.
      expect(tester.widget<Text>(find.byKey(const Key('demo-tempo'))).data,
          contains('120'));

      await tester.tap(find.byKey(const Key('demo-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('a single-level song shows no arrangement picker',
        (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(testDoc),
      );
      await openChooser(tester, container);

      // The picker is conditional on having a choice to make; a song with one
      // arrangement must not gain a row of buttons that do nothing.
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Three Friends'), findsNothing);
    });
  });

  group('multi-level arrangement picker', () {
    Future<void> openChooser(
        WidgetTester tester, ProviderContainer container) async {
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GOLDEN'));
      await tester.pumpAndSettle();
    }

    /// The sheet is scrollable, so on a short viewport a mode row can sit below
    /// the fold; scroll it into view rather than tapping blind.
    Future<void> tapMode(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    testWidgets('adding arrangements does not overflow the sheet',
        (tester) async {
      // The reported landscape bug was a sheet-sized Column that could not
      // grow. Three chips plus two rows must stay scrollable, not overflow.
      tester.view.physicalSize = const Size(640, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(songDoc),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GOLDEN'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('level-choice-golden-hard')), findsOneWidget);
    });

    testWidgets('offers every arrangement and defaults to the first',
        (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(songDoc),
      );
      await openChooser(tester, container);

      for (final level in songDoc.lessons.single.levels) {
        expect(find.byKey(Key('level-choice-${level.id}')), findsOneWidget,
            reason: '${level.id} has no picker chip');
      }
      expect(
        find.widgetWithText(ActionChip, 'Beginner - right-hand melody'),
        findsOneWidget,
      );
    });

    testWidgets('plays the selected arrangement, not always the first',
        (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(songDoc),
      );
      await openChooser(tester, container);

      await tester.tap(find.byKey(const Key('level-choice-golden-hard')));
      await tester.pumpAndSettle();
      await tapMode(tester, const Key('play-mode-on-screen'));

      final screen =
          tester.widget<LevelPlayScreen>(find.byType(LevelPlayScreen));
      expect(screen.level.id, 'golden-hard',
          reason: 'the picker selection was ignored in favour of levels.first');
    });

    testWidgets('preselects the first uncleared arrangement', (tester) async {
      final container = await makeContainer(
        lessonsFuture: Future<ContentDocument>.value(songDoc),
      );
      container.read(playerProgressProvider.notifier).applyLevelCompletion(
            levelId: 'golden-beginner',
            payout: songDoc.lessons.single.levels.first.rewardPayout,
            accuracy: 0.9,
          );
      await openChooser(tester, container);
      await tester.pumpAndSettle();

      final selected = tester.widget<ActionChip>(
          find.byKey(const Key('level-choice-golden-medium')));
      expect(selected.backgroundColor, isNot(Colors.transparent),
          reason: 'a cleared beginner should resume at medium');

      await tapMode(tester, const Key('play-mode-on-screen'));
      expect(
        tester.widget<LevelPlayScreen>(find.byType(LevelPlayScreen)).level.id,
        'golden-medium',
      );
    });
  });
}
