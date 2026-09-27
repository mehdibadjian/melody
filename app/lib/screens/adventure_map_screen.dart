import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/theme/tama_theme.dart';
import 'package:melody_app/widgets/lesson_quest_tile.dart';
import 'package:melody_app/widgets/song_demo_dialog.dart';
import 'acoustic_practice_screen.dart';
import 'level_play_screen.dart';

/// How the child wants to play a lesson: hear the arrangement first (the demo),
/// play on their own electric piano (the app listens through the mic and
/// coaches), or play on the on-screen keyboard.
enum PlayMode { demo, realKeyboard, onScreen }

class AdventureMapScreen extends ConsumerWidget {
  const AdventureMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(lessonsProvider);
    final progress = ref.watch(playerProgressProvider);
    final canClaim = progress.canClaimDailyChest(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('$kTamaMelodyAppName Quest'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  const Icon(Icons.music_note, size: 20),
                  const SizedBox(width: 4),
                  Text('Notes ${progress.noteCurrency}'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: lessonsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Could not load lessons: $err')),
        data: (doc) => ListView(
          children: [
            ListTile(
              key: const Key('daily-chest-button'),
              enabled: canClaim,
              leading: const Icon(Icons.card_giftcard, size: 36),
              title: const Text('Daily Chest'),
              subtitle: Text(canClaim
                  ? 'Claim your daily notes!'
                  : 'Come back tomorrow (streak: ${progress.dailyChestStreak})'),
              onTap: canClaim
                  ? () => ref
                      .read(playerProgressProvider.notifier)
                      .claimDailyChest(DateTime.now())
                  : null,
            ),
            for (final lesson in doc.lessons)
              LessonQuestTile(
                lesson: lesson,
                progress: progress,
                onTap: () => _choosePlayMode(context, lesson, progress),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet letting the child pick an arrangement and how to play it,
  /// then routes to the matching screen. Defaulting to a chooser keeps the
  /// real-keyboard experience one tap away without hiding the on-screen
  /// keyboard.
  ///
  /// The arrangement row only appears for a song with more than one level.
  /// Every song in the shipped library was single-level, so without this the
  /// routing below could hardcode `levels.first` and nobody would notice; a
  /// multi-level song would silently offer only its easiest arrangement while
  /// its quest card showed pips that could never all fill.
  Future<void> _choosePlayMode(
    BuildContext context,
    Lesson lesson,
    PlayerProgress progress,
  ) async {
    var selectedIndex = _resumeIndex(lesson, progress);
    final chosen = await showModalBottomSheet<_LevelAndMode>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('How do you want to play ${lesson.title}?',
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                ),
                if (lesson.levels.length > 1) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < lesson.levels.length; i++)
                          _LevelChoice(
                            level: lesson.levels[i],
                            selected: i == selectedIndex,
                            cleared: progress.completedLevelIds
                                .contains(lesson.levels[i].id),
                            onTap: () => setSheetState(() => selectedIndex = i),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ListTile(
                  key: const Key('play-mode-demo'),
                  leading: const Icon(Icons.headphones, size: 32),
                  title: const Text('Hear it first'),
                  subtitle: const Text(
                      'Listen to the tune and feel the beat before you play'),
                  onTap: () => Navigator.of(sheetContext).pop(_LevelAndMode(
                      lesson.levels[selectedIndex], PlayMode.demo)),
                ),
                ListTile(
                  key: const Key('play-mode-real-keyboard'),
                  leading: const Icon(Icons.piano, size: 32),
                  title: const Text('My real keyboard'),
                  subtitle: const Text(
                      '$kTamaMelodyAppName listens and guides your fingers'),
                  onTap: () => Navigator.of(sheetContext).pop(_LevelAndMode(
                      lesson.levels[selectedIndex], PlayMode.realKeyboard)),
                ),
                ListTile(
                  key: const Key('play-mode-on-screen'),
                  leading: const Icon(Icons.touch_app, size: 32),
                  title: const Text('On-screen keys'),
                  subtitle: const Text('Tap the notes on your device'),
                  onTap: () => Navigator.of(sheetContext).pop(_LevelAndMode(
                      lesson.levels[selectedIndex], PlayMode.onScreen)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (chosen == null || !context.mounted) return;
    // A statement switch rather than an expression one, because the demo is a
    // dialog and not a route: it is a look at the tune, not a place to be.
    // Pushing it would stack a page the child has to back out of to reach the
    // play modes they were just looking at. Exhaustiveness is kept on purpose,
    // so a fourth mode fails the build instead of silently doing nothing.
    switch (chosen.mode) {
      case PlayMode.demo:
        await SongDemoDialog.show(context, chosen.level);
      case PlayMode.realKeyboard:
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AcousticPracticeScreen(level: chosen.level)));
      case PlayMode.onScreen:
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => LevelPlayScreen(level: chosen.level)));
    }
  }

  /// The arrangement to preselect: the first one not yet cleared, so a
  /// partially-learned song resumes where it was left rather than at the top.
  /// Falls back to the first level when all are cleared or none qualify.
  static int _resumeIndex(Lesson lesson, PlayerProgress progress) {
    for (var i = 0; i < lesson.levels.length; i++) {
      if (!progress.completedLevelIds.contains(lesson.levels[i].id)) return i;
    }
    return 0;
  }
}

/// A level and a play mode, chosen together in the lesson sheet.
class _LevelAndMode {
  const _LevelAndMode(this.level, this.mode);

  final Level level;
  final PlayMode mode;
}

/// One arrangement button in the lesson sheet, marked done once cleared.
class _LevelChoice extends StatelessWidget {
  const _LevelChoice({
    required this.level,
    required this.selected,
    required this.cleared,
    required this.onTap,
  });

  final Level level;
  final bool selected;
  final bool cleared;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? TamaColors.purple : TamaColors.ink.withOpacity(0.3);
    return Semantics(
      selected: selected,
      child: ActionChip(
        key: Key('level-choice-${level.id}'),
        avatar: Icon(
          cleared ? Icons.check_circle : Icons.music_note,
          size: 18,
          color: color,
        ),
        label: Text(level.name),
        backgroundColor:
            selected ? TamaColors.purple.withOpacity(0.15) : Colors.transparent,
        side: BorderSide(color: color, width: selected ? 2 : 1),
        onPressed: onTap,
      ),
    );
  }
}
