import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/widgets/lesson_quest_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const standard = Level(
    id: 'l-a',
    name: 'Verse',
    type: LevelType.standard,
    requiredNotes: ['C4', 'D4', 'E4'],
    tempoBpm: 80,
    successThreshold: SuccessThreshold(minAccuracy: 0.7, minNotesHit: 2),
    rewardPayout: RewardPayout(stars: 3, noteCurrency: 5),
  );

  const boss = Level(
    id: 'l-b',
    name: 'Boss',
    type: LevelType.bossBattle,
    requiredNotes: ['G4', 'A4'],
    tempoBpm: 100,
    successThreshold: SuccessThreshold(minAccuracy: 0.8, minNotesHit: 2),
    rewardPayout: RewardPayout(stars: 5, noteCurrency: 10),
  );

  const lesson = Lesson(
    id: 'q1',
    title: 'Ode to Joy',
    difficulty: Difficulty.beginner,
    levels: [standard, boss],
  );

  // `PlayerProgress` has no public named constructor (state is only ever moved
  // forward by gameplay), so cleared levels are applied through the real API.
  PlayerProgress progressWith(Set<String> done) {
    final progress = PlayerProgress.initial(profileId: 'p1');
    for (final level in [standard, boss]) {
      if (done.contains(level.id)) {
        progress.applyLevelCompletion(
          levelId: level.id,
          payout: level.rewardPayout,
          accuracy: 1,
        );
      }
    }
    return progress;
  }

  Future<void> pump(
    WidgetTester tester, {
    required Lesson lesson,
    required PlayerProgress progress,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: LessonQuestTile(
              lesson: lesson,
              progress: progress,
              onTap: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows title, difficulty and the total reward', (tester) async {
    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {}),
    );
    expect(find.text('Ode to Joy'), findsOneWidget);
    expect(find.text('beginner'), findsOneWidget);
    // 3 + 5 stars, 5 + 10 notes: the stakes are readable before the tap.
    expect(find.text('8'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('the badge letter comes from the song, not a generic glyph',
      (tester) async {
    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {}),
    );
    // First required note is C4 -> the pitch-class letter 'C'.
    expect(find.byKey(const Key('quest-badge-q1')), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('renders one pip per level and a cleared count', (tester) async {
    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {'l-a'}),
    );
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byKey(const Key('pip-l-a')), findsOneWidget);
    expect(find.byKey(const Key('pip-l-b')), findsOneWidget);
  });

  testWidgets('progress ring appears only once something is cleared',
      (tester) async {
    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {}),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {'l-a'}),
    );
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, 0.5);
  });

  testWidgets('a fully cleared lesson gets the crown and a done label',
      (tester) async {
    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {'l-a', 'l-b'}),
    );
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('done'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, 1.0);
    expect(ring.valueColor!.value, const Color(0xFFFBBF24));
  });

  testWidgets('a boss lesson is marked on the badge and the title row',
      (tester) async {
    await pump(
      tester,
      lesson: lesson,
      progress: progressWith(const {}),
    );
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('an all-standard lesson shows no boss affordance',
      (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q2',
        title: 'Twinkle',
        difficulty: Difficulty.intermediate,
        levels: [standard],
      ),
      progress: progressWith(const {}),
    );
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    expect(find.byIcon(Icons.bolt), findsNothing);
    expect(find.text('beginner'), findsNothing);
    expect(find.text('intermediate'), findsOneWidget);
  });

  testWidgets('advanced difficulty uses its own tint', (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q3',
        title: 'Grand',
        difficulty: Difficulty.advanced,
        levels: [standard],
      ),
      progress: progressWith(const {}),
    );
    expect(find.text('advanced'), findsOneWidget);
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, const Color(0xFFFBF6FF));
  });

  testWidgets('a song title distinct from the lesson title is shown',
      (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q4',
        title: 'Lesson 3',
        difficulty: Difficulty.beginner,
        levels: [standard],
        songTitle: 'Hot Cross Buns',
      ),
      progress: progressWith(const {}),
    );
    expect(find.text('Lesson 3'), findsOneWidget);
    expect(find.text('Hot Cross Buns'), findsOneWidget);
  });

  testWidgets('a lesson with no levels does not divide by zero',
      (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q5',
        title: 'Empty',
        difficulty: Difficulty.beginner,
        levels: [],
      ),
      progress: progressWith(const {}),
    );
    expect(find.text('0/0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unparseable note is skipped for the badge', (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q6',
        title: 'Garbage',
        difficulty: Difficulty.beginner,
        levels: [
          Level(
            id: 'l-x',
            name: 'Bad notes',
            type: LevelType.standard,
            requiredNotes: ['nope', 'C4'],
            tempoBpm: 60,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.5, minNotesHit: 1),
            rewardPayout: RewardPayout(stars: 1, noteCurrency: 1),
          ),
        ],
      ),
      progress: progressWith(const {}),
    );
    // The unparseable entry is skipped rather than crashing or blanking.
    expect(find.text('C'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
  });

  testWidgets('a lesson with only unparseable notes still shows a badge',
      (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q7',
        title: 'No notes',
        difficulty: Difficulty.beginner,
        levels: [
          Level(
            id: 'l-y',
            name: 'All bad',
            type: LevelType.standard,
            requiredNotes: ['nope', ''],
            tempoBpm: 60,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.5, minNotesHit: 1),
            rewardPayout: RewardPayout(stars: 1, noteCurrency: 1),
          ),
        ],
      ),
      progress: progressWith(const {}),
    );
    expect(find.text('C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sharp-anchored song shows its accidental on the badge',
      (tester) async {
    await pump(
      tester,
      lesson: const Lesson(
        id: 'q8',
        title: 'Sharps',
        difficulty: Difficulty.beginner,
        levels: [
          Level(
            id: 'l-z',
            name: 'F sharp',
            type: LevelType.standard,
            requiredNotes: ['F#4', 'G4'],
            tempoBpm: 60,
            successThreshold:
                SuccessThreshold(minAccuracy: 0.5, minNotesHit: 1),
            rewardPayout: RewardPayout(stars: 1, noteCurrency: 1),
          ),
        ],
      ),
      progress: progressWith(const {}),
    );
    expect(find.text('F#'), findsOneWidget);
  });

  testWidgets('tapping the card fires onTap once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: LessonQuestTile(
              lesson: lesson,
              progress: progressWith(const {}),
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-tile-q1')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
