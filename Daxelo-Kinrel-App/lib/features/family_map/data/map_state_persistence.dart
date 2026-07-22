// lib/features/family_map/data/map_state_persistence.dart
//
// P10.9 — Map State Persistence.
//
// When a user reopens the Family Map, restore their previous session:
// last camera position, zoom, pitch, bearing, selected person, timeline
// year, focus mode state, and expanded household state. This makes the
// experience feel polished and personal — the map "remembers" where
// you were.
//
// Per-family: state is keyed by familyId. Switching families loads
// each family's saved state.
//
// Local-only: state is stored in SharedPreferences. NOT synced to
// the server. Map position is a personal preference, not family data.
//
// Migration-safe: fromJson gracefully handles missing fields (uses
// defaults). Versioned via MapVisualConstants.stateVersion.
//
// Edge cases handled:
//   - Saved state references a deleted person → ignore selectedPersonId.
//   - Saved state references a non-existent household → ignore
//     expandedHouseholdId.
//   - Timeline year in the future → clamp to current year.
//   - Camera far outside family bounds → accept (user explicitly went there).
//   - Corrupted JSON → catch parse error, return null, use defaults.
//
// Rule 15 (Offline): SharedPreferences is local — works offline.
// Rule 14: stateSaveDebounce + stateKeyPrefix + stateVersion from
// MapVisualConstants.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/map_visual_constants.dart';

/// Immutable snapshot of the map's session state for one family.
///
/// Serialized to JSON and stored in SharedPreferences under the key
/// 'map_session_<familyId>'. Restored on map open.
@immutable
class MapSessionState {
  const MapSessionState({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.pitch,
    required this.bearing,
    this.selectedPersonId,
    this.timelineYear,
    this.isFocusMode = false,
    this.expandedHouseholdId,
    this.mapStyleId = 'kinrel_dark',
    this.layerToggles,
    this.version = 1,
    this.savedAt,
  });

  /// Camera center latitude.
  final double lat;

  /// Camera center longitude.
  final double lng;

  /// Camera zoom level.
  final double zoom;

  /// Camera pitch (tilt) in degrees.
  final double pitch;

  /// Camera bearing (rotation) in degrees.
  final double bearing;

  /// Currently-selected person (P10.3 selection). Null when no selection.
  final String? selectedPersonId;

  /// Currently-viewing timeline year (P10.7). Null when not in timeline mode.
  final int? timelineYear;

  /// True when Focus Mode (P10.6) is active.
  final bool isFocusMode;

  /// Currently-expanded household (P10.4). Null when no cluster expanded.
  final String? expandedHouseholdId;

  /// Map style ID (for future style switching).
  final String mapStyleId;

  /// P13 — Per-layer toggle state. Maps the MapControlLayer.name() to a
  /// bool (true = visible). Null on first launch (defaults to all-on).
  /// Stored as a Map<String, bool> rather than Map<MapControlLayer, bool>
  /// so the enum can evolve without breaking serialized state (forward-
  /// compat: unknown keys are dropped on load; missing keys default to
  /// true via the screen's [_layerState] initialization).
  final Map<String, bool>? layerToggles;

  /// Schema version (for forward-compat migrations).
  final int version;

  /// When this state was saved (UTC ISO 8601).
  final String? savedAt;

  /// Default state — used on first launch when no saved state exists.
  /// Centered on India at a country-level zoom.
  factory MapSessionState.defaults() => MapSessionState(
    lat: 22.0,
    lng: 79.0,
    zoom: 4.5,
    pitch: 0,
    bearing: 0,
    version: MapVisualConstants.stateVersion,
    savedAt: DateTime.now().toUtc().toIso8601String(),
  );

  MapSessionState copyWith({
    double? lat,
    double? lng,
    double? zoom,
    double? pitch,
    double? bearing,
    String? selectedPersonId,
    int? timelineYear,
    bool? isFocusMode,
    String? expandedHouseholdId,
    String? mapStyleId,
    Map<String, bool>? layerToggles,
    int? version,
    String? savedAt,
  }) {
    return MapSessionState(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      zoom: zoom ?? this.zoom,
      pitch: pitch ?? this.pitch,
      bearing: bearing ?? this.bearing,
      selectedPersonId: selectedPersonId ?? this.selectedPersonId,
      timelineYear: timelineYear ?? this.timelineYear,
      isFocusMode: isFocusMode ?? this.isFocusMode,
      expandedHouseholdId: expandedHouseholdId ?? this.expandedHouseholdId,
      mapStyleId: mapStyleId ?? this.mapStyleId,
      layerToggles: layerToggles ?? this.layerToggles,
      version: version ?? this.version,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lat': lat,
    'lng': lng,
    'zoom': zoom,
    'pitch': pitch,
    'bearing': bearing,
    'selectedPersonId': selectedPersonId,
    'timelineYear': timelineYear,
    'isFocusMode': isFocusMode,
    'expandedHouseholdId': expandedHouseholdId,
    'mapStyleId': mapStyleId,
    if (layerToggles != null) 'layerToggles': layerToggles,
    'version': version,
    'savedAt': savedAt ?? DateTime.now().toUtc().toIso8601String(),
  };

  /// Parse from JSON. Gracefully handles missing fields + version skew.
  /// Returns null only on a JSON parse error (caller treats as "no saved state").
  factory MapSessionState.fromJson(Map<String, dynamic> json) {
    final currentYear = DateTime.now().year;
    // P13 — Parse layer toggles. Accepts a Map<String, dynamic> from JSON
    // and casts each value to bool. Unknown keys are kept (forward-compat:
    // newer clients may add layers; older clients ignore them via the
    // screen's default-true fallback).
    Map<String, bool>? parseLayerToggles() {
      final raw = json['layerToggles'];
      if (raw is! Map) return null;
      final out = <String, bool>{};
      for (final entry in raw.entries) {
        if (entry.value is bool) {
          out[entry.key.toString()] = entry.value as bool;
        }
      }
      return out.isEmpty ? null : out;
    }

    return MapSessionState(
      lat: _asDouble(json['lat']) ?? 22.0,
      lng: _asDouble(json['lng']) ?? 79.0,
      zoom: _asDouble(json['zoom']) ?? 4.5,
      pitch: _asDouble(json['pitch']) ?? 0,
      bearing: _asDouble(json['bearing']) ?? 0,
      selectedPersonId: json['selectedPersonId'] as String?,
      timelineYear: () {
        final year = json['timelineYear'];
        if (year is int) {
          // Clamp future years to current year.
          return year > currentYear ? currentYear : year;
        }
        return null;
      }(),
      isFocusMode: json['isFocusMode'] as bool? ?? false,
      expandedHouseholdId: json['expandedHouseholdId'] as String?,
      mapStyleId: json['mapStyleId'] as String? ?? 'kinrel_dark',
      layerToggles: parseLayerToggles(),
      version: json['version'] as int? ?? 1,
      savedAt: json['savedAt'] as String?,
    );
  }

  @override
  String toString() =>
      'MapSessionState(lat: $lat, lng: $lng, zoom: $zoom, pitch: $pitch, '
      'bearing: $bearing, selected: $selectedPersonId, year: $timelineYear, '
      'focus: $isFocusMode, household: $expandedHouseholdId, '
      'layers: $layerToggles, v$version)';
}

double? _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return null;
}

/// Save / load / clear [MapSessionState] for a family.
///
/// All methods are async — they hit SharedPreferences on disk. Save is
/// debounced by the caller (typically 500ms — MapVisualConstants.stateSaveDebounce).
class MapStatePersistence {
  MapStatePersistence._();

  static const _keyPrefix = MapVisualConstants.stateKeyPrefix;

  /// Save the session state for [familyId].
  static Future<void> save(String familyId, MapSessionState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(state.toJson());
      await prefs.setString('$_keyPrefix$familyId', json);
    } catch (e) {
      debugPrint('⚠️ MapStatePersistence.save failed: $e');
    }
  }

  /// Load the session state for [familyId]. Returns null if no saved
  /// state exists or the JSON is corrupted.
  static Future<MapSessionState?> load(String familyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_keyPrefix$familyId');
      if (json == null) return null;
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return MapSessionState.fromJson(decoded);
    } catch (e) {
      debugPrint('⚠️ MapStatePersistence.load failed: $e — using defaults');
      return null;
    }
  }

  /// Clear the session state for [familyId].
  static Future<void> clear(String familyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$familyId');
    } catch (e) {
      debugPrint('⚠️ MapStatePersistence.clear failed: $e');
    }
  }

  /// Clear all saved map session states (every family). Used by the
  /// dev reset + on logout.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('⚠️ MapStatePersistence.clearAll failed: $e');
    }
  }
}

/// Debounced saver — wraps [MapStatePersistence.save] with a debounce
/// timer so rapid camera changes don't write to disk on every frame.
class DebouncedMapStateSaver {
  DebouncedMapStateSaver(this.familyId, {Duration? debounce})
    : _debounce = debounce ?? MapVisualConstants.stateSaveDebounce;

  final String familyId;
  final Duration _debounce;
  Timer? _timer;
  MapSessionState? _pending;

  /// Schedules a save after [_debounce] has elapsed. If another [schedule]
  /// call arrives before the timer fires, the timer resets.
  void schedule(MapSessionState state) {
    _pending = state;
    _timer?.cancel();
    _timer = Timer(_debounce, _flush);
  }

  /// Saves immediately (cancels any pending debounced save). Call on
  /// app dispose / AppLifecycleState.paused.
  Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;
    await _flush();
  }

  Future<void> _flush() async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    await MapStatePersistence.save(familyId, pending);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
