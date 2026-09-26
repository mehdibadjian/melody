import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/screens/acoustic_practice_screen.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';
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

  Future<Widget> app(FakeMicCapture fake) async {
    final prefs = await SharedPreferences.getInstance();
    return UncontrolledProviderScope(
      container: ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioEngineProvider.overrideWith((ref) => SynthAudioEngine()),
        micCaptureProvider.overrideWithValue(fake),
      ]),
      child: const MaterialApp(home: AcousticPracticeScreen(level: song)),
    );
  }

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

  testWidgets('playing the whole song completes and celebrates',
      (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    for (final note in song.requiredNotes) {
      await play(tester, note);
    }

    expect(find.byKey(const Key('song-complete')), findsOneWidget);
    expect(find.textContaining('You played it'), findsOneWidget);
  });

  testWidgets('progress strip shows position through the song', (tester) async {
    await tester.pumpWidget(await app(mic));
    await tester.pumpAndSettle();
    await startListening(tester);

    await play(tester, 'E4');

    // 1 of 7 notes done.
    expect(find.textContaining('1 / 7'), findsOneWidget);
  });
}
