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
  };

  static double? of(String note) => _frequencies[note];
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
    await _player.play(AssetSource('audio/notes/${note.toLowerCase()}.wav'));
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
