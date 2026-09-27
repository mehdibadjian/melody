import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/coaching/acoustic_practice_controller.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/theme/tama_theme.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';

/// Acoustic practice screen — the real-keyboard coaching experience.
///
/// The child plays their own electric piano; the app listens through the mic
/// and guides them note by note. An illustrated keyboard shows *which physical
/// key* to press, the current target glows green, the note the mic just heard is
/// marked orange, and a directional arrow + plain-language message tells them
/// how to correct a wrong note ("too high — move down to C4"). A wrong note
/// never advances or fails them; they stay until they land it (PRD §3).
///
/// All audio is analysed on-device for pitch only and never stored or sent
/// anywhere (PRD §7, COPPA/GDPR-K).
class AcousticPracticeScreen extends ConsumerStatefulWidget {
  const AcousticPracticeScreen({super.key, required this.level});

  final Level level;

  @override
  ConsumerState<AcousticPracticeScreen> createState() =>
      _AcousticPracticeScreenState();
}

class _AcousticPracticeScreenState
    extends ConsumerState<AcousticPracticeScreen> {
  late final AcousticPracticeController _controller;

  /// Working copy of progress, committed back on completion (matches the
  /// on-screen keyboard flow in LevelPlayScreen).
  late final PlayerProgress _sessionProgress;

  static final KeyboardLayout _board = KeyboardLayout.sixtyOne;

  /// Two octaves (25 keys) around the target. The window is C-anchored rather
  /// than merely centred — see [KeyboardLayout.octaveAlignedWindow] — so the
  /// black-key pattern matches the note names at every width.
  static const _windowOctaves = 2;

  @override
  void initState() {
    super.initState();
    _sessionProgress = ref.read(playerProgressProvider).clone();
    _controller = AcousticPracticeController(
      notes: widget.level.requiredNotes,
      mic: ref.read(micCaptureProvider),
      level: widget.level,
      childProfileId: ref.read(playerProgressProvider).profileId,
      onAnalyticsEvent: (e) => ref.read(analyticsStoreProvider).append(e),
      onComplete: (_) => _onSongComplete(),
    );
    _controller.addListener(_onSnapshot);
  }

  void _onSnapshot(AcousticSnapshot snapshot) {
    if (!mounted) return;
    setState(() {});
  }

  void _onSongComplete() {
    final passed = _controller.snapshot.coach.accuracy >=
            widget.level.successThreshold.minAccuracy &&
        _controller.snapshot.coach.correctHits >=
            widget.level.successThreshold.minNotesHit;
    if (passed) {
      _sessionProgress.applyLevelCompletion(
        levelId: widget.level.id,
        payout: widget.level.rewardPayout,
        accuracy: _controller.snapshot.coach.accuracy,
      );
    }
    _sessionProgress.recordPracticeDay(DateTime.now().toUtc());
    ref
        .read(playerProgressProvider.notifier)
        .commitSessionProgress(_sessionProgress);
    // Stop listening once done so the mic light goes off.
    _controller.stopListening();
    // Celebrate non-blockingly: a toast, never a full-screen takeover or modal.
    _showResultToast();
  }

  /// Non-blocking, auto-dismissing toast (mirrors LevelPlayScreen). The result
  /// is delivered as a toast so the child is never interrupted by a popup.
  void _showResultToast() {
    final hits = _controller.snapshot.coach.correctHits;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('result-toast'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text('You played it! $hits notes — nice work!'),
        ),
      );
  }

  @override
  void dispose() {
    _controller.removeListener(_onSnapshot);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _controller.start();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snap = _controller.snapshot;
    final notes = widget.level.requiredNotes;
    // Target drives the window; fall back to the first note when complete.
    final anchor = snap.targetNote ?? notes.first;
    final window = _board.octaveAlignedWindow(anchor, octaves: _windowOctaves);

    final progress =
        _SongProgress(index: snap.coach.index, total: notes.length);
    final panel = Expanded(child: _CoachingPanel(snap: snap));
    final status = <Widget>[
      if (snap.permissionDenied)
        _PermissionDenied(onRetry: _start)
      else if (!snap.listening && !snap.complete)
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const Key('start-listening'),
            onPressed: _start,
            icon: const Icon(Icons.mic),
            label: const Text('Start listening'),
          ),
        )
      else if (snap.listening)
        const Padding(
          padding: EdgeInsets.all(12),
          child: _ListeningIndicator(),
        ),
    ];
    final guide = _KeyboardGuide(
      window: window,
      targetNote: anchor,
      detectedNote: snap.detectedNote,
      arrow: snap.feedback?.arrow,
      isComplete: snap.complete,
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.level.name)),
      body: SafeArea(
        // In landscape the phone is already short, so stacking a text panel on
        // top of a keyboard leaves both unreadable. The coaching readout and the
        // keys sit side by side instead, and the keys get the full remaining
        // height because they are the part the child has to aim at.
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.landscape) {
              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [progress, panel, ...status],
                    ),
                  ),
                  Expanded(flex: 4, child: guide),
                ],
              );
            }
            return Column(
              children: [progress, panel, ...status, guide],
            );
          },
        ),
      ),
    );
  }
}

/// "Note 3 of 7" strip with a linear progress bar.
class _SongProgress extends StatelessWidget {
  const _SongProgress({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final done = index.clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            // Both halves flex, because in landscape this strip shares the
            // screen with the keyboard and two bare Texts overflowed the rail.
            children: [
              Expanded(
                child: Text('$done / $total',
                    style: const TextStyle(fontSize: 18)),
              ),
              Expanded(
                child: Text(index >= total ? 'Done!' : 'Keep going',
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
              value: total == 0 ? 0 : done / total,
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// The big coaching readout: what to play, what was heard, and how to fix it.
class _CoachingPanel extends StatelessWidget {
  const _CoachingPanel({required this.snap});

  final AcousticSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snap.complete) {
      // Non-blocking inline "all done" state. The celebratory result is
      // delivered as a toast (see _showResultToast), so this is just a calm
      // resting indicator — never a full-screen takeover or popup.
      return Center(
        child: Column(
          key: const Key('song-complete'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 40, color: TamaColors.emerald),
            const SizedBox(height: 8),
            Text('All done — tap a lesson to play again',
                style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    final fb = snap.feedback;
    final message = fb?.message ?? 'Play ${snap.targetNote}';
    return Center(
      // FittedBox rather than a fixed layout: in landscape this panel sits in a
      // rail roughly a third of the screen tall, where the note name at
      // displayLarge plus the coaching line overflowed the box by ~50 px.
      // Scaling the whole block down keeps the text legible and on screen at
      // any height instead of clipping it.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Play this note:', style: TextStyle(fontSize: 16)),
              Text(snap.targetNote ?? '',
                  style: theme.textTheme.displayLarge
                      ?.copyWith(color: TamaColors.purple)),
              const SizedBox(height: 12),
              Text(
                message,
                key: const Key('coaching-message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: fb?.isCorrect == true
                      ? TamaColors.emerald
                      : TamaColors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeningIndicator extends StatelessWidget {
  const _ListeningIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: Key('listening-indicator'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.graphic_eq, color: TamaColors.rose, size: 28),
        SizedBox(width: 8),
        Flexible(
          child: Text('Listening… play the highlighted key',
              style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

/// Gentle, non-punitive prompt when the mic permission is off.
class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const Key('mic-permission-denied'),
        children: [
          const Text(
            'Tama Melody needs the microphone to hear you play. '
            'Allow it, then tap below.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('start-listening'),
            onPressed: onRetry,
            icon: const Icon(Icons.mic),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// The illustrated real-keyboard guide (read-only here: the child plays their
/// own instrument, not the screen).
///
/// It fills whatever box the parent gives it rather than sizing itself from the
/// full screen height, so the landscape side-by-side layout — where the keys
/// own only part of the screen — gets a board that actually fits instead of one
/// that overflows off the bottom.
class _KeyboardGuide extends StatelessWidget {
  const _KeyboardGuide({
    required this.window,
    required this.targetNote,
    required this.detectedNote,
    required this.arrow,
    required this.isComplete,
  });

  final List<String> window;
  final String targetNote;
  final String? detectedNote;
  final String? arrow;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height * 0.30;
        return SizedBox(
          height: height,
          child: IllustratedKeyboard(
            windowNotes: window,
            targetNote: targetNote,
            detectedNote: detectedNote,
            arrow: isComplete ? null : arrow,
            onNote: null, // read-only guide: input comes from the real keyboard
            height: height,
          ),
        );
      },
    );
  }
}
