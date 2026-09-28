import 'dart:async';

import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/rhythm/song_demo.dart';
import 'package:melody_app/domain/rhythm/song_meter.dart';
import 'package:test/test.dart';

/// Records what the demo asked to be heard, in order.
class _Recorder implements NotePlayer, ClickPlayer {
  final List<String> log = [];

  @override
  void playNote(String note) => log.add('note:$note');

  @override
  void click({required bool strong}) => log.add('click:${strong ? '1' : 'x'}');
}

/// Captures scheduled callbacks instead of waiting real seconds for them.
class _FakeTimers {
  final List<({Duration delay, void Function() callback})> scheduled = [];

  /// Returns a do-nothing timer: the callback lives in [scheduled] so the test
  /// can fire it in delay order, and the handle exists only so the player's
  /// cancel-on-stop path has something real to cancel.
  TimerFactory get factory => (delay, callback) {
        scheduled.add((delay: delay, callback: callback));
        return Timer(Duration.zero, () {});
      };

  /// Fires everything scheduled so far, in delay order, like the clock would.
  void runAll() {
    final pending = [...scheduled]..sort((a, b) => a.delay.compareTo(b.delay));
    scheduled.clear();
    for (final t in pending) {
      t.callback();
    }
  }
}

Level _level({
  required List<String> notes,
  int bpm = 120,
  SongMeter meter = SongMeter.simple,
  List<double>? durations,
}) =>
    Level(
      id: 't',
      name: 'T',
      type: LevelType.standard,
      requiredNotes: notes,
      tempoBpm: bpm,
      meter: meter,
      durations: durations,
      successThreshold:
          const SuccessThreshold(minAccuracy: 0.7, minNotesHit: 1),
      rewardPayout: const RewardPayout(stars: 1, noteCurrency: 1),
    );

/// The 12/8 shape GOLDEN is written in: four dotted-crotchet beats, three
/// notes to each.
const _compound =
    SongMeter(beatsPerMeasure: 4, beatUnit: 4, dotted: true, notesPerBeat: 3);

void main() {
  group('SongMeter', () {
    test('simple defaults to 4/4 with one note per beat', () {
      const meter = SongMeter();
      expect(meter.notation, '4/4');
      expect(meter.beatName, 'quarter');
      expect(meter.noteMs(120), 500);
      expect(meter.measureMs(120), 2000);
    });

    test('a dotted quarter beat notates as 12/8', () {
      expect(_compound.notation, '12/8');
      expect(_compound.beatName, 'dotted quarter');
    });

    test('three notes per beat puts each note a third of a beat apart', () {
      // 120 dotted-quarter beats per minute = 360 eighth notes per minute, so
      // an eighth is 166.67ms. This is the number that decides whether the demo
      // sounds like the song.
      expect(_compound.beatMs(120), closeTo(500, 0.001));
      expect(_compound.noteMs(120), closeTo(166.667, 0.01));
    });

    test('equal meters compare equal so toJson can omit them', () {
      expect(const SongMeter(), SongMeter.simple);
      expect(_compound, isNot(SongMeter.simple));
      // Equal values must hash equal, or a meter in a Set or Map key misbehaves.
      expect(
          _compound.hashCode,
          const SongMeter(
                  beatsPerMeasure: 4,
                  beatUnit: 4,
                  dotted: true,
                  notesPerBeat: 3)
              .hashCode);
    });

    test('every beat unit the parser accepts has a name a child can read', () {
      // The parser allows 1..16, so an unmapped unit still has to say something
      // sensible rather than throw while building the demo's tempo label.
      expect(const SongMeter(beatUnit: 1).beatName, 'whole');
      expect(const SongMeter(beatUnit: 2).beatName, 'half');
      expect(const SongMeter(beatUnit: 8).beatName, 'eighth');
      expect(const SongMeter(beatUnit: 16).beatName, 'sixteenth');
      expect(const SongMeter(beatUnit: 32).beatName, '32-th');
      expect(
          const SongMeter(beatUnit: 8, dotted: true).beatName, 'dotted eighth');
    });

    test('toString names the meter for a debug label', () {
      expect(_compound.toString(),
          'SongMeter(12/8, 3 notes per dotted quarter beat)');
      expect(SongMeter.simple.toString(),
          'SongMeter(4/4, 1 notes per quarter beat)');
    });
  });

  group('DemoTimeline.plan', () {
    test('count-in is one full bar of clicks before note 0', () {
      final timeline = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4', 'E4', 'G4'], bpm: 120));
      final clicks = timeline.events.where((e) => e.isClick).toList();
      // Four count-in clicks, then one per beat under the melody.
      expect(clicks.take(4).map((e) => e.atMs), [0, 500, 1000, 1500]);
      expect(clicks[0].isStrong, isTrue);
      expect(clicks[1].isStrong, isFalse);
      expect(timeline.leadInMs, 2000);
    });

    test('notes are spaced by the meter, not by assumption', () {
      final timeline = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4', 'E4', 'G4'], bpm: 120));
      final notes = timeline.events.where((e) => !e.isClick).toList();
      expect(notes.map((e) => e.atMs), [2000, 2500, 3000, 3500]);
      expect(notes.map((e) => e.note), ['C4', 'D4', 'E4', 'G4']);
      expect(notes.map((e) => e.noteIndex), [0, 1, 2, 3]);
    });

    test('compound meter spaces notes a third of a beat apart', () {
      final timeline = DemoTimeline.plan(_level(
        notes: const ['G4', 'G4', 'A4', 'B4', 'G4', 'G4', 'A4', 'B4'],
        bpm: 120,
        meter: _compound,
      ));
      final notes = timeline.events.where((e) => !e.isClick).toList();
      // One bar of count-in = 4 x 500ms = 2000ms, then eighths at 166.67ms.
      expect(notes[0].atMs, 2000);
      expect(notes[1].atMs, closeTo(2167, 1));
      expect(notes[2].atMs, closeTo(2333, 1));
      // The beat click lands with the first note of each group of three.
      final clicks = timeline.events
          .where((e) => e.isClick && e.atMs >= timeline.leadInMs)
          .toList();
      expect(clicks[0].atMs, 2000);
      expect(clicks[1].atMs, closeTo(2500, 1));
      expect(clicks[0].beatInMeasure, 0);
      expect(clicks[1].beatInMeasure, 1);
    });

    test('events come out in the order they fire', () {
      final timeline = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4', 'E4'], bpm: 96, meter: _compound));
      final times = timeline.events.map((e) => e.atMs).toList();
      final sorted = [...times]..sort();
      expect(times, sorted);
    });

    test('tempoBpm override slows the whole timeline proportionally', () {
      final level = _level(notes: const ['C4', 'D4'], bpm: 120);
      final full = DemoTimeline.plan(level);
      final slow = DemoTimeline.plan(level, tempoBpm: 60);
      expect(slow.noteMs, full.noteMs * 2);
      expect(slow.leadInMs, full.leadInMs * 2);
    });

    test('withClicks off leaves a clean melody', () {
      final timeline = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4', 'E4'], bpm: 120),
          withClicks: false);
      expect(timeline.events.where((e) => e.isClick).length, 4);
      expect(
          timeline.events
              .every((e) => e.isClick || e.atMs >= timeline.leadInMs),
          isTrue);
    });

    test('the timeline outlasts the last note so it can ring out', () {
      final timeline =
          DemoTimeline.plan(_level(notes: const ['C4', 'D4', 'E4'], bpm: 120));
      final last = timeline.events.last.atMs;
      expect(timeline.totalMs, greaterThan(last));
    });

    test('a one-note level still plans without going negative', () {
      final timeline = DemoTimeline.plan(_level(notes: const ['C4'], bpm: 120));
      expect(timeline.totalMs, greaterThan(timeline.leadInMs));
    });
  });

  group('DemoTimeline.plan with authored durations', () {
    // 4/4 at 120 bpm: a beat (and a base note) is 500ms, the count-in is one
    // 2000ms bar, so note 0 lands at 2000ms.
    test('a held note pushes everything after it later', () {
      final timeline = DemoTimeline.plan(_level(
          notes: const ['C4', 'D4', 'E4'],
          bpm: 120,
          durations: const [1, 3, 1]));
      final notes = timeline.events.where((e) => !e.isClick).toList();
      expect(notes.map((e) => e.atMs), [2000, 2500, 4000]);
      // D4 rings for three base notes, so E4 starts three slots later rather
      // than one — that gap is the rhythm the child is meant to hear.
      expect(notes[2].atMs - notes[1].atMs, 1500);
    });

    test('a dotted lilt spaces notes 1.5 and 0.5 slots apart', () {
      final timeline = DemoTimeline.plan(_level(
          notes: const ['C4', 'D4', 'E4'],
          bpm: 120,
          durations: const [1.5, 0.5, 2]));
      final notes = timeline.events.where((e) => !e.isClick).toList();
      expect(notes.map((e) => e.atMs), [2000, 2750, 3000]);
    });

    test('clicks keep the beat while a note is held across several beats', () {
      final timeline = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4'], bpm: 120, durations: const [1, 4]));
      final clicks = timeline.events.where((e) => e.isClick).toList();
      // Four count-in beats, then one click per beat of the melody: D4 is held
      // for four base notes, so three clicks land while it is still ringing.
      expect(clicks.length, 4 + 5);
      expect(clicks.map((e) => e.atMs),
          [0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000]);
      // The count-in still marks its downbeat, and the melody's beats keep
      // cycling through the bar rather than freezing on the held note's beat.
      expect(clicks[4].beatInMeasure, 0);
      expect(clicks[5].beatInMeasure, 1);
      expect(clicks[8].beatInMeasure, 4 % 4);
    });

    test('a note after a held one reports the beat it actually lands on', () {
      final timeline = DemoTimeline.plan(_level(
          notes: const ['C4', 'D4', 'E4', 'G4'],
          bpm: 120,
          durations: const [1, 4, 1, 2]));
      final notes = timeline.events.where((e) => !e.isClick).toList();
      // D4 is held across a whole bar, so E4 arrives on the second bar's
      // second beat rather than where an index-derived beat would put it.
      expect(notes.map((e) => e.atMs), [2000, 2500, 4500, 5000]);
      expect(notes.map((e) => e.beatInMeasure), [0, 1, 1, 2]);
    });

    test('the timeline covers a held final note and still rings out', () {
      final timeline = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4'], bpm: 120, durations: const [1, 4]));
      // D4 ends at 2500 + 4*500 = 4500ms; the timeline gives it one more slot.
      expect(timeline.totalMs, 5000);
      expect(timeline.totalMs,
          greaterThan(timeline.events.where((e) => !e.isClick).last.atMs));
    });

    test('durations divide a compound beat the same way the meter does', () {
      final timeline = DemoTimeline.plan(_level(
          notes: const ['C4', 'D4', 'E4'],
          bpm: 120,
          meter: _compound,
          durations: const [3, 3, 6]));
      // Three base notes to the dotted quarter: at 120 bpm a base note is
      // 166.7ms, so holding for 3 is exactly one beat.
      final notes = timeline.events.where((e) => !e.isClick).toList();
      expect(notes[1].atMs - notes[0].atMs, closeTo(500, 1));
      expect(notes[2].atMs - notes[1].atMs, closeTo(500, 1));
    });

    test('an unauthored level plans exactly as it did before durations existed',
        () {
      final plain = DemoTimeline.plan(
          _level(notes: const ['C4', 'D4', 'E4', 'G4'], bpm: 120));
      final explicit = DemoTimeline.plan(_level(
          notes: const ['C4', 'D4', 'E4', 'G4'],
          bpm: 120,
          durations: const [1, 1, 1, 1]));
      expect(explicit.totalMs, plain.totalMs);
      expect(explicit.leadInMs, plain.leadInMs);
      expect(explicit.events.map((e) => (e.atMs, e.noteIndex, e.isClick)),
          plain.events.map((e) => (e.atMs, e.noteIndex, e.isClick)));
    });
  });

  group('SongDemoPlayer', () {
    test('playing sounds every note of the level, in order', () {
      final recorder = _Recorder();
      final timers = _FakeTimers();
      final player = SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4', 'E4'], bpm: 120),
        notes: recorder,
        clicks: recorder,
        timerFactory: timers.factory,
      );
      player.start();
      timers.runAll();
      expect(
          recorder.log, containsAllInOrder(['note:C4', 'note:D4', 'note:E4']));
      expect(recorder.log.where((e) => e.startsWith('click')).length,
          greaterThanOrEqualTo(4));
    });

    test('the downbeat click is distinguishable from the others', () {
      final recorder = _Recorder();
      final timers = _FakeTimers();
      SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4', 'E4', 'G4'], bpm: 120),
        notes: recorder,
        clicks: recorder,
        timerFactory: timers.factory,
      ).start();
      timers.runAll();
      expect(recorder.log.first, 'click:1');
      expect(recorder.log, contains('click:x'));
    });

    test('stop() silences everything already scheduled', () {
      final recorder = _Recorder();
      final timers = _FakeTimers();
      final player = SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4', 'E4'], bpm: 120),
        notes: recorder,
        clicks: recorder,
        timerFactory: timers.factory,
      );
      player.start();
      player.stop();
      timers.runAll();
      expect(recorder.log, isEmpty);
      expect(player.isPlaying, isFalse);
    });

    test('a timer fired after stop() cannot sound a note', () {
      // The production risk: a child leaves the screen, the engine is disposed,
      // and a queued callback fires anyway.
      final recorder = _Recorder();
      final timers = _FakeTimers();
      final player = SongDemoPlayer(
        level: _level(notes: const ['C4'], bpm: 120),
        notes: recorder,
        clicks: recorder,
        timerFactory: timers.factory,
      );
      player.start();
      player.dispose();
      expect(timers.scheduled, isNotEmpty);
      timers.runAll();
      expect(recorder.log, isEmpty);
    });

    test('restarting mid-run does not double up the old timeline', () {
      final recorder = _Recorder();
      final timers = _FakeTimers();
      final player = SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4'], bpm: 120),
        notes: recorder,
        clicks: recorder,
        timerFactory: timers.factory,
      );
      player.start();
      player.start();
      timers.runAll();
      expect(recorder.log.where((e) => e == 'note:C4').length, 1);
    });

    test('onStep reports the note and beat so the UI can light them up', () {
      final steps = <DemoProgress>[];
      final timers = _FakeTimers();
      SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4', 'E4'], bpm: 120),
        notes: _Recorder(),
        clicks: _Recorder(),
        timerFactory: timers.factory,
        onStep: steps.add,
      ).start();
      timers.runAll();
      expect(steps.first.countingIn, isTrue);
      expect(steps.first.note, isNull);
      final played = steps.where((s) => s.note != null).toList();
      expect(played.map((s) => s.note), ['C4', 'D4', 'E4']);
      expect(played.last.fraction, 1.0);
      // Beats cycle through the bar rather than counting up forever.
      expect(played.map((s) => s.beatInMeasure), everyElement(lessThan(4)));
    });

    test('onComplete fires once, after the timeline ends', () {
      var completions = 0;
      final timers = _FakeTimers();
      final player = SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4'], bpm: 120),
        notes: _Recorder(),
        clicks: _Recorder(),
        timerFactory: timers.factory,
        onComplete: () => completions++,
      );
      player.start();
      timers.runAll();
      expect(completions, 1);
      expect(player.isPlaying, isFalse);
    });

    test('without a click player the demo still plays the melody', () {
      final recorder = _Recorder();
      final timers = _FakeTimers();
      SongDemoPlayer(
        level: _level(notes: const ['C4', 'D4'], bpm: 120),
        notes: recorder,
        timerFactory: timers.factory,
      ).start();
      timers.runAll();
      expect(recorder.log, ['note:C4', 'note:D4']);
    });

    test('withClicks false at start overrides the constructor default', () {
      final recorder = _Recorder();
      final timers = _FakeTimers();
      SongDemoPlayer(
        level: _level(notes: const ['C4'], bpm: 120),
        notes: recorder,
        clicks: recorder,
        timerFactory: timers.factory,
      ).start(withClicks: false);
      timers.runAll();
      // Count-in only: nothing under the melody.
      expect(recorder.log,
          ['click:1', 'click:x', 'click:x', 'click:x', 'note:C4']);
    });
  });
}
