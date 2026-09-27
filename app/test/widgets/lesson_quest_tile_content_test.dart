import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/content/content_parser.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/widgets/lesson_quest_tile.dart';

/// Guards the point of the quest card: the eleven shipped lessons must be
/// distinguishable *without reading text*.
///
/// The reported problem was "icons on home page are very boring" — nine (in
/// fact all eleven) lessons drew the same `music_note` glyph. A first cut of the
/// redesign keyed the badge on difficulty tint plus the song's first note and
/// its payout, and checking that against the real content showed it had not
/// actually fixed anything: four beginner songs start on C4 and pay 4 stars/6
/// notes and two start on E4 and pay 3/5, so six of the eleven cards rendered
/// identically. Asserting distinctness over `lessons.json` is the only way that
/// stays true as authors add songs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final doc = ContentParser.parseDocument(
    File('assets/content/lessons.json').readAsStringSync(),
  );
  final lessons = doc.lessons;

  /// The card's full visual signature: everything a child can see without
  /// reading, plus the ribbon's note sequence.
  ({String tint, String letter, String ribbon, String reward, int levels})
      signatureOf(Lesson lesson) {
    final pitches = <int>[];
    for (final level in lesson.levels) {
      for (final note in level.requiredNotes) {
        final midi = midiFromNote(note);
        if (midi == null) continue;
        pitches.add(midi);
        if (pitches.length == 12) break;
      }
      if (pitches.length == 12) break;
    }
    String contour;
    if (pitches.isEmpty) {
      contour = 'none';
    } else {
      final low = pitches.reduce(math.min);
      final high = pitches.reduce(math.max);
      final range = (high - low) < 1 ? 1 : (high - low);
      contour = pitches
          .map((m) => ((m - low) / range * 8).round().toString())
          .join(',');
    }
    var firstMidi = 0;
    for (final level in lesson.levels) {
      for (final note in level.requiredNotes) {
        final m = midiFromNote(note);
        if (m != null) {
          firstMidi = m;
          break;
        }
      }
    }
    final stars = lesson.levels.fold(0, (s, l) => s + l.rewardPayout.stars);
    final notes =
        lesson.levels.fold(0, (s, l) => s + l.rewardPayout.noteCurrency);
    return (
      tint: lesson.difficulty.name,
      letter: noteFromMidi((firstMidi % 12) + 60).replaceAll(RegExp(r'\d'), ''),
      ribbon: contour,
      reward: '$stars/$notes',
      levels: lesson.levels.length,
    );
  }

  test('every shipped lesson has a distinct melody ribbon', () {
    final byRibbon = <String, List<String>>{};
    for (final lesson in lessons) {
      byRibbon
          .putIfAbsent(signatureOf(lesson).ribbon, () => [])
          .add(lesson.title);
    }
    final collisions =
        byRibbon.entries.where((e) => e.value.length > 1).toList();
    expect(collisions, isEmpty,
        reason: 'lessons sharing a ribbon contour: '
            '${collisions.map((e) => '${e.key} -> ${e.value.join(' + ')}').join('; ')}');
  });

  test('the card is visually distinct for every pair of shipped lessons', () {
    final seen = <String, String>{};
    for (final lesson in lessons) {
      final key = signatureOf(lesson).toString();
      expect(seen.containsKey(key), isFalse,
          reason: '${lesson.title} renders identically to ${seen[key]}');
      seen[key] = lesson.title;
    }
    expect(seen.length, lessons.length);
  });

  testWidgets('the ribbon renders for each shipped lesson', (tester) async {
    for (final lesson in lessons) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: LessonQuestTile(
                lesson: lesson,
                progress: PlayerProgress.initial(),
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('melody-ribbon-${lesson.id}')),
        findsOneWidget,
        reason: '${lesson.id} ribbon missing',
      );
      expect(tester.takeException(), isNull, reason: lesson.id);
    }
  });
}
