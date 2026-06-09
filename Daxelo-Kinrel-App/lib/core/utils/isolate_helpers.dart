import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../family/family_provider.dart'
    show Family, Person, FamilyRelationship;

// ── Top-Level Isolate Functions ──────────────────────────────────────
// These MUST be top-level functions (not class methods or closures)
// because Flutter's compute() can only invoke top-level or static
// functions in a separate isolate.

/// Parses a list of JSON maps into [Family] objects.
///
/// Used as the isolate entry-point for [IsolateHelpers.parseFamilyList].
/// Runs entirely off the main thread so that parsing large family lists
/// does not cause jank or ANR.
List<Family> _parseFamilyList(List<dynamic> jsonList) {
  return jsonList
      .map((e) => Family.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Parses a list of JSON maps into [Person] objects.
///
/// Used as the isolate entry-point for [IsolateHelpers.parsePersonList].
List<Person> _parsePersonList(List<dynamic> jsonList) {
  return jsonList
      .map((e) => Person.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Parses a list of JSON maps into [FamilyRelationship] objects.
///
/// Used as the isolate entry-point for
/// [IsolateHelpers.parseRelationshipList].
List<FamilyRelationship> _parseRelationshipList(List<dynamic> jsonList) {
  return jsonList
      .map((e) => FamilyRelationship.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Decodes a raw JSON string into its corresponding Dart object
/// (Map or List).
///
/// Used as the isolate entry-point for [IsolateHelpers.parseJson].
dynamic _parseJson(String jsonString) {
  return json.decode(jsonString);
}

/// Batch-parses a list of JSON-encoded strings into [Family] objects.
///
/// Each element in [jsonStrings] is a complete JSON object string that
/// represents a single family.  Decoding + model construction happens
/// inside a single isolate call for maximum efficiency.
List<Family> _batchParseFamilies(List<String> jsonStrings) {
  return jsonStrings
      .map((s) => Family.fromJson(json.decode(s) as Map<String, dynamic>))
      .toList();
}

/// Batch-parses a list of JSON-encoded strings into [Person] objects.
///
/// Same strategy as [_batchParseFamilies] but for [Person] models.
List<Person> _batchParsePersons(List<String> jsonStrings) {
  return jsonStrings
      .map((s) => Person.fromJson(json.decode(s) as Map<String, dynamic>))
      .toList();
}

// ── Helper Class for Path Computation ────────────────────────────────

/// Carries the input for a shortest-path BFS computation across isolate
/// boundaries.
///
/// Must consist only of primitive types and collections of primitives
/// so that it can be sent via [SendPort] when [compute] spawns a new
/// isolate.
class _PathRequest {
  const _PathRequest({
    required this.adjacencyList,
    required this.fromId,
    required this.toId,
  });

  /// Adjacency list representation of the family graph.
  /// Key = person ID, Value = list of directly-connected person IDs.
  final Map<String, List<String>> adjacencyList;

  /// ID of the person to start the search from.
  final String fromId;

  /// ID of the person to search for.
  final String toId;
}

/// Isolate entry-point that delegates to [_bfs] using a [_PathRequest].
List<String>? _computeShortestPath(_PathRequest request) {
  return _bfs(request.adjacencyList, request.fromId, request.toId);
}

/// Iterative BFS (breadth-first search) that finds the shortest path
/// between [from] and [to] in an undirected graph represented by [adj].
///
/// Returns the ordered list of node IDs forming the shortest path, or
/// `null` when no path exists.
///
/// Uses an iterative approach (not recursive) to avoid stack overflow
/// on very large family graphs.
List<String>? _bfs(Map<String, List<String>> adj, String from, String to) {
  if (from == to) return [from];

  final visited = <String>{};
  final queue = <List<String>>[
    [from],
  ];
  visited.add(from);

  while (queue.isNotEmpty) {
    final path = queue.removeAt(0);
    final node = path.last;

    for (final neighbor in adj[node] ?? <String>[]) {
      if (neighbor == to) return [...path, neighbor];
      if (!visited.contains(neighbor)) {
        visited.add(neighbor);
        queue.add([...path, neighbor]);
      }
    }
  }

  return null; // No path found
}

// ── IsolateHelpers ───────────────────────────────────────────────────

/// Centralized isolate helpers for offloading heavy computations off the
/// main thread.
///
/// Uses Flutter's [compute] for one-shot isolate tasks and provides typed
/// helper functions for common heavy operations in the Kinrel app:
///
/// - JSON list parsing for [Family], [Person], [FamilyRelationship]
/// - Raw JSON string decoding
/// - Batch parsing of pre-serialized JSON strings
/// - BFS shortest-path computation in the family graph
///
/// **Threshold**: Lists with fewer than 20 items are parsed on the main
/// thread because the overhead of spawning an isolate outweighs the
/// parsing cost for small datasets.  This matches the existing behaviour
/// in `family_provider.dart`.
///
/// **Usage**:
/// ```dart
/// // Instead of:
/// final families = jsonList.map((e) => Family.fromJson(e)).toList();
///
/// // Use:
/// final families = await IsolateHelpers.parseFamilyList(jsonList);
/// ```
class IsolateHelpers {
  // ── List Parsing ─────────────────────────────────────────────────

  /// Parses a list of JSON maps into [Family] objects.
  ///
  /// Automatically falls back to main-thread parsing for small lists
  /// (< 20 items) where isolate overhead would exceed the parsing cost.
  static Future<List<Family>> parseFamilyList(List<dynamic> jsonList) async {
    if (jsonList.length < 20) {
      return jsonList
          .map((e) => Family.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return compute(_parseFamilyList, jsonList);
  }

  /// Parses a list of JSON maps into [Person] objects.
  ///
  /// Automatically falls back to main-thread parsing for small lists
  /// (< 20 items).
  static Future<List<Person>> parsePersonList(List<dynamic> jsonList) async {
    if (jsonList.length < 20) {
      return jsonList
          .map((e) => Person.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return compute(_parsePersonList, jsonList);
  }

  /// Parses a list of JSON maps into [FamilyRelationship] objects.
  ///
  /// Automatically falls back to main-thread parsing for small lists
  /// (< 20 items).
  static Future<List<FamilyRelationship>> parseRelationshipList(
    List<dynamic> jsonList,
  ) async {
    if (jsonList.length < 20) {
      return jsonList
          .map((e) => FamilyRelationship.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return compute(_parseRelationshipList, jsonList);
  }

  // ── Raw JSON Decoding ────────────────────────────────────────────

  /// Parses a large JSON string in a separate isolate.
  ///
  /// Returns the decoded `Map<String, dynamic>` or `List<dynamic>`.
  /// Use this for large API response payloads that would otherwise block
  /// the main thread during `json.decode`.
  static Future<dynamic> parseJson(String jsonString) async {
    return compute(_parseJson, jsonString);
  }

  // ── Batch Parsing ────────────────────────────────────────────────

  /// Batch-processes a list of JSON strings into [Family] objects.
  ///
  /// Each element of [jsonStrings] must be a valid JSON-encoded string
  /// representing a single family.  All decoding and model construction
  /// happens inside a single isolate call for efficiency.
  static Future<List<Family>> batchParseFamilies(
    List<String> jsonStrings,
  ) async {
    return compute(_batchParseFamilies, jsonStrings);
  }

  /// Batch-processes a list of JSON strings into [Person] objects.
  ///
  /// Same strategy as [batchParseFamilies] but for [Person] models.
  static Future<List<Person>> batchParsePersons(
    List<String> jsonStrings,
  ) async {
    return compute(_batchParsePersons, jsonStrings);
  }

  // ── Graph Computation ────────────────────────────────────────────

  /// Computes the shortest path between two persons in a family graph
  /// using BFS.
  ///
  /// - [adjacencyList]: Map from person ID to list of directly-connected
  ///   person IDs.
  /// - [fromId]: ID of the starting person.
  /// - [toId]: ID of the target person.
  ///
  /// Returns the ordered list of person IDs forming the shortest path,
  /// or `null` if no path exists.
  ///
  /// For graphs with fewer than 50 nodes the computation runs on the
  /// main thread (negligible cost); larger graphs are offloaded to a
  /// separate isolate to avoid jank.
  static Future<List<String>?> computeShortestPath({
    required Map<String, List<String>> adjacencyList,
    required String fromId,
    required String toId,
  }) async {
    if (adjacencyList.length < 50) {
      return _bfs(adjacencyList, fromId, toId);
    }
    return compute(
      _computeShortestPath,
      _PathRequest(
        adjacencyList: adjacencyList,
        fromId: fromId,
        toId: toId,
      ),
    );
  }
}
