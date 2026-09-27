import 'dart:io';

import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:test/test.dart';

void main() {
  group('AudioEngine contract', () {
    test('NoteAudio has correct frequency mapping for C4', () {
      // Derived from A4=440 equal temperament, so C4 is 261.6256 Hz rather than
      // the rounded 261.63 a hand-typed table used to hold.
      expect(NoteFrequency.of('C4'), closeTo(261.63, 0.01));
    });

    test('NoteAudio maps all white keys in octave 4', () {
      expect(NoteFrequency.of('C4'), closeTo(261.63, 0.01));
      expect(NoteFrequency.of('D4'), closeTo(293.66, 0.01));
      expect(NoteFrequency.of('E4'), closeTo(329.63, 0.01));
      expect(NoteFrequency.of('F4'), closeTo(349.23, 0.01));
      expect(NoteFrequency.of('G4'), closeTo(392.00, 0.01));
      expect(NoteFrequency.of('A4'), closeTo(440.00, 0.01));
      expect(NoteFrequency.of('B4'), closeTo(493.88, 0.01));
    });

    test('NoteAudio maps octave 5 notes', () {
      expect(NoteFrequency.of('C5'), closeTo(523.25, 0.01));
    });

    test('unknown note returns null frequency', () {
      expect(NoteFrequency.of('X9'), isNull);
    });

    test('the sharp and top-octave keys GOLDEN needs have frequencies', () {
      expect(NoteFrequency.of('F#4'), closeTo(369.99, 0.01));
      expect(NoteFrequency.of('D6'), closeTo(1174.66, 0.01));
    });

    test('playableNotes is exactly the set the engine can sound', () {
      expect(NoteFrequency.playableNotes, contains('F#4'));
      expect(NoteFrequency.playableNotes, contains('G#6'));
    });

    test('SynthAudioEngine can be created and disposed', () async {
      final engine = SynthAudioEngine();
      expect(engine.isInitialized, isFalse);
      await engine.initialize();
      expect(engine.isInitialized, isTrue);
      await engine.dispose();
      expect(engine.isInitialized, isFalse);
    });

    test('playNote is safe to call before initialization (no-op)', () async {
      final engine = SynthAudioEngine();
      await engine.playNote('C4');
      await engine.dispose();
    });

    test('playNote records last played note for testing', () async {
      final engine = SynthAudioEngine();
      await engine.initialize();
      await engine.playNote('E4');
      expect(engine.lastPlayedNote, 'E4');
      await engine.dispose();
    });
  });

  group('NoteAsset spelling', () {
    test('naturals map to the historical file names', () {
      expect(NoteAsset.pathFor('C4'), 'audio/notes/c4.wav');
      expect(NoteAsset.pathFor('B5'), 'audio/notes/b5.wav');
    });

    test('sharps are spelled with s so no fragment marker reaches the loader',
        () {
      // `#` is the URL fragment delimiter, and AssetAudioEngine.playNote
      // swallows a failed source instead of throwing. An `f#4.wav` that the
      // platform asset loader could not resolve would therefore present as a
      // key that silently does nothing, so the name must never contain one.
      expect(NoteAsset.pathFor('F#4'), 'audio/notes/fs4.wav');
      expect(NoteAsset.pathFor('F#4'), isNot(contains('#')));
    });

    test('noteNameFromFile is the exact inverse of fileBaseFor', () {
      for (final note in NoteFrequency.playableNotes) {
        expect(
          NoteAsset.noteNameFromFile('${NoteAsset.fileBaseFor(note)}.wav'),
          note,
          reason: 'round trip broke for $note',
        );
      }
    });
  });

  group('bundled audio matches the frequency table', () {
    final onDisk = Directory('assets/audio/notes')
        .listSync()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .where((n) => n.endsWith('.wav'))
        .toSet();

    test('every playable note has a bundled WAV', () {
      // The table and the bundle drift apart easily and the symptom is silence
      // rather than an error, which is exactly how a missing key would ship.
      for (final note in NoteFrequency.playableNotes) {
        final file = NoteAsset.fileBaseFor(note);
        expect(onDisk, contains('$file.wav'),
            reason: '$note is in NoteFrequency but $file.wav is not bundled');
      }
    });

    test('no bundled WAV is missing a frequency entry', () {
      for (final file in onDisk) {
        expect(NoteFrequency.playableNotes,
            contains(NoteAsset.noteNameFromFile(file)),
            reason: '$file exists but has no frequency entry');
      }
    });
  });

  group('the frequency table is derived from the board', () {
    test('it covers every key of the 61-key board and nothing else', () {
      // The map is generated from KeyboardLayout.sixtyOne — the same definition
      // the illustrated keyboard draws — so this pins the two together. A board
      // key with no pitch entry is a silent key, and playNote returns without
      // an error, so the old hand-typed table drifted in exactly the places
      // content later grew into.
      expect(
          NoteFrequency.playableNotes, KeyboardLayout.sixtyOne.notes.toSet());
      expect(NoteFrequency.playableNotes, hasLength(61));
    });

    test('reference pitches match the values tuners use', () {
      // Hard-coded rather than recomputed, so this cannot agree with a broken
      // formula just by using it.
      const reference = {
        'C4': 261.63,
        'E4': 329.63,
        'A4': 440.00,
        'C5': 523.25,
        'F#4': 369.99,
        'A5': 880.00,
        'C7': 2093.00,
      };
      reference.forEach((note, hz) {
        expect(NoteFrequency.of(note)!, closeTo(hz, 0.01), reason: note);
      });
    });

    test('adjacent keys are one equal-tempered semitone apart', () {
      // The structural property that makes it a piano at all: every neighbour
      // ratio is 2^(1/12) and every octave exactly doubles, across the whole
      // board rather than at sampled notes.
      const twelfthRoot2 = 1.0594630940595574;
      final notes = KeyboardLayout.sixtyOne.notes;
      for (var i = 1; i < notes.length; i++) {
        final ratio =
            NoteFrequency.of(notes[i])! / NoteFrequency.of(notes[i - 1])!;
        expect(ratio, closeTo(twelfthRoot2, 1e-6),
            reason: '${notes[i - 1]} -> ${notes[i]}');
      }
      for (var i = 0; i + 12 < notes.length; i++) {
        expect(
          NoteFrequency.of(notes[i + 12])!,
          closeTo(NoteFrequency.of(notes[i])! * 2, 1e-6),
          reason: '${notes[i]} octave',
        );
      }
    });
  });
}
