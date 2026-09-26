import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/mic_capture.dart';
import 'package:melody_app/domain/coaching/coaching.dart';
import 'package:melody_app/domain/coaching/acoustic_practice_controller.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:test/test.dart';

const sr = 22050;

/// Synthetic mono 16-bit PCM for a note's frequency — stands in for the mic.
Uint8List toneFor(String note, {double seconds = 0.5}) {
  final semis = <String, double>{
    'C4': 261.63,
    'D4': 293.66,
    'E4': 329.63,
    'F4': 349.23,
    'G4': 392.00,
    'A4': 440.00,
    'C5': 523.25,
    'G5': 783.99,
  };
  final freq = semis[note] ?? 440;
  final n = (seconds * sr).round();
  final bytes = Uint8List(n * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final s = math.sin(2 * math.pi * freq * t) +
        0.5 * math.sin(2 * math.pi * 2 * freq * t) +
        0.3 * math.sin(2 * math.pi * 3 * freq * t);
    data.setInt16(
        i * 2, ((s * 0.8).clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return bytes;
}

/// Fake capture: [hasPermission] result and a controller we push bytes into.
class FakeMicCapture implements MicCapture {
  FakeMicCapture({this.permission = true});
  bool permission;
  final controller = StreamController<Uint8List>.broadcast();
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> dispose() async => disposed = true;

  void emit(Uint8List chunk) => controller.add(chunk);
}

void main() {
  Level makeLevel(List<String> notes) => Level(
        id: 'lvl',
        name: 'Song',
        type: LevelType.standard,
        requiredNotes: notes,
        tempoBpm: 90,
        successThreshold:
            const SuccessThreshold(minAccuracy: 0.7, minNotesHit: 2),
        rewardPayout: const RewardPayout(stars: 3, noteCurrency: 5),
      );

  AcousticPracticeController build(FakeMicCapture mic, {List<String>? notes}) {
    final n = notes ?? const ['C4', 'E4', 'G4'];
    return AcousticPracticeController(
      notes: n,
      mic: mic,
      level: makeLevel(n),
    );
  }

  group('AcousticPracticeController', () {
    test('requests permission and captures on start', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      await c.start();
      expect(mic.started, isTrue);
      expect(c.listening, isTrue);
      expect(c.snapshot.permissionDenied, isFalse);
      await c.dispose();
    });

    test('surfaces permission denial without starting capture', () async {
      final mic = FakeMicCapture(permission: false);
      final c = build(mic);
      await c.start();
      expect(mic.started, isFalse);
      expect(c.listening, isFalse);
      expect(c.snapshot.permissionDenied, isTrue);
      await c.dispose();
    });

    test('a correct note from the mic advances the target', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      await c.start();
      expect(c.snapshot.coach.targetNote, 'C4');

      mic.emit(toneFor('C4'));
      await pump();

      expect(c.snapshot.coach.targetNote, 'E4');
      expect(c.snapshot.feedback?.isCorrect, isTrue);
      await c.dispose();
    });

    test('a wrong note coaches direction and holds the target', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      await c.start();

      mic.emit(toneFor('G4')); // too high vs C4
      await pump();

      expect(c.snapshot.coach.targetNote, 'C4');
      expect(c.snapshot.feedback?.direction, PitchDirection.tooHigh);
      expect(c.snapshot.detectedNote, 'G4');
      await c.dispose();
    });

    test('plays a whole song and reports completion', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      await c.start();

      mic.emit(toneFor('C4'));
      await pump();
      mic.emit(toneFor('E4'));
      await pump();
      mic.emit(toneFor('G4'));
      await pump();

      expect(c.snapshot.complete, isTrue);
      expect(c.snapshot.coach.correctHits, 3);
      await c.dispose();
    });

    test('completion commits progress + analytics exactly once', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      var analytics = 0;
      c.onAnalyticsEvent = (_) => analytics++;
      await c.start();

      for (final n in ['C4', 'E4', 'G4']) {
        mic.emit(toneFor(n));
        await pump();
      }
      expect(analytics, 1);

      mic.emit(toneFor('G4')); // extra input after completion
      await pump();
      expect(analytics, 1, reason: 'must not double-fire');
      await c.dispose();
    });

    test('dispose stops capture and releases resources', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      await c.start();
      await c.dispose();
      expect(mic.stopped, isTrue);
      expect(mic.disposed, isTrue);
      expect(c.listening, isFalse);
    });

    test('start before permission is re-checked each time', () async {
      final mic = FakeMicCapture(permission: false);
      final c = build(mic);
      await c.start();
      expect(c.snapshot.permissionDenied, isTrue);
      mic.permission = true;
      await c.start();
      expect(c.snapshot.permissionDenied, isFalse);
      expect(c.listening, isTrue);
      await c.dispose();
    });

    test('emits snapshot changes to listeners', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      final snaps = <AcousticSnapshot>[];
      c.addListener(snaps.add);
      await c.start();
      mic.emit(toneFor('C4'));
      await pump();
      expect(snaps.length, greaterThanOrEqualTo(2));
      expect(snaps.last.coach.correctHits, 1);
      await c.dispose();
    });

    test('silence between notes does not advance or error', () async {
      final mic = FakeMicCapture();
      final c = build(mic);
      await c.start();
      mic.emit(Uint8List((0.3 * sr).round() * 2)); // silence
      await pump();
      expect(c.snapshot.coach.targetNote, 'C4');
      expect(c.snapshot.coach.correctHits, 0);
      await c.dispose();
    });
  });
}

Future<void> pump() async {
  // Let stream events + microtasks + debounce flush through.
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
