import 'package:melody_app/domain/content/content_parser.dart';
import 'package:test/test.dart';

/// The `durations` array: how long each note of a tune is actually held.
///
/// Before this field existed the schema could only say *which* notes a song
/// uses, so every arrangement played as a march of equal-length notes. These
/// tests pin the two properties that make it safe to add:
///
/// 1. An absent `durations` means "one base note each" — the eleven levels
///    written before the field existed must not be retimed by adding it.
/// 2. A malformed array is rejected at parse time, not played back wrong.
void main() {
  group('durations array', () {
    test('absent durations means every note is one base note long', () {
      final level =
          ContentParser.parseDocument(noDurationsJson).lessons.first.levels.single;
      expect(level.durations, isNull);
      for (var i = 0; i < level.requiredNotes.length; i++) {
        expect(level.durationNotesAt(i), 1.0);
      }
      expect(level.totalNoteUnits, level.requiredNotes.length.toDouble());
    });

    test('parses held and short notes alongside the required notes', () {
      final level =
          ContentParser.parseDocument(rhythmJson).lessons.first.levels.single;
      expect(level.durations, [1, 1.5, 0.5, 2]);
      expect(level.durationNotesAt(0), 1.0);
      expect(level.durationNotesAt(1), 1.5);
      expect(level.durationNotesAt(2), 0.5);
      expect(level.durationNotesAt(3), 2.0);
      // Four notes, but five beats long: the held final note is what makes it
      // sound like the tune rather than a scale exercise.
      expect(level.totalNoteUnits, 5.0);
    });

    test('an index past the end of the array falls back to one beat', () {
      final level =
          ContentParser.parseDocument(rhythmJson).lessons.first.levels.single;
      expect(level.durationNotesAt(99), 1.0);
      expect(level.durationNotesAt(-1), 1.0);
    });

    test('durations are read against the base note, not the beat', () {
      // A compound meter splits each beat into three notes; a duration of 1
      // therefore means one *base note*, a third of a beat.
      final level = ContentParser.parseDocument(compoundJson)
          .lessons
          .first
          .levels
          .single;
      expect(level.meter.notesPerBeat, 3);
      expect(level.durations, [1, 1, 1, 3]);
      expect(level.totalNoteUnits, 6.0);
      // Six base notes, but two whole dotted-quarter beats.
      expect(level.totalNoteUnits / level.meter.notesPerBeat, 2.0);
    });

    test('rejects a durations list shorter than the note list', () {
      expect(() => ContentParser.parseDocument(tooShortJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a durations list longer than the note list', () {
      expect(() => ContentParser.parseDocument(tooLongJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects an empty durations list', () {
      expect(() => ContentParser.parseDocument(emptyJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a durations list that is not a list', () {
      expect(() => ContentParser.parseDocument(notAListJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a zero-length note, which would never be heard', () {
      expect(() => ContentParser.parseDocument(zeroJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a negative note length', () {
      expect(() => ContentParser.parseDocument(negativeJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a non-numeric entry', () {
      expect(() => ContentParser.parseDocument(nonNumericJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a duration longer than a whole note', () {
      expect(() => ContentParser.parseDocument(tooLongDurationJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('a duration of exactly one whole note is allowed', () {
      final level = ContentParser.parseDocument(wholeNoteJson)
          .lessons
          .first
          .levels
          .single;
      expect(level.durations, [ContentParser.maxNoteDurationNotes, 1, 1, 1]);
    });
  });

  group('round trip', () {
    test('durations survive toJson and reparse', () {
      final doc = ContentParser.parseDocument(rhythmJson);
      final reparsed = ContentParser.parseMap(doc.toJson());
      expect(reparsed.lessons.first.levels.single.durations, [1, 1.5, 0.5, 2]);
      expect(reparsed.lessons.first.levels.single.totalNoteUnits, 5.0);
    });

    test('an unauthored level does not grow a durations key in toJson', () {
      final doc = ContentParser.parseDocument(noDurationsJson);
      final lesson =
          (doc.toJson()['lessons'] as List).first as Map<String, dynamic>;
      final level = (lesson['levels'] as List).first as Map<String, dynamic>;
      expect(level.containsKey('durations'), isFalse);
    });

    test('an all-ones durations array is not written back out', () {
      // It carries no information, and omitting it keeps the JSON honest about
      // which songs actually have an authored rhythm.
      final doc = ContentParser.parseDocument(allOnesJson);
      expect(doc.lessons.first.levels.single.durations, [1, 1, 1, 1]);
      final lesson =
          (doc.toJson()['lessons'] as List).first as Map<String, dynamic>;
      final level = (lesson['levels'] as List).first as Map<String, dynamic>;
      expect(level.containsKey('durations'), isFalse);
    });
  });
}

String _levelJson(String extra) => '''
{
  "schemaVersion": 2,
  "lessons": [
    {
      "id": "l1",
      "title": "T",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "lv1",
          "name": "A",
          "type": "standard",
          "requiredNotes": ["C4", "D4", "E4", "F4"],
          "tempoBpm": 92,$extra
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 3 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}''';

final noDurationsJson = _levelJson('');

final rhythmJson = _levelJson('''
          "durations": [1, 1.5, 0.5, 2],''');

final compoundJson = _levelJson('''
          "meter": { "beatsPerMeasure": 4, "beatUnit": 4, "dotted": true, "notesPerBeat": 3 },
          "durations": [1, 1, 1, 3],''');

final allOnesJson = _levelJson('''
          "durations": [1, 1, 1, 1],''');

final tooShortJson = _levelJson('''
          "durations": [1, 1, 2],''');

final tooLongJson = _levelJson('''
          "durations": [1, 1, 2, 1, 1],''');

final emptyJson = _levelJson('''
          "durations": [],''');

final notAListJson = _levelJson('''
          "durations": "long",''');

final zeroJson = _levelJson('''
          "durations": [1, 0, 1, 2],''');

final negativeJson = _levelJson('''
          "durations": [1, -1, 1, 2],''');

final nonNumericJson = _levelJson('''
          "durations": [1, "half", 1, 2],''');

final tooLongDurationJson = _levelJson('''
          "durations": [1, 1, 1, 16],''');

final wholeNoteJson = _levelJson('''
          "durations": [8, 1, 1, 1],''');
