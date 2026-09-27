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

  Future<void> playNotes(WidgetTester tester, List<String> notes) async {
    for (final note in notes) {
      await tester.tap(find.text(note).last);
      await tester.pumpAndSettle();
    }
  }

  /// The note the child is being asked for right now.
  String targetText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('target-note'))).data!;

  Future<void> playPerfectRun(WidgetTester tester) =>
      playNotes(tester, ['C4', 'D4', 'E4']);

  /// Drains the result toast's 3s auto-dismiss timer so teardown is clean.
  Future<void> dismissToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
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

      // Result toast appears; HUD must already reflect the payout.
      expect(find.byKey(const Key('result-toast')), findsOneWidget);
      expect(find.text('Stars 3'), findsOneWidget);
      expect(find.text('Notes 5'), findsOneWidget);

      await dismissToast(tester);
      expect(find.text('Stars 3'), findsOneWidget);
    });
  });

  group('LevelPlayScreen result', () {
    testWidgets('passing run shows a non-blocking toast and a result card',
        (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      await playPerfectRun(tester);

      // No modal dialog and no tap-through button; the toast is non-blocking
      // so the child can keep playing straight away.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('OK'), findsNothing);
      expect(find.byKey(const Key('result-toast')), findsOneWidget);
      // The card is the part that stays after the toast goes.
      expect(find.byKey(const Key('result-title')), findsOneWidget);
      expect(find.text('You did it!'), findsOneWidget);
      expect(find.text('3 of 3 notes • 100% accurate'), findsOneWidget);

      await dismissToast(tester);
      // The reported bug was a dead end: the toast vanished and nothing was
      // left to act on. The card must outlive it.
      expect(find.byKey(const Key('result-toast')), findsNothing);
      expect(find.byKey(const Key('play-again')), findsOneWidget);
    });

    testWidgets('a wrong tap does not end the run', (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      // Longer than the whole song in fumbles.
      await playNotes(tester, ['F4', 'F4', 'F4', 'F4', 'F4', 'F4']);

      expect(find.byKey(const Key('result-toast')), findsNothing);
      expect(find.byKey(const Key('play-again')), findsNothing);
      // Still being asked for the first note, because none has been landed.
      expect(targetText(tester), 'C4');
      // Progress bar has moved zero notes even after six taps.
      expect(find.text('0 / 3'), findsOneWidget);
    });

    testWidgets('a wrong tap is coached, not just scored', (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      await playNotes(tester, ['F4']); // target is C4, so F4 is too high

      expect(find.byKey(const Key('coaching-message')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('coaching-message'))).data,
        contains('lower'),
      );
    });

    testWidgets('progress counts notes landed, not taps made', (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      await playNotes(tester, ['F4', 'C4', 'F4', 'D4']);

      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Keep going'), findsOneWidget);
    });

    testWidgets('failing run ends by playing the song out, then offers a retry',
        (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      // One fumble per note: 3 hits in 6 taps = 50% accuracy, below the 0.7
      // threshold, so this now fails on merit rather than by running out.
      await playNotes(tester, ['F4', 'C4', 'F4', 'D4', 'F4', 'E4']);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Good try!'), findsOneWidget);
      expect(find.text('3 of 3 notes • 50% accurate'), findsOneWidget);
      expect(find.textContaining('So close!'), findsOneWidget);

      await dismissToast(tester);
      expect(find.byKey(const Key('play-again')), findsOneWidget);
      // No stars for a failed run.
      expect(find.text('Stars 0'), findsOneWidget);
    });

    testWidgets('Play again restarts the run in place', (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      await playPerfectRun(tester);
      expect(find.text('You did it!'), findsOneWidget);
      expect(find.text('Stars 3'), findsOneWidget);

      // Toast still covering the keys at this point — that is the hazard the
      // retry button has to clear, or the first taps of the replay land on it.
      expect(find.byKey(const Key('result-toast')), findsOneWidget);

      await tester.tap(find.byKey(const Key('play-again')));
      // Only the hide animation is allowed to run here. pumpAndSettle would also
      // advance the toast's 3s auto-dismiss timer, so the assertion would pass
      // with or without the fix and prove nothing.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('result-toast')), findsNothing);
      await tester.pumpAndSettle();

      // Fresh run: result gone, progress back to zero, asked for the first note.
      expect(find.byKey(const Key('result-title')), findsNothing);
      expect(find.text('0 / 3'), findsOneWidget);
      expect(targetText(tester), 'C4');
      // The replay has to be playable, not just visible: with the old toast
      // still on screen it absorbs these taps and the run never moves.
      await tester.tap(find.byKey(const Key('key-C4')));
      await tester.pump();
      expect(find.text('1 / 3'), findsOneWidget);
      // And replaying must not pay the level out a second time.
      await playNotes(tester, ['D4', 'E4']);
      expect(find.text('Stars 3'), findsOneWidget);
      await dismissToast(tester);
    });

    testWidgets('taps after a finished run are ignored until retry',
        (tester) async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildScreen(container));
      await tester.pumpAndSettle();
      await playPerfectRun(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Tapping more keys must not re-commit progress or re-toast.
      await tester.tap(find.byKey(const Key('key-C4')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('result-toast')), findsOneWidget);
      expect(find.text('Stars 3'), findsOneWidget);
      await dismissToast(tester);
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

      await dismissToast(tester);
    });
  });
}
