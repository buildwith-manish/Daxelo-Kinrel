# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **fix(graph): ALL non-self nodes render grey — directionality bug in relationship key resolution (v65 CRITICAL)**
  - Every non-self node (father, sibling, children, etc.) was rendering with the default grey/slate outline regardless of actual relationship category. Edge line colors also disagreed with node label colors (e.g. label showed blue "Father" but edge line was pink).
  - Root cause: `GraphRelationshipLabels.getRelationshipKey()` and `getRelationLabel()` had their two if-branches SWAPPED. The stored relationship `from: Rajesh, to: anchor, key: 'father'` means "Rajesh IS the father OF the anchor" — from the anchor's perspective, Rajesh IS 'father' (the stored key). But the code was returning the INVERSE ('son') because it applied `getInverseKey()` to the wrong branch. This made every father node pink (child), every child node blue (parent), etc.
  - The same directionality bug existed in `family_graph_engine_view.dart`'s `_relationKeys()` backfill logic — edges pointing TO the anchor were assigned the inverse key instead of the direct key.
  - Fix: swapped both branches in `getRelationshipKey()` and `getRelationLabel()` so that:
    - Edge points TO anchor (`to == anchor`): return stored key DIRECTLY (it IS the anchor's perspective)
    - Edge points FROM anchor (`from == anchor`): return INVERSE key (anchor's perspective is the inverse)
  - Also fixed the backfill in `_relationKeys()` with the same directionality correction, added a BFS source guard (falls back to anchor when viewer is not in graphPersons), and resolved edge LINE colors from the anchor's perspective so they match node colors.
  - This fix is 100% data-driven based on the relationship type — no name/ID/family-specific logic. Works for ANY family structure.
  - Regression test added at `test/graph/widgets/relationship_directionality_test.dart` (18 test cases covering both edge directions × all relationship types + 6 generic multi-family scenarios).

- **fix(graph): node colors not applying when a member is added (BUG-1)**
  - Newly-added members were rendering with the default 'extended' slate-gray fallback color instead of their selected category color (parent=blue, child=pink, etc.) during the ~200–800ms server refetch window after `createRelationship()` succeeded.
  - Root cause: `createRelationship()` calls `ref.invalidate(familyGraphProvider(familyId))` which triggers a fresh Supabase round-trip, but during the refetch window the graph widget rebuilds with the STALE cached `FlatGraphResult` (which has no entry for the new person). The new node then has no `relationshipKey` and falls through to the 'extended' fallback.
  - Fix: added `FamilyGraphNotifier.injectOptimisticEdge()` which appends a synthetic person + relationship entry to the cached `FlatGraphResult` using the EXACT `relationshipKey` the user selected. `add_person_sheet.dart` calls this immediately after `createRelationship()` succeeds, so the very next paint assigns the correct `KinshipEdgeCategory` color. The injected entry is replaced by authoritative server data when the refetch lands.
  - Idempotent (safe to call twice) and no-op when no cache exists.

- **fix(graph): overlapping/duplicate edge lines between the same two nodes (BUG-2)**
  - When a person had multiple relationship rows to another node (e.g. the DB stores both A→B "father" AND B→A "child" inverse rows, or a pair genuinely has parent + spouse relationships), the graph drew two separate edges stacked directly on top of each other.
  - Root cause: the old dedup was first-match-wins — it picked whichever relationship row came first from the DB, which could be the wrong category, and it didn't handle the case of multiple DISTINCT conceptual relationships between the same pair.
  - Fix: added `lib/graph/engine/edge_dedup.dart` with `EdgeDeduplicator.deduplicate()` which:
    1. Groups all edges by sorted node-pair key.
    2. Within each group, picks the STRONGEST category (blood > marriage > extended) — so a "father" edge wins over a "related" fallback row.
    3. Collapses duplicate same-category rows (A→B "father" + B→A "child") into ONE edge.
    4. Keeps DISTINCT categories (e.g. parent + spouse) as separate edges with lateral offsets (±18dp) so both are visible instead of stacked.
  - Both `family_graph.dart` and `family_graph_engine_view.dart` now route edges through `EdgeDeduplicator`. The V2.1 engine painter (`_EngineEdgePainter`) applies the `lateralOffset` to its bezier control points so parallel edges bow in different directions.
  - Regression test added at `test/graph/engine/edge_dedup_test.dart`.

- **fix(graph): node colors wrong for aunt/uncle category string**
  - `KinshipEdgeClassifier.classify()` now recognizes server-computed category strings (snake_case like `"aunt_uncle"`, `"in_law"`, `"grandparent"`, `"indirect"`) at the top of the function. Previously only raw kinship keys (`"father"`, `"uncle"`, `"paternal_uncle"`) were handled, so when `family_graph.dart` stored `PersonData.kinshipCategory` as `GraphPersonData.relationshipKey` and GraphNode passed it through `RelationshipColors.borderColorFor()` → `KinshipEdgeStyleResolver.styleFor()` → `classify()`, the value `"aunt_uncle"` fell through to the `extended` fallback and aunts/uncles rendered with slate gray (#64748B) instead of cyan (#06B6D4). Hyphenated (`"aunt-uncle"`, `"in-law"`) and unseparated (`"auntuncle"`, `"inlaw"`) variants are matched defensively. Regression test added at `test/core/kinship/kinship_edge_classifier_category_test.dart`.

- **fix(graph): multi-hop relatives (grandparent, aunt/uncle, cousin, in-law) fall through to extended fallback (v63)**
  - `family_graph.dart`'s `_buildNodes()` only called `GraphRelationshipLabels.getRelationshipKey()`, which scans for a DIRECT edge from anchor → person. For multi-hop relatives (no direct edge to anchor), this returned null and the node fell through to the 'extended' slate-gray fallback — making every grandparent/aunt/uncle/cousin/in-law look the same color.
  - Fix: added `_resolveMultiHopKey()` which calls `RelationshipEngine.instance.resolveKey()` for any person not reachable via a direct edge. The engine BFS-traverses the graph and composes a kinship key (e.g. "paternal_grandfather", "fathers_elder_brother") which the classifier maps to the correct color category.
  - Same fix applied to `family_graph_engine_view.dart`'s `_relationKeys()` no-viewer fallback path (now uses BFS from the anchor instead of direct-edge-only assignment).
  - Results are cached per (anchorId, personCount, relationshipCount) and the engine cache is invalidated on family/data changes. Regression test added at `test/graph/widgets/multi_hop_node_color_test.dart`.

- **fix(graph): onboarding overlay, single-node render, FAB, kinship edge labels**
  - BUG-1: Onboarding overlay dismissal now persists via `onboardingDismissedProvider`; tapping "Skip" correctly sets `_permanentlyDismissed` and updates the Riverpod state so the overlay never reappears for that family
  - BUG-2: Single-member graph renders the anchor node instead of a blank screen; viewport culling fallback ensures `_visibleNodeIds.isEmpty` falls back to all nodes in `_personMap`
  - BUG-3: FloatingActionButton with `Icons.person_add_alt_1_rounded` is always present on `FamilyGraphScreen`, independent of onboarding state or member count; tapping navigates to `/family/:familyId/add-person`
  - BUG-4: Kinship terms flow into graph edge labels; `KinshipService.getRelationship()` and `getKinshipTerm()` return correct native-language names (e.g. Hindi 'पिता' for 'father') for edge rendering

### Added

- Regression tests for all 4 graph bugs (Agent-08):
  - `test/graph/widgets/onboarding_flow_dismissal_test.dart` — onboarding overlay skip + persistence
  - `test/graph/widgets/single_member_graph_test.dart` — single-node rendering, no blank screen
  - `test/features/family/family_graph_screen_fab_test.dart` — FAB presence and navigation
  - `test/graph/widgets/graph_kinship_edge_label_test.dart` — kinship term lookup and edge label data
