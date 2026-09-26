import 'package:melody_app/domain/content/content_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ContentParser schema v2 (song metadata, backward compatible)', () {
    test('accepts schemaVersion 2', () {
      final doc = ContentParser.parseDocument(v2SongJson);
      expect(doc.schemaVersion, 2);
      expect(doc.lessons, hasLength(1));
    });

    test('still accepts schemaVersion 1 documents', () {
      final doc = ContentParser.parseDocument(v1Json);
      expect(doc.schemaVersion, 1);
    });

    test('rejects unsupported schema versions', () {
      expect(() => ContentParser.parseDocument(v0Json),
          throwsA(isA<ContentValidationException>()));
      expect(() => ContentParser.parseDocument(v3Json),
          throwsA(isA<ContentValidationException>()));
    });

    test('parses songTitle, genre, and attribution on a v2 lesson', () {
      final lesson = ContentParser.parseDocument(v2SongJson).lessons.first;
      expect(lesson.songTitle, 'Twinkle Twinkle Little Star');
      expect(lesson.genre, 'nursery');
      expect(lesson.attribution, contains('public domain'));
    });

    test('defaults song metadata when omitted (v1 stays valid)', () {
      final lesson = ContentParser.parseDocument(v1Json).lessons.first;
      expect(lesson.songTitle, lesson.title);
      expect(lesson.genre, '');
      expect(lesson.attribution, '');
    });

    test('rejects an empty genre string when the field is present', () {
      expect(() => ContentParser.parseDocument(emptyGenreJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('round-trips song metadata through toJson', () {
      final doc = ContentParser.parseDocument(v2SongJson);
      final json = doc.toJson();
      final reparsed = ContentParser.parseMap(json);
      final lesson = reparsed.lessons.first;
      expect(lesson.genre, 'nursery');
      expect(lesson.songTitle, 'Twinkle Twinkle Little Star');
    });
  });

  group('derived note range (for the keyboard guide window)', () {
    test('level reports its lowest and highest note', () {
      final level =
          ContentParser.parseDocument(v2SongJson).lessons.first.levels.first;
      expect(level.noteRange.low, 'C4');
      expect(level.noteRange.high, 'A4');
    });

    test('a single-note level has equal low and high', () {
      final level =
          ContentParser.parseDocument(v1Json).lessons.first.levels.first;
      expect(level.noteRange.low, 'C4');
      expect(level.noteRange.high, 'C4');
    });

    test('unparseable notes are ignored in the range', () {
      final level = ContentParser.parseDocument(rangeWithJunkJson)
          .lessons
          .first
          .levels
          .first;
      expect(level.noteRange.low, 'D4');
      expect(level.noteRange.high, 'G4');
    });
  });
}

const v1Json = '''
{
  "schemaVersion": 1,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "First Notes",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "One Note",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 1 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}
''';

const v2SongJson = '''
{
  "schemaVersion": 2,
  "lessons": [
    {
      "id": "song-twinkle",
      "title": "Twinkle Twinkle",
      "songTitle": "Twinkle Twinkle Little Star",
      "genre": "nursery",
      "attribution": "Traditional, public domain",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "twinkle-a",
          "name": "First phrase",
          "type": "standard",
          "requiredNotes": ["C4", "C4", "G4", "G4", "A4"],
          "tempoBpm": 84,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 4 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}
''';

const emptyGenreJson = '''
{
  "schemaVersion": 2,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "Bad Genre",
      "genre": "",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "A",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 1 },
          "rewardPayout": { "stars": 1, "noteCurrency": 1 }
        }
      ]
    }
  ]
}
''';

const rangeWithJunkJson = '''
{
  "schemaVersion": 2,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "Range",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "A",
          "type": "standard",
          "requiredNotes": ["G4", "D4", "E4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 1 },
          "rewardPayout": { "stars": 1, "noteCurrency": 1 }
        }
      ]
    }
  ]
}
''';

const v0Json = '''
{
  "schemaVersion": 0,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "X",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "A",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 1 },
          "rewardPayout": { "stars": 1, "noteCurrency": 1 }
        }
      ]
    }
  ]
}
''';

const v3Json = '''
{
  "schemaVersion": 3,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "X",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "A",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 1 },
          "rewardPayout": { "stars": 1, "noteCurrency": 1 }
        }
      ]
    }
  ]
}
''';
