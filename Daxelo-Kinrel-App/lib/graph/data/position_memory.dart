// lib/graph/data/position_memory.dart
//
// DAXELO KINREL — Position Memory (V2.1 Data Layer)
//
// Persists camera state (pan, zoom, focused node) to SharedPreferences
// so the user returns to exactly where they left off. Per-family
// memory keyed by familyId.
//
// Iron Rules:
//   1. Never drift — camera never moves without user action.
//   2. Never auto-center — the saved position is always restored.
//   3. Never auto-zoom without user action.
//
// Restoration flow on graph re-open:
//   1. Saved position applied instantly (no animation).
//   2. Single frame rendered to confirm layout matches.
//   3. If data changed since position saved (cache timestamp
//      comparison) → 300 ms repositioning animation.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════════════════

/// Immutable snapshot of camera position and zoom state.
///
/// Represents the exact camera configuration that should be restored
/// when the user re-opens a family graph.
class CameraPosition {
  /// Creates a camera position snapshot.
  const CameraPosition({
    required this.panX,
    required this.panY,
    required this.zoomLevel,
    this.focusedNodeId,
    required this.lastModified,
  });

  /// Horizontal pan offset in graph-space pixels.
  final double panX;

  /// Vertical pan offset in graph-space pixels.
  final double panY;

  /// Zoom level (1.0 = default, range 0.2x–5.0x).
  final double zoomLevel;

  /// ID of the node that was focused when this position was saved,
  /// or null if no node was focused.
  final String? focusedNodeId;

  /// When this position was last saved.
  final DateTime lastModified;

  /// Deserializes from a JSON map.
  factory CameraPosition.fromJson(Map<String, dynamic> json) {
    return CameraPosition(
      panX: (json['pan_x'] as num).toDouble(),
      panY: (json['pan_y'] as num).toDouble(),
      zoomLevel: (json['zoom_level'] as num).toDouble(),
      focusedNodeId: json['focused_node_id'] as String?,
      lastModified: json['last_modified'] != null
          ? DateTime.parse(json['last_modified'] as String)
          : DateTime.now(),
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'pan_x': panX,
        'pan_y': panY,
        'zoom_level': zoomLevel,
        'focused_node_id': focusedNodeId,
        'last_modified': lastModified.toIso8601String(),
      };

  /// Creates a copy with optional overrides.
  CameraPosition copyWith({
    double? panX,
    double? panY,
    double? zoomLevel,
    String? focusedNodeId,
    DateTime? lastModified,
  }) {
    return CameraPosition(
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      focusedNodeId: focusedNodeId ?? this.focusedNodeId,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraPosition &&
          panX == other.panX &&
          panY == other.panY &&
          zoomLevel == other.zoomLevel &&
          focusedNodeId == other.focusedNodeId;

  @override
  int get hashCode =>
      Object.hash(panX, panY, zoomLevel, focusedNodeId);
}

// ═══════════════════════════════════════════════════════════════════════
// POSITION MEMORY
// ═══════════════════════════════════════════════════════════════════════

/// Persists and restores camera state via SharedPreferences.
///
/// Camera state is saved after a 500 ms debounce when the camera
/// stops moving, and restored instantly (no animation) when the
/// graph is reopened. If the underlying data has changed since the
/// position was saved, a 300 ms repositioning animation is used
/// instead.
///
/// Memory is per-family (keyed by [familyId]), so switching
/// families always restores the correct camera position.
///
/// Iron Rules (enforced by this class and [CameraController]):
///   1. Never drift — camera never moves without user action.
///   2. Never auto-center — the saved position is always restored.
///   3. Never auto-zoom without user action.
class PositionMemory {
  /// Creates a position memory instance.
  ///
  /// [debounceDuration] controls how long the camera must be idle
  /// before the position is persisted (default: 500 ms).
  PositionMemory({
    Duration debounceDuration = const Duration(milliseconds: 500),
  }) : _debounceDuration = debounceDuration;

  final Duration _debounceDuration;

  /// SharedPreferences key prefix for camera positions.
  static const String _keyPrefix = 'kinrel_camera_pos_';

  /// SharedPreferences key prefix for graph data timestamps.
  static const String _dataTimestampPrefix = 'kinrel_data_ts_';

  /// Active debounce timers keyed by familyId.
  final Map<String, Timer> _debounceTimers = <String, Timer>{};

  /// Pending camera position updates (applied after debounce).
  final Map<String, CameraPosition> _pendingPositions =
      <String, CameraPosition>{};

  /// Cached SharedPreferences instance.
  SharedPreferences? _prefs;

  bool _isDisposed = false;

  // ── Public API ───────────────────────────────────────────────────

  /// Saves the camera position for the given [familyId].
  ///
  /// The save is debounced by [_debounceDuration] to avoid excessive
  /// writes during continuous panning/zooming. Only the final position
  /// after the camera stops moving is persisted.
  Future<void> savePosition(
    String familyId, {
    required double panX,
    required double panY,
    required double zoomLevel,
    String? focusedNodeId,
  }) async {
    _checkDisposed();

    final position = CameraPosition(
      panX: panX,
      panY: panY,
      zoomLevel: zoomLevel,
      focusedNodeId: focusedNodeId,
      lastModified: DateTime.now(),
    );

    _pendingPositions[familyId] = position;

    // Cancel any existing debounce timer.
    _debounceTimers[familyId]?.cancel();

    // Start a new debounce timer.
    _debounceTimers[familyId] = Timer(_debounceDuration, () async {
      await _persistPosition(familyId);
    });
  }

  /// Loads the saved camera position for the given [familyId].
  ///
  /// Returns null if no position has been saved for this family.
  Future<CameraPosition?> loadPosition(String familyId) async {
    _checkDisposed();

    try {
      final prefs = await _getPrefs();
      final key = '$_keyPrefix$familyId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CameraPosition.fromJson(json);
    } catch (e) {
      debugPrint('⚠️ PositionMemory.loadPosition error: $e');
      return null;
    }
  }

  /// Clears the saved camera position for the given [familyId].
  Future<void> clearPosition(String familyId) async {
    _checkDisposed();

    try {
      final prefs = await _getPrefs();
      await prefs.remove('$_keyPrefix$familyId');
      await prefs.remove('$_dataTimestampPrefix$familyId');
    } catch (e) {
      debugPrint('⚠️ PositionMemory.clearPosition error: $e');
    }
  }

  /// Returns whether a saved position exists for [familyId].
  Future<bool> hasPosition(String familyId) async {
    _checkDisposed();

    try {
      final prefs = await _getPrefs();
      return prefs.containsKey('$_keyPrefix$familyId');
    } catch (e) {
      debugPrint('⚠️ PositionMemory.hasPosition error: $e');
      return false;
    }
  }

  /// Returns whether the graph data has changed since the position
  /// was last saved.
  ///
  /// Compares the saved data timestamp with the position's
  /// [CameraPosition.lastModified]. If data is newer, the graph
  /// should use a 300 ms repositioning animation instead of instant
  /// restoration.
  Future<bool> hasDataChanged(String familyId) async {
    _checkDisposed();

    try {
      final prefs = await _getPrefs();
      final positionKey = '$_keyPrefix$familyId';
      final dataTimestampKey = '$_dataTimestampPrefix$familyId';

      final posJsonStr = prefs.getString(positionKey);
      final dataTimestampMs = prefs.getInt(dataTimestampKey);

      if (posJsonStr == null || dataTimestampMs == null) return true;

      final posJson = jsonDecode(posJsonStr) as Map<String, dynamic>;
      final position = CameraPosition.fromJson(posJson);

      final dataTimestamp =
          DateTime.fromMillisecondsSinceEpoch(dataTimestampMs);
      return dataTimestamp.isAfter(position.lastModified);
    } catch (e) {
      debugPrint('⚠️ PositionMemory.hasDataChanged error: $e');
      return true; // Assume data changed on error.
    }
  }

  /// Records the current data timestamp for a family.
  ///
  /// This should be called whenever graph data is fetched/refreshed.
  /// The timestamp is compared against the saved camera position's
  /// lastModified to determine if a repositioning animation is needed.
  Future<void> recordDataTimestamp(String familyId) async {
    _checkDisposed();

    try {
      final prefs = await _getPrefs();
      await prefs.setInt(
        '$_dataTimestampPrefix$familyId',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('⚠️ PositionMemory.recordDataTimestamp error: $e');
    }
  }

  /// Flushes any pending debounced saves immediately.
  ///
  /// Call this when the graph screen is being disposed to ensure
  /// the last camera position is persisted.
  Future<void> flush() async {
    final familyIds = _pendingPositions.keys.toList();
    for (final familyId in familyIds) {
      _debounceTimers[familyId]?.cancel();
      await _persistPosition(familyId);
    }
  }

  /// Disposes all timers and resources.
  void dispose() {
    _isDisposed = true;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pendingPositions.clear();
  }

  // ── Private Helpers ──────────────────────────────────────────────

  /// Persists the pending position for [familyId] to SharedPreferences.
  Future<void> _persistPosition(String familyId) async {
    final position = _pendingPositions.remove(familyId);
    if (position == null) return;

    try {
      final prefs = await _getPrefs();
      final key = '$_keyPrefix$familyId';
      await prefs.setString(key, jsonEncode(position.toJson()));
    } catch (e) {
      debugPrint('⚠️ PositionMemory._persistPosition error: $e');
    }
  }

  /// Returns the SharedPreferences instance, initializing it lazily.
  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Throws if this instance has been disposed.
  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('PositionMemory has been disposed');
    }
  }
}
