import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/content/content_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ContentParser (lesson content schema)', () {
    test('parses a valid lesson JSON document', () {
      final doc = ContentParser.parseDocument(lessonJson);
      expect(doc.schemaVersion, 1);
      expect(doc.lessons, hasLength(2));
    });

    test('parses lesson metadata and difficulty', () {
      final doc = ContentParser.parseDocument(lessonJson);
      final lesson = doc.lessons.first;
      expect(lesson.id, 'lesson-001');
      expect(lesson.title, 'First Notes');
      expect(lesson.difficulty, Difficulty.beginner);
    });

    test('parses level: required notes, tempo, success threshold, rewards', () {
      final doc = ContentParser.parseDocument(lessonJson);
      final level = doc.lessons.first.levels.single;
      expect(level.id, 'level-001-a');
      expect(level.requiredNotes, ['C4', 'D4', 'E4']);
      expect(level.tempoBpm, 80);
      expect(level.successThreshold.minAccuracy, 0.7);
      expect(level.successThreshold.minNotesHit, 2);
      expect(level.rewardPayout.stars, 3);
      expect(level.rewardPayout.noteCurrency, 5);
    });

    test('parses boss battle level type with its own thresholds', () {
      final doc = ContentParser.parseDocument(lessonJson);
      final boss = doc.lessons[1].levels.single;
      expect(boss.isBossBattle, isTrue);
      expect(boss.successThreshold.minAccuracy, 0.85);
    });

    test('rejects empty required notes', () {
      expect(
        () => ContentParser.parseDocument(lessonJsonWithEmptyNotes),
        throwsA(isA<ContentValidationException>()),
      );
    });

    test('rejects tempo outside playable range', () {
      expect(
        () => ContentParser.parseDocument(lessonJsonBadTempo),
        throwsA(isA<ContentValidationException>()),
      );
    });

    test('rejects accuracy threshold outside 0..1', () {
      expect(
        () => ContentParser.parseDocument(lessonJsonBadThreshold),
        throwsA(isA<ContentValidationException>()),
      );
    });

    test('rejects unknown difficulty', () {
      expect(
        () => ContentParser.parseDocument(lessonJsonBadDifficulty),
        throwsA(isA<ContentValidationException>()),
      );
    });
  });
}

const lessonJson = '''
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
          "name": "Three Friends",
          "type": "standard",
          "requiredNotes": ["C4", "D4", "E4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 2 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    },
    {
      "id": "lesson-002",
      "title": "Boss: Note Guardian",
      "difficulty": "advanced",
      "levels": [
        {
          "id": "level-002-boss",
          "name": "The Guardian",
          "type": "boss_battle",
          "requiredNotes": ["G4", "A4"],
          "tempoBpm": 100,
          "successThreshold": { "minAccuracy": 0.85, "minNotesHit": 1 },
          "rewardPayout": { "stars": 8, "noteCurrency": 12 }
        }
      ]
    }
  ]
}
''';

const lessonJsonWithEmptyNotes = '''
{
  "schemaVersion": 1,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "Broken",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "Empty",
          "type": "standard",
          "requiredNotes": [],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 0 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}
''';

const lessonJsonBadTempo = '''
{
  "schemaVersion": 1,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "Too Fast",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "Fast",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 500,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 0 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}
''';

const lessonJsonBadThreshold = '''
{
  "schemaVersion": 1,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "Bad Threshold",
      "difficulty": "beginner",
      "levels": [
        {
          "id": "level-001-a",
          "name": "Bad",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 1.5, "minNotesHit": 0 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}
''';

const lessonJsonBadDifficulty = '''
{
  "schemaVersion": 1,
  "lessons": [
    {
      "id": "lesson-001",
      "title": "Bad Difficulty",
      "difficulty": "impossible",
      "levels": [
        {
          "id": "level-001-a",
          "name": "Bad",
          "type": "standard",
          "requiredNotes": ["C4"],
          "tempoBpm": 80,
          "successThreshold": { "minAccuracy": 0.7, "minNotesHit": 0 },
          "rewardPayout": { "stars": 3, "noteCurrency": 5 }
        }
      ]
    }
  ]
}
''';