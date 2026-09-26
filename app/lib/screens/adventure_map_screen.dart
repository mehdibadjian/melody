import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/providers.dart';
import 'level_play_screen.dart';

class AdventureMapScreen extends ConsumerWidget {
  const AdventureMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(lessonsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Melody Quest')),
      body: lessonsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Could not load lessons: $err')),
        data: (doc) => ListView(
          children: [
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LevelPlayScreen(level: lesson.levels.first),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
