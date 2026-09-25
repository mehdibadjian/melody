import 'package:flutter/material.dart';

import 'domain/content/content_models.dart';
import 'domain/content/content_repository.dart';
import 'domain/gamification/player_progress.dart';
import 'domain/keyboard/keyboard_instrument.dart';
import 'domain/session/level_session_flow.dart';

void main() => runApp(const MelodyApp());

class MelodyApp extends StatelessWidget {
  const MelodyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Melody',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
      ),
      home: const AdventureMapScreen(),
    );
  }
}

/// Musical Quest framed as an adventure map (PRD §6): lessons as levels.
class AdventureMapScreen extends StatelessWidget {
  const AdventureMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Melody Quest')),
      body: FutureBuilder<ContentDocument>(
        future: const ContentRepository().loadLessons(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load lessons: ${snapshot.error}'));
          }
          final doc = snapshot.data!;
          return ListView(
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
                      builder: (_) => LevelPlayScreen(
                        level: lesson.levels.first,
                        progress: PlayerProgress.initial(),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Level play: adaptive layout — game zone on top, keyboard below
/// (PRD §6 adaptive UX strategy).
class LevelPlayScreen extends StatefulWidget {
  const LevelPlayScreen(
      {super.key, required this.level, required this.progress});

  final Level level;
  final PlayerProgress progress;

  @override
  State<LevelPlayScreen> createState() => _LevelPlayScreenState();
}

class _LevelPlayScreenState extends State<LevelPlayScreen> {
  late final KeyboardInstrument _instrument;
  late final LevelSessionFlow _flow;
  int _submittedCount = 0;

  @override
  void initState() {
    super.initState();
    _instrument = KeyboardInstrument();
    _flow = LevelSessionFlow(
      level: widget.level,
      instrument: _instrument,
      progress: widget.progress,
    );
  }

  @override
  void dispose() {
    _instrument.dispose();
    super.dispose();
  }

  void _onKeyTap(String note) {
    _instrument.press(note);
    _instrument.release(note);
    setState(() {
      _submittedCount++;
      if (_flow.isComplete) {
        _showResultDialog();
      }
    });
  }

  void _showResultDialog() {
    final result = _flow.result!;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(result.passed ? 'You did it!' : 'Nice try!'),
        content: Text(result.passed
            ? 'You earned ${result.starsAwarded} stars!'
            : 'Accuracy ${(result.accuracy * 100).round()}% — try again, you got this!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requiredNotes = widget.level.requiredNotes;
    final targetNote =
        requiredNotes[_submittedCount.clamp(0, requiredNotes.length - 1)];
    return Scaffold(
      appBar: AppBar(title: Text(widget.level.name)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Adaptive layout (PRD §6): stacked layout for phones — game view
          // dominates; keyboard sized for kid-friendly touch targets.
          final keyboardHeight = constraints.maxHeight * 0.35;
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Play this note:'),
                      Text(
                        targetNote,
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                    ],
                  ),
                ),
              ),
              _Keyboard(
                onNote: _onKeyTap,
                targetNote: targetNote,
                height: keyboardHeight,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Simplified 1-octave keyboard with color-coded, labeled keys
/// (PRD §6: color-coded/labeled early). Phone layout scales to ~1 octave;
/// wide screens show more keys (adaptive strategy, PRD §6).
class _Keyboard extends StatelessWidget {
  const _Keyboard({
    required this.onNote,
    required this.targetNote,
    required this.height,
  });

  final void Function(String note) onNote;
  final String targetNote;
  final double height;

  static const _whiteKeys = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  static const _whiteKeyColors = [
    Color(0xFFEF5350),
    Color(0xFFFFCA28),
    Color(0xFF66BB6A),
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
    Color(0xFF26C6DA),
  ];

  @override
  Widget build(BuildContext context) {
    final keys = MediaQuery.of(context).size.width > 900
        ? [..._whiteKeys, ..._whiteKeys] // tablet: up to 2 octaves of whites
        : _whiteKeys; // phone: 1 octave
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++)
            Expanded(
              child: Material(
                color: _whiteKeyColors[i % _whiteKeyColors.length],
                child: InkWell(
                  onTap: () =>
                      onNote('${keys[i]}${i < _whiteKeys.length ? 4 : 5}'),
                  child: Center(
                    child: Text(
                      '${keys[i]}${i < _whiteKeys.length ? 4 : 5}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
