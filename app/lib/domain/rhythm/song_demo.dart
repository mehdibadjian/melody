/// A "listen first" demo: plays a level's notes in time, with a metronome, so a
/// child hears the rhythm and the tempo before they try to play it.
///
/// The scheduling maths lives here, pure and synchronous, and the only
/// side-effecting seam is a [TimerFactory]. That is deliberate: what is most
/// likely to be wrong in a feature like this is not the audio call, it is the
/// offsets — a demo that drifts, or clicks on a different pulse than the notes
/// move to, teaches the wrong rhythm more confidently than no demo at all. So
/// the whole timeline is a pure function of a [Level] and gets asserted note by
/// note in `test/domain/rhythm/song_demo_test.dart`.
library;

import 'dart:async';

import 'package:melody_app/domain/content/content_models.dart';

/// Schedules a callback [delay] from now. Production is [Timer]; tests capture
/// the callbacks and fire them by hand, which is how a four-bar timeline gets
/// verified without a four-second test.
typedef TimerFactory = Timer Function(Duration delay, void Function() callback);

/// One thing that happens during a demo: a melody note, or a metronome click.
class DemoEvent {
  const DemoEvent._({
    required this.atMs,
    required this.note,
    required this.noteIndex,
    required this.beatInMeasure,
  });

  /// A melody note. [noteIndex] is its position in `Level.requiredNotes`.
  const DemoEvent.note({
    required int atMs,
    required String note,
    required int noteIndex,
  }) : this._(atMs: atMs, note: note, noteIndex: noteIndex, beatInMeasure: -1);

  /// A metronome click. [beatInMeasure] is 0-based, so 0 is the downbeat.
  const DemoEvent.click({required int atMs, required int beatInMeasure})
      : this._(
            atMs: atMs,
            note: null,
            noteIndex: -1,
            beatInMeasure: beatInMeasure);

  /// Milliseconds from the start of the demo (the count-in begins at 0).
  final int atMs;

  /// The note to sound, or null for a click.
  final String? note;

  /// Index into the level's notes; -1 for a click.
  final int noteIndex;

  /// Which beat of the bar this click lands on; -1 for a melody note.
  final int beatInMeasure;

  bool get isClick => note == null;
  bool get isStrong => beatInMeasure == 0;
}

/// Where the demo is, published on every step so the UI can light up the key
/// and the beat dots together.
class DemoProgress {
  const DemoProgress({
    required this.note,
    required this.noteIndex,
    required this.totalNotes,
    required this.beatInMeasure,
    required this.beatsPerMeasure,
    required this.countingIn,
  });

  /// The note sounding now, or null during the count-in.
  final String? note;

  /// Index of [note] in the level; -1 during the count-in.
  final int noteIndex;
  final int totalNotes;

  /// The beat of the bar the child should be feeling right now.
  final int beatInMeasure;
  final int beatsPerMeasure;

  /// True while the count-in is playing, before note 0.
  final bool countingIn;

  /// How far through the melody this step is, for a progress bar.
  double get fraction =>
      totalNotes == 0 ? 1 : ((noteIndex + 1) / totalNotes).clamp(0.0, 1.0);
}

/// The planned timeline for one run of a level.
class DemoTimeline {
  const DemoTimeline._({
    required this.events,
    required this.leadInMs,
    required this.totalMs,
    required this.noteMs,
    required this.beatMs,
    required this.beatsPerMeasure,
  });

  /// Plans a run of [level].
  ///
  /// [tempoBpm] overrides the level's tempo for a slow-practice listen; it
  /// defaults to what the level says. [withClicks] off gives a clean melodic
  /// demo — the clicks are a teaching aid, not part of the tune.
  factory DemoTimeline.plan(Level level,
      {int? tempoBpm, bool withClicks = true}) {
    final bpm = tempoBpm ?? level.tempoBpm;
    final meter = level.meter;
    final beatMs = meter.beatMs(bpm);
    final noteMs = meter.noteMs(bpm);
    final events = <DemoEvent>[];

    // Count-in: one full bar of clicks, so the child feels the pulse and the
    // bar line before the tune starts, exactly like a teacher counting down.
    for (var beat = 0; beat < meter.beatsPerMeasure; beat++) {
      events.add(
          DemoEvent.click(atMs: (beat * beatMs).round(), beatInMeasure: beat));
    }
    final leadInMs = meter.measureMs(bpm).round();

    final notes = level.requiredNotes;
    for (var i = 0; i < notes.length; i++) {
      final atMs = (leadInMs + i * noteMs).round();
      events.add(DemoEvent.note(atMs: atMs, note: notes[i], noteIndex: i));
      if (!withClicks) continue;
      // Clicks run under the whole melody, not just the count-in: a child who
      // hears the pulse only before note 0 has been taught a tempo, not a
      // rhythm. One click per beat, landing on that beat's first note.
      if (i % meter.notesPerBeat == 0) {
        events.add(DemoEvent.click(
            atMs: atMs,
            beatInMeasure: (i ~/ meter.notesPerBeat) % meter.beatsPerMeasure));
      }
    }

    // Ring the last note out instead of ending exactly on it.
    final totalMs =
        (leadInMs + (notes.length - 1) * noteMs + noteMs * 2).round();
    return DemoTimeline._(
      events: events,
      leadInMs: leadInMs,
      totalMs: totalMs,
      noteMs: noteMs,
      beatMs: beatMs,
      beatsPerMeasure: meter.beatsPerMeasure,
    );
  }

  /// Every event, in the order it fires.
  final List<DemoEvent> events;

  /// When note 0 happens, i.e. the length of the count-in.
  final int leadInMs;

  /// When the demo is over.
  final int totalMs;

  /// Spacing between two melody notes.
  final double noteMs;

  /// Spacing between two clicks.
  final double beatMs;

  final int beatsPerMeasure;
}

/// Sounds one melody note.
abstract interface class NotePlayer {
  void playNote(String note);
}

/// Clicks the metronome; [strong] is the downbeat.
abstract interface class ClickPlayer {
  void click({required bool strong});
}

/// Plays a level's tune in time.
///
/// Deliberately not a `ValueNotifier` and not a Riverpod object: a screen owns
/// one, disposes it, and rebuilds on [onStep]. Stopping is always safe — every
/// scheduled callback checks the generation counter, so a timer that fires after
/// `stop()` (or after the screen is gone) is dropped rather than sounding a note
/// into a disposed audio engine.
class SongDemoPlayer {
  SongDemoPlayer({
    required this.level,
    required NotePlayer notes,
    ClickPlayer? clicks,
    TimerFactory? timerFactory,
    this.onStep,
    this.onComplete,
  })  : _notes = notes,
        _clicks = clicks,
        _timerFactory = timerFactory ?? Timer.new,
        _clicksByDefault = clicks != null;

  final Level level;
  final NotePlayer _notes;
  final ClickPlayer? _clicks;
  final TimerFactory _timerFactory;
  final bool _clicksByDefault;

  /// Called on every melody note and every click, so the UI can follow along.
  final void Function(DemoProgress progress)? onStep;

  /// Called once when the timeline finishes on its own.
  final void Function()? onComplete;

  DemoTimeline? _timeline;
  int _generation = 0;
  bool _playing = false;
  final List<Timer> _pending = [];

  bool get isPlaying => _playing;

  /// The plan for the current (or most recent) run, for tempo/meter labels.
  DemoTimeline? get timeline => _timeline;

  /// Starts from the top. Restarting mid-run is expected — a child will hit
  /// play again before the first play has finished.
  void start({int? tempoBpm, bool? withClicks}) {
    stop();
    final generation = ++_generation;
    final timeline = DemoTimeline.plan(level,
        tempoBpm: tempoBpm, withClicks: withClicks ?? _clicksByDefault);
    _timeline = timeline;
    _playing = true;
    final meter = level.meter;
    final totalNotes = level.requiredNotes.length;

    for (final event in timeline.events) {
      _pending.add(_timerFactory(Duration(milliseconds: event.atMs), () {
        if (generation != _generation) return;
        if (event.isClick) {
          _clicks?.click(strong: event.isStrong);
          // A click that lands on the same instant as a note (every beat after
          // the count-in) carries no news — the note reports that same beat.
          // Publishing it anyway would overwrite the note step, because both
          // fire in one clock tick and the click is scheduled second; the
          // visible symptom is a demo stuck announcing "note 1" all the way
          // through the tune.
          if (event.atMs >= timeline.leadInMs) return;
        } else {
          _notes.playNote(event.note!);
        }
        onStep?.call(DemoProgress(
          note: event.note,
          noteIndex: event.noteIndex,
          totalNotes: totalNotes,
          beatInMeasure: event.isClick
              ? event.beatInMeasure
              : (event.noteIndex ~/ meter.notesPerBeat) % meter.beatsPerMeasure,
          beatsPerMeasure: meter.beatsPerMeasure,
          countingIn: event.atMs < timeline.leadInMs,
        ));
      }));
    }
    _pending.add(_timerFactory(Duration(milliseconds: timeline.totalMs), () {
      if (generation != _generation) return;
      _playing = false;
      onComplete?.call();
    }));
  }

  /// Silences the demo. Safe when not playing, and safe to call twice.
  ///
  /// Cancels the timers rather than only ignoring them: the generation counter
  /// already makes a late callback harmless, but a song demo schedules a timer
  /// per note — 85 for GOLDEN's hardest arrangement, some minutes out — and
  /// leaving those alive holds the isolate open long after the child has left.
  void stop() {
    _generation++;
    _playing = false;
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
  }

  /// Releases the player; a disposed demo must never be restarted.
  void dispose() => stop();
}
