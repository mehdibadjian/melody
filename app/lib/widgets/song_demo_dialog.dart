import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/domain/rhythm/song_demo.dart';
import 'package:melody_app/domain/rhythm/song_meter.dart';
import 'package:melody_app/providers.dart';
import 'package:melody_app/theme/tama_theme.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';
import 'package:melody_app/widgets/piano_keyboard.dart';

/// "Listen first" demo: plays the arrangement through in time with a metronome,
/// lighting the key and the beat as it goes, so a child hears the rhythm and the
/// tempo before trying to play it themselves.
///
/// It is a dialog rather than a screen because that is where a child actually
/// wants it: after picking a song and an arrangement, before committing to a
/// play mode. The arrangement is what determines the tempo, so the demo has to
/// sit below the arrangement chooser, not beside it.
///
/// The player itself is [SongDemoPlayer]; this widget only owns its lifecycle
/// and draws what it reports.
class SongDemoDialog extends ConsumerStatefulWidget {
  const SongDemoDialog({super.key, required this.level});

  final Level level;

  /// Shows the demo and waits for the child to close it.
  static Future<void> show(BuildContext context, Level level) {
    return showDialog<void>(
      context: context,
      builder: (_) => SongDemoDialog(level: level),
    );
  }

  @override
  ConsumerState<SongDemoDialog> createState() => _SongDemoDialogState();
}

class _SongDemoDialogState extends ConsumerState<SongDemoDialog>
    implements NotePlayer, ClickPlayer {
  static final KeyboardLayout _board = KeyboardLayout.sixtyOne;

  /// Practice speeds, as a fraction of the arrangement's tempo. Default is
  /// Full: the point of the demo is that the child hears the tempo the song
  /// actually has, and Slow is there for when they cannot pick the notes out.
  static const _speeds = <String, double>{
    'Slow': 0.6,
    'Steady': 0.8,
    'Full': 1.0,
  };

  late SongDemoPlayer _player;
  DemoProgress? _progress;
  String _speed = 'Full';
  bool _clicksOn = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _player = SongDemoPlayer(
      level: widget.level,
      notes: this,
      clicks: this,
      onStep: (p) => setState(() {
        _progress = p;
        _finished = false;
      }),
      onComplete: () => setState(() => _finished = true),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // NotePlayer / ClickPlayer: the demo shares the app's one audio engine, so a
  // child hears the same piano they will play on.
  @override
  void playNote(String note) {
    final engine = ref.read(audioEngineProvider);
    engine.playNote(note).catchError((_) {});
  }

  @override
  void click({required bool strong}) {
    final engine = ref.read(audioEngineProvider);
    engine.playClick(strong: strong).catchError((_) {});
  }

  /// Keyboard height, capped so a short landscape screen does not push the
  /// play button off the dialog.
  double _keyboardHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.22).clamp(110.0, 220.0);

  /// The tempo to demo at, given the selected speed label.
  int get _tempoBpm =>
      (widget.level.tempoBpm * _speeds[_speed]!).round().clamp(40, 240);

  void _play() {
    setState(() => _finished = false);
    _player.start(tempoBpm: _tempoBpm, withClicks: _clicksOn);
  }

  void _stop() {
    _player.stop();
    setState(() {
      _progress = null;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final meter = level.meter;
    final progress = _progress;
    final notes = level.requiredNotes;
    // Follow the demo's current note, so the window travels with the tune;
    // before the first note, centre on where the tune starts.
    final anchor = progress?.note ?? notes.first;

    return AlertDialog(
      title: Text('Listen to ${level.name}'),
      // maxFinite, not a fraction of the screen: AlertDialog pads its own
      // inset and content padding, so a width taken from MediaQuery is wider
      // than the dialog can actually hold and the row spills off the edge.
      // This lets the dialog's interior decide, at any screen size.
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TempoLine(
                tempoBpm: _tempoBpm,
                levelTempoBpm: level.tempoBpm,
                songTempoBpm: level.songTempoBpm,
                meter: meter,
              ),
              const SizedBox(height: 8),
              _BeatRow(
                beatsPerMeasure: meter.beatsPerMeasure,
                activeBeat: progress?.beatInMeasure ?? -1,
                countingIn: progress?.countingIn ?? false,
              ),
              const SizedBox(height: 12),
              // LayoutBuilder, not MediaQuery: this keyboard is drawn inside a
              // dialog, which is narrower than the screen. Sizing the window off
              // the screen width asks for two octaves the dialog cannot hold and
              // the row spills off the right edge.
              LayoutBuilder(
                builder: (context, constraints) {
                  final octaves =
                      PianoKeyboard.octavesFor(constraints.maxWidth);
                  return SizedBox(
                    height: _keyboardHeight(context),
                    child: IllustratedKeyboard(
                      windowNotes:
                          _board.octaveAlignedWindow(anchor, octaves: octaves),
                      targetNote: anchor,
                      // Read-only: the demo is for listening. Tapping along
                      // would add a second voice a child cannot tell apart from
                      // the demo's.
                      onNote: null,
                      height: _keyboardHeight(context),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                progress == null
                    ? 'Press play and listen for the beat before you try it.'
                    : progress.countingIn
                        ? 'Count in…'
                        : 'Note ${progress.noteIndex + 1} of '
                            '${progress.totalNotes}',
                key: const Key('demo-status'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  key: const Key('demo-progress'),
                  value: progress?.fraction ?? 0,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              // Wrap, not Row: three chips plus their padding are wider than a
              // phone dialog's interior, and a Row overflows off the right edge
              // instead of dropping to a second line.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final label in _speeds.keys)
                    ChoiceChip(
                      key: Key('demo-speed-$label'),
                      label: Text(label),
                      selected: _speed == label,
                      onSelected: (_) => setState(() => _speed = label),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                key: const Key('demo-clicks'),
                title: const Text('Metronome'),
                subtitle: const Text('Click the beat while it plays'),
                value: _clicksOn,
                onChanged: (v) => setState(() => _clicksOn = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('demo-close'),
          onPressed: () {
            _player.dispose();
            Navigator.of(context).pop();
          },
          child: const Text('Done'),
        ),
        FilledButton.icon(
          key: const Key('demo-play'),
          onPressed: _player.isPlaying ? _stop : _play,
          icon: Icon(_player.isPlaying ? Icons.stop : Icons.play_arrow),
          label: Text(_player.isPlaying
              ? 'Stop'
              : _finished
                  ? 'Play again'
                  : 'Play'),
        ),
      ],
    );
  }
}

/// What the demo is about to do, in terms a child can act on.
///
/// The beat is named on purpose. "120 bpm" means nothing to a 7-year-old, and
/// means something *different* depending on which note value the arranger
/// counted: GOLDEN is marked `half note = 90` in some printed arrangements and
/// `dotted quarter = 123` in others, which is the same real speed written two
/// ways. Naming the beat keeps a slow demo and the real song from looking like
/// two different tempos, and shows the child which reading is being used.
class _TempoLine extends StatelessWidget {
  const _TempoLine({
    required this.tempoBpm,
    required this.levelTempoBpm,
    required this.songTempoBpm,
    required this.meter,
  });

  final int tempoBpm;
  final int levelTempoBpm;
  final int? songTempoBpm;
  final SongMeter meter;

  @override
  Widget build(BuildContext context) {
    final slower = tempoBpm < levelTempoBpm;
    // The song's own tempo, when the arrangement is deliberately slower than it.
    final song = songTempoBpm;
    final songLine = (song != null && song != levelTempoBpm)
        ? 'The song itself is $song per ${meter.beatName}.'
        : null;
    return Column(children: [
      Text(
        '${meter.notation} • $tempoBpm per ${meter.beatName} beat'
        '${slower ? ' (practice speed)' : ''}',
        key: const Key('demo-tempo'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: slower ? TamaColors.orange : TamaColors.purple,
        ),
      ),
      if (songLine != null)
        Text(
          songLine,
          key: const Key('demo-song-tempo'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: TamaColors.ink),
        ),
    ]);
  }
}

/// One dot per beat of the bar, lighting as the demo passes through. This is
/// the part that teaches "feel the pulse": a tempo number cannot do it.
class _BeatRow extends StatelessWidget {
  const _BeatRow({
    required this.beatsPerMeasure,
    required this.activeBeat,
    required this.countingIn,
  });

  final int beatsPerMeasure;
  final int activeBeat;
  final bool countingIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('demo-beats'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var beat = 0; beat < beatsPerMeasure; beat++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: AnimatedContainer(
              key: Key('demo-beat-$beat'),
              duration: const Duration(milliseconds: 90),
              width: beat == 0 ? 22 : 16,
              height: beat == 0 ? 22 : 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: beat == activeBeat
                    ? (countingIn ? TamaColors.amber : TamaColors.purple)
                    : TamaColors.ink.withOpacity(0.15),
              ),
            ),
          ),
      ],
    );
  }
}
