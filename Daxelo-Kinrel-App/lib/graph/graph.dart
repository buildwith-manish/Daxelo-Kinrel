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
export 'data/family_graph_repository.dart';
export 'data/supabase_data_source.dart';
export 'data/graph_cache.dart';
export 'data/position_memory.dart';
export 'data/offline_manager.dart';
export 'data/realtime_sync.dart';
export 'data/data_validator.dart';

// ── Interaction Layer ─────────────────────────────────────────────────────────
export 'interaction/camera_controller.dart';
export 'interaction/expand_collapse.dart';

// ── Security Layer ────────────────────────────────────────────────────────────
export 'security/permission_validator.dart' hide GraphNodeData, GraphEdgeData, GraphRealtimeEvent;

// ── Analytics Layer ───────────────────────────────────────────────────────────
export 'analytics/analytics_tracker.dart';

// ── Presentation Layer (Widgets) ─────────────────────────────────────────────
export 'widgets/family_graph.dart';
export 'widgets/graph_node.dart';
export 'widgets/relationship_edge.dart' hide GraphEdgeData;
export 'widgets/empty_state.dart';
export 'widgets/onboarding_flow.dart';
export 'widgets/search_bar.dart';
export 'widgets/filter_panel.dart';
export 'widgets/graph_legend.dart';
export 'widgets/control_bar.dart';
