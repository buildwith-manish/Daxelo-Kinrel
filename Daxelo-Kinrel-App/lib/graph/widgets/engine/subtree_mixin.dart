// lib/graph/widgets/engine/subtree_mixin.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// Contains relation-label/anchor resolution helpers for the engine view.
//
// v5.132 (System B REMOVAL): _toggleSubtree and _descendantsOf were
// deleted — they fed the legacy ExpandCollapseController state store
// that the real collapse pipeline (branchCollapseProvider /
// proximityGraphProvider) never writes. Branch expand/collapse now
// flows exclusively through _fetchAndExpandBranch in
// branch_affordance.dart.

part of '../family_graph_engine_view.dart';

/// Mixin containing subtree/anchor resolution helpers for
/// _FamilyGraphEngineViewState.
extension _SubtreeMethods on _FamilyGraphEngineViewState {

  /// v2.2: Computes a relation label for every person in the graph from
  /// the VIEWER's perspective using [RelationshipEngine.resolveKey].
  ///
  /// The viewer's own node is omitted (the UI shows "You" for it).
  ///
  /// Falls back to the stored `relationshipKey` only when no viewer is
  /// available (e.g., anonymous mode), preserving legacy behavior.
  ///
  /// v5.x (BUG-3 fix): every node now gets a label (the previous v5.86
  /// skip for indirect relations has been removed). See the inline
  /// comment below for the full context.
  Map<String, String> _relationLabels(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final labels = <String, String>{};

    // v5.7: No viewer → return EMPTY labels (no perspective).
    //
    // PREVIOUS BUG: When viewerPersonId was null, this function fell back
    // to the anchor's perspective (isAnchor == true). This caused labels
    // to always be computed from the family creator's perspective, even
    // when a different user was logged in.
    //
    // Now: no viewer → no labels. The graph shows node names only, with
    // no relationship labels. This is better than showing labels from
    // the WRONG perspective.
    if (viewerPersonId == null) {
      return labels;
    }

    // v5.x (BUG-3 fix — labels for EVERY node): the previous version
    // (v5.86) computed the set of INDIRECT relation node IDs (distance
    // >= 2 from viewer) and SKIPPED label computation for them — those
    // nodes showed no relationship label on the canvas, only a badge
    // icon. The user reported: "Relationship labels are missing for
    // most nodes. Only some nodes show a label describing their
    // relationship to the anchor/main person — for example, Yakshitha
    // correctly shows 'Wife' under her name. But most other nodes on
    // the graph show no relationship label at all."
    //
    // The fix: REMOVE the indirect-relation skip. Every node now gets
    // its computed relationship label (e.g. "Father", "Mother",
    // "Cousin", "Aunt") underneath its name, the same way "Wife"
    // appears under Yakshitha. The label is computed from the actual
    // relationship data via RelationshipEngine.resolveClassification
    // (NOT hardcoded) and updates correctly when the anchor person
    // changes (because the engine recomputes from the viewer's
    // perspective every time).
    //
    // The indirect-relation BADGE (the small icon that opens the
    // Connection detail sheet) is unaffected — it's rendered
    // separately by GraphNode based on `indirectRelationIdsProvider`.
    // The badge still appears for indirect relations; we just no
    // longer suppress the LABEL for them.

    // Build typed inputs for RelationshipEngine.
    final graphPersons = <GraphPerson>[
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null)
          GraphPerson(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? '',
            gender: p['gender'] as String?,
            generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
            isAnchor: (p['isAnchor'] as bool?) ?? false,
            photoUrl: p['photoUrl'] as String?,
            isDeceased: (p['isDeceased'] as bool?) ?? false,
          ),
    ];
    final graphRels = <({String fromId, String toId, String type})>[
      for (final Map<String, dynamic> r in flat.relationships)
        if (r['fromPersonId'] != null &&
            r['toPersonId'] != null &&
            r['relationshipKey'] != null)
          (
            fromId: r['fromPersonId'] as String,
            toId: r['toPersonId'] as String,
            type: (r['labelAtoB'] as String?) ??
                r['relationshipKey'] as String,
          ),
    ];

    final engine = RelationshipEngine.instance;
    for (final GraphPerson p in graphPersons) {
      if (p.id == viewerPersonId) continue; // viewer's own label is "You"
      // v5.x (BUG-3 fix): the v5.86 skip for indirect relations has
      // been REMOVED — every node now gets a label. See the doc block
      // above for the full context.
      final classification = engine.resolveClassification(
        viewerPersonId: viewerPersonId,
        targetPersonId: p.id,
        persons: graphPersons,
        relationships: graphRels,
      );
      if (classification != null) {
        // v66: Use the structural classifier's label directly — it's
        // already human-readable ("Father", "Grandfather", "Cousin", etc.)
        // and matches the category color. This replaces the old
        // _localizeKinshipKey() lookup which failed for multi-hop paths.
        labels[p.id] = classification.label;
      }
    }
    return labels;
  }

  /// Computes the RAW kinship key (e.g., "father", "mothers_brother")
  /// for each person from the viewer's perspective.
  ///
  /// Unlike [_relationLabels] which returns LOCALIZED display names
  /// (e.g., "Father"), this returns the raw key needed for color
  /// resolution via [KinshipEdgeStyleResolver.styleFor].
  ///
  /// Used to pass `relationshipKey` to [GraphNode] so node borders,
  /// tints, and dots use the correct 8-color scheme.


  /// v69: Computes the AUTHORITATIVE [KinshipEdgeCategory] for every
  /// person in the graph from the viewer/anchor's perspective.
  ///
  /// This is the SINGLE source of truth for node AND edge colors. It
  /// eliminates the lossy string round-trip that caused grey nodes:
  /// previously, the render path stored only the kinship key STRING
  /// (via `_relationKeys`), then re-classified it via
  /// `KinshipEdgeClassifier.classify()` — which has gaps (e.g.
  /// 'great_grandfather', 'unknown', compound keys → all fall through
  /// to 'extended' grey).
  ///
  /// This method returns the category DIRECTLY from the structural
  /// classifier, which never has gaps. The caller passes the category
  /// to `GraphNode` and the edge painter, which use
  /// `KinshipEdgeStyleResolver.styleForCategory(category)` — always
  /// correct, never grey for a known relationship.
  ///
  /// PRIORITY (first match wins):
  ///   1. Direct edge from anchor to person → use the STORED key the
  ///      user explicitly selected (honor their choice, don't let BFS
  ///      overwrite it). Classify via the structural classifier.
  ///   2. Multi-hop BFS via RelationshipEngine → use classification.category.
  ///   3. Fallback: null (GraphNode uses 'extended' grey — spec-correct
  ///      for genuinely unclassifiable nodes).
  /// v83: Extracts custom colors from the relationship data.
  ///
  /// Returns a Map<personId, customColors> where customColors is the
  /// JSONB object stored in the Relationship table's customColors column.
  /// Used to override the standard category colors for custom kinships.
  Map<String, Map<String, dynamic>> _extractCustomColors(
    FlatGraphResult flat,
  ) {
    final result = <String, Map<String, dynamic>>{};

    // Find the anchor
    String? anchorId;
    for (final p in flat.persons) {
      if (p['isAnchor'] == true) {
        anchorId = p['id'] as String?;
        break;
      }
    }
    if (anchorId == null) return result;

    for (final r in flat.relationships) {
      final from = r['fromPersonId'] as String?;
      final to = r['toPersonId'] as String?;
      final customColors = r['customColors'];
      if (customColors == null || customColors is! Map) continue;

      // Assign custom colors to the non-anchor person
      final customMap = Map<String, dynamic>.from(customColors);
      if (to == anchorId && from != null) {
        result[from] = customMap;
      } else if (from == anchorId && to != null) {
        result[to] = customMap;
      }
    }

    return result;
  }

  Map<String, KinshipEdgeCategory> _relationCategories(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final categories = <String, KinshipEdgeCategory>{};

    // Build GraphPerson list for the structural classifier.
    final graphPersons = <GraphPerson>[
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null)
          GraphPerson(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? '',
            gender: p['gender'] as String?,
            generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
            isAnchor: (p['isAnchor'] as bool?) ?? false,
            photoUrl: p['photoUrl'] as String?,
            isDeceased: (p['isDeceased'] as bool?) ?? false,
          ),
    ];
    final graphRels = <({String fromId, String toId, String type})>[
      for (final Map<String, dynamic> r in flat.relationships)
        if (r['fromPersonId'] != null &&
            r['toPersonId'] != null &&
            r['relationshipKey'] != null)
          (
            fromId: r['fromPersonId'] as String,
            toId: r['toPersonId'] as String,
            type: (r['labelAtoB'] as String?) ??
                r['relationshipKey'] as String,
          ),
    ];

    // Find the BFS source (viewer or anchor).
    // v5.7: Viewer ONLY. No anchor fallback.
    String? bfsSource = viewerPersonId;
    // Guard: if source is not in graphPersons, return empty (no perspective).
    final effectiveSource = graphPersons.any((p) => p.id == bfsSource)
        ? bfsSource
        : null;

    if (effectiveSource == null || graphPersons.isEmpty) return categories;

    // Build a set of direct-edge person IDs for fast lookup.
    // A "direct edge" is any edge where one endpoint is the source.
    final directEdgePersons = <String>{};
    for (final r in flat.relationships) {
      final from = r['fromPersonId'] as String?;
      final to = r['toPersonId'] as String?;
      final key = r['relationshipKey'] as String?;
      if (key == null || key.isEmpty) continue;
      if (to == effectiveSource && from != null) {
        directEdgePersons.add(from);
      }
      if (from == effectiveSource && to != null) {
        directEdgePersons.add(to);
      }
    }

    final engine = RelationshipEngine.instance;
    for (final GraphPerson p in graphPersons) {
      if (p.id == effectiveSource) continue; // source is "self"

      KinshipEdgeCategory? category;

      // Priority 1: Direct edge from anchor → use the STORED label.
      // Honor the user's explicit selection — don't let BFS overwrite.
      //
      // v5.101 BUG FIX: Use labelAtoB (specific label like 'father')
      // instead of relationshipKey (fundamental type like 'parent').
      // The labelAtoB convention is: "toPerson is fromPerson's <label>"
      // So if from=Manish, to=Jdhfhd, labelAtoB='father' → Jdhfhd IS
      // Manish's father → Jdhfhd's category = parent (blue).
      //
      // Previously used relationshipKey ('parent') which was then
      // inverted to 'child' → child category (pink) for BOTH father
      // and mother nodes, causing inconsistent ring colors.
      //
      // With labelAtoB, NO inversion is needed — the label already
      // describes the target's relationship to the source.
      if (directEdgePersons.contains(p.id)) {
        // Find the stored label for this direct edge.
        String? storedLabel;
        for (final r in flat.relationships) {
          final from = r['fromPersonId'] as String?;
          final to = r['toPersonId'] as String?;
          if (from == null || to == null) continue;
          // Check if this edge connects source and target
          if (!((from == effectiveSource && to == p.id) ||
                (to == effectiveSource && from == p.id))) continue;

          // v5.101: Use labelAtoB (specific label) — it describes
          // "toPerson is fromPerson's <label>" regardless of direction.
          // If the edge is from=source, to=target → label is correct as-is
          // If the edge is from=target, to=source → we need the INVERSE
          //   (because labelAtoB describes source from target's perspective)
          final label = (r['labelAtoB'] as String?) ??
              (r['relationshipKey'] as String?);
          if (label == null || label.isEmpty) continue;

          if (from == effectiveSource && to == p.id) {
            // Edge: source → target, labelAtoB describes target
            // from source's perspective. Use directly.
            storedLabel = label;
          } else {
            // Edge: target → source, labelAtoB describes source
            // from target's perspective. Need inverse.
            storedLabel = _inverseKeyForCategory(label);
          }
          break;
        }
        if (storedLabel != null) {
          // v71: Use the 5,363-entry lookup map as the PRIMARY resolver
          final effectiveKey = storedLabel;
          if (KinshipCategoryMap.isKnown(effectiveKey)) {
            category = KinshipCategoryMap.categoryFor(effectiveKey);
          } else {
            final classification = StructuralKinshipClassifier.classify(
              path: [effectiveKey],
              targetGender: p.gender,
            );
            category = classification.category;
          }
        }
      }

      // Priority 2: Multi-hop BFS via RelationshipEngine.
      category ??= engine.resolveClassification(
        viewerPersonId: effectiveSource,
        targetPersonId: p.id,
        persons: graphPersons,
        relationships: graphRels,
      )?.category;

      // v5.110: Priority 3 — Generation-based fallback.
      // If BFS failed to resolve a category (common for distant nodes
      // in large trees where the BFS is too expensive or the path is
      // too long), assign a category based on the node's generation
      // index relative to the viewer. This ensures EVERY node gets
      // a non-gray color — no node should ever fall through to the
      // default gray/extended just because the kinship BFS couldn't
      // reach it.
      if (category == null) {
        final genDelta = p.generationIndex;
        if (genDelta <= -2) {
          category = KinshipEdgeCategory.grandparent;
        } else if (genDelta == -1) {
          category = KinshipEdgeCategory.parent;
        } else if (genDelta >= 2) {
          category = KinshipEdgeCategory.grandparent; // grandchild uses same color
        } else if (genDelta == 1) {
          category = KinshipEdgeCategory.child;
        } else {
          // gen 0 — same generation as viewer. Could be sibling,
          // spouse, or cousin. Default to sibling (most common).
          category = KinshipEdgeCategory.sibling;
        }
      }

      categories[p.id] = category;
    }

    return categories;
  }

  /// v76: Returns the inverse relationship key for common kinship terms.
  ///
  /// Used by `_relationCategories()` when the stored edge points FROM
  /// the anchor (e.g. `from: anchor, to: newPerson, key: 'son'`).
  /// In this case, 'son' means "anchor IS son OF newPerson", so
  /// newPerson's category is the INVERSE of 'son' = 'parent'.
  ///
  /// For keys not in this map, returns the key unchanged (the
  /// structural classifier will handle it via path analysis).
  static String _inverseKeyForCategory(String key) {
    const inverseMap = <String, String>{
      // Parent ↔ Child
      'father': 'child',
      'mother': 'child',
      'parent': 'child',
      'child': 'parent',
      'son': 'parent',
      'daughter': 'parent',
      // Sibling (symmetric)
      'brother': 'sibling',
      'sister': 'sibling',
      'sibling': 'sibling',
      'elder_brother': 'sibling',
      'younger_brother': 'sibling',
      'elder_sister': 'sibling',
      'younger_sister': 'sibling',
      // Spouse (symmetric)
      'husband': 'spouse',
      'wife': 'spouse',
      'spouse': 'spouse',
      'partner': 'spouse',
      // Grandparent ↔ Grandchild
      'grandfather': 'grandchild',
      'grandmother': 'grandchild',
      'grandparent': 'grandchild',
      'grandchild': 'grandparent',
      'grandson': 'grandparent',
      'granddaughter': 'grandparent',
      // Aunt/Uncle ↔ Nephew/Niece
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      // Cousin (symmetric)
      'cousin': 'cousin',
      // In-law
      'father_in_law': 'child_in_law',
      'mother_in_law': 'child_in_law',
      'son_in_law': 'parent_in_law',
      'daughter_in_law': 'parent_in_law',
      'brother_in_law': 'sibling_in_law',
      'sister_in_law': 'sibling_in_law',
      // Step
      'step_father': 'step_child',
      'step_mother': 'step_child',
      'step_son': 'step_parent',
      'step_daughter': 'step_parent',
      'step_brother': 'step_sibling',
      'step_sister': 'step_sibling',
      // Compound Indian kinship (common ones)
      'fathers_brother': 'nephew',
      'fathers_sister': 'niece',
      'mothers_brother': 'nephew',
      'mothers_sister': 'niece',
      'brothers_son': 'uncle',
      'brothers_daughter': 'uncle',
      'sisters_son': 'uncle',
      'sisters_daughter': 'uncle',
    };
    return inverseMap[key] ?? key;
  }

  /// v65: Finds the anchor person ID from the flat graph data.
  ///
  /// Used to identify which node is the graph's center so that edge
  /// colors can be resolved from the anchor's perspective (matching
  /// the node colors).
  ///
  /// v5.4: Resolution order is now VIEWER-FIRST:
  ///   1. [viewerPersonId] — the currently logged-in user's Person ID.
  ///      This ensures the graph is rendered from the VIEWER's perspective,
  ///      not the family creator's perspective.
  ///   2. The person with `isAnchor == true` in [flat.persons] — legacy
  ///      fallback (family creator).
  ///   3. null if neither exists.
  ///
  /// PREVIOUS BUG: _findAnchorId preferred `isAnchor` (family creator)
  /// over `viewerPersonId` (current user). This caused the graph to
  /// always render from the creator's perspective, even when a different
  /// user was logged in. Edge colors and relationship labels were
  /// computed from the creator's perspective instead of the viewer's.
  static String? _findAnchorId(FlatGraphResult flat, String? viewerPersonId) {
    // v5.7: Viewer-FIRST and ONLY. If viewerPersonId is set and exists in
    // the graph, use it. If viewerPersonId is null (user not linked to a
    // Person node), return null — do NOT fall back to isAnchor.
    //
    // PREVIOUS BUG: When viewerPersonId was null, this function fell back
    // to the isAnchor-flagged person (family creator). This caused the
    // graph to ALWAYS show the family creator as "You", even when a
    // different user was logged in. The anchor fallback was a legacy
    // pattern from before viewer-perspective was implemented.
    //
    // Now: no viewer → no "You" node. This is better than showing the
    // WRONG person as "You". The user will be prompted to claim their
    // profile via the ClaimProfileBanner (or they can manually link).
    if (viewerPersonId != null && viewerPersonId.isNotEmpty) {
      // Verify the viewerPersonId exists in the flat.persons list
      for (final Map<String, dynamic> p in flat.persons) {
        if (p['id'] == viewerPersonId) {
          return viewerPersonId;
        }
      }
    }
    // v5.7: NO anchor fallback. Return null when no viewer is resolved.
    return null;
  }



  /// Resolves a kinship key (e.g. "father", "mothers_brother") to a
  /// human-readable display name using [KinshipService]. Returns the
  /// pretty-printed raw key if no translation is available.
}
