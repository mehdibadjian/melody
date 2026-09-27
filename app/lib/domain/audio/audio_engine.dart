import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:melody_app/domain/piano/piano_layout.dart';

abstract interface class AudioEngine {
  Future<void> initialize();
  Future<void> playNote(String note);

  /// Metronome click for the demo and count-in. [strong] is the downbeat, so a
  /// child hears where the bar begins rather than an undifferentiated tick.
  Future<void> playClick({bool strong = true});

  Future<void> dispose();
  bool get isInitialized;
}

/// The notes the app can sound, and their pitches.
///
/// This is derived from [KeyboardLayout.sixtyOne] — the same definition the
/// illustrated keyboard draws and the content guards check — rather than being
/// typed out note by note. A hand-written table and a hand-written asset
/// folder drift by exactly one key at a time, silently, because
/// [AssetAudioEngine.playNote] returns without a word for anything it has no
/// entry for; the reported symptom of that drift is a piano with a dead key,
/// not a crash. Deriving it means a key that exists on the board either has
/// audio or fails a test.
class NoteFrequency {
  static final Map<String, double> _frequencies = {
    for (final note in KeyboardLayout.sixtyOne.notes)
      note: _equalTempered(note),
  };

  /// Equal-tempered frequency with A4 = 440 Hz, computed from the note's MIDI
  /// number (see [midiFromNote], the repo's one note-name parser).
  static double _equalTempered(String note) {
    final midi = midiFromNote(note);
    if (midi == null) {
      throw StateError('$note is not a parseable note name');
    }
    return 440.0 * math.pow(2, (midi - 69) / 12).toDouble();
  }

  static double? of(String note) => _frequencies[note];

  /// Which notes the app can actually sound: the keys with a table entry.
  static Set<String> get playableNotes => Set.unmodifiable(_frequencies.keys);
}

/// Maps a note name to its bundled asset path.
///
/// Note names spell sharps with `#` (`F#4`), but `#` is the URL fragment
/// delimiter and an asset path is URI-encoded for web and unpacked to a real
/// file on Android and iOS. A `#` in a bundle path can therefore be read as the
/// end of the path. That would be invisible rather than loud, because
/// [AssetAudioEngine.playNote] returns without throwing when a source fails —
/// a sharp key would simply feel broken.
///
/// So sharps are spelled `s` on disk (`fs4.wav`, the conventional MIDI spelling)
/// and translated here, once, where a test can pin it.
class NoteAsset {
  const NoteAsset._();

  /// Bundle-relative path for [note], e.g. `audio/notes/fs4.wav` for `F#4`.
  static String pathFor(String note) => 'audio/notes/${fileBaseFor(note)}.wav';

  /// Asset file name without extension: lower-cased, `#` spelled `s`.
  static String fileBaseFor(String note) =>
      note.toLowerCase().replaceAll('#', 's');

  /// Reverses [fileBaseFor] for a file name (`fs4.wav` -> `F#4`).
  ///
  /// Safe to invert because note letters are A–G, so an `S` can only have come
  /// from a `#`. Takes a bare file name; callers that list a directory split
  /// the path first.
  static String noteNameFromFile(String fileName) => fileName
      .replaceAll(RegExp(r'\.wav$'), '')
      .toUpperCase()
      .replaceAll('S', '#');
}

class AssetAudioEngine implements AudioEngine {
  AssetAudioEngine({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  /// A second deck, because the click has to sound *with* the note it lands on.
  /// Sharing [_player] would `stop()` the melody note every time the metronome
  /// ticked, which turns a rhythm demo into a click track with gaps in it.
  ///
  /// Built on first use, never in the constructor: an `AudioPlayer` touches the
  /// platform channel as it is created, so a second eager one turned the
  /// plugin's absence under `flutter test` into an unhandled error instead of a
  /// caught one.
  AudioPlayer? _clickPlayer;
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    await _player.setReleaseMode(ReleaseMode.stop);
    _initialized = true;
  }

  @override
  Future<void> playNote(String note) async {
    if (!_initialized || NoteFrequency.of(note) == null) return;
    await _player.stop();
    await _player.play(AssetSource(NoteAsset.pathFor(note)));
  }

  @override
  Future<void> playClick({bool strong = true}) async {
    if (!_initialized) return;
    final click = _clickPlayer ??= AudioPlayer();
    await click.setReleaseMode(ReleaseMode.stop);
    await click.stop();
    await click.play(AssetSource(strong ? _strongClickPath : _weakClickPath));
  }

  static const _strongClickPath = 'audio/clicks/strong.wav';
  static const _weakClickPath = 'audio/clicks/weak.wav';

  @override
  Future<void> dispose() async {
    _initialized = false;
    await _player.dispose();
    await _clickPlayer?.dispose();
  }
}

class SynthAudioEngine implements AudioEngine {
  bool _initialized = false;
  String? _lastPlayedNote;
  bool? _lastClickStrong;

  @override
  bool get isInitialized => _initialized;

  String? get lastPlayedNote => _lastPlayedNote;

  /// Which click was last asked for (null until one is played). Lets a widget
  /// test assert the downbeat is distinguishable without a speaker.
  bool? get lastClickStrong => _lastClickStrong;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> playNote(String note) async {
    if (!_initialized || NoteFrequency.of(note) == null) return;
    _lastPlayedNote = note;
  }

  @override
  Future<void> playClick({bool strong = true}) async {
    if (!_initialized) return;
    _lastClickStrong = strong;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    _lastPlayedNote = null;
    _lastClickStrong = null;
  }
}
