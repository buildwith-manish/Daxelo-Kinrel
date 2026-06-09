// lib/core/utils/isolate_utils.dart
//
// DAXELO KINREL — Dart Isolate Utilities for Heavy Work
//
// Centralizes compute() calls for JSON parsing, batch operations,
// and graph computation to keep the main thread jank-free.
//
// Key design:
// - compute() for one-shot parallel work (JSON parse, batch upsert)
// - IsolateNameServer for persistent sync isolate (single-entrypoint)
// - Threshold: use compute() when list.length > 20 (matching existing pattern)
// - All isolate functions are TOP-LEVEL (required by compute())
// - compute() can only pass data (no closures/functions across boundaries)
//
// Thread safety: Drift is NOT thread-safe. All DB writes MUST happen on
// the main isolate. compute() is only used for CPU-bound work (parsing,
// filtering, graph algorithms) that doesn't touch the DB.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

// ════════════════════════════════════════════════════════════════════
// THRESHOLD CONSTANTS
// ════════════════════════════════════════════════════════════════════

/// Minimum list size to trigger compute() for JSON parsing.
/// Lists smaller than this are parsed on the main thread (overhead of
/// isolate spawn > parse time for small lists).
const kComputeThreshold = 20;

// ════════════════════════════════════════════════════════════════════
// JSON PARSING ISOLATES — Type-Specific Top-Level Functions
// ════════════════════════════════════════════════════════════════════
//
// compute() can only call top-level or static functions — it cannot
// pass closures across isolate boundaries. So we define one top-level
// function per domain type, just like the existing _parseFamilyList etc.
// These are the same functions, but centralized here for reuse.

/// Parse a raw JSON list into a list of typed maps.
/// This is a lightweight pre-processing step that can run in an isolate.
/// The actual `fromJson` construction still happens, but for simple
/// models the cost is minimal.
///
/// For types that need `fromJson` in the isolate, use the specific
/// top-level functions below.
List<Map<String, dynamic>> parseJsonList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => json as Map<String, dynamic>)
      .toList();
}

/// Filter a list of maps by checking if a key is null.
/// Used for filtering out soft-deleted entities.
List<Map<String, dynamic>> filterNotNullKey(
    _FilterByKeyPayload payload) {
  return payload.maps
      .where((m) => m[payload.key] == null)
      .toList();
}

/// Payload for filter-by-key isolate work.
class _FilterByKeyPayload {
  final List<Map<String, dynamic>> maps;
  final String key;

  const _FilterByKeyPayload(this.maps, this.key);
}

// ════════════════════════════════════════════════════════════════════
// JSON ENCODE ISOLATE
// ════════════════════════════════════════════════════════════════════

/// Encode a list of maps to JSON strings on a background isolate.
/// Useful when batch-caching hundreds of objects to Drift.
///
/// Usage:
/// ```dart
/// final jsonStrings = await compute(encodeMapList, maps);
/// ```
List<String> encodeMapList(List<Map<String, dynamic>> maps) {
  return maps.map((m) {
    try {
      return const JsonEncoder().convert(m);
    } catch (_) {
      // Sanitize unencodable values
      final sanitized = <String, dynamic>{};
      for (final entry in m.entries) {
        try {
          const JsonEncoder().convert(entry.value);
          sanitized[entry.key] = entry.value;
        } catch (_) {
          sanitized[entry.key] = entry.value?.toString();
        }
      }
      return const JsonEncoder().convert(sanitized);
    }
  }).toList();
}

// ════════════════════════════════════════════════════════════════════
// GRAPH COMPUTATION ISOLATE
// ════════════════════════════════════════════════════════════════════

/// Compute the shortest relationship path between two persons in a family
/// graph using BFS on a background isolate.
///
/// This is CPU-intensive for large graphs (100+ nodes), so it must
/// run off the main thread to prevent ANR.
///
/// Usage:
/// ```dart
/// final path = await compute(
///   findRelationshipPath,
///   GraphPayload(
///     relationships: relMaps,
///     fromPersonId: personA.id,
///     toPersonId: personB.id,
///   ),
/// );
/// ```
List<String> findRelationshipPath(GraphPayload payload) {
  final rels = payload.relationships;
  final from = payload.fromPersonId;
  final to = payload.toPersonId;

  if (from == to) return [from];

  // Build adjacency list
  final adjacency = <String, List<String>>{};
  for (final rel in rels) {
    final fromId = rel['fromPersonId'] as String? ?? '';
    final toId = rel['toPersonId'] as String? ?? '';
    final isActive = rel['isActive'] as bool? ?? true;
    if (!isActive || fromId.isEmpty || toId.isEmpty) continue;

    adjacency.putIfAbsent(fromId, () => []).add(toId);
    adjacency.putIfAbsent(toId, () => []).add(fromId);
  }

  // BFS
  final queue = <List<String>>[[from]];
  final visited = <String>{from};

  while (queue.isNotEmpty) {
    final path = queue.removeAt(0);
    final current = path.last;

    final neighbors = adjacency[current] ?? [];
    for (final neighbor in neighbors) {
      if (neighbor == to) {
        return [...path, neighbor];
      }
      if (!visited.contains(neighbor)) {
        visited.add(neighbor);
        queue.add([...path, neighbor]);
      }
    }
  }

  return []; // No path found
}

/// Payload for graph path computation isolate.
class GraphPayload {
  final List<Map<String, dynamic>> relationships;
  final String fromPersonId;
  final String toPersonId;

  const GraphPayload({
    required this.relationships,
    required this.fromPersonId,
    required this.toPersonId,
  });
}

// ════════════════════════════════════════════════════════════════════
// BATCH SORT ISOLATE
// ════════════════════════════════════════════════════════════════════

/// Sort a list of maps by a DateTime key on a background isolate.
/// Used for sorting large cached lists before displaying.
///
/// Usage:
/// ```dart
/// final sorted = await compute(
///   sortByDateTimeKey,
///   SortPayload(maps, 'createdAt', descending: true),
/// );
/// ```
List<Map<String, dynamic>> sortByDateTimeKey(SortPayload payload) {
  final sorted = List<Map<String, dynamic>>.from(payload.maps);
  sorted.sort((a, b) {
    final aVal = DateTime.tryParse(a[payload.key]?.toString() ?? '');
    final bVal = DateTime.tryParse(b[payload.key]?.toString() ?? '');
    final aDate = aVal ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = bVal ?? DateTime.fromMillisecondsSinceEpoch(0);
    return payload.descending
        ? bDate.compareTo(aDate)
        : aDate.compareTo(bDate);
  });
  return sorted;
}

/// Payload for sort isolate work.
class SortPayload {
  final List<Map<String, dynamic>> maps;
  final String key;
  final bool descending;

  const SortPayload(this.maps, this.key, {this.descending = false});
}

// ════════════════════════════════════════════════════════════════════
// ISOLATE NAME SERVER FOR SYNC
// ════════════════════════════════════════════════════════════════════

/// A simple named isolate registry for coordinating background work.
/// Ensures that the sync isolate is created only once and can be
/// referenced by name across the app.
///
/// Usage:
/// ```dart
/// final sendPort = await IsolateNameServer.getOrCreate('sync', _syncEntryPoint);
/// IsolateNameServer.send('sync', message);
/// ```
class IsolateNameServer {
  IsolateNameServer._();

  static final Map<String, Isolate> _isolates = {};
  static final Map<String, SendPort> _sendPorts = {};
  static final Map<String, ReceivePort> _receivePorts = {};

  /// Get or create a named isolate. Returns the SendPort for communication.
  static Future<SendPort> getOrCreate(
    String name,
    void Function(SendPort) entryPoint,
  ) async {
    if (_sendPorts.containsKey(name)) {
      return _sendPorts[name]!;
    }

    final receivePort = ReceivePort('${name}_main');
    _receivePorts[name] = receivePort;

    final isolate = await Isolate.spawn(
      entryPoint,
      receivePort.sendPort,
      debugName: name,
    );
    _isolates[name] = isolate;

    // Wait for the isolate to send back its SendPort
    final completer = Completer<SendPort>();
    final subscription = receivePort.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
      }
    });

    final sendPort = await completer.future;
    _sendPorts[name] = sendPort;

    return sendPort;
  }

  /// Send a message to a named isolate.
  static void send(String name, dynamic message) {
    _sendPorts[name]?.send(message);
  }

  /// Get the ReceivePort for a named isolate (for listening to responses).
  static ReceivePort? getReceivePort(String name) => _receivePorts[name];

  /// Dispose a named isolate and clean up resources.
  static void dispose(String name) {
    _isolates[name]?.kill(priority: Isolate.immediate);
    _isolates.remove(name);
    _receivePorts[name]?.close();
    _receivePorts.remove(name);
    _sendPorts.remove(name);
  }

  /// Dispose all named isolates.
  static void disposeAll() {
    for (final name in _isolates.keys.toList()) {
      dispose(name);
    }
  }

  /// Check if a named isolate exists.
  static bool exists(String name) => _isolates.containsKey(name);
}
