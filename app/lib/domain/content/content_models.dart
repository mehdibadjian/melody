/// Content schema models (PRD §4): lessons, levels, boss battles as data.
///
/// Authored as JSON in `assets/content/` — never hardcoded per-level logic.
library;

import 'package:melody_app/domain/piano/piano_layout.dart';
import 'package:melody_app/domain/rhythm/song_meter.dart';

/// Difficulty tiers for lessons.
enum Difficulty { beginner, intermediate, advanced }

/// Level kind: standard practice level or boss battle.
enum LevelType { standard, bossBattle }

/// A lesson in the adventure map.
///
/// Schema v2 adds optional song metadata ([songTitle], [genre],
/// [attribution]) so real, recognizable tunes can be authored across genres.
/// All three are optional and default sensibly, keeping v1 content valid.
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.levels,
    String? songTitle,
    this.genre = '',
    this.attribution = '',
  }) : _songTitle = songTitle;

  final String id;
  final String title;
  final Difficulty difficulty;
  final List<Level> levels;

  /// Full song name for display (defaults to [title] when not authored).
  String get songTitle => _songTitle ?? title;
  final String? _songTitle;

  /// Free-form genre tag for grouping/filtering the library (e.g. `nursery`,
  /// `classical`, `folk`, `hymn`, `holiday`). Empty when not authored.
  final String genre;

  /// Attribution/licence note (e.g. "Traditional, public domain"). Empty when
  /// not authored.
  final String attribution;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'difficulty': difficulty.name,
        if (_songTitle != null) 'songTitle': _songTitle,
        if (genre.isNotEmpty) 'genre': genre,
        if (attribution.isNotEmpty) 'attribution': attribution,
        'levels': levels.map((l) => l.toJson()).toList(),
      };
}

/// The lowest and highest note a level touches, used to size and position the
/// illustrated keyboard's visible window around the song's actual range.
class NoteRange {
  const NoteRange(this.low, this.high);

  /// Lowest note name, or null when the level has no parseable notes.
  final String? low;

  /// Highest note name, or null when the level has no parseable notes.
  final String? high;

  bool get isEmpty => low == null;
}

/// A playable level within a lesson.
class Level {
  const Level({
    required this.id,
    required this.name,
    required this.type,
    required this.requiredNotes,
    required this.tempoBpm,
    required this.successThreshold,
    required this.rewardPayout,
    this.meter = SongMeter.simple,
    this.durations,
    this.songTempoBpm,
  }) : assert(durations == null ||
            durations.length == requiredNotes.length);

  final String id;
  final String name;
  final LevelType type;
  final List<String> requiredNotes;
  final int tempoBpm;
  final SuccessThreshold successThreshold;
  final RewardPayout rewardPayout;

  /// How [tempoBpm] is felt: which note gets a click and how many of
  /// [requiredNotes] fit inside one click. Common time, one note per beat, when
  /// not authored — so a demo of a 4/4 tune is unchanged by this field existing.
  final SongMeter meter;

  /// How long each note of [requiredNotes] lasts, in units of the meter's base
  /// note value ([SongMeter.notesPerBeat] of them per beat). 1.0 is one base
  /// note; 2.0 is a note held across two of them.
  ///
  /// Null means every note is one base note long, which is what every level
  /// authored before this field existed is — so the whole public-domain library
  /// keeps its exact current timing without a single JSON edit.
  ///
  /// This is the field that makes a demo sound like the tune it teaches. Without
  /// it the melody is a march of equal-length notes: Twinkle's phrase-final G
  /// held two beats, Ode to Joy's closing half note and Amazing Grace's long
  /// "grace" are all unstatable, because [meter] can only move the grid, never
  /// lengthen one note on it. Deliberately parallel to [requiredNotes] rather
  /// than folded into it, and deliberately demo-only: [requiredNotes] is the
  /// scoring contract (`LessonSession` walks it note by note), and a held note
  /// is one note to hit, not two.
  final List<double>? durations;

  /// Duration of the note at [index] in [requiredNotes], in base-note units.
  ///
  /// 1.0 when [durations] is not authored, which is exactly the spacing
  /// [SongMeter.noteMs] has always implied.
  double durationNotesAt(int index) {
    final authored = durations;
    if (authored == null || index < 0 || index >= authored.length) return 1.0;
    return authored[index];
  }

  /// Total length of the melody in base-note units.
  double get totalNoteUnits {
    final authored = durations;
    if (authored == null) return requiredNotes.length.toDouble();
    return authored.fold(0.0, (sum, d) => sum + d);
  }

  /// The tempo of the real recording, counted in the same beat as [tempoBpm].
  ///
  /// Only meaningful for an arrangement of an existing song, and only useful
  /// because a practice tempo and a song tempo are different numbers that are
  /// easy to confuse. When present, the demo says both, so a child hearing a
  /// slow arrangement is not left believing that is how fast the song is.
  final int? songTempoBpm;

  bool get isBossBattle => type == LevelType.bossBattle;

  /// Lowest and highest note across [requiredNotes], derived on demand. Notes
  /// that fail to parse are ignored; an all-unparseable level yields an empty
  /// range. Used to position the illustrated keyboard window on the song's
  /// real span (PRD §3 connected-instrument guidance).
  NoteRange get noteRange {
    var low = 1 << 30;
    var high = -1 << 30;
    for (final note in requiredNotes) {
      final midi = midiFromNote(note);
      if (midi == null) continue;
      if (midi < low) low = midi;
      if (midi > high) high = midi;
    }
    if (high < low) return const NoteRange(null, null);
    return NoteRange(noteFromMidi(low), noteFromMidi(high));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type == LevelType.bossBattle ? 'boss_battle' : 'standard',
        'requiredNotes': requiredNotes,
        'tempoBpm': tempoBpm,
        // Only written when it differs from 4/4-with-one-note-per-beat, so
        // round-tripping the public-domain tunes keeps their existing shape.
        if (meter != SongMeter.simple) 'meter': meter.toJson(),
        // Only written when some note is held longer than one base note. An
        // all-ones list is exactly what "absent" already means, so emitting it
        // would add 85 numbers to GOLDEN's hardest arrangement and change
        // nothing about how it plays.
        if (durations != null && durations!.any((d) => d != 1.0))
          'durations': durations,
        if (songTempoBpm != null) 'songTempoBpm': songTempoBpm,
        'successThreshold': successThreshold.toJson(),
        'rewardPayout': rewardPayout.toJson(),
      };
}

/// What a player must achieve to complete a level.
class SuccessThreshold {
  const SuccessThreshold({
    required this.minAccuracy,
    required this.minNotesHit,
  });

  /// Fraction (0.0–1.0) of notes that must be hit correctly.
  final double minAccuracy;

  /// Absolute minimum number of correct notes.
  final int minNotesHit;

  Map<String, dynamic> toJson() => {
        'minAccuracy': minAccuracy,
        'minNotesHit': minNotesHit,
      };
}

/// Rewards granted on level completion. Spendable on cosmetics only.
class RewardPayout {
  const RewardPayout({required this.stars, required this.noteCurrency});

  final int stars;
  final int noteCurrency;

  Map<String, dynamic> toJson() => {
        'stars': stars,
        'noteCurrency': noteCurrency,
      };
}

/// Root of an authored content document.
class ContentDocument {
  const ContentDocument({required this.schemaVersion, required this.lessons});

  final int schemaVersion;
  final List<Lesson> lessons;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'lessons': lessons.map((l) => l.toJson()).toList(),
      };
}
