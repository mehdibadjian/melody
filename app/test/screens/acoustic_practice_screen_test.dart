import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/screens/acoustic_practice_screen.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';
import 'package:melody_app/widgets/song_demo_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_mic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A short real song: "Mary Had a Little Lamb" first phrase.
  const song = Level(
    id: 'mary-lamb-full',
    name: 'First verse',
    type: LevelType.standard,
    requiredNotes: ['E4', 'D4', 'C4', 'D4', 'E4', 'E4', 'E4'],
    tempoBpm: 84,
    successThreshold: SuccessThreshold(minAccuracy: 0.7, minNotesHit: 5),
    rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
  );
  late FakeMicCapture mic;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mic = FakeMicCapture();
  });

  /// Builds the screen over a fake mic. [harness] additionally hands back the
  /// container: the acoustic screen has no stars HUD, so a test that needs to
  /// prove a child was *paid* has to read the committed progress state. It also
  /// hands back the audio engine, so a test can prove the Hear it demo actually
  /// sounded notes from this screen.
  Future<
      ({
        ProviderContainer container,
        SynthAudioEngine engine,
        Widget widget
      })> harness(FakeMicCapture fake) async {
    final prefs = await SharedPreferences.getInstance();
    final engine = SynthAudioEngine();
    await engine.initialize();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioEngineProvider.overrideWith((ref) => engine),
      micCaptureProvider.overrideWithValue(fake),
    ]);
    return (
      container: container,
      engine: engine,
      widget: UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AcousticPracticeScreen(level: song)),
      ),
    );
  }

  Future<Widget> app(FakeMicCapture fake) async => (await harness(fake)).widget;

  /// Taps start-listening and lets the controller spin up capture.
  Future<void> startListening(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('start-listening')));
    await tester.pumpAndSettle();
  }

  /// Emits one note's PCM followed by a short gap, then lets detection settle.
  /// The gap models a child lifting their finger between discrete notes: the
  /// note-stability debouncer re-arms on silence so repeated pitches (e.g. the
  /// "E4 E4 E4" at the end of Mary Had a Little Lamb) each register.
  Future<void> play(WidgetTester tester, String note) async {
    mic.emit(pcmToneFor(note));
    mic.emit(pcmSilenceFor(seconds: 0.15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('shows the song title and a start-listening prompt',
      (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();

    expect(find.text('First verse'), findsOneWidget);
    expect(find.text('E4'), findsWidgets); // first target on the board
    expect(find.byKey(const Key('start-listening')), findsOneWidget);
    expect(find.byType(IllustratedKeyboard), findsOneWidget);
  });

  testWidgets('start begins listening once permission is granted',
      (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    expect(mic.started, isTrue);
    expect(find.byKey(const Key('listening-indicator')), findsOneWidget);
  });

  testWidgets('permission denied shows an enable-mic message, not a crash',
      (tester) async {
    mic.permission = false;
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    expect(find.byKey(const Key('mic-permission-denied')), findsOneWidget);
    expect(mic.started, isFalse);
  });

  testWidgets('a correct note from the mic advances the target',
      (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    expect(find.byKey(const Key('target-E4')), findsOneWidget);

    await play(tester, 'E4');

    // Now on the second note, D4.
    expect(find.byKey(const Key('target-D4')), findsOneWidget);
  });

  testWidgets('a wrong note shows directional coaching and holds the target',
      (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    await play(tester, 'G4'); // too high vs E4

    expect(find.byKey(const Key('coaching-message')), findsOneWidget);
    expect(find.byKey(const Key('target-E4')), findsOneWidget);
    final msg = tester.widget<Text>(find.byKey(const Key('coaching-message')));
    expect(msg.data, contains('too high'));
  });

  testWidgets('playing the whole song celebrates with a non-blocking toast',
      (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    for (final note in song.requiredNotes) {
      await play(tester, note);
    }

    // Result arrives as a toast, never a full-screen takeover or modal dialog.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('result-toast')), findsOneWidget);
    expect(find.textContaining('You played it'), findsOneWidget);
    // The inline completion state is a calm resting indicator, not a popup.
    expect(find.byKey(const Key('song-complete')), findsOneWidget);

    // Settle the toast's entrance so its 3s auto-dismiss timer is scheduled,
    // then advance past it so teardown is clean.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result-toast')), findsNothing);
  });

  testWidgets('a child who lands every note is paid, even after fumbles',
      (tester) async {
    // The acoustic path judges a run on hits/attempts, where attempts counts
    // every wrong note heard. SongCoach only completes when every note has been
    // landed, so correctHits == requiredNotes.length at the finish line — which
    // meant a slow-but-thorough child could cross it and still be denied the
    // payout, silently: the screen said "All done" and the toast said "nice
    // work", while awarding nothing.
    final h = await harness(mic);
    addTearDown(h.container.dispose);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();
    await startListening(tester);

    for (final note in song.requiredNotes) {
      await play(tester, 'A3'); // one wrong key heard before each note
      await play(tester, note);
    }

    expect(find.byKey(const Key('song-complete')), findsOneWidget,
        reason: 'the song was played all the way through');
    final progress = h.container.read(playerProgressProvider);
    expect(progress.completedLevelIds, contains(song.id),
        reason: 'landing every note of the song must complete the level');
    expect(progress.stars, song.rewardPayout.stars);
    expect(progress.noteCurrency, song.rewardPayout.noteCurrency);
  });

  testWidgets('progress strip shows position through the song', (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    await play(tester, 'E4');

    // 1 of 7 notes done.
    expect(find.textContaining('1 / 7'), findsOneWidget);
  });

  group('Hear it', () {
    testWidgets('the demo plays this screen\'s own arrangement',
        (tester) async {
      final h = await harness(mic);
      addTearDown(h.container.dispose);
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('hear-it')));
      await tester.pumpAndSettle();
      expect(find.byType(SongDemoDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('demo-play')));
      // A bar of count-in comes first: at 84 in 4/4 that is 2857ms of clicks
      // before note 0, so pumping 3s lands exactly on the first melody note.
      await tester.pump(const Duration(milliseconds: 3000));
      expect(h.engine.lastPlayedNote, 'E4',
          reason: 'the demo must sound the level this screen is teaching');

      await tester.tap(find.byKey(const Key('demo-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('listening stops for the demo and resumes after it',
        (tester) async {
      // The demo comes out of the phone's own speaker, which is aimed straight
      // at the mic. Left listening, the coach would hear those notes as the
      // child's and advance the target on its own, so a child who stopped to
      // listen would come back to a song half-played by nobody.
      final h = await harness(mic);
      addTearDown(h.container.dispose);
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();
      await startListening(tester);
      expect(mic.stopped, isFalse);

      // runAsync, because stopping capture awaits the PCM subscription's cancel
      // and the fake mic's stream lives in the real zone: under fake pumps that
      // future never completes, so `stopped` would stay false no matter what the
      // screen did.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('hear-it')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(mic.stopped, isTrue);
      expect(find.byKey(const Key('listening-indicator')), findsNothing);

      await tester.tap(find.byKey(const Key('demo-close')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('listening-indicator')), findsOneWidget,
          reason:
              'a listen should not cost the child the session they were in');

      // The pipeline really was rebuilt, not just flagged: a note heard now
      // still advances the song. Also in runAsync, because the restarted
      // capture subscribes in the real zone — the fake-pump `play` helper could
      // not deliver PCM to it.
      await tester.runAsync(() async {
        mic.emit(pcmToneFor('E4'));
        mic.emit(pcmSilenceFor(seconds: 0.15));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      expect(find.byKey(const Key('target-D4')), findsOneWidget);
    });

    testWidgets('a denied mic still gets the demo', (tester) async {
      // The main reason a child cannot get the tune out of their own fingers is
      // that the app is not allowed to hear them. Listening is unavailable on
      // that path; hearing must not be.
      mic.permission = false;
      await tester.pumpWidget(await app(mic));
      await tester.pumpAndSettle();
      await startListening(tester);
      expect(find.byKey(const Key('mic-permission-denied')), findsOneWidget);

      await tester.tap(find.byKey(const Key('hear-it')));
      await tester.pumpAndSettle();
      expect(find.byType(SongDemoDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('demo-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mic-permission-denied')), findsOneWidget);
    });
  });
  group('orientation', () {
    // The widget-test surface is 800x600, which is already landscape; these
    // pin both orientations explicitly so the layout swap is actually covered.
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await app(mic));
      await tester.pumpAndSettle();
    }

    testWidgets('landscape puts the keys beside the coaching panel',
        (tester) async {
      await pumpAt(tester, const Size(900, 420));
      final panel = tester.getRect(find.byKey(const Key('coaching-message')));
      final keys = tester.getRect(find.byKey(const Key('keys-layer')));
      // Side by side: the board occupies the right of the screen and uses most
      // of its height, instead of a crushed strip under stacked text.
      expect(keys.left, greaterThan(panel.right));
      expect(keys.height, greaterThan(420 * 0.6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('portrait keeps the keys below the panel', (tester) async {
      await pumpAt(tester, const Size(420, 900));
      final panel = tester.getRect(find.byKey(const Key('coaching-message')));
      final keys = tester.getRect(find.byKey(const Key('keys-layer')));
      expect(keys.top, greaterThan(panel.bottom));
      // Portrait keeps the established ~30%-of-screen board: the guide is not
      // flexed, so it falls back to the screen-height fraction rather than
      // eating every remaining pixel.
      expect(keys.height, greaterThan(900 * 0.25));
      expect(keys.height, lessThan(900 * 0.4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the guide window is anchored to a C', (tester) async {
      await pumpAt(tester, const Size(420, 900));
      // The song starts on E4; a centred window would begin mid-octave and
      // render a keyboard whose black-key pattern does not exist.
      final keyboard = tester.widget<IllustratedKeyboard>(
        find.byType(IllustratedKeyboard),
      );
      expect(midiFromNote(keyboard.windowNotes.first)! % 12, 0,
          reason: 'window starts on ${keyboard.windowNotes.first}');
      expect(keyboard.windowNotes, contains('E4'));
    });

    testWidgets('landscape does not overflow on a small phone', (tester) async {
      await pumpAt(tester, const Size(640, 320));
      await startListening(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
