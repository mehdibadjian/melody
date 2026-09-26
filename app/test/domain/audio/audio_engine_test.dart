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
}
