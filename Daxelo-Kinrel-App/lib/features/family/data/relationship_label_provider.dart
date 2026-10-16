// lib/features/family/data/relationship_label_provider.dart
//
// DAXELO KINREL — Relationship-Aware Sender Labels (v140)
//
// Resolves the kinship label between the currently logged-in viewer
// and any other family member — e.g. "Chacha", "Bhaiya", "Nani".
// This is Kinrel's #1 differentiator: every message in the family
// group chat shows the sender's relationship to the viewer, pulled
// from the K-Graph.
//
// How it works (v140 — full Family-Graph integration):
//   1. Find the Person record linked to the current user (linkedUserId
//      == auth.currentUser.id) and the sender's Person record.
//   2. Direct edge lookup (Priority 1 — same as the graph engine's
//      _relationCategories): an edge between the two persons carries
//      the viewer's label for the sender via the CANONICAL convention
//      "from=A, to=B, labelAtoB=X → B is A's X":
//        • edge from=viewer → to=sender : viewer's label = labelAtoB
//        • edge from=sender → to=viewer : viewer's label = labelBtoA
//      (falls back to relationshipKey for legacy rows without labels)
//   3. If no direct edge exists, the Family Graph's RelationshipEngine
//      (BFS path finding via GraphService + KinshipService chain rules
//      + StructuralKinshipClassifier fallback) resolves the key from
//      the SHORTEST PATH between viewer and sender (Priority 2 — the
//      exact engine the family graph screen uses for node labels).
//   4. Format the key into a formal display name using the kinship
//      dataset (KinshipService: englishTerm / displayNames), falling
//      back to a sentence-cased key.
//
// If no relationship can be resolved (sender not linked to a Person,
// no path in the graph), the providers return null and the UI falls
// back to the sender's display name only.
//
// Viewer-specific: the label changes based on who is logged in. If
// user A views a message from user B, they might see "Chacha". If
// user C views the same message, they might see "Bhaiya".
//
// v5.216 (viewer/sender resolution parity with the graph): BOTH the
// viewer's and the sender's Person records are now resolved with the
// SAME chain the family graph uses (viewerPersonIdProvider —
// resolveViewerPersonIdWithCreatorFallback):
//   1. Person.linkedUserId == user → that Person
//   2. anchor Person + anchor.linkedUserId == user → the anchor
//   3. anchor Person + anchor.linkedUserId is null + user is the
//      Family creator → the anchor (v5.177.1 creator fallback)
// Previously the chat ONLY did step 1, so in families where the
// creator's anchor Person had linkedUserId = NULL (the common case
// when the creator already has a Person in another family — the
// creation trigger leaves the anchor unlinked), the graph showed the
// relationship labels correctly while the group chat showed NONE:
// the viewer (creator) resolved to no Person, and messages SENT by
// the unlinked creator resolved to no Person for other viewers.
// Members added via "Find on Kinrel" who accepted their invitation
// ARE linked (fn_accept_graph_invitation sets linkedUserId), so their
// messages showed labels for linked viewers but NOT for the creator
// — exactly the "the graph has the rules but the chat doesn't" bug.
// Reusing the graph's shared pure resolver fixes both directions
// without introducing any chat-specific rules.
//
// Performance: every provider here is a Riverpod `Provider.family`
// keyed by (familyId, senderUserId) — resolved once, cached, and
// rebuilt only when the underlying familyDetailProvider state
// changes. The RelationshipEngine additionally caches BFS paths
// internally per (viewer, target) pair, so multi-hop resolution
// never re-runs on widget rebuilds. [ChatKinshipResolver] memoizes
// the Person→GraphPerson conversion with a single-slot cache so the
// per-sender cost is a map lookup, not a list rebuild. When the
// family's data actually changes (new list identity), the engine's
// classification cache is invalidated so edited/added relationships
// re-resolve instead of serving stale labels.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_service.dart';
import '../../../core/relationship/relationship_engine.dart';
import '../../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../../core/services/supabase_service.dart';
import '../../../core/viewer/viewer_provider.dart'
    show resolveViewerPersonIdWithCreatorFallback, ViewerQueryResult;

// ═══════════════════════════════════════════════════════════════════════
// PURE RESOLVER — no providers, no Supabase, unit-testable in isolation
// (mirrors lib/graph/widgets/graph_relationship_labels.dart's philosophy)
// ═══════════════════════════════════════════════════════════════════════

/// Resolves the viewer's kinship key for a sender from the family's
/// Person + Relationship rows.
///
/// Reuses the SAME engines the Family Graph screen uses:
///   • Priority 1 — direct edge with the canonical label convention
///     (labelAtoB / labelBtoA — the specific label, not the structural
///     relationshipKey), exactly like the graph engine's
///     `_relationCategories` Priority 1.
///   • Priority 2 — `RelationshipEngine` BFS path resolution
///     (GraphService BFS + KinshipService chain rules +
///     StructuralKinshipClassifier fallback) for multi-hop relatives,
///     exactly like the graph engine's Priority 2.
class ChatKinshipResolver {
  ChatKinshipResolver._();

  /// Single-slot conversion cache: (members, relationships) identity →
  /// converted (GraphPerson list, edge tuples). All senders in one
  /// family share the same FamilyDetail lists, so the conversion runs
  /// once per data refresh instead of once per sender.
  static List<Person>? _cachedMembers;
  static List<FamilyRelationship>? _cachedRelationships;
  static List<GraphPerson>? _cachedGraphPersons;
  static List<({String fromId, String toId, String type})>?
      _cachedGraphRels;

  /// Resolves the relationship key describing [senderPerson] from
  /// [viewerPerson]'s perspective, or null when no relationship path
  /// exists between them.
  ///
  /// Example: viewer = child, sender = their maternal grandmother
  /// (no direct edge — connected via the viewer's mother) → the BFS
  /// composes the path and returns "maternal_grandmother".
  static String? resolveKey({
    required Person viewerPerson,
    required Person senderPerson,
    required List<Person> members,
    required List<FamilyRelationship> relationships,
  }) {
    if (viewerPerson.id.isEmpty || senderPerson.id.isEmpty) return null;
    if (viewerPerson.id == senderPerson.id) return null;

    // ── Priority 1: direct edge between viewer and sender ──────────
    // Canonical convention: from=A, to=B, labelAtoB=X → "B is A's X".
    //   • from=viewer, to=sender → sender is viewer's <labelAtoB>
    //   • from=sender, to=viewer → sender is viewer's <labelBtoA>
    for (final r in relationships) {
      if (!r.isActive) continue;
      if (r.fromPersonId == viewerPerson.id &&
          r.toPersonId == senderPerson.id) {
        final key = _firstNonEmpty(r.labelAtoB, r.relationshipKey);
        if (key != null) return key;
      }
      if (r.fromPersonId == senderPerson.id &&
          r.toPersonId == viewerPerson.id) {
        final key = _firstNonEmpty(r.labelBtoA, r.relationshipKey);
        if (key != null) return key;
      }
    }

    // ── Priority 2: Family Graph RelationshipEngine (BFS path) ──────
    // Reuses the exact engine the family graph uses for node labels:
    // GraphService BFS + KinshipService chain rules + structural
    // classifier. Cached internally per (viewer, target) pair.
    try {
      final graphData = _graphDataFor(members, relationships);
      final key = RelationshipEngine.instance.resolveKey(
        viewerPersonId: viewerPerson.id,
        targetPersonId: senderPerson.id,
        persons: graphData.$1,
        relationships: graphData.$2,
      );
      if (key != null && key.isNotEmpty) return key;
    } catch (e) {
      debugPrint('ChatKinshipResolver: BFS resolution failed: $e');
    }

    return null;
  }

  /// Converts the family's Person/Relationship rows into the
  /// GraphPerson + edge-tuple lists the RelationshipEngine consumes,
  /// with a single-slot identity cache (all senders in a family share
  /// the same lists).
  ///
  /// Edge types carry the SPECIFIC label (labelAtoB) when present —
  /// the same input contract the graph engine uses
  /// (subtree_mixin._relationCategories → RelationshipEngine).
  static (List<GraphPerson>,
      List<({String fromId, String toId, String type})>) _graphDataFor(
    List<Person> members,
    List<FamilyRelationship> relationships,
  ) {
    if (identical(_cachedMembers, members) &&
        identical(_cachedRelationships, relationships) &&
        _cachedGraphPersons != null) {
      return (_cachedGraphPersons!, _cachedGraphRels!);
    }

    // v5.216: the family's data changed (new list identity) — any
    // previously composed (viewer → target) classifications may be
    // stale (relationship added/edited between the viewer and an
    // existing sender). Null results are never cached by the engine,
    // so newly-added members always resolve; this invalidation
    // ensures EDITED relationships re-resolve too.
    if (_cachedGraphPersons != null) {
      RelationshipEngine.instance.invalidateCache();
    }

    final graphPersons = <GraphPerson>[
      for (final p in members)
        GraphPerson(
          id: p.id,
          name: p.name,
          gender: p.gender,
          generationIndex: p.generationIndex,
          isAnchor: p.isAnchor,
          photoUrl: p.photoUrl,
          isDeceased: p.isDeceased,
          deletedAt: p.deletedAt,
        ),
    ];
    final graphRels = <({String fromId, String toId, String type})>[
      for (final r in relationships)
        if (r.isActive)
          (
            fromId: r.fromPersonId,
            toId: r.toPersonId,
            type: _firstNonEmpty(r.labelAtoB, r.relationshipKey) ??
                'related',
          ),
    ];

    _cachedMembers = members;
    _cachedRelationships = relationships;
    _cachedGraphPersons = graphPersons;
    _cachedGraphRels = graphRels;
    return (graphPersons, graphRels);
  }

  /// Test hook — clears the single-slot conversion cache and the
  /// RelationshipEngine's internal caches between test cases.
  static void clearCacheForTest() {
    _cachedMembers = null;
    _cachedRelationships = null;
    _cachedGraphPersons = null;
    _cachedGraphRels = null;
    RelationshipEngine.instance.invalidateCache();
  }

  /// v5.216: Resolves the Person node a given user (viewer OR message
  /// sender) occupies in a family — using the EXACT chain the family
  /// graph uses for the viewer (viewerPersonIdProvider →
  /// resolveViewerPersonIdWithCreatorFallback):
  ///   1. Person.linkedUserId == [userId] → that Person
  ///   2. anchor + anchor.linkedUserId == userId → the anchor
  ///   3. anchor + anchor.linkedUserId is null + userId is the family
  ///      creator → the anchor (v5.177.1 creator fallback)
  ///
  /// This is a thin adapter over the graph's shared pure resolver —
  /// no chat-specific mapping rules. It fixes the asymmetry where the
  /// graph showed relationship labels for the family creator (via the
  /// creator fallback) while the group chat showed none because the
  /// creator's anchor Person has linkedUserId = null.
  ///
  /// Returns null when the user has no Person node in this family.
  static Person? personForUser({
    required List<Person> members,
    required String? familyCreatedBy,
    required String? userId,
  }) {
    if (userId == null || userId.isEmpty) return null;

    // Step 1: the user's linked Person in this family.
    for (final p in members) {
      if (p.linkedUserId == userId) return p;
    }

    // Steps 2–3: anchor / creator fallback — the shared graph rules.
    Person? anchor;
    for (final p in members) {
      if (p.isAnchor) {
        anchor = p;
        break;
      }
    }
    if (anchor == null) return null;

    final resolvedId = resolveViewerPersonIdWithCreatorFallback(
      result: ViewerQueryResult(
        linkedPersonId: null, // already checked above
        anchorPersonId: anchor.id,
        anchorLinkedUserId: anchor.linkedUserId,
      ),
      familyCreatedBy: familyCreatedBy,
      currentUserId: userId,
    );
    return resolvedId == anchor.id ? anchor : null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS — thin wrappers around the pure resolver
// ═══════════════════════════════════════════════════════════════════════

/// Resolves the RAW relationshipKey for a given (familyId, senderUserId)
/// pair from the viewer's perspective. Returns null if no relationship
/// is found.
///
/// This is the specific kinship key (e.g. "fathers_younger_brother",
/// "maternal_grandmother") used for kinship category classification
/// via KinshipEdgeStyleResolver.styleFor(). For the display label, use
/// [relationshipLabelProvider] instead.
final relationshipKeyProvider =
    Provider.family<String?, ({String familyId, String senderUserId})>(
  (ref, params) {
    final client = ref.read(supabaseProvider);
    if (client == null) return null;

    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId == null) return null;

    final detailAsync = ref.watch(familyDetailProvider(params.familyId));
    final detail = detailAsync.valueOrNull;
    if (detail == null) return null;

    // v5.216: resolve the viewer's Person with the SAME chain the
    // family graph uses (linked → anchor-is-user → creator fallback).
    // The chat previously only did the linked lookup, so the family
    // creator (whose anchor Person has linkedUserId = null) saw NO
    // relationship labels while the graph showed them correctly.
    final viewerPerson = ChatKinshipResolver.personForUser(
      members: detail.members,
      familyCreatedBy: detail.family.createdBy,
      userId: currentUserId,
    );
    if (viewerPerson == null) return null;

    // v5.216: same shared chain for the sender — messages FROM the
    // unlinked creator anchor now resolve for every linked viewer.
    final senderPerson = ChatKinshipResolver.personForUser(
      members: detail.members,
      familyCreatedBy: detail.family.createdBy,
      userId: params.senderUserId,
    );
    if (senderPerson == null) return null;

    return ChatKinshipResolver.resolveKey(
      viewerPerson: viewerPerson,
      senderPerson: senderPerson,
      members: detail.members,
      relationships: detail.relationships,
    );
  },
);

/// Resolves the FORMAL relationship label for a given
/// (familyId, senderUserId) pair from the viewer's perspective.
/// Returns null if no relationship is found.
///
/// Example: if the sender is the viewer's maternal grandmother, this
/// returns "Maternal grandmother". If the sender is the viewer's
/// father, this returns "Father".
///
/// The label is sentence-cased to match the chat UI reference
/// screenshot ("Papa · Father", "Nani · Maternal grandmother").
///
/// The label is viewer-specific — it depends on who is logged in.
final relationshipLabelProvider =
    Provider.family<String?, ({String familyId, String senderUserId})>(
  (ref, params) {
    final rawKey = ref.watch(relationshipKeyProvider(params));
    if (rawKey == null) return null;
    return formatRelationshipLabel(rawKey);
  },
);

/// Formats a relationship key into the formal display label.
///
/// Resolution chain (all existing data — no new mapping):
///   1. KinshipService english display name (displayNames.english.native,
///      e.g. "Maternal Grandmother") — sentence-cased.
///   2. KinshipService englishTerm (e.g. "Father's Younger Brother") —
///      sentence-cased.
///   3. Sentence-cased key (e.g. "fathers_younger_brother" →
///      "Fathers younger brother").
///
/// Examples:
///   "father"               → "Father"
///   "maternal_grandmother" → "Maternal grandmother"
///   "elder_brother"        → "Elder brother"
String formatRelationshipLabel(String key) {
  final kinship = KinshipService.instance;
  if (kinship.isLoaded) {
    final rel = kinship.getRelationship(key);
    if (rel != null) {
      // displayNames.english.native (core entries): "Maternal Grandmother".
      final englishDisplay = rel.displayNames['english'];
      final native = englishDisplay is Map<String, dynamic>
          ? englishDisplay['native']?.toString()
          : null;
      if (native != null && native.isNotEmpty) {
        return _sentenceCase(native);
      }
      // englishTerm (all 5,396 terms): "Father's Younger Brother".
      if (rel.englishTerm.isNotEmpty) {
        return _sentenceCase(rel.englishTerm);
      }
    }
  }
  return _sentenceCase(key.replaceAll('_', ' '));
}

/// Sentence case: capitalise only the first letter of the entire
/// label, lowercase the rest. Matches the chat UI reference
/// screenshot ("Maternal grandmother", not "Maternal Grandmother").
String _sentenceCase(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
}

String? _firstNonEmpty(String? a, String? b) {
  if (a != null && a.trim().isNotEmpty) return a.trim();
  if (b != null && b.trim().isNotEmpty) return b.trim();
  return null;
}
