# Task 4 — Graph UI Overlay Widgets (V2.1 K-Graph Blueprint)

## Summary
Created 4 Flutter widget files for the family graph screen overlay UI, following the V2.1 K-Graph Blueprint specifications.

## Files Created

### 1. `lib/features/family/presentation/widgets/generation_filter_bar.dart`
- **Class**: `GenerationFilterBar` (StatelessWidget)
- Horizontal scrollable row of generation filter chips at the top of the graph screen
- First chip is always "All" (sets `highlightedGeneration` to null)
- Generation chips dynamically created from `presentGenerations` set
- Toggle behavior: tapping selected chip deselects to "All"
- Styling: darkCard bg, rounded bottom corners (12px), orange selected state (8% bg, orange border), silver default (#2A2A3D border)
- Typography: bodyFont, 12px, w500, `TextDecoration.none`

### 2. `lib/features/family/presentation/widgets/graph_toolbar.dart`
- **Class**: `GraphToolbar` (StatelessWidget)
- Floating bottom-center toolbar with zoom controls
- Contains: zoom_out, zoom % display, zoom_in, divider, center/reset, optional add_member
- Private `_ToolbarIconButton` (StatefulWidget) with hover→orange state
- Styling: darkElevated bg, 12px radius, #2A2A3D border
- Buttons: 40×40 touch target, 20px silver icons, orange splash (10%)
- Wrapped in `Material(transparent)` + `SafeArea`

### 3. `lib/features/family/presentation/widgets/relationship_legend.dart`
- **Class**: `RelationshipLegend` (StatelessWidget)
- Vertical legend panel showing relationship type → color mappings
- Only shows types present in `presentRelationshipKeys`
- Groups: Self, Parent, Spouse, Sibling, Child, Grandparent, Aunt/Uncle, Cousin, In-Law, Extended
- Color mapping uses all `KinrelColors.node*` constants
- `_colorForRelationshipKey()` helper method
- Tap to filter, tap again to deselect
- AnimatedOpacity for non-hovered items (0.4)
- Styling: darkCard bg, 12px radius, shadow, 8px color circle + 4px spacing

### 4. `lib/features/family/presentation/widgets/stats_panel.dart`
- **Class**: `StatsPanel` (StatelessWidget)
- Compact bottom-left stats panel with graph metrics
- Rows: MEMBERS, LINKS, GENS (with optional TRUNCATED warning in amber)
- Labels: monoFont, 9px, w600, textDim, 0.15em letter spacing, uppercase
- Values: displayFont, 14px, w700, textPrimary 90% alpha, tabular figures
- Private `_StatRow` and `_TruncatedWarning` widgets

## Compliance
- ✅ All 4 files use `Material(color: Colors.transparent)` wrapper
- ✅ All Text widgets include `decoration: TextDecoration.none`
- ✅ KinrelTypography font families used (bodyFont, monoFont, displayFont)
- ✅ KinrelColors color constants used throughout
- ✅ Proper dartdoc comments on all public classes and members
- ✅ File header comments present
- ✅ Relative import paths: `../../../../core/constants/`
