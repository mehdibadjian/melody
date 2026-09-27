/// How a level's notes are grouped into felt beats, and the timing maths that
/// falls out of it.
///
/// A level has always carried a `tempoBpm`, but never said *which note gets
/// that beat*. That ambiguity is not academic: "GOLDEN" is a 12/8 song whose
/// published piano arrangements mark it `half note = 90`, which is the same
/// real-world speed as `dotted quarter = 120` and a very different one from
/// `quarter note = 120`. A demo played at the wrong reading is either twice as
/// fast or half as fast as the song the child heard on the soundtrack.
///
/// So the beat is named, not implied: [beatUnit] says which note value the
/// metronome clicks, [dotted] extends it by half, and [notesPerBeat] says how
/// many of the level's notes fit inside one click. Everything else — click
/// spacing, note spacing, measure length — is derived here so no other file
/// re-derives it differently.
library;

/// The felt pulse of a level.
///
/// Defaults to common time with one note per beat, which is what every
/// public-domain tune in the shipped library is: no meter authored means the
/// level behaves exactly as it did before this existed.
class SongMeter {
  const SongMeter({
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
    this.dotted = false,
    this.notesPerBeat = 1,
  });

  /// Common time, one note per click — the shape of Twinkle, Jingle Bells, etc.
  static const SongMeter simple = SongMeter();

  /// Beats per measure as conducted (the number of clicks in a bar), not the
  /// notated top number. 12/8 conducted in four is `4` here.
  final int beatsPerMeasure;

  /// Denominator of the note that gets one beat: `4` = crotchet, `8` = quaver.
  final int beatUnit;

  /// Whether the beat note is dotted (a dotted crotchet is the 12/8 beat).
  final bool dotted;

  /// How many of the level's notes fall inside one beat. 3 in 12/8 where the
  /// notes are quavers.
  final int notesPerBeat;

  /// Length of one beat in ms at [tempoBpm], where the tempo counts *this*
  /// meter's beat.
  double beatMs(int tempoBpm) => 60000.0 / tempoBpm;

  /// Length of one of the level's notes in ms.
  double noteMs(int tempoBpm) => beatMs(tempoBpm) / notesPerBeat;

  /// Length of a full bar in ms.
  double measureMs(int tempoBpm) => beatMs(tempoBpm) * beatsPerMeasure;

  /// Human-readable beat name for the UI, e.g. `dotted quarter` or `quarter`.
  String get beatName {
    final base = switch (beatUnit) {
      1 => 'whole',
      2 => 'half',
      4 => 'quarter',
      8 => 'eighth',
      16 => 'sixteenth',
      _ => '$beatUnit-th',
    };
    return dotted ? 'dotted $base' : base;
  }

  /// The notated time signature a reader would recognise, e.g. `12/8` or `4/4`.
  ///
  /// Reconstructed from the conducted shape: a dotted beat holds three of the
  /// next-smaller note value, so a bar of four dotted crotchets is twelve
  /// eighths — which is why 12/8 is written that way rather than as 4/4 with
  /// triplets.
  String get notation {
    if (!dotted) return '$beatsPerMeasure/$beatUnit';
    return '${beatsPerMeasure * 3}/${beatUnit * 2}';
  }

  Map<String, dynamic> toJson() => {
        'beatsPerMeasure': beatsPerMeasure,
        'beatUnit': beatUnit,
        if (dotted) 'dotted': true,
        'notesPerBeat': notesPerBeat,
      };

  /// Value equality, because a parsed meter and [SongMeter.simple] are
  /// different objects describing the same thing — and `toJson` needs to know
  /// when to leave the field out.
  @override
  bool operator ==(Object other) =>
      other is SongMeter &&
      other.beatsPerMeasure == beatsPerMeasure &&
      other.beatUnit == beatUnit &&
      other.dotted == dotted &&
      other.notesPerBeat == notesPerBeat;

  @override
  int get hashCode =>
      Object.hash(beatsPerMeasure, beatUnit, dotted, notesPerBeat);

  @override
  String toString() =>
      'SongMeter($notation, $notesPerBeat notes per $beatName beat)';
}
