import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/providers.dart';
import 'acoustic_practice_screen.dart';
import 'level_play_screen.dart';

/// How the child wants to play a lesson: on their own electric piano (the app
/// listens through the mic and coaches) or on the on-screen keyboard.
enum PlayMode { realKeyboard, onScreen }

class AdventureMapScreen extends ConsumerWidget {
  const AdventureMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(lessonsProvider);
    final progress = ref.watch(playerProgressProvider);
    final canClaim = progress.canClaimDailyChest(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Melody Quest'),
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
              ListTile(
                leading: Icon(
                  lesson.levels.any((l) => l.isBossBattle)
                      ? Icons.local_fire_department
                      : Icons.music_note,
                  size: 36,
                ),
                title: Text(lesson.title),
                subtitle: Text(lesson.difficulty.name),
                onTap: () => _choosePlayMode(context, lesson),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet letting the child pick how to play, then routes to the
  /// matching screen. Defaulting to a chooser keeps the real-keyboard
  /// experience one tap away without hiding the on-screen keyboard.
  Future<void> _choosePlayMode(BuildContext context, Lesson lesson) async {
    final mode = await showModalBottomSheet<PlayMode>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('How do you want to play ${lesson.title}?',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
            ),
            ListTile(
              key: const Key('play-mode-real-keyboard'),
              leading: const Icon(Icons.piano, size: 32),
              title: const Text('My real keyboard'),
              subtitle: const Text('Melody listens and guides your fingers'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(PlayMode.realKeyboard),
            ),
            ListTile(
              key: const Key('play-mode-on-screen'),
              leading: const Icon(Icons.touch_app, size: 32),
              title: const Text('On-screen keys'),
              subtitle: const Text('Tap the notes on your device'),
              onTap: () => Navigator.of(sheetContext).pop(PlayMode.onScreen),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (mode == null || !context.mounted) return;
    final level = lesson.levels.first;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (mode) {
          PlayMode.realKeyboard => AcousticPracticeScreen(level: level),
          PlayMode.onScreen => LevelPlayScreen(level: level),
        },
      ),
    );
  }
}
