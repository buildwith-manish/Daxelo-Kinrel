// lib/graph/widgets/engine/subtree_mixin.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// Contains the _toggleSubtree method — expand/collapse subtree logic.

part of '../family_graph_engine_view.dart';

/// Mixin containing subtree toggle logic for _FamilyGraphEngineViewState.
extension _SubtreeMethods on _FamilyGraphEngineViewState {
  void _toggleSubtree(String id) {
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat == null) return;

    final all = <String>{
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null) p['id'] as String,
    };
    final Set<String> visible = _expandCollapse.state.visibleNodeIds.isEmpty
        ? Set<String>.of(all)
        : Set<String>.of(_expandCollapse.state.visibleNodeIds);

    final Set<String> descendants = _descendantsOf(id, flat);
    final bool isExpanded = descendants.any(visible.contains);
    if (isExpanded) {
      visible.removeAll(descendants);
    } else {
      visible.addAll(descendants);
    }
    _expandCollapse.updateVisibleNodes(visible);
    _culler.invalidate();
    if (mounted) setState(() {});
  }

  Set<String> _descendantsOf(String root, FlatGraphResult flat) {
    final children = <String, List<String>>{};
    for (final Map<String, dynamic> r in flat.relationships) {
      final s = r['fromPersonId'] as String?;
      final t = r['toPersonId'] as String?;
      if (s == null || t == null) continue;
      children.putIfAbsent(s, () => <String>[]).add(t);
    }
    final out = <String>{};
    final queue = <String>[...?children[root]];
    while (queue.isNotEmpty) {
      final String n = queue.removeLast();
      if (out.add(n)) {
        queue.addAll(children[n] ?? const <String>[]);
      }
    }
    return out;
  }

  /// v2.2: Computes a relation label for every person in the graph from
  /// the VIEWER's perspective using [RelationshipEngine.resolveKey].
  ///
  /// The viewer's own node is omitted (the UI shows "You" for it).
  ///
  /// Falls back to the stored `relationshipKey` only when no viewer is
  /// available (e.g., anonymous mode), preserving legacy behavior.
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

    // v5.86 (CANVAS LABEL FIX): Compute the set of INDIRECT relation
    // node IDs (distance >= 2 from viewer). These nodes should NOT
    // show their viewer-relative label on the canvas — only the badge
    // icon. The actual label (e.g. "Father-in-law") is shown only in
    // the Connection detail sheet when the user taps the node.
    final indirectIds = ref.read(
        indirectRelationIdsProvider(widget.familyId));

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
      // v5.86: Skip label computation for INDIRECT relations.
      // Their label is shown only in the Connection sheet, not on canvas.
      if (indirectIds.contains(p.id)) continue;
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
  Map<String, String> _relationKeys(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final keys = <String, String>{};

    // v63: Build the GraphPerson + GraphRelationship shapes ONCE for both
    // code paths. Previously this was only built inside the viewer != null
    // branch, so the no-viewer path couldn't use the RelationshipEngine
    // for multi-hop BFS resolution. Now both paths share the same data
    // shapes and the engine is used whenever an anchor (or viewer) can be
    // identified.
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

    // v5.7: Pick the BFS source — viewer ONLY. No anchor fallback.
    // If no viewer is resolved, return empty keys (no perspective).
    String? bfsSource = viewerPersonId;

    if (bfsSource == null || graphPersons.isEmpty) {
      // No source — fall back to direct-edge assignment so connected
      // nodes still get a color (better than nothing).
      for (final Map<String, dynamic> r in flat.relationships) {
        final from = r['fromPersonId'] as String?;
        final to = r['toPersonId'] as String?;
        final key = r['relationshipKey'] as String?;
        if (key == null) continue;
        if (to != null && !keys.containsKey(to)) {
          keys[to] = key;
        }
        if (from != null && !keys.containsKey(from)) {
          final inverseKey = _inverseRelationshipKey(key);
          if (inverseKey != null) {
            keys[from] = inverseKey;
          }
        }
      }
      return keys;
    }

    // v63: Use RelationshipEngine for BFS resolution from the chosen
    // source. This handles multi-hop relatives (e.g. paternal_grandfather
    // via father → grandfather) which the direct-edge lookup missed,
    // causing them to fall through to the 'extended' slate gray fallback.
    //
    // v65 GUARD: If bfsSource is not in graphPersons (e.g. the viewer's
    // Person was deleted or is from a different family), the BFS will
    // silently fail for ALL targets, leaving every non-self node grey.
    // Fall back to the anchor in that case.
    final effectiveSource = graphPersons.any((p) => p.id == bfsSource)
        ? bfsSource
        : (graphPersons.any((p) => p.isAnchor)
            ? graphPersons.firstWhere((p) => p.isAnchor).id
            : (graphPersons.isNotEmpty ? graphPersons.first.id : null));

    if (effectiveSource != null) {
      final engine = RelationshipEngine.instance;
      for (final GraphPerson p in graphPersons) {
        if (p.id == effectiveSource) continue;
        // v66: Use resolveClassification — returns the category-correct
        // key even when chain rules fail. This ensures EVERY reachable
        // node gets a color, not just the 2-3 that match the 26-key
        // kinship dataset.
        final classification = engine.resolveClassification(
          viewerPersonId: effectiveSource,
          targetPersonId: p.id,
          persons: graphPersons,
          relationships: graphRels,
        );
        if (classification != null && classification.key.isNotEmpty) {
          keys[p.id] = classification.key;
        }
      }
    }

    // v65 (BUGFIX): Backfill for any person the engine couldn't resolve.
    //
    // CRITICAL DIRECTIONALITY FIX: The stored relationship
    //   from: Rajesh, to: anchor, key: 'father'
    // means "Rajesh IS the father OF the anchor". From the ANCHOR's
    // perspective, Rajesh IS 'father' — the stored key already IS the
    // anchor's perspective on Rajesh. The previous code was assigning
    // the INVERSE ('child') to Rajesh, which is the relationship from
    // RAJESH's perspective, not the anchor's. This caused every node
    // to get the wrong color (e.g. a father node colored pink/child
    // instead of blue/parent).
    //
    // The correct logic:
    //   - Edge points TO anchor (to == source): the stored key IS the
    //     source's perspective on `from`. Assign key DIRECTLY to `from`.
    //   - Edge points FROM anchor (from == source): the stored key IS
    //     the source's perspective on `to`. Assign key DIRECTLY to `to`.
    //   - Edge doesn't involve anchor: assign key to `to` and inverse
    //     to `from` (legacy behavior for non-anchor-centric edges).
    final sourceId = effectiveSource;
    for (final Map<String, dynamic> r in flat.relationships) {
      final from = r['fromPersonId'] as String?;
      final to = r['toPersonId'] as String?;
      final key = r['relationshipKey'] as String?;
      if (key == null || key.isEmpty) continue;
      if (sourceId == null) continue;

      // Case 1: Edge points TO the anchor.
      // Stored key = anchor's perspective on `from` person.
      if (to == sourceId && from != null && !keys.containsKey(from)) {
        keys[from] = key;
        continue;
      }

      // Case 2: Edge points FROM the anchor.
      // v76 FIX: The stored key describes the anchor's relationship TO
      // `to`, NOT the anchor's perspective ON `to`.
      // Example: from: anchor, to: newPerson, key: 'son'
      // → "anchor IS son OF newPerson"
      // → anchor's perspective on newPerson = INVERSE of 'son' = 'parent'
      // Previously this used the raw key 'son', giving the wrong label.
      if (from == sourceId && to != null && !keys.containsKey(to)) {
        final inverseKey = _inverseRelationshipKey(key) ?? key;
        keys[to] = inverseKey;
        continue;
      }

      // Case 3: Edge doesn't involve the anchor (e.g. between two
      // non-anchor nodes).
      //
      // v67 (BUG-18 FIX): Previously this assigned keys to BOTH
      // endpoints from the same edge — but the key only describes one
      // person's relationship to the other, not the anchor's
      // perspective on either. This produced wrong colors for non-
      // anchor-connected nodes.
      //
      // The fix: SKIP non-anchor edges entirely. The BFS above should
      // have already resolved keys for any node reachable from the
      // anchor. If a node is NOT reachable (disconnected subgraph),
      // it's better to leave it with no key (GraphNode falls back to
      // 'extended' grey) than to assign a wrong key from an arbitrary
      // edge. The grey fallback is the spec-correct behavior for
      // genuinely unclassifiable nodes.
      //
      // Exception: if the edge is a spouse edge between two non-anchor
      // nodes and ONE of them already has a BFS-resolved key, we can
      // infer the other is the spouse. But this is rare and the BFS
      // usually handles it. Skip for safety.
      break;
    }

    return keys;
  }

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

      if (category != null) {
        categories[p.id] = category;
      }
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

  /// Returns the inverse relationship key for common kinship terms.
  /// Used by [_relationKeys] when no viewer is available to assign
  /// colors to BOTH endpoints of an edge.
  static String? _inverseRelationshipKey(String key) {
    const inverseMap = <String, String>{
      'father': 'child',
      'mother': 'child',
      'parent': 'child',
      'child': 'parent',
      'son': 'parent',
      'daughter': 'parent',
      'brother': 'sibling',
      'sister': 'sibling',
      'sibling': 'sibling',
      'husband': 'wife',
      'wife': 'husband',
      'spouse': 'spouse',
      'grandfather': 'grandchild',
      'grandmother': 'grandchild',
      'grandson': 'grandparent',
      'granddaughter': 'grandparent',
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'cousin': 'cousin',
    };
    return inverseMap[key];
  }

  /// Resolves a kinship key (e.g. "father", "mothers_brother") to a
  /// human-readable display name using [KinshipService]. Returns the
  /// pretty-printed raw key if no translation is available.
}
