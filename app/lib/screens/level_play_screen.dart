import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:melody_app/domain/keyboard/keyboard_instrument.dart';
import 'package:melody_app/domain/session/level_session_flow.dart';
import 'package:melody_app/providers.dart';
import '../widgets/piano_keyboard.dart';

class LevelPlayScreen extends ConsumerStatefulWidget {
  const LevelPlayScreen({super.key, required this.level});

  final Level level;

  @override
  ConsumerState<LevelPlayScreen> createState() => _LevelPlayScreenState();
}

class _LevelPlayScreenState extends ConsumerState<LevelPlayScreen> {
  late final KeyboardInstrument _instrument;
  late final LevelSessionFlow _flow;

  /// Working copy of player progress for this session; committed back to the
  /// provider (as a fresh instance) when the run completes.
  late final PlayerProgress _sessionProgress;
  int _submittedCount = 0;

  @override
  void initState() {
    super.initState();
    final audio = ref.read(audioEngineProvider);
    _sessionProgress = ref.read(playerProgressProvider).clone();
    _instrument = KeyboardInstrument(audio: audio);
    _flow = LevelSessionFlow(
      level: widget.level,
      instrument: _instrument,
      progress: _sessionProgress,
      onAnalyticsEvent: (event) {
        ref.read(analyticsStoreProvider).append(event);
      },
    );
  }

  @override
  void dispose() {
    _instrument.dispose();
    super.dispose();
  }

  void _onKeyTap(String note) {
    _instrument.press(note);
    _flow.submit(
      NoteEvent(note: note, timestampMs: DateTime.now().millisecondsSinceEpoch),
    );
    _instrument.release(note);
    setState(() {
      _submittedCount++;
      if (_flow.isComplete) {
        ref
            .read(playerProgressProvider.notifier)
            .commitSessionProgress(_sessionProgress);
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
    final progress = ref.watch(playerProgressProvider);
    final requiredNotes = widget.level.requiredNotes;
    final targetNote =
        requiredNotes[_submittedCount.clamp(0, requiredNotes.length - 1)];
    return Scaffold(
      appBar: AppBar(title: Text(widget.level.name)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final keyboardHeight = constraints.maxHeight * 0.35;
          return Column(
            children: [
              ProgressHud(
                  stars: progress.stars, noteCurrency: progress.noteCurrency),
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
              PianoKeyboard(
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

/// Stars + note-currency readout shown during play (PRD §6 reward economy).
class ProgressHud extends StatelessWidget {
  const ProgressHud(
      {super.key, required this.stars, required this.noteCurrency});

  final int stars;
  final int noteCurrency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.amber),
          const SizedBox(width: 4),
          Text('Stars $stars'),
          const SizedBox(width: 16),
          const Icon(Icons.music_note, color: Colors.deepPurple),
          const SizedBox(width: 4),
          Text('Notes $noteCurrency'),
        ],
      ),
    );
  }
}
