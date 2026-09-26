import 'package:melody_app/domain/coaching/coaching.dart';
import 'package:test/test.dart';

void main() {
  group('coach (directional wrong-note feedback)', () {
    test('matching note is correct', () {
      final fb = coach(detected: 'C4', target: 'C4');
      expect(fb.isCorrect, isTrue);
      expect(fb.semitonesFromTarget, 0);
      expect(fb.direction, PitchDirection.match);
      expect(fb.message, contains('Perfect'));
    });

    test('detected note above target says go lower', () {
      final fb = coach(detected: 'G4', target: 'C4');
      expect(fb.isCorrect, isFalse);
      expect(fb.direction, PitchDirection.tooHigh);
      expect(fb.semitonesFromTarget, greaterThan(0));
      expect(fb.message, contains('too high'));
      expect(fb.message, contains('lower'));
      expect(fb.arrow, isNotNull);
    });

    test('detected note below target says go higher', () {
      final fb = coach(detected: 'C4', target: 'G4');
      expect(fb.isCorrect, isFalse);
      expect(fb.direction, PitchDirection.tooLow);
      expect(fb.semitonesFromTarget, lessThan(0));
      expect(fb.message, contains('too low'));
      expect(fb.message, contains('higher'));
    });

    test('reports exact semitone distance in both directions', () {
      expect(coach(detected: 'D4', target: 'C4').semitonesFromTarget, 2);
      expect(coach(detected: 'C4', target: 'D4').semitonesFromTarget, -2);
      expect(coach(detected: 'C5', target: 'C4').semitonesFromTarget, 12);
    });

    test('one-semitone miss still gives a direction', () {
      final fb = coach(detected: 'C#4', target: 'C4');
      expect(fb.direction, PitchDirection.tooHigh);
      expect(fb.semitonesFromTarget, 1);
    });

    test('unknown or missing detected note is a non-punitive prompt', () {
      final fb = coach(detected: null, target: 'C4');
      expect(fb.isCorrect, isFalse);
      expect(fb.direction, PitchDirection.unknown);
      expect(fb.semitonesFromTarget, isNull);
      expect(fb.message, contains('Play'));
    });

    test('unparseable detected note is handled gracefully', () {
      final fb = coach(detected: 'garbage', target: 'C4');
      expect(fb.direction, PitchDirection.unknown);
    });

    test('names both notes in the correction message', () {
      final fb = coach(detected: 'G4', target: 'C4');
      expect(fb.message, contains('G4'));
      expect(fb.message, contains('C4'));
    });
  });
}
