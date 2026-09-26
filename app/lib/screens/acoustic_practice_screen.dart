import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/coaching/acoustic_practice_controller.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/providers.dart';
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

  /// Half-octave-plus window so a child sees a couple of keys of context either
  /// side of the target without the board becoming unreadable on a phone.
  static const _windowSize = 15;

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
    final window = _board.visibleWindow(anchor, size: _windowSize);

    return Scaffold(
      appBar: AppBar(title: Text(widget.level.name)),
      body: SafeArea(
        child: Column(
          children: [
            _SongProgress(index: snap.coach.index, total: notes.length),
            Expanded(child: _CoachingPanel(snap: snap)),
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
            _KeyboardGuide(
              window: window,
              targetNote: anchor,
              detectedNote: snap.detectedNote,
              arrow: snap.feedback?.arrow,
              isComplete: snap.complete,
            ),
          ],
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$done / $total', style: const TextStyle(fontSize: 18)),
              Text(index >= total ? 'Done!' : 'Keep going',
                  style: const TextStyle(fontSize: 16)),
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
      return Center(
        child: Column(
          key: const Key('song-complete'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.celebration, size: 72, color: Colors.amber),
            const SizedBox(height: 8),
            Text('You played it!', style: theme.textTheme.headlineMedium),
            Text('${snap.coach.correctHits} notes — nice work!'),
          ],
        ),
      );
    }
    final fb = snap.feedback;
    final message = fb?.message ?? 'Play ${snap.targetNote}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Play this note:', style: TextStyle(fontSize: 16)),
            Text(snap.targetNote ?? '',
                style: theme.textTheme.displayLarge
                    ?.copyWith(color: const Color(0xFF00C853))),
            const SizedBox(height: 12),
            Text(
              message,
              key: const Key('coaching-message'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: fb?.isCorrect == true ? Colors.green : Colors.deepOrange,
              ),
            ),
          ],
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
        Icon(Icons.graphic_eq, color: Colors.red, size: 28),
        SizedBox(width: 8),
        Text('Listening… play the highlighted key',
            style: TextStyle(fontSize: 16)),
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
            'Melody needs the microphone to hear you play. '
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
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.30,
      child: IllustratedKeyboard(
        windowNotes: window,
        targetNote: targetNote,
        detectedNote: detectedNote,
        arrow: isComplete ? null : arrow,
        onNote: null, // read-only guide: input comes from the real keyboard
        height: MediaQuery.of(context).size.height * 0.30,
      ),
    );
  }
}
