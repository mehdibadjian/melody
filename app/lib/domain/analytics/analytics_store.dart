import 'dart:convert';

import 'package:melody_app/domain/analytics/analytics_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local sink for analytics events (PRD §4, §7). Events are appended as JSON
/// and round-trip through [AnalyticsEvent.fromJson]; corrupt data is dropped
/// defensively so a bad write never blocks play. Backend upload lands with the
/// sync workstream (Phase 1.3) — this store is its local source of truth.
///
/// The buffer is bounded to the most recent [maxEvents] entries:
/// SharedPreferences loads the whole blob into memory on every app start, so
/// an unbounded list would progressively slow launch. Oldest events are
/// evicted first (ring-buffer semantics).
class AnalyticsStore {
  AnalyticsStore(this._prefs, {this.maxEvents = defaultMaxEvents});

  static const _key = 'analytics_events_v1';

  /// Default local retention: enough for the parental dashboard's recent
  /// history, small enough to keep the prefs blob bounded.
  static const defaultMaxEvents = 500;

  final SharedPreferences _prefs;

  /// Maximum number of events retained locally (most recent kept).
  final int maxEvents;

  /// Returns all persisted events in append order. Corrupt top-level data
  /// yields an empty list; individual corrupt entries are skipped.
  List<AnalyticsEvent> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    final List<dynamic> entries;
    try {
      entries = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
    final events = <AnalyticsEvent>[];
    for (final entry in entries) {
      try {
        events.add(
          AnalyticsEvent.fromJson((entry as Map).cast<String, Object?>()),
        );
      } catch (_) {
        // Skip unreadable entries; keep the rest.
      }
    }
    return events;
  }

  /// Appends [event], evicting the oldest entries beyond [maxEvents], and
  /// persists the result.
  Future<void> append(AnalyticsEvent event) async {
    final events = <AnalyticsEvent>[...load(), event];
    final trimmed = events.length > maxEvents
        ? events.sublist(events.length - maxEvents)
        : events;
    final encoded = trimmed.map((e) => e.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(encoded));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
