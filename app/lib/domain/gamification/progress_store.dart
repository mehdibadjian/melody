import 'dart:convert';

import 'package:melody_app/domain/gamification/player_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressStore {
  ProgressStore(this._prefs);

  static const _key = 'player_progress_v1';

  final SharedPreferences _prefs;

  PlayerProgress load({String profileId = 'child-local'}) {
    final raw = _prefs.getString(_key);
    if (raw == null) return PlayerProgress.initial(profileId: profileId);
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PlayerProgress.fromJson(json);
    } catch (_) {
      return PlayerProgress.initial(profileId: profileId);
    }
  }

  Future<void> save(PlayerProgress progress) async {
    await _prefs.setString(_key, jsonEncode(progress.toJson()));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
