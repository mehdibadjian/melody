import 'dart:convert';

import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/rhythm/song_meter.dart';

/// Parses and validates lesson content documents against schema v1.
class ContentParser {
  static const supportedSchemaVersion = 2;
  static const supportedSchemaVersions = {1, 2};
  static const minTempoBpm = 40;
  static const maxTempoBpm = 240;

  /// Upper bound on one note's `durations` entry, in base-note units.
  ///
  /// 8 is a whole note in 4/4, the longest value a single held note plausibly
  /// takes in this library. It also bounds how far out one note can push the
  /// demo's timer: at the slowest tempo (40 bpm, one base note per beat) a
  /// whole note is 12 seconds, so a stray typo cannot schedule a multi-minute
  /// timer that holds the isolate open.
  static const maxNoteDurationNotes = 8.0;

  static const allowedDifficulties = {'beginner', 'intermediate', 'advanced'};
  static const allowedLevelTypes = {'standard', 'boss_battle'};

  /// Throws [ContentValidationException] on any schema violation.
  static ContentDocument parseDocument(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw const ContentValidationException('document must be a JSON object');
    }
    return parseMap(json);
  }

  static ContentDocument parseMap(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int ||
        !supportedSchemaVersions.contains(schemaVersion)) {
      throw ContentValidationException(
        'unsupported schemaVersion: $schemaVersion',
      );
    }
    final lessonsJson = json['lessons'];
    if (lessonsJson is! List || lessonsJson.isEmpty) {
      throw const ContentValidationException(
          'lessons must be a non-empty list');
    }
    final lessons = lessonsJson.map(_parseLesson).toList();
    final lessonIds = lessons.map((l) => l.id).toList();
    final duplicateLessonId = _firstDuplicate(lessonIds);
    if (duplicateLessonId != null) {
      throw ContentValidationException(
          'duplicate lesson id: $duplicateLessonId');
    }
    return ContentDocument(schemaVersion: schemaVersion, lessons: lessons);
  }

  static Lesson _parseLesson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const ContentValidationException('lesson must be an object');
    }
    final difficulty = raw['difficulty'];
    if (!allowedDifficulties.contains(difficulty)) {
      throw ContentValidationException('unknown difficulty: $difficulty');
    }
    final levelsJson = raw['levels'];
    if (levelsJson is! List || levelsJson.isEmpty) {
      throw const ContentValidationException('levels must be a non-empty list');
    }
    final levels = levelsJson.map(_parseLevel).toList();
    final duplicateLevelId = _firstDuplicate(levels.map((l) => l.id));
    if (duplicateLevelId != null) {
      throw ContentValidationException('duplicate level id: $duplicateLevelId');
    }
    return Lesson(
      id: _requiredString(raw, 'id'),
      title: _requiredString(raw, 'title'),
      difficulty: Difficulty.values.byName(difficulty as String),
      levels: levels,
      songTitle: _optionalString(raw, 'songTitle'),
      genre: _optionalString(raw, 'genre', allowEmpty: false) ?? '',
      attribution: _optionalString(raw, 'attribution') ?? '',
    );
  }

  /// Reads an optional string field. Returns null when absent. When
  /// [allowEmpty] is false, an empty string is rejected (a present-but-blank
  /// value is an authoring error; an absent value is fine).
  static String? _optionalString(
    Map<String, dynamic> json,
    String key, {
    bool allowEmpty = true,
  }) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw ContentValidationException('$key must be a string');
    }
    if (!allowEmpty && value.isEmpty) {
      throw ContentValidationException('$key must not be empty when present');
    }
    return value;
  }

  static Level _parseLevel(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const ContentValidationException('level must be an object');
    }
    final type = raw['type'];
    if (!allowedLevelTypes.contains(type)) {
      throw ContentValidationException('unknown level type: $type');
    }
    final requiredNotes = raw['requiredNotes'];
    if (requiredNotes is! List || requiredNotes.isEmpty) {
      throw const ContentValidationException(
        'requiredNotes must be a non-empty list',
      );
    }
    for (final note in requiredNotes) {
      if (note is! String || note.isEmpty) {
        throw const ContentValidationException(
          'requiredNotes entries must be non-empty strings',
        );
      }
    }
    final tempo = raw['tempoBpm'];
    if (tempo is! int || tempo < minTempoBpm || tempo > maxTempoBpm) {
      throw const ContentValidationException(
        'tempoBpm must be between $minTempoBpm and $maxTempoBpm',
      );
    }
    // Optional: the real recording's tempo, so a slow arrangement can say so.
    // Same range as tempoBpm — it is the same kind of number.
    final songTempo = raw['songTempoBpm'];
    if (songTempo != null &&
        (songTempo is! int ||
            songTempo < minTempoBpm ||
            songTempo > maxTempoBpm)) {
      throw const ContentValidationException(
        'songTempoBpm must be between $minTempoBpm and $maxTempoBpm',
      );
    }
    final thresholdJson = raw['successThreshold'];
    if (thresholdJson is! Map<String, dynamic>) {
      throw const ContentValidationException(
        'successThreshold must be an object',
      );
    }
    final minAccuracy = thresholdJson['minAccuracy'];
    if (minAccuracy is! num ||
        minAccuracy < 0 ||
        minAccuracy > 1 ||
        minAccuracy.toDouble().isNaN) {
      throw const ContentValidationException(
        'minAccuracy must be between 0 and 1',
      );
    }
    final minNotesHit = thresholdJson['minNotesHit'];
    if (minNotesHit is! int || minNotesHit < 0) {
      throw const ContentValidationException('minNotesHit must be >= 0');
    }
    final payoutJson = raw['rewardPayout'];
    if (payoutJson is! Map<String, dynamic>) {
      throw const ContentValidationException('rewardPayout must be an object');
    }
    final stars = payoutJson['stars'];
    final noteCurrency = payoutJson['noteCurrency'];
    if (stars is! int || stars < 0) {
      throw const ContentValidationException(
          'stars must be a non-negative int');
    }
    if (noteCurrency is! int || noteCurrency < 0) {
      throw const ContentValidationException(
        'noteCurrency must be a non-negative int',
      );
    }
    // Optional: per-note durations in base-note units, parallel to
    // requiredNotes. Absent means "every note is one base note", which is what
    // every level authored before this field existed is. Present-but-wrong
    // throws rather than defaulting, because a half-typed duration list would
    // silently desynchronize the melody from the meter — the exact failure the
    // `meter` field was added to prevent.
    final durations = _parseDurations(raw['durations'], requiredNotes.length);
    return Level(
      id: _requiredString(raw, 'id'),
      name: _requiredString(raw, 'name'),
      type: type == 'boss_battle' ? LevelType.bossBattle : LevelType.standard,
      requiredNotes: requiredNotes.cast<String>(),
      tempoBpm: tempo,
      meter: _parseMeter(raw['meter']),
      durations: durations,
      songTempoBpm: songTempo as int?,
      successThreshold: SuccessThreshold(
          minAccuracy: minAccuracy.toDouble(), minNotesHit: minNotesHit),
      rewardPayout: RewardPayout(stars: stars, noteCurrency: noteCurrency),
    );
  }

  /// Validates the optional `durations` array against [noteCount].
  ///
  /// Returns null when absent, meaning "one base note each". Rejects a length
  /// mismatch, non-numeric entries, and anything that is not a positive
  /// duration: a zero or negative entry would place two notes at the same
  /// instant, and a huge one would schedule a timer minutes out for a single
  /// held note.
  static List<double>? _parseDurations(Object? raw, int noteCount) {
    if (raw == null) return null;
    if (raw is! List || raw.isEmpty) {
      throw const ContentValidationException(
        'durations must be a non-empty list when present',
      );
    }
    if (raw.length != noteCount) {
      throw ContentValidationException(
        'durations must have one entry per note '
        '(expected $noteCount, got ${raw.length})',
      );
    }
    final out = <double>[];
    for (final value in raw) {
      if (value is! num) {
        throw ContentValidationException(
          'durations entries must be numbers, got $value',
        );
      }
      final d = value.toDouble();
      if (!d.isFinite || d <= 0 || d > maxNoteDurationNotes) {
        throw ContentValidationException(
          'durations entries must be between 0 (exclusive) and '
          '$maxNoteDurationNotes base notes, got $d',
        );
      }
      out.add(d);
    }
    return out;
  }

  /// Optional `meter` block: how `tempoBpm` is felt.
  ///
  /// Absent means common time with one note per beat, which is what every tune
  /// written before this field existed actually is — so the whole public-domain
  /// library keeps its exact current timing without a single JSON edit.
  /// Present-but-wrong throws: a half-typed meter falling back to 4/4 would
  /// play the demo at the wrong speed, which is the failure this field exists
  /// to prevent.
  static SongMeter _parseMeter(Object? raw) {
    if (raw == null) return SongMeter.simple;
    if (raw is! Map<String, dynamic>) {
      throw const ContentValidationException('meter must be an object');
    }
    for (final key in const ['beatsPerMeasure', 'beatUnit', 'notesPerBeat']) {
      final value = raw[key];
      if (value != null && (value is! int || value < 1 || value > 16)) {
        throw ContentValidationException(
            'meter.$key must be an int between 1 and 16');
      }
    }
    final dotted = raw['dotted'];
    if (dotted != null && dotted is! bool) {
      throw const ContentValidationException('meter.dotted must be a bool');
    }
    final beatUnit = raw['beatUnit'] as int? ?? 4;
    // A dotted beat only means "compound" on a quarter or eighth. On anything
    // else it is a typo that would silently triple the note spacing.
    if (dotted == true && beatUnit != 4 && beatUnit != 8) {
      throw ContentValidationException(
        'meter.dotted only applies to a quarter or eighth beat, not '
        '$beatUnit',
      );
    }
    return SongMeter(
      beatsPerMeasure: raw['beatsPerMeasure'] as int? ?? 4,
      beatUnit: beatUnit,
      dotted: dotted as bool? ?? false,
      notesPerBeat: raw['notesPerBeat'] as int? ?? 1,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw ContentValidationException('$key must be a non-empty string');
    }
    return value;
  }

  static String? _firstDuplicate(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) return id;
    }
    return null;
  }
}

class ContentValidationException implements Exception {
  const ContentValidationException(this.message);
  final String message;

  @override
  String toString() => 'ContentValidationException: $message';
}
