import 'package:melody_app/domain/content/content_parser.dart';
import 'package:melody_app/domain/rhythm/song_meter.dart';
import 'package:test/test.dart';

/// The `meter` and `songTempoBpm` blocks: how a level's tempo is felt, and how
/// fast the real song is.
///
/// The important behaviour is the default. Every tune in the library written
/// before these fields existed is in common time with one note per beat, so an
/// absent `meter` must produce exactly that — otherwise adding the field would
/// silently retime eleven songs.
void main() {
  group('meter block', () {
    test('absent meter means common time, one note per beat', () {
      final level =
          ContentParser.parseDocument(noMeterJson).lessons.first.levels.single;
      expect(level.meter, SongMeter.simple);
      expect(level.meter.notation, '4/4');
      // One note per beat at the level's 92 bpm.
      expect(level.meter.noteMs(level.tempoBpm), closeTo(652.17, 0.01));
    });

    test('parses a compound 12/8 meter', () {
      final level =
          ContentParser.parseDocument(compoundJson).lessons.first.levels.single;
      expect(level.meter.beatsPerMeasure, 4);
      expect(level.meter.beatUnit, 4);
      expect(level.meter.dotted, isTrue);
      expect(level.meter.notesPerBeat, 3);
      expect(level.meter.notation, '12/8');
      expect(level.meter.beatName, 'dotted quarter');
    });

    test('a compound meter divides the beat into three notes', () {
      final level =
          ContentParser.parseDocument(compoundJson).lessons.first.levels.single;
      // At the arrangement's 92 dotted-quarter beats per minute, a beat is
      // 652ms and each of the three notes inside it is 217ms.
      expect(level.meter.beatMs(level.tempoBpm), closeTo(652.17, 0.01));
      expect(level.meter.noteMs(level.tempoBpm), closeTo(217.39, 0.01));
      // At the recording's own tempo the same maths gives the real pulse.
      expect(level.meter.beatMs(level.songTempoBpm!), closeTo(487.8, 0.1));
    });

    test('absent sub-fields default rather than throwing', () {
      final level = ContentParser.parseDocument(partialMeterJson)
          .lessons
          .first
          .levels
          .single;
      expect(level.meter.beatsPerMeasure, 4);
      expect(level.meter.notesPerBeat, 2);
      expect(level.meter.dotted, isFalse);
    });

    test('rejects a non-object meter', () {
      expect(() => ContentParser.parseDocument(meterNotAnObjectJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects an out-of-range beat count', () {
      expect(() => ContentParser.parseDocument(meterBadBeatsJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a zero note group, which would divide by zero', () {
      expect(() => ContentParser.parseDocument(meterZeroNotesJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a dotted beat on a note value it cannot apply to', () {
      expect(() => ContentParser.parseDocument(meterBadDottedJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a non-boolean dotted flag', () {
      expect(() => ContentParser.parseDocument(meterDottedNotBoolJson),
          throwsA(isA<ContentValidationException>()));
    });
  });

  group('songTempoBpm', () {
    test('absent when not authored', () {
      final level =
          ContentParser.parseDocument(noMeterJson).lessons.first.levels.single;
      expect(level.songTempoBpm, isNull);
    });

    test('parses the recording tempo alongside a slower practice tempo', () {
      final level =
          ContentParser.parseDocument(compoundJson).lessons.first.levels.single;
      expect(level.tempoBpm, 92);
      expect(level.songTempoBpm, 123);
    });

    test('rejects a song tempo outside the playable range', () {
      expect(() => ContentParser.parseDocument(songTempoTooFastJson),
          throwsA(isA<ContentValidationException>()));
    });

    test('rejects a non-integer song tempo', () {
      expect(() => ContentParser.parseDocument(songTempoNotIntJson),
          throwsA(isA<ContentValidationException>()));
    });
  });

  group('round trip', () {
    test('a meter survives toJson and reparse', () {
      final doc = ContentParser.parseDocument(compoundJson);
      final reparsed = ContentParser.parseMap(doc.toJson());
      final authored = doc.lessons.first.levels.single;
      final reparsedLevel = reparsed.lessons.first.levels.single;
      expect(reparsedLevel.meter, authored.meter);
      expect(reparsedLevel.songTempoBpm, 123);
    });

    test('a plain level does not grow a meter block in toJson', () {
      final doc = ContentParser.parseDocument(noMeterJson);
      final lesson =
          (doc.toJson()['lessons'] as List).first as Map<String, dynamic>;
      final level = (lesson['levels'] as List).first as Map<String, dynamic>;
      expect(level.containsKey('meter'), isFalse);
      expect(level.containsKey('songTempoBpm'), isFalse);
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

final noMeterJson = _levelJson('');

final compoundJson = _levelJson('''
          "meter": { "beatsPerMeasure": 4, "beatUnit": 4, "dotted": true, "notesPerBeat": 3 },
          "songTempoBpm": 123,''');

final partialMeterJson = _levelJson('''
          "meter": { "notesPerBeat": 2 },''');

final meterNotAnObjectJson = _levelJson('''
          "meter": "12/8",''');

final meterBadBeatsJson = _levelJson('''
          "meter": { "beatsPerMeasure": 40 },''');

final meterZeroNotesJson = _levelJson('''
          "meter": { "notesPerBeat": 0 },''');

final meterBadDottedJson = _levelJson('''
          "meter": { "beatUnit": 2, "dotted": true },''');

final meterDottedNotBoolJson = _levelJson('''
          "meter": { "dotted": "yes" },''');

final songTempoTooFastJson = _levelJson('''
          "songTempoBpm": 900,''');

final songTempoNotIntJson = _levelJson('''
          "songTempoBpm": 123.5,''');
