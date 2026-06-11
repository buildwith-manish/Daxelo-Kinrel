# Task: Create 4 Flutter Files for Daxelo-Kinrel Family Graph UI

## Task ID: graph-ui-widgets-phase

## Summary

Created 4 complete Flutter widget/painter files for the Daxelo-Kinrel family graph visualization UI:

### Files Created

1. **`lib/shared/painters/family_tree_painter.dart`** (13.9 KB)
   - `FamilyTreePainter` CustomPainter for drawing graph edges
   - `EdgeData` model class for lightweight edge descriptors
   - Cubic Bezier curves for parent-child connections (smooth S-curves)
   - Dashed lines for spouse connections
   - Level-of-Detail (LOD) rendering: minimal (< 0.3), simplified (0.3-0.8), full (> 0.8)
   - Relationship key labels in full LOD mode with background rects
   - Edge colors: default rgba(255,255,255,0.12), selected orange, spouse gold@40%

2. **`lib/features/family/presentation/widgets/edge_dot_widget.dart`** (5.4 KB)
   - `EdgeDotWidget` animated dot at edge midpoints
   - Three states: default (10px, textDim), selected (14px, orange with glow + pulse), hover (12px, amber)
   - Pulse animation: scale 1.0 → 1.3 → 1.0 over 600ms using SingleTickerProviderStateMixin
   - 32x32px transparent tap area centered on dot
   - MouseRegion for hover detection on desktop

3. **`lib/features/family/presentation/widgets/relationship_popup_widget.dart`** (15.4 KB)
   - `RelationshipPopupWidget` popup showing bidirectional relationships
   - Forward direction with orange arrow, inverse with gold arrow
   - Hindi kinship terms from static lookup map
   - Entrance animation: scale 0.8 → 1.0 + fade in over 200ms
   - Auto-positioning above/below dot based on canvas space
   - Close button, background label chips, proper typography

4. **`lib/features/family/presentation/widgets/graph_canvas_widget.dart`** (22.1 KB)
   - `GraphCanvasWidget` main canvas combining all layers
   - InteractiveViewer with TransformationController (min 0.1, max 4.0)
   - 4-layer Stack: edges → edge dots → person nodes → popup
   - `PersonData` and `RelationshipData` models for API integration
   - Person node cards: avatar with gender border, name, generation badge, "You" badge
   - Deceased persons rendered at 0.4 opacity
   - Inverse key lookup map for popup

### Dependencies Referenced
- `KinrelColors` from `lib/core/constants/brand_colors.dart`
- `KinrelTypography` from `lib/core/constants/brand_typography.dart`
- `GraphLayoutService`, `GraphPerson`, `GraphRelationship`, `GraphLayoutResult` from `lib/core/services/graph_layout_service.dart`

### Design Decisions
- Used Flutter's built-in `AnimatedBuilder` for pulse and entrance animations
- Edge endpoints computed from node centers (accounting for node width/height)
- Bezier control points placed at vertical midpoint for smooth S-curves
- Popup boundary checking clamps position within canvas bounds
- Hindi font uses 'NotoSansDevanagari' (available in assets/fonts/)
