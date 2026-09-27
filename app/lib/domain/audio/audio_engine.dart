import 'package:audioplayers/audioplayers.dart';

abstract interface class AudioEngine {
  Future<void> initialize();
  Future<void> playNote(String note);
  Future<void> dispose();
  bool get isInitialized;
}

class NoteFrequency {
  static const _frequencies = <String, double>{
    'C4': 261.63,
    'D4': 293.66,
    'E4': 329.63,
    'F4': 349.23,
    'F#4': 369.99,
    'G4': 392.00,
    'A4': 440.00,
    'B4': 493.88,
    'C5': 523.25,
    'D5': 587.33,
    'E5': 659.25,
    'F5': 698.46,
    'G5': 783.99,
    'A5': 880.00,
    'B5': 987.77,
    'D6': 1174.66,
  };

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
  Future<void> dispose() async {
    _initialized = false;
    await _player.dispose();
  }
}

class SynthAudioEngine implements AudioEngine {
  bool _initialized = false;
  String? _lastPlayedNote;

  @override
  bool get isInitialized => _initialized;

  String? get lastPlayedNote => _lastPlayedNote;

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
  Future<void> dispose() async {
    _initialized = false;
    _lastPlayedNote = null;
  }
}
