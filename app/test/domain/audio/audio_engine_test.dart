import 'dart:io';

import 'package:melody_app/domain/audio/audio_engine.dart';
import 'package:test/test.dart';

void main() {
  group('AudioEngine contract', () {
    test('NoteAudio has correct frequency mapping for C4', () {
      expect(NoteFrequency.of('C4'), 261.63);
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
      expect(NoteFrequency.playableNotes, isNot(contains('G#6')));
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
}
