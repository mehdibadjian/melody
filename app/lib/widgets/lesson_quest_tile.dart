import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:melody_app/domain/content/content_models.dart';
import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/theme/tama_theme.dart';
import 'package:melody_app/widgets/illustrated_keyboard.dart';

/// A lesson rendered as a quest card on the adventure map.
///
/// The map used to be a plain [ListTile] whose leading widget was the same
/// `music_note` icon for **all eleven** lessons shipped at the time — and there
/// were no boss levels in that content either, so the `local_fire_department`
/// branch never fired. Every song looked identical, so a child could not tell an
/// easy tune from a hard one, or one they had beaten from one they had not,
/// without reading the small print.
/// This card puts those facts into things that read at a glance:
///
///  * **Identity** — the card draws the song's own opening phrase as a coloured
///    contour ribbon (see `_MelodyRibbon`), so two lessons cannot render the
///    same card. Difficulty tint plus a first-note badge looked promising but
///    collapsed: four beginner songs share C4 and 4★/6♫, so they were
///    pixel-identical.
///  * **Progress** — a ring around the badge fills with the share of levels
///    cleared, and the levels light up as pips.
///  * **Stakes** — the reward is shown as stars and notes before the tap, not
///    only after.
///
/// It stays a single tap target and routes through the same play-mode sheet, so
/// navigation is unchanged.
class LessonQuestTile extends StatelessWidget {
  const LessonQuestTile({
    super.key,
    required this.lesson,
    required this.progress,
    required this.onTap,
  });

  final Lesson lesson;
  final PlayerProgress progress;
  final VoidCallback onTap;

  /// Number of this lesson's levels the child has cleared.
  int get clearedCount => lesson.levels
      .where((l) => progress.completedLevelIds.contains(l.id))
      .length;

  /// 0..1 share of levels cleared; 0 for a lesson with no levels, which cannot
  /// ship but must not divide by zero if one is authored.
  double get fraction {
    if (lesson.levels.isEmpty) return 0;
    return clearedCount / lesson.levels.length;
  }

  bool get isCleared => clearedCount == lesson.levels.length;

  bool get isBoss => lesson.levels.any((l) => l.isBossBattle);

  /// The first note the song actually uses, as the badge glyph's letter, and
  /// the colour that note's pitch class owns.
  ({String letter, Color color}) get _anchor {
    for (final level in lesson.levels) {
      for (final note in level.requiredNotes) {
        final midi = midiFromNote(note);
        if (midi == null) continue;
        return (
          // Read the pitch class through octave 4 so the name never carries a
          // negative octave: noteFromMidi(0) is 'C-1', and stripping digits
          // from that leaves a stray minus sign.
          letter: noteFromMidi((midi % 12) + 60).replaceAll(RegExp(r'\d'), ''),
          color: IllustratedKeyboard.colorForNote(note),
        );
      }
    }
    // A level with no parseable notes cannot ship (the content validator
    // rejects it), but the badge must never be blank.
    return (letter: 'C', color: TamaColors.purple);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _QuestTint.of(lesson.difficulty);
    final cleared = isCleared;
    final anchor = _anchor;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: tint.border, width: cleared ? 2.5 : 1.5),
      ),
      color: tint.card,
      child: InkWell(
        key: Key('lesson-tile-${lesson.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _QuestBadge(
                tint: tint,
                letter: anchor.letter,
                noteColor: anchor.color,
                fraction: fraction,
                cleared: cleared,
                isBoss: isBoss,
                badgeKey: Key('quest-badge-${lesson.id}'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lesson.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (isBoss)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.local_fire_department,
                              size: 20,
                              color: TamaColors.rose,
                              semanticLabel: 'Boss battle',
                              key: Key('boss-${lesson.id}'),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (lesson.songTitle != lesson.title)
                      Text(
                        lesson.songTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: TamaColors.ink.withOpacity(0.75)),
                      ),
                    Text(
                      lesson.difficulty.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tint.pip,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _LevelPips(
                      lesson: lesson,
                      progress: progress,
                      tint: tint,
                    ),
                    const SizedBox(height: 6),
                    _MelodyRibbon(lesson: lesson),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RewardStack(lesson: lesson, cleared: cleared),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-difficulty palette for a quest card.
class _QuestTint {
  const _QuestTint({
    required this.top,
    required this.bottom,
    required this.card,
    required this.border,
    required this.pip,
  });

  final Color top;
  final Color bottom;
  final Color card;
  final Color border;
  final Color pip;

  static const _beginner = _QuestTint(
    top: TamaColors.emerald,
    bottom: TamaColors.purple,
    card: Color(0xFFFFFFFF),
    border: TamaColors.emerald,
    pip: TamaColors.emerald,
  );

  static const _intermediate = _QuestTint(
    top: TamaColors.amber,
    bottom: TamaColors.orange,
    card: Color(0xFFFFFBF3),
    border: TamaColors.amber,
    pip: TamaColors.amber,
  );

  static const _advanced = _QuestTint(
    top: TamaColors.purple,
    bottom: TamaColors.pink,
    card: Color(0xFFFBF6FF),
    border: TamaColors.purple,
    pip: TamaColors.purple,
  );

  static _QuestTint of(Difficulty difficulty) => switch (difficulty) {
        Difficulty.beginner => _beginner,
        Difficulty.intermediate => _intermediate,
        Difficulty.advanced => _advanced,
      };
}

/// The badge: gradient disc, note glyph, progress ring, and a crown when the
/// whole lesson is beaten.
class _QuestBadge extends StatelessWidget {
  const _QuestBadge({
    required this.tint,
    required this.letter,
    required this.noteColor,
    required this.fraction,
    required this.cleared,
    required this.isBoss,
    required this.badgeKey,
  });

  final _QuestTint tint;
  final String letter;
  final Color noteColor;
  final double fraction;
  final bool cleared;
  final bool isBoss;

  /// Unique so two lessons that happen to start on the same note do not share a
  /// key (which would make `find.byKey` ambiguous in a widget test).
  final Key badgeKey;

  static const double _size = 58;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 8,
      height: _size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.top, tint.bottom],
              ),
              boxShadow: [
                BoxShadow(
                  color: tint.bottom.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                letter,
                key: badgeKey,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  // On a cleared badge the disc goes white so the stars/crown
                  // read; the letter keeps the song's own colour there.
                  color: cleared ? noteColor : Colors.white,
                ),
              ),
            ),
          ),
          // Progress ring. Drawn only while there is something to show, so an
          // untouched lesson is a clean disc rather than a grey "0%" halo.
          if (fraction > 0)
            IgnorePointer(
              child: SizedBox(
                width: _size + 8,
                height: _size + 8,
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 4,
                  backgroundColor: tint.bottom.withOpacity(0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    cleared ? TamaColors.amber : tint.bottom,
                  ),
                ),
              ),
            ),
          if (cleared)
            const Positioned(
              right: -2,
              top: -6,
              child: Icon(
                Icons.workspace_premium,
                size: 22,
                color: TamaColors.amber,
                semanticLabel: 'Lesson complete',
              ),
            )
          else if (isBoss)
            Positioned(
              left: -2,
              top: -6,
              child: Transform.rotate(
                angle: -math.pi / 10,
                child: const Icon(
                  Icons.bolt,
                  size: 20,
                  color: TamaColors.rose,
                  semanticLabel: 'Boss battle',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The song's opening phrase drawn as a pitch contour.
///
/// This is what makes two cards differ. A first attempt at "gamify the icons"
/// keyed the badge on difficulty tint plus the song's first note, and I checked
/// it against the shipped content rather than trusting it: four beginner songs
/// start on C4 and pay 4★/6♫, two start on E4 and pay 3★/5♫, so six of eleven
/// cards would have rendered pixel-identically — the same complaint the issue
/// was filed about. Every lesson here has a distinct note *sequence*, so the
/// sequence itself is the honest identity signal.
///
/// Each bar's height is the note's pitch relative to the phrase, and its colour
/// is that note's pitch class via [IllustratedKeyboard.colorForNote], so the
/// ribbon teaches the same colour code the practice keyboard uses. Only the
/// first [_maxNotes] are drawn; the row scrolls and a long phrase adds nothing a
/// short one does not.
class _MelodyRibbon extends StatelessWidget {
  const _MelodyRibbon({required this.lesson});

  final Lesson lesson;

  static const int _maxNotes = 12;

  /// Pitch of the first [_maxNotes] parseable notes, or empty when the lesson
  /// has none (the content validator rejects that, so it is a render-time
  /// guard rather than a supported state).
  List<int> get pitches {
    final out = <int>[];
    for (final level in lesson.levels) {
      for (final note in level.requiredNotes) {
        final midi = midiFromNote(note);
        if (midi == null) continue;
        out.add(midi);
        if (out.length == _maxNotes) return out;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final notes = pitches;
    if (notes.isEmpty) return const SizedBox(height: 18);
    return SizedBox(
      height: 18,
      // Semantics name the phrase, so a screen-reader child gets "Melody of
      // Twinkle Twinkle Little Star" instead of an unlabeled strip of bars.
      child: LayoutBuilder(
        // CustomPaint takes its size from `size`, so the width has to come from
        // the incoming constraints; Size(double.infinity, 18) is unbounded.
        builder: (context, constraints) => Semantics(
          label: 'Melody of ${lesson.songTitle}',
          child: CustomPaint(
            key: Key('melody-ribbon-${lesson.id}'),
            size: Size(constraints.maxWidth, 18),
            painter: _RibbonPainter(notes: notes),
          ),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter({required this.notes});

  final List<int> notes;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) return;
    final low = notes.reduce(math.min);
    final high = notes.reduce(math.max);
    // A phrase on one repeated note has no contour; give the range a floor so
    // the bars spread instead of collapsing onto a single baseline.
    final range = math.max(high - low, 1);
    final slot = size.width / notes.length;
    final barWidth = math.min(math.max(slot * 0.55, 2.0), size.width);
    final minBar = size.height * 0.22;
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final t = (note - low) / range;
      final height = minBar + (size.height - minBar) * t;
      final left = i * slot + (slot - barWidth) / 2;
      final rect = Rect.fromLTWH(left, size.height - height, barWidth, height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        // Same pitch-class colour the practice keyboard uses, so the ribbon
        // teaches the code rather than inventing a second one.
        Paint()..color = IllustratedKeyboard.colorForPitchClass(note),
      );
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.notes.join() != notes.join();
}

/// One dot per level, filled when cleared; a boss level gets a diamond.
class _LevelPips extends StatelessWidget {
  const _LevelPips({
    required this.lesson,
    required this.progress,
    required this.tint,
  });

  final Lesson lesson;
  final PlayerProgress progress;
  final _QuestTint tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final level in lesson.levels)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: CustomPaint(
              key: Key('pip-${level.id}'),
              size: const Size(13, 13),
              painter: _PipPainter(
                filled: progress.completedLevelIds.contains(level.id),
                diamond: level.isBossBattle,
                color: tint.pip,
              ),
            ),
          ),
        const SizedBox(width: 2),
        Text(
          '${lesson.levels.where((l) => progress.completedLevelIds.contains(l.id)).length}'
          '/${lesson.levels.length}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: TamaColors.ink.withOpacity(0.65),
          ),
        ),
      ],
    );
  }
}

class _PipPainter extends CustomPainter {
  const _PipPainter({
    required this.filled,
    required this.diamond,
    required this.color,
  });

  final bool filled;
  final bool diamond;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final centre = size.center(Offset.zero);
    final radius = size.width / 2 - 1;
    paint.color = filled ? color : color.withOpacity(0.35);
    if (filled) {
      paint.style = PaintingStyle.fill;
      paint.color = color;
    }
    if (diamond) {
      final path = Path()
        ..moveTo(centre.dx, centre.dy - radius)
        ..lineTo(centre.dx + radius, centre.dy)
        ..lineTo(centre.dx, centre.dy + radius)
        ..lineTo(centre.dx - radius, centre.dy)
        ..close();
      canvas.drawPath(path, paint);
    } else {
      canvas.drawCircle(centre, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PipPainter old) =>
      old.filled != filled || old.diamond != diamond || old.color != color;
}

/// Stars and note-currency the lesson is worth, before the tap.
class _RewardStack extends StatelessWidget {
  const _RewardStack({required this.lesson, required this.cleared});

  final Lesson lesson;
  final bool cleared;

  int get stars =>
      lesson.levels.fold(0, (sum, l) => sum + l.rewardPayout.stars);
  int get notes =>
      lesson.levels.fold(0, (sum, l) => sum + l.rewardPayout.noteCurrency);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 15, color: TamaColors.amber),
            const SizedBox(width: 2),
            Text('$stars',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, size: 15, color: TamaColors.purple),
            const SizedBox(width: 2),
            Text('$notes',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
        if (cleared)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              'done',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: TamaColors.emerald.withOpacity(0.9),
              ),
            ),
          ),
      ],
    );
  }
}
