// lib/graph/data/graph_data_models.dart
//
// DAXELO KINREL — Graph Data Models (V2.1 Data Layer)
//
// Single home for the graph data-layer model classes that were
// previously co-located in now-deleted legacy files (the repository
// file and the v49 graph canvas widget).
//
// This file is a pure RELOCATION of the model definitions — the class
// APIs are unchanged. It exists so that live code can continue to
// import GraphNodeData, GraphEdgeData, GraphData, BranchData,
// SearchResult, KinshipResult, GraphRealtimeEvent, PersonData,
// RelationshipData and the BranchType enum without depending on the
// dead classes.
//
// See: Feature P0.1 (Delete ~8,500 lines of dead code).

import '../../core/services/graph_layout_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════

/// Branch types that can be expanded in the family graph.
///
/// Each type corresponds to a distinct family branch that can be
/// lazily loaded and independently expanded/collapsed.
enum BranchType {
  /// Maternal ancestors and siblings.
  maternal,

  /// Paternal ancestors and siblings.
  paternal,

  /// Children of aunts/uncles.
  cousins,

  /// Spouse's parents and siblings.
  inLaws,

  /// Children of the selected child.
  grandchildren,

  /// Beyond immediate family — concentric rings.
  extended,
}

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Complete graph data returned by the repository.
///
/// Contains all nodes and edges for a given family graph query,
/// along with metadata about truncation and total counts.
class GraphData {
  /// Creates graph data with the given [nodes], [edges], and metadata.
  const GraphData({
    required this.nodes,
    required this.edges,
    this.isTruncated = false,
    this.totalCount = 0,
  });

  /// Person nodes in the graph.
  final List<GraphNodeData> nodes;

  /// Relationship edges between nodes.
  final List<GraphEdgeData> edges;

  /// Whether the result was truncated due to size limits.
  final bool isTruncated;

  /// Total number of nodes in the full graph (may differ from
  /// [nodes.length] if [isTruncated] is true).
  final int totalCount;

  /// Deserializes from a JSON map.
  factory GraphData.fromJson(Map<String, dynamic> json) {
    return GraphData(
      nodes: (json['nodes'] as List<dynamic>)
          .map((dynamic e) =>
              GraphNodeData.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>)
          .map((dynamic e) =>
              GraphEdgeData.fromJson(e as Map<String, dynamic>))
          .toList(),
      isTruncated: json['is_truncated'] as bool? ?? false,
      totalCount: json['total_count'] as int? ?? 0,
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'nodes': nodes.map((GraphNodeData n) => n.toJson()).toList(),
        'edges': edges.map((GraphEdgeData e) => e.toJson()).toList(),
        'is_truncated': isTruncated,
        'total_count': totalCount,
      };
}

/// A person node in the graph data model.
///
/// Represents a single family member with their core attributes.
/// This is the data-layer representation; the layout-layer uses
/// [GraphPerson] instead.
class GraphNodeData {
  /// Creates a graph node data instance.
  const GraphNodeData({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.isDeceased = false,
    this.visibility,
  });

  /// Unique identifier for this person.
  final String id;

  /// Display name.
  final String name;

  /// URL for the person's avatar image.
  final String? avatarUrl;

  /// Gender string (e.g. "male", "female", "non-binary").
  final String? gender;

  /// Generation index relative to the anchor person.
  /// Anchor = 0, parents = -1, children = 1, etc.
  final int generationIndex;

  /// Whether this person is the anchor (ego) of the current view.
  final bool isAnchor;

  /// Whether this person is deceased.
  final bool isDeceased;

  /// Visibility level (e.g. "public", "family", "private").
  final String? visibility;

  /// Deserializes from a JSON map.
  factory GraphNodeData.fromJson(Map<String, dynamic> json) {
    return GraphNodeData(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      gender: json['gender'] as String?,
      generationIndex: json['generation_index'] as int? ?? 0,
      isAnchor: json['is_anchor'] as bool? ?? false,
      isDeceased: json['is_deceased'] as bool? ?? false,
      visibility: json['visibility'] as String?,
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatar_url': avatarUrl,
        'gender': gender,
        'generation_index': generationIndex,
        'is_anchor': isAnchor,
        'is_deceased': isDeceased,
        'visibility': visibility,
      };

  /// Converts this data model to the layout-layer [GraphPerson].
  GraphPerson toGraphPerson() => GraphPerson(
        id: id,
        name: name,
        gender: gender,
        generationIndex: generationIndex,
        isAnchor: isAnchor,
        photoUrl: avatarUrl,
        isDeceased: isDeceased,
      );
}

/// A relationship edge in the graph data model.
///
/// Connects two [GraphNodeData] instances with a typed relationship.
class GraphEdgeData {
  /// Creates a graph edge data instance.
  const GraphEdgeData({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationshipKey,
    this.isPrivate = false,
  });

  /// Unique identifier for this edge.
  final String id;

  /// Source node ID (the "from" person).
  final String sourceId;

  /// Target node ID (the "to" person).
  final String targetId;

  /// Relationship type key (e.g. "father", "spouse", "child").
  final String relationshipKey;

  /// Whether this relationship is marked private.
  final bool isPrivate;

  /// Deserializes from a JSON map.
  factory GraphEdgeData.fromJson(Map<String, dynamic> json) {
    return GraphEdgeData(
      id: json['id'] as String,
      sourceId: json['source_id'] as String,
      targetId: json['target_id'] as String,
      relationshipKey: json['relationship_key'] as String,
      isPrivate: json['is_private'] as bool? ?? false,
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'source_id': sourceId,
        'target_id': targetId,
        'relationship_key': relationshipKey,
        'is_private': isPrivate,
      };

  /// Converts this data model to the layout-layer [GraphRelationship].
  GraphRelationship toGraphRelationship() => GraphRelationship(
        id: id,
        fromPersonId: sourceId,
        toPersonId: targetId,
        relationshipKey: relationshipKey,
      );
}

/// Data for a specific family branch (maternal, paternal, etc.).
class BranchData {
  /// Creates branch data with the given [nodes] and [edges].
  const BranchData({
    required this.nodes,
    required this.edges,
  });

  /// Person nodes in this branch.
  final List<GraphNodeData> nodes;

  /// Relationship edges within this branch.
  final List<GraphEdgeData> edges;

  /// Deserializes from a JSON map.
  factory BranchData.fromJson(Map<String, dynamic> json) {
    return BranchData(
      nodes: (json['nodes'] as List<dynamic>)
          .map((dynamic e) =>
              GraphNodeData.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>)
          .map((dynamic e) =>
              GraphEdgeData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'nodes': nodes.map((GraphNodeData n) => n.toJson()).toList(),
        'edges': edges.map((GraphEdgeData e) => e.toJson()).toList(),
      };
}

/// Search result containing matching family members.
class SearchResult {
  /// Creates a search result with the given [results] and [total].
  const SearchResult({
    required this.results,
    required this.total,
  });

  /// Matching person nodes.
  final List<GraphNodeData> results;

  /// Total number of matches (may exceed [results.length] if
  /// paginated).
  final int total;

  /// Deserializes from a JSON map.
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      results: (json['results'] as List<dynamic>)
          .map((dynamic e) =>
              GraphNodeData.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'results': results.map((GraphNodeData n) => n.toJson()).toList(),
        'total': total,
      };
}

/// Result of resolving kinship between two family members.
///
/// Contains the computed relationship type, display label, and
/// cultural context.
class KinshipResult {
  /// Creates a kinship result.
  const KinshipResult({
    required this.relationshipType,
    required this.displayLabel,
    required this.degreeOfSeparation,
    this.culturalContext,
    this.isMatrilateral = false,
    this.isPatrilateral = false,
    this.isByMarriage = false,
  });

  /// Machine-readable relationship type key.
  final String relationshipType;

  /// Human-readable display label.
  final String displayLabel;

  /// Number of relationship hops between the two members.
  final int degreeOfSeparation;

  /// Cultural context for the kinship term (e.g. "North Indian",
  /// "South Indian", "Bengali").
  final String? culturalContext;

  /// Whether this is a matrilateral relationship (through mother's side).
  final bool isMatrilateral;

  /// Whether this is a patrilateral relationship (through father's side).
  final bool isPatrilateral;

  /// Whether this relationship is established through marriage.
  final bool isByMarriage;

  /// Deserializes from a JSON map.
  factory KinshipResult.fromJson(Map<String, dynamic> json) {
    return KinshipResult(
      relationshipType: json['relationship_type'] as String,
      displayLabel: json['display_label'] as String,
      degreeOfSeparation: json['degree_of_separation'] as int? ?? 0,
      culturalContext: json['cultural_context'] as String?,
      isMatrilateral: json['is_matrilateral'] as bool? ?? false,
      isPatrilateral: json['is_patrilateral'] as bool? ?? false,
      isByMarriage: json['is_by_marriage'] as bool? ?? false,
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'relationship_type': relationshipType,
        'display_label': displayLabel,
        'degree_of_separation': degreeOfSeparation,
        'cultural_context': culturalContext,
        'is_matrilateral': isMatrilateral,
        'is_patrilateral': isPatrilateral,
        'is_by_marriage': isByMarriage,
      };
}

/// Realtime event from graph subscription.
class GraphRealtimeEvent {
  /// Creates a realtime event.
  const GraphRealtimeEvent({
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  /// Event type (e.g. "relationship_added", "member_updated",
  /// "permission_changed").
  final String type;

  /// Event payload data.
  final Map<String, dynamic> payload;

  /// When the event occurred.
  final DateTime timestamp;

  /// Deserializes from a JSON map.
  factory GraphRealtimeEvent.fromJson(Map<String, dynamic> json) {
    return GraphRealtimeEvent(
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>? ??
          <String, dynamic>{},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════
// API FLAT GRAPH RESPONSE MODELS
// ═══════════════════════════════════════════════════════════════════════
// P0.1/P0.3 fix: These two classes were originally defined in the
// deleted graph_canvas_widget.dart (lines 47-127). Relocated here so
// that family_graph_provider.dart can import them without depending
// on the dead widget file.

/// Person data as received from the API flat graph response.
class PersonData {
  /// Creates a person data instance.
  const PersonData({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
    this.kinshipCategory,
    this.computedKinship,
  });

  /// Unique identifier for this person.
  final String id;

  /// Display name.
  final String name;

  /// Gender string (e.g. "male", "female", "non-binary").
  final String? gender;

  /// Generation index relative to the anchor person.
  final int generationIndex;

  /// Whether this person is the anchor (ego) of the current view.
  final bool isAnchor;

  /// URL for the person's photo/avatar.
  final String? photoUrl;

  /// Whether this person is deceased.
  final bool isDeceased;

  /// Server-computed kinship category (e.g., "parent", "aunt_uncle")
  /// for node coloring.
  final String? kinshipCategory;

  /// Server-computed kinship term (e.g., "Uncle", "Cousin") for node
  /// label.
  final String? computedKinship;

  /// Converts to [GraphPerson] for layout computation.
  GraphPerson toGraphPerson() => GraphPerson(
        id: id,
        name: name,
        gender: gender,
        generationIndex: generationIndex,
        isAnchor: isAnchor,
        photoUrl: photoUrl,
        isDeceased: isDeceased,
      );
}

/// Relationship data as received from the API flat graph response.
class RelationshipData {
  /// Creates a relationship data instance.
  const RelationshipData({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.displayLabel,
  });

  /// Unique identifier for this relationship.
  final String id;

  /// Source person ID (the "from" person).
  final String fromPersonId;

  /// Target person ID (the "to" person).
  final String toPersonId;

  /// Relationship type key (e.g. "father", "spouse", "child").
  final String relationshipKey;

  /// Optional display label from enriched graph API (e.g., "Father",
  /// "Mother's Brother").
  final String? displayLabel;

  /// Converts to [GraphRelationship] for layout computation.
  GraphRelationship toGraphRelationship() => GraphRelationship(
        id: id,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        relationshipKey: relationshipKey,
      );
}
