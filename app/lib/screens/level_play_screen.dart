import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/content/content_models.dart';
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
  int _submittedCount = 0;

  @override
  void initState() {
    super.initState();
    final audio = ref.read(audioEngineProvider);
    final progress = ref.read(playerProgressProvider);
    _instrument = KeyboardInstrument(audio: audio);
    _flow = LevelSessionFlow(
      level: widget.level,
      instrument: _instrument,
      progress: progress,
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
