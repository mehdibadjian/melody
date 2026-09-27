import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/rhythm/song_meter.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/widgets/song_demo_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The demo dialog, driven by the fake clock so timing assertions are exact
/// rather than racy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const simple4 = Level(
    id: 'demo-simple',
    name: 'Four Notes',
    type: LevelType.standard,
    requiredNotes: ['C4', 'D4', 'E4', 'G4'],
    tempoBpm: 120,
    successThreshold: SuccessThreshold(minAccuracy: 0.7, minNotesHit: 3),
    rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
  );

  /// The GOLDEN shape: 12/8, four dotted-quarter beats, three notes each,
  /// arranged slower than the recording.
  const compound = Level(
    id: 'demo-compound',
    name: 'Anthem',
    type: LevelType.standard,
    requiredNotes: ['G4', 'G4', 'A4', 'B4', 'G4', 'G4', 'A4', 'B4'],
    tempoBpm: 92,
    meter: SongMeter(
        beatsPerMeasure: 4, beatUnit: 4, dotted: true, notesPerBeat: 3),
    songTempoBpm: 123,
    successThreshold: SuccessThreshold(minAccuracy: 0.7, minNotesHit: 6),
    rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
  );

  late SynthAudioEngine engine;

  Future<void> openDemo(WidgetTester tester, Level level) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The synth double records what it was asked to sound, so a test can
      // assert the demo drove real audio without a platform channel.
      audioEngineProvider.overrideWith((ref) => engine),
    ]);
    await engine.initialize();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SongDemoDialog(level: level)),
      ),
    );
  }

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('demo-status'))).data!;

  String tempo(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('demo-tempo'))).data!;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine = SynthAudioEngine();
  });

  testWidgets('the demo names the tempo and the beat it counts',
      (tester) async {
    await openDemo(tester, simple4);

    expect(tempo(tester), contains('4/4'));
    expect(tempo(tester), contains('120'));
    expect(tempo(tester), contains('quarter'));
    // Nothing is playing yet, so the child is told what to do first.
    expect(status(tester), contains('Press play'));
  });

  testWidgets('a compound arrangement shows 12/8 and a dotted-quarter beat',
      (tester) async {
    await openDemo(tester, compound);

    expect(tempo(tester), contains('12/8'));
    expect(tempo(tester), contains('dotted quarter'));
  });

  testWidgets('a slower arrangement says how fast the real song is',
      (tester) async {
    await openDemo(tester, compound);

    final song = find.byKey(const Key('demo-song-tempo'));
    expect(song, findsOneWidget);
    expect(tester.widget<Text>(song).data, contains('123'));
  });

  testWidgets('a level at the song tempo does not claim to be practice speed',
      (tester) async {
    await openDemo(tester, simple4);

    expect(find.byKey(const Key('demo-song-tempo')), findsNothing);
    expect(tempo(tester), isNot(contains('practice speed')));
  });

  testWidgets('play sounds the notes in order and follows them on screen',
      (tester) async {
    await openDemo(tester, simple4);

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pump(const Duration(milliseconds: 10));
    // Count-in bar: 2000ms of clicks before note 0 at 120bpm in 4/4.
    expect(status(tester), contains('Count in'));

    await tester.pump(const Duration(milliseconds: 2000));
    expect(status(tester), contains('Note 1 of 4'));

    await tester.pump(const Duration(milliseconds: 500));
    expect(status(tester), contains('Note 2 of 4'));

    await tester.pump(const Duration(milliseconds: 1500));
    expect(status(tester), contains('Note 4 of 4'));

    // Stop cleanly so no timer outlives the test.
    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pumpAndSettle();
  });

  testWidgets('the beat dots light up in turn, one per beat of the bar',
      (tester) async {
    await openDemo(tester, simple4);

    // Four dots in a 4/4 bar, and no fifth.
    expect(find.byKey(const Key('demo-beat-0')), findsOneWidget);
    expect(find.byKey(const Key('demo-beat-3')), findsOneWidget);
    expect(find.byKey(const Key('demo-beat-4')), findsNothing);

    Color dotColor(WidgetTester tester, int beat) => (tester
            .widget<AnimatedContainer>(find.byKey(Key('demo-beat-$beat')))
            .decoration as BoxDecoration)
        .color!;

    // The dots fade over 90ms, so every check advances the clock and then
    // settles the fade before reading a colour.
    Future<void> advance(WidgetTester tester, int ms) async {
      await tester.pump(Duration(milliseconds: ms));
      await tester.pump(const Duration(milliseconds: 120));
    }

    final idle = dotColor(tester, 0);

    await tester.tap(find.byKey(const Key('demo-play')));
    await advance(tester, 10);
    // Count-in beat 0 is live, and it is amber — a count-in is not the tune.
    expect(dotColor(tester, 0), isNot(idle));
    expect(dotColor(tester, 1), idle);

    await advance(tester, 500);
    expect(dotColor(tester, 1), isNot(idle));
    expect(dotColor(tester, 0), idle);

    await advance(tester, 1500);
    // Beat 0 of the melody's first bar, now a different colour because the
    // tune has started.
    expect(dotColor(tester, 0), isNot(idle));

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pumpAndSettle();
  });

  testWidgets('the metronome switch is respected on the next play',
      (tester) async {
    await openDemo(tester, simple4);

    await tester.tap(find.byKey(const Key('demo-clicks')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pump(const Duration(milliseconds: 2100));
    // Melody still plays with the clicks off — the switch is not a mute.
    expect(status(tester), contains('Note 1 of 4'));

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pumpAndSettle();
  });

  testWidgets('choosing Slow drops the displayed tempo and labels it',
      (tester) async {
    await openDemo(tester, simple4);

    await tester.tap(find.byKey(const Key('demo-speed-Slow')));
    await tester.pump();

    expect(tempo(tester), contains('72'));
    expect(tempo(tester), contains('practice speed'));
  });

  testWidgets('stop resets the demo to its resting state', (tester) async {
    await openDemo(tester, simple4);

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pump(const Duration(milliseconds: 2500));
    expect(status(tester), contains('Note 2 of 4'));

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pumpAndSettle();

    expect(status(tester), contains('Press play'));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('the play button becomes Stop while the demo runs',
      (tester) async {
    await openDemo(tester, simple4);

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pumpAndSettle();
  });

  testWidgets('play drives the audio engine, notes and both click weights',
      (tester) async {
    await openDemo(tester, simple4);

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pump(const Duration(milliseconds: 10));
    // Downbeat click, then a weak one — a metronome that cannot tell them
    // apart does not teach where the bar begins.
    expect(engine.lastClickStrong, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.lastClickStrong, isFalse);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(engine.lastPlayedNote, 'C4');
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.lastPlayedNote, 'D4');

    await tester.tap(find.byKey(const Key('demo-play')));
    await tester.pumpAndSettle();
  });

  for (final size in const [Size(320, 480), Size(400, 900), Size(800, 360)]) {
    testWidgets('the demo fits a $size screen without overflowing',
        (tester) async {
      // An AlertDialog caps its content width, so a keyboard sized off the
      // screen width can demand more than the dialog is allowed to give. The
      // short landscape case is the tight one: the dialog has to scroll rather
      // than spill the piano over the buttons.
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openDemo(tester, simple4);

      await tester.tap(find.byKey(const Key('demo-play')));
      await tester.pump(const Duration(milliseconds: 2200));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('demo-play')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Done closes the dialog', (tester) async {
    await openDemo(tester, simple4);

    await tester.tap(find.byKey(const Key('demo-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('demo-play')), findsNothing);
  });
}
