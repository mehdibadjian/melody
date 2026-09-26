import 'package:melody_app/domain/coaching/coaching.dart';
import 'package:melody_app/domain/coaching/song_coach.dart';
import 'package:test/test.dart';

void main() {
  group('SongCoach (acoustic coaching state machine)', () {
    test('starts at the first note with no feedback', () {
      final coach = SongCoach(notes: const ['C4', 'E4', 'G4']);
      expect(coach.state.targetNote, 'C4');
      expect(coach.state.index, 0);
      expect(coach.state.isComplete, isFalse);
      expect(coach.state.feedback, isNull);
    });

    test('a correct note advances to the next target', () {
      final coach = SongCoach(notes: const ['C4', 'E4', 'G4']);
      coach.onDetectedNote('C4');
      expect(coach.state.targetNote, 'E4');
      expect(coach.state.index, 1);
      expect(coach.state.correctHits, 1);
      expect(coach.state.feedback!.isCorrect, isTrue);
    });

    test('a wrong note does NOT advance — it coaches instead', () {
      final coach = SongCoach(notes: const ['C4', 'E4', 'G4']);
      coach.onDetectedNote('G4'); // too high vs C4
      expect(coach.state.targetNote, 'C4', reason: 'must stay on C4');
      expect(coach.state.index, 0);
      expect(coach.state.feedback!.isCorrect, isFalse);
      expect(coach.state.feedback!.direction, PitchDirection.tooHigh);
      expect(coach.state.wrongAttempts, 1);
    });

    test('repeated wrong notes keep coaching without failing the child', () {
      final coach = SongCoach(notes: const ['C4', 'E4']);
      coach.onDetectedNote('G4');
      coach.onDetectedNote('A4');
      coach.onDetectedNote('C4'); // finally correct
      expect(coach.state.targetNote, 'E4');
      expect(coach.state.correctHits, 1);
      expect(coach.state.wrongAttempts, 2);
      expect(coach.state.isComplete, isFalse);
    });

    test('a null (silence) frame is ignored — no advance, no penalty', () {
      final coach = SongCoach(notes: const ['C4', 'E4']);
      coach.onDetectedNote(null);
      expect(coach.state.targetNote, 'C4');
      expect(coach.state.wrongAttempts, 0);
      expect(coach.state.correctHits, 0);
    });

    test('plays through a whole song and completes', () {
      final coach = SongCoach(notes: const ['C4', 'E4', 'G4']);
      coach.onDetectedNote('C4');
      coach.onDetectedNote('E4');
      coach.onDetectedNote('G4');
      expect(coach.state.isComplete, isTrue);
      expect(coach.state.correctHits, 3);
      expect(coach.state.index, 3);
      expect(coach.state.targetNote, isNull);
    });

    test('detectedNote is surfaced for the UI marker', () {
      final coach = SongCoach(notes: const ['C4', 'E4']);
      coach.onDetectedNote('G4');
      expect(coach.state.detectedNote, 'G4');
      coach.onDetectedNote(null);
      expect(coach.state.detectedNote, isNull);
    });

    test('ignores input after completion (non-punitive, no overflow)', () {
      final coach = SongCoach(notes: const ['C4']);
      coach.onDetectedNote('C4');
      expect(coach.state.isComplete, isTrue);
      coach.onDetectedNote('C4');
      expect(coach.state.correctHits, 1);
      expect(coach.state.index, 1);
    });

    test('accuracy reflects clean vs. corrected runs', () {
      final clean = SongCoach(notes: const ['C4', 'E4']);
      clean.onDetectedNote('C4');
      clean.onDetectedNote('E4');
      expect(clean.state.accuracy, 1.0);

      final messy = SongCoach(notes: const ['C4', 'E4']);
      messy.onDetectedNote('G4'); // wrong
      messy.onDetectedNote('C4'); // right
      messy.onDetectedNote('E4'); // right
      // 2 correct, 1 wrong => 2/3
      expect(messy.state.accuracy, closeTo(2 / 3, 1e-9));
    });

    test('accuracy is 1.0 before anything is attempted', () {
      final coach = SongCoach(notes: const ['C4', 'E4']);
      expect(coach.state.accuracy, 1.0);
    });

    test('exposes the full note sequence for the score strip', () {
      final coach = SongCoach(notes: const ['C4', 'E4', 'G4']);
      expect(coach.state.notes, ['C4', 'E4', 'G4']);
    });

    test('fires onComplete exactly once when the song finishes', () {
      var completions = 0;
      final coach =
          SongCoach(notes: const ['C4', 'E4'], onComplete: () => completions++);
      coach.onDetectedNote('C4');
      expect(completions, 0);
      coach.onDetectedNote('E4');
      expect(completions, 1);
      coach.onDetectedNote('E4');
      expect(completions, 1);
    });

    test('handles repeated identical target notes (e.g. Jingle Bells)', () {
      final coach = SongCoach(notes: const ['E4', 'E4', 'E4']);
      coach.onDetectedNote('E4');
      expect(coach.state.index, 1);
      coach.onDetectedNote('E4');
      expect(coach.state.index, 2);
      coach.onDetectedNote('E4');
      expect(coach.state.isComplete, isTrue);
    });

    test('empty song is immediately complete', () {
      final coach = SongCoach(notes: const []);
      expect(coach.state.isComplete, isTrue);
      expect(coach.state.targetNote, isNull);
    });
  });
}
