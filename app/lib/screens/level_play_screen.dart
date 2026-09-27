import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/coaching/coaching.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/instrument/note_event.dart';
import 'package:melody_app/domain/keyboard/keyboard_instrument.dart';
import 'package:melody_app/domain/session/level_session_flow.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/theme/tama_theme.dart';
import 'package:melody_app/widgets/piano_keyboard.dart';

/// On-screen-keyboard play screen: the child taps notes on the device.
///
/// The run is a loop with an exit and a way back in. Before this, a level ended
/// after exactly `requiredNotes.length` taps — including wrong ones — and then
/// [LevelSessionFlow.isComplete] latched, so every later tap did nothing at all
/// while the screen kept showing "Play this note". The result was delivered
/// only as a 3-second toast, so a child who fumbled once watched the level end,
/// read "try again", and found no way to try again without leaving and
/// re-entering. That is what this layout fixes: progress is always visible, a
/// finished run shows a result card with a Play again button, and a wrong tap
/// says what was heard and which way to move.
class LevelPlayScreen extends ConsumerStatefulWidget {
  const LevelPlayScreen({super.key, required this.level});

  final Level level;

  @override
  ConsumerState<LevelPlayScreen> createState() => _LevelPlayScreenState();
}

class _LevelPlayScreenState extends ConsumerState<LevelPlayScreen> {
  // Reassignable because Play again builds a fresh run in place; `final` would
  // throw a LateInitializationError the first time the button is tapped.
  late KeyboardInstrument _instrument;
  late LevelSessionFlow _flow;

  /// Working copy of player progress for this session; committed back to the
  /// provider (as a fresh instance) when the run completes.
  late PlayerProgress _sessionProgress;

  /// The last wrong tap, for the coaching line. Cleared on a hit so the child
  /// is not left reading an old complaint.
  CoachingFeedback? _miss;

  LevelRunResult? _result;

  @override
  void initState() {
    super.initState();
    _startRun(disposingPrevious: false);
  }

  /// Build a fresh run. Called on first entry and by Play again, so a replay
  /// does not have to leave the screen.
  void _startRun({required bool disposingPrevious}) {
    // The instrument owns a broadcast stream controller; without this each
    // replay would leak one.
    if (disposingPrevious) _instrument.dispose();
    final audio = ref.read(audioEngineProvider);
    // Re-clone from committed state: the previous run's payouts are already in
    // the provider, and re-applying them from a stale copy would double-pay.
    _sessionProgress = ref.read(playerProgressProvider).clone();
    _instrument = KeyboardInstrument(
      audio: audio,
      // Timing tolerance follows the level's tempo, so the tap path and the
      // acoustic path forgive the same slop on the same song.
      tempoBpm: widget.level.tempoBpm,
    );
    _flow = LevelSessionFlow(
      level: widget.level,
      instrument: _instrument,
      progress: _sessionProgress,
      onAnalyticsEvent: (event) {
        ref.read(analyticsStoreProvider).append(event);
      },
    );
    _miss = null;
    _result = null;
  }

  @override
  void dispose() {
    _instrument.dispose();
    super.dispose();
  }

  void _onKeyTap(String note) {
    if (_flow.isComplete) return;
    // Read the target before submitting: after a hit that completes the song
    // there is no next note, and the coaching line must name the note the child
    // was actually aiming at.
    final target = _flow.targetNote;
    if (target == null) return;
    _instrument.press(note);
    final hit = _flow.submit(
      NoteEvent(
        note: note,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _instrument.release(note);
    setState(() {
      // Same coaching the acoustic path uses, so a wrong tap in either mode
      // tells the child the same thing about the same mistake. Cleared on a hit
      // so an old complaint does not stay on screen.
      _miss = hit ? null : coach(detected: note, target: target);
      if (_flow.isComplete) {
        _result = _flow.result;
        ref
            .read(playerProgressProvider.notifier)
            .commitSessionProgress(_sessionProgress);
        _showResultToast();
      }
    });
  }

  /// Non-blocking, auto-dismissing toast (was a modal AlertDialog that forced a
  /// tap-through). The persistent result card below it is the part that stays.
  void _showResultToast() {
    final result = _flow.result;
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('result-toast'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            result.passed
                ? 'You did it! You earned ${result.starsAwarded} stars!'
                : 'So close! ${result.notesLanded} of '
                    '${widget.level.requiredNotes.length} notes — '
                    'tap Play again.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(playerProgressProvider);
    final notes = widget.level.requiredNotes;
    final targetNote = _flow.targetNote ?? notes.last;
    final done = _flow.notesCleared;
    return Scaffold(
      appBar: AppBar(title: Text(widget.level.name)),
      body: SafeArea(
        child: Column(
          children: [
            ProgressHud(
                stars: progress.stars, noteCurrency: progress.noteCurrency),
            SongProgressBar(done: done, total: notes.length),
            Expanded(
              child: Center(
                child: _result == null
                    ? _Prompt(targetNote: targetNote, miss: _miss)
                    : _ResultCard(
                        result: _result!,
                        level: widget.level,
                        onPlayAgain: () {
                          // The finished run's toast floats directly over the
                          // keys and survives a restart, so without this the
                          // fresh board spends its first seconds swallowing
                          // taps aimed at the piano.
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          setState(() => _startRun(disposingPrevious: true));
                        },
                      ),
              ),
            ),
            PianoKeyboard(
              onNote: _onKeyTap,
              targetNote: _result == null ? targetNote : notes.last,
              height: MediaQuery.sizeOf(context).height * 0.30,
            ),
          ],
        ),
      ),
    );
  }
}

/// The note to play, plus what went wrong if it did.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.targetNote, required this.miss});

  final String targetNote;
  final CoachingFeedback? miss;

  @override
  Widget build(BuildContext context) {
    final fb = miss;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Play this note:', style: TextStyle(fontSize: 16)),
            Text(
              targetNote,
              key: const Key('target-note'),
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(color: TamaColors.purple),
            ),
            const SizedBox(height: 12),
            SizedBox(
              // Fixed height so the layout does not jump between "go" and
              // "that one was wrong".
              height: 28,
              child: Text(
                fb?.message ?? '',
                key: const Key('coaching-message'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: TamaColors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once a run ends. The toast disappears in 3s; this does not, and it is
/// the only honest place to put a way back into the game.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.level,
    required this.onPlayAgain,
  });

  final LevelRunResult result;
  final Level level;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final total = level.requiredNotes.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            result.passed ? Icons.emoji_events : Icons.healing,
            size: 44,
            color: result.passed ? TamaColors.amber : TamaColors.purple,
          ),
          const SizedBox(height: 8),
          Text(
            result.passed ? 'You did it!' : 'Good try!',
            key: const Key('result-title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${result.notesLanded} of $total notes • '
            '${(result.accuracy * 100).round()}% accurate',
            key: const Key('result-detail'),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('play-again'),
            onPressed: onPlayAgain,
            icon: const Icon(Icons.replay),
            label: Text(result.passed ? 'Play again' : 'Try again'),
          ),
        ],
      ),
    );
  }
}

/// "Note 3 of 7" strip with a linear progress bar.
class SongProgressBar extends StatelessWidget {
  const SongProgressBar({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cleared = done.clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$cleared / $total',
                    style: const TextStyle(fontSize: 18)),
              ),
              Expanded(
                child: Text(cleared >= total ? 'Done!' : 'Keep going',
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : cleared / total,
              minHeight: 10,
            ),
          ),
        ],
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
          const Icon(Icons.star, color: TamaColors.amber),
          const SizedBox(width: 4),
          Text('Stars $stars'),
          const SizedBox(width: 16),
          const Icon(Icons.music_note, color: TamaColors.purple),
          const SizedBox(width: 4),
          Text('Notes $noteCurrency'),
        ],
      ),
    );
  }
}
