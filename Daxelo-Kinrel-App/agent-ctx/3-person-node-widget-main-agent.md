# Task 3 — Person Node Widget (V2.1 K-Graph Blueprint)

## Agent: Main Agent
## Task ID: 3
## Status: ✅ Completed

## Summary
Created `person_node_widget.dart` implementing the complete V2.1 K-Graph Blueprint person node widget, plus three supporting dependency files.

## Files Created

### 1. `lib/features/family/presentation/widgets/person_node_widget.dart`
Main widget file with:

- **`PersonNodeWidget`** — `ConsumerStatefulWidget` with all specified parameters (memberId, name, avatarUrl, gender, relationshipKey, relationLabel, hindiLabel, username, generationIndex, isSelf, isAnchor, isDeceased, position, isSelected, isHovered, isDimmed, onTap, onHover, entryDelay)
- **3 Animation Controllers** (with TickerProviderStateMixin):
  - `_pulseController` — 2500ms repeat reverse (self/selected glow)
  - `_rotationController` — 8000ms repeat (selected dashed ring)
  - `_entryController` — 600ms forward (with stagger delay)
- **7 Widget Layers** (bottom → top):
  1. **Glow** — AnimatedBuilder + RadialGradient (colors.glow → transparent), size: nodeSize + 32
  2. **Rotating Dashed Ring** — AnimatedBuilder + Transform.rotate + DashedCirclePainter, size: nodeSize + 12
  3. **Main Node Circle** — Container with gradient fill, colored border (selected=3px, hovered=2.5px, default=2px), box shadows, ClipOval avatar with errorBuilder fallback
  4. **Self Badge** — Positioned right:0 bottom:0, 20x20 teal gradient circle with ★ icon
  5. **Deceased Indicator** — Positioned left:0 top:0, 14x14 cloud icon
  6. **Labels** — Column with UPPERCASE relationship key (10px bold, ring color, letterSpacing 0.5), name (10px medium, white 60%), Hindi label (9px, white 25%)
  7. **Info Card** — `_MemberInfoCard` private widget with FadeTransition + SlideTransition + ScaleTransition (Curves.elasticOut), 220px width, arrow at top, avatar+name, relationship dot+label, generation row, deceased row, View Profile/Edit action buttons

- **`DashedCirclePainter`** — CustomPainter with color, strokeWidth, dashRatio parameters; calculates dash count from dashRatio and draws arc segments via Path

- **`_MemberInfoCard`** — Private widget with animated entrance (elasticOut), arrow overlay, full content layout
- **`_ActionButton`** — Private text button widget for the info card actions

### 2. `lib/shared/utils/node_colors.dart`
Supporting dependency with:
- `RelationshipType` enum (self, parent, sibling, child, spouse, grandparent, auntUncle, cousin, inLaw, extended)
- `NodeColorSet` class (ring, background, glow colors)
- `getNodeColors(RelationshipType)` function mapping each type to KinrelColors constants
- `relationshipTypeFromKey(String?)` function mapping 30+ relationship keys to RelationshipType

### 3. `lib/core/constants/graph_canvas_config.dart`
Supporting dependency with `GraphCanvasConfig` class constants:
- selfNodeSize=88, defaultNodeSize=76, selectedRingWidth=3, hoveredRingWidth=2.5, defaultRingWidth=2, glowExtent=16, badgeSize=20, badgeBorderWidth=2

### 4. `lib/core/constants/animation_constants.dart`
Supporting dependency with `GraphAnimations` class constants:
- pulseDuration=2500ms, rotationDuration=8000ms, entryDuration=600ms, infoCardDuration=400ms, hoverDuration=150ms, dotPulseDuration=1200ms, popupDuration=200ms
- Corresponding Curves for each animation

## Key Design Decisions
- Uses `withValues(alpha:)` instead of deprecated `withOpacity()`
- Wrapped in `Material(color: Colors.transparent)` to avoid debug underlines
- Added `decoration: TextDecoration.none` to all Text widgets
- No `RepaintBoundary` inside the widget (parent's responsibility)
- All controllers properly disposed
- Stagger entry via `Future.delayed` with entryDelay parameter
- Info card uses separate `_infoCardController` with elasticOut curve for smooth show/hide
- didUpdateWidget handles pulse/rotation state transitions correctly
