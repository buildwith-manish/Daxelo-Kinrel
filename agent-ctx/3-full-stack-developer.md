# Task 3 — Create Advanced Family Relationship Graph Screen

## Agent: full-stack-developer

## Status: ✅ COMPLETED

## Files Created

1. **`Daxelo-Kinrel-App/lib/features/family/presentation/relationship_graph_screen.dart`** (~700 lines)
   - `RelationshipGraphScreen` — Full-screen graph screen with AppBar, InteractiveViewer, bottom controls, generation legend
   - `_GenColors` — Generation color system matching Figma reference (lavender → purple → blue → teal → pink)
   - `_GraphNode`, `_GraphEdge`, `_EdgeType` — Layout data models
   - `_LayoutResult`, `_computeLayout()` — Hierarchical layout algorithm using BFS from anchor person
   - `_RelationshipGraphPainter` — CustomPainter with:
     - Generation label pills on left side
     - Dashed parent-child step-down lines with arrow dots
     - Dashed spouse lines with heart at midpoint
     - Circular nodes with initials, name, relationship label
     - Pulsing glow ring on anchor "You" node
     - Generation-by-generation entry animation (fade + scale)
   - `_ControlPill`, `_PillButton` — Bottom floating control bar (zoom in/out, center you, fit all)
   - `_GenerationLegend` — Bottom legend showing generation colors

## Files Modified

2. **`Daxelo-Kinrel-App/lib/features/family/presentation/family_detail_screen.dart`**
   - Changed `_GraphTab` from `ConsumerWidget` to `ConsumerStatefulWidget`
   - Added `_showHierarchy` toggle (defaults to new hierarchy view)
   - Added `_HierarchyGraphView` — Embedded graph widget for in-tab use
   - Added `_ViewTogglePill` — Tree/Constellation toggle pill at top-left
   - Added `_ToggleOption` — Toggle button component
   - Added fullscreen button at top-right navigating to `/family/:id/graph`
   - Added import for `relationship_graph_screen.dart`

3. **`Daxelo-Kinrel-App/lib/core/routing/app_router.dart`**
   - Added import for `RelationshipGraphScreen`
   - Added `GoRoute` for `/family/:id/graph` with fast fade transition

## Key Design Decisions

- **Layout Algorithm**: BFS from anchor person (isAnchor=true), assigning generation levels relative to anchor (anchor=3, parents=2, grandparents=1, children=4). Spouses placed at same generation.
- **Color System**: Generation-based as per Figma reference — great-grandparents=lavender, grandparents=light purple, parents=blue, self=teal with glow, children=pink
- **Entry Animation**: Nodes fade in generation-by-generation with easeOutBack scale effect
- **Anchor Glow**: Radial gradient glow + pulsing stroke ring on "You" node
- **Edge Rendering**: Manual dashed path drawing using PathMetrics; step-down pattern for parent-child, horizontal with heart for spouse
- **Relationship Label Inference**: Uses generation difference + gender to infer labels (Father/Mother, Son/Daughter, etc.) when explicit labels unavailable

## Dependencies
- Uses existing `familyDetailProvider`, `kinshipServiceProvider`
- Uses `PersonDetailSheet` for tap interactions
- Uses `DKColors`, `KinrelColors`, `KinrelTypography`, `DKEmptyState`, `DKErrorState`
- Uses `flutter_animate` for UI animations
- Uses `go_router` for navigation
