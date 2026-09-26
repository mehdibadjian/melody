import 'dart:convert';

import 'package:melody_app/domain/content/content_models.dart';

/// Parses and validates lesson content documents against schema v1.
class ContentParser {
  static const supportedSchemaVersion = 2;
  static const supportedSchemaVersions = {1, 2};
  static const minTempoBpm = 40;
  static const maxTempoBpm = 240;
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
    return Level(
      id: _requiredString(raw, 'id'),
      name: _requiredString(raw, 'name'),
      type: type == 'boss_battle' ? LevelType.bossBattle : LevelType.standard,
      requiredNotes: requiredNotes.cast<String>(),
      tempoBpm: tempo,
      successThreshold: SuccessThreshold(
          minAccuracy: minAccuracy.toDouble(), minNotesHit: minNotesHit),
      rewardPayout: RewardPayout(stars: stars, noteCurrency: noteCurrency),
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
