import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/content/content_parser.dart';

/// Loads authored lesson content from the bundled asset (PRD §4: lessons are
/// data, not hardcoded logic).
class ContentRepository {
  const ContentRepository();

  static const assetPath = 'assets/content/lessons.json';

  Future<ContentDocument> loadLessons() async {
    final raw = await rootBundle.loadString(assetPath);
    return ContentParser.parseDocument(raw);
  }

  ContentDocument parse(String raw) => ContentParser.parseDocument(raw);

  String encode(ContentDocument doc) => jsonEncode(doc.toJson());
}
