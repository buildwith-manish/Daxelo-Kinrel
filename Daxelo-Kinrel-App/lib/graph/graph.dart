/// Kinrel Family Graph V2.1 — Barrel Export
///
/// This barrel file exports all public APIs from the graph architecture
/// as specified in the Family Graph Redesign V2.1 Blueprint.
///
/// Architecture layers:
///   - Engine: Force simulation, layout engines, fallback management
///   - Rendering: RepaintBoundary, path caching, viewport culling
///   - Data: Repository, Supabase data source, caching, position memory
///   - Interaction: Camera controller, expand/collapse
///   - Security: Permission validation
///   - Analytics: Event tracking and performance monitoring
///   - Widgets: FamilyGraph, GraphNode, RelationshipEdge, etc.

// ── Engine Layer ──────────────────────────────────────────────────────────────
export 'engine/force_simulator.dart';
export 'engine/radial_layout.dart';
export 'engine/hierarchical_layout.dart';
export 'engine/fallback_manager.dart';
export 'engine/collision_detector.dart';
export 'engine/edge_router.dart';

// ── Rendering Layer ───────────────────────────────────────────────────────────
export 'rendering/node_render_coordinator.dart';
export 'rendering/edge_path_cache.dart';
export 'rendering/viewport_culler.dart';

// ── Data Layer ────────────────────────────────────────────────────────────────
// P0.1: five legacy data-layer files (repository, supabase source,
// cache, offline manager, realtime sync) were deleted as dead code.
// Their live model classes were relocated to graph_data_models.dart
// (pure relocation, unchanged APIs).
export 'data/graph_data_models.dart';
export 'data/position_memory.dart';
export 'data/data_validator.dart';

// ── Interaction Layer ─────────────────────────────────────────────────────────
export 'interaction/camera_controller.dart';
export 'interaction/expand_collapse.dart';

// ── Security Layer ────────────────────────────────────────────────────────────
export 'security/permission_validator.dart' hide GraphNodeData, GraphEdgeData, GraphRealtimeEvent;

// ── Analytics Layer ───────────────────────────────────────────────────────────
export 'analytics/analytics_tracker.dart';

// ── Presentation Layer (Widgets) ─────────────────────────────────────────────
// v68: family_graph.dart (FamilyGraphWidget v40) removed — dead code.
// relationship_edge.dart removed — only used by the old engine.
export 'widgets/family_graph_engine_view.dart';
export 'widgets/graph_node.dart';
export 'widgets/empty_state.dart';
export 'widgets/search_bar.dart';
// v5.x (dead-code cleanup): filter_panel.dart and control_bar.dart
// exports removed. Both were orphaned — GraphFilterPanel was never
// rendered (its filter button only flipped a state flag without
// showing any UI) and GraphControlBar was never instantiated (its
// unsafe `(cameraController as dynamic).zoomIn()` calls would have
// failed silently if it had been wired up). The files have been
// deleted; the existing graphFocusProvider "Isolate Connections"
// feature already covers the actual filter UX users need.
export 'widgets/graph_legend.dart';
export 'widgets/onboarding_flow.dart';
