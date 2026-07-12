// lib/graph/widgets/graph_node.dart
//
// DAXELO KINREL — Graph Node Widget
//
// A circular avatar node widget supporting 7 visual states and
// 10 relationship color categories with full animation support.
//
// Node States:
//   Normal: Standard appearance per relationship color
//   Hover: Scale up 7%, elevated shadow, tooltip preview
//   Selected: Accent border glow, background tint, info sheet appears
//   Focused: Pulsing glow animation, camera centers on node
//   Expanded: Expand indicator rotates, new nodes animate in
//   Loading: Shimmer animation, spinner on expand indicator
//   Error: Red border pulse, error icon overlay, tap to retry
//
// Relationship Color System:
//   Self: Teal #0D9488
//   Parent: Blue #3B82F6
//   Sibling: Purple #8B5CF6
//   Child: Pink #EC4899
//   Spouse: Orange #F97316
//   Grandparent: Indigo #6366F1
//   Aunt/Uncle: Cyan #06B6D4
//   Cousin: Emerald #10B981
//   In-Law: Amber #F59E0B
//   Extended: Slate #64748B

import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/constants/feature_flags.dart';
import '../../core/kinship/kinship_edge_style.dart';
import '../../core/widgets/cached_avatar.dart';
import '../../features/kinrel_intelligence/providers/kinrel_provider.dart';
import '../../features/kinrel_intelligence/widgets/role_glyph_badge.dart' show RoleGlyphBadge;

// ═══════════════════════════════════════════════════════════════════════
// NODE STATE ENUM
// ═══════════════════════════════════════════════════════════════════════

/// All possible visual states for a graph node.
enum NodeState {
  /// Standard appearance with relationship-colored border ring.
  normal,

  /// Scale up 7%, elevated shadow, tooltip preview.
  /// Desktop: cursor enter; Mobile: long-press proximity.
  hover,

  /// Accent border glow, background tint, info sheet appears.
  selected,

  /// Pulsing glow animation, camera centers on node.
  focused,

  /// Expand indicator rotates, new nodes animate in.
  expanded,

  /// Shimmer animation, spinner on expand indicator.
  loading,

  /// Red border pulse, error icon overlay, tap to retry.
  error,
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP COLOR SYSTEM
// ═══════════════════════════════════════════════════════════════════════

// ── Relationship Color System ──────────────────────────────────────
//
// P0.2: The duplicate node color system was REMOVED. Node ring
// colors now resolve through the SAME canonical system as edge colors:
//
//   Static category color → KinshipEdgeColors.<category>
//   Key-based resolution  → KinshipEdgeStyleResolver.styleFor(key).color
//   Tint (4% alpha)       → <color>.withValues(alpha: 0.04)
//
// This ensures node rings and edge lines ALWAYS use the same palette.
// See: lib/core/kinship/kinship_edge_style.dart (Feature P0.2).

// ═══════════════════════════════════════════════════════════════════════
// EXPAND INDICATOR CATEGORIES
// ═══════════════════════════════════════════════════════════════════════

/// Defines what branch type each relationship can expand into.
class ExpandIndicators {
  ExpandIndicators._();

  /// Returns the expand label for a given relationship key.
  static String? expandLabelFor(String? relationshipKey) {
    if (relationshipKey == null) return null;
    return _expandMap[relationshipKey];
  }

  static const Map<String, String> _expandMap = {
    'parent': 'Grandparents / Aunts / Uncles',
    'father': 'Grandparents / Aunts / Uncles',
    'mother': 'Grandparents / Aunts / Uncles',
    'sibling': 'Sibling spouses / children',
    'brother': 'Sibling spouses / children',
    'sister': 'Sibling spouses / children',
    'child': 'Grandchildren',
    'son': 'Grandchildren',
    'daughter': 'Grandchildren',
    'spouse': 'In-laws',
    'husband': 'In-laws',
    'wife': 'In-laws',
    'partner': 'In-laws',
    'grandparent': 'Great-grandparents',
    'grandfather': 'Great-grandparents',
    'grandmother': 'Great-grandparents',
    'aunt': 'Cousins',
    'uncle': 'Cousins',
    'paternal_uncle': 'Cousins',
    'paternal_aunt': 'Cousins',
    'maternal_uncle': 'Cousins',
    'maternal_aunt': 'Cousins',
    'cousin': 'Cousin spouses / children',
    'cousin_brother': 'Cousin spouses / children',
    'cousin_sister': 'Cousin spouses / children',
    'father_in_law': 'In-law siblings',
    'mother_in_law': 'In-law siblings',
    'brother_in_law': 'In-law siblings',
    'sister_in_law': 'In-law siblings',
    'stepfather': 'Deeper connections',
    'stepmother': 'Deeper connections',
  };
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH NODE WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A circular avatar node widget with 7 visual states and 10 relationship
/// color categories.
///
/// Features:
///   - 72dp circular avatar with colored border ring per relationship type
///   - 2-letter initials inside circle, photo support
///   - Name + relation label BELOW circle
///   - Tap → person detail, Long-press → quick actions bottom sheet
///   - 30+ entry inverse key map with gender-aware resolution
///   - highlightedGeneration dimming support
///
/// Anchor node: double-ring (outer teal 88dp glow, inner 72dp solid)
/// Deceased: opacity 0.4
/// Private relationship: lock icon on node
/// Hidden member: gray, no avatar, no name (anonymous node)
///
/// Accessibility: Semantics label "[Name], [Relationship], [Generation]. [Expand status]."
/// Responsive node sizes: compact 48dp, standard 56dp, expanded 60dp, large 64dp
class GraphNode extends ConsumerStatefulWidget {
  const GraphNode({
    super.key,
    required this.personId,
    required this.name,
    this.gender,
    required this.generationIndex,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
    this.isAnonymous = false,
    this.relationshipKey,
    this.category,
    required this.relationLabel,
    this.nodeState = NodeState.normal,
    this.opacity = 1.0,
    this.nodeSize = 72.0,
    this.isPrivate = false,
    this.isUnclaimed = false,
    this.familyId,
    this.showRelationLabel = true,
    required this.onTap,
    required this.onLongPress,
    this.onDoubleTap,
  });

  /// Unique person identifier.
  final String personId;

  /// Display name (empty for anonymous nodes).
  final String name;

  /// Optional gender string ('male', 'female', etc.).
  final String? gender;

  /// Generation index for ring placement.
  final int generationIndex;

  /// Whether this is the anchor (center) person.
  final bool isAnchor;

  /// Optional photo/avatar URL.
  final String? photoUrl;

  /// Whether this person is deceased.
  final bool isDeceased;

  /// Whether this node should display as anonymous (hidden member).
  final bool isAnonymous;

  /// The relationship type key from the anchor to this person.
  final String? relationshipKey;

  /// v69: The AUTHORITATIVE kinship category — the single source of
  /// truth for node/edge color. When present, used directly via
  /// styleForCategory(category). When null, falls back to
  /// borderColorFor(relationshipKey) (lossy string round-trip).
  final KinshipEdgeCategory? category;

  /// Display label for the relationship (e.g., "Father").
  final String relationLabel;

  /// Current visual state of the node.
  final NodeState nodeState;

  /// Opacity for generation dimming.
  final double opacity;

  /// Diameter of the node circle (responsive).
  final double nodeSize;

  /// Whether this relationship is private.
  final bool isPrivate;

  /// Whether this Person node has NOT been claimed by a linked Kinrel user
  /// (linkedUserId is null). Shows a small "Pending" badge on the node.
  final bool isUnclaimed;

  /// Optional family ID — when provided AND kEnableKinrel is true, the
  /// node shows an Kinrel role glyph badge (root/anchor/bridge/weaver/leaf/
  /// twin_node) on the bottom-right of the avatar. Pass null to skip
  /// the badge (e.g. on preview nodes outside a family context).
  final String? familyId;

  /// v93 (ZOOM FIX): When false, the secondary relationship label
  /// (e.g. "Husband", "You") is hidden to reduce clutter at lower
  /// zoom. The primary member name is ALWAYS visible regardless of
  /// this flag.
  final bool showRelationLabel;

  /// Callback when the node is tapped.
  final VoidCallback onTap;

  /// Callback when the node is long-pressed.
  final VoidCallback onLongPress;

  /// Callback when the node is double-tapped.
  final VoidCallback? onDoubleTap;

  @override
  ConsumerState<GraphNode> createState() => _GraphNodeState();
}

class _GraphNodeState extends ConsumerState<GraphNode>
    with TickerProviderStateMixin {
  // ── Animation Controllers ───────────────────────────────────────────

  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;
  late final AnimationController _errorPulseController;
  late final AnimationController _expandRotateController;

  late final Animation<double> _pulseAnimation;
  late final Animation<double> _shimmerAnimation;
  late final Animation<double> _errorPulseAnimation;

  /// Whether high contrast mode is active (updated on build).
  // v60: _highContrast is set in build() from MediaQuery. Using a local
  // in build would require passing it to every helper, so we keep the
  // field but set it at the START of build (not mid-build).
  bool _highContrast = false;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Pulse animation for focused state (1.5s repeat, scale 1.0↔1.15)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Shimmer animation for loading state (1.5s repeat)
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    // Error pulse animation for error state (800ms repeat)
    _errorPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _errorPulseAnimation = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _errorPulseController, curve: Curves.easeInOut),
    );

    // Expand rotate animation for expanded state
    _expandRotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _updateAnimations();
  }

  @override
  void didUpdateWidget(covariant GraphNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeState != widget.nodeState) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    // Stop all animations first
    _pulseController.stop();
    _shimmerController.stop();
    _errorPulseController.stop();
    _expandRotateController.stop();

    switch (widget.nodeState) {
      case NodeState.focused:
        _pulseController.repeat(reverse: true);
      case NodeState.loading:
        _shimmerController.repeat();
      case NodeState.error:
        _errorPulseController.repeat(reverse: true);
      case NodeState.expanded:
        _expandRotateController.forward();
      case NodeState.normal:
      case NodeState.hover:
      case NodeState.selected:
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    _errorPulseController.dispose();
    _expandRotateController.dispose();
    super.dispose();
  }

  // ── Initials ───────────────────────────────────────────────────────

  String get _initials {
    if (widget.isAnonymous) return '?';
    final trimmed = widget.name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].length >= 2
          ? parts[0].substring(0, 2).toUpperCase()
          : parts[0][0].toUpperCase();
    }
    return '?';
  }

  // ── Relationship Color ─────────────────────────────────────────────

  Color get _borderColor {
    if (widget.isAnonymous) return _highContrast ? Colors.grey : KinrelColors.textDim;
    if (widget.isAnchor) return KinshipEdgeColors.self;
    // v69: Prefer the AUTHORITATIVE category — no lossy string round-trip.
    // styleForCategory() is always correct and never falls through to
    // grey for a known relationship.
    Color color;
    if (widget.category != null) {
      color = KinshipEdgeStyleResolver.styleForCategory(widget.category!).color;
    } else {
      color = KinshipEdgeStyleResolver.styleFor(widget.relationshipKey ?? '').color;
    }
    // High contrast: full opacity colors for WCAG AA 4.5:1 contrast
    return _highContrast ? Color.fromRGBO(color.red, color.green, color.blue, 1.0) : color;
  }

  Color get _tintColor {
    if (widget.isAnonymous) return Colors.transparent;
    if (widget.isAnchor) return KinshipEdgeColors.self.withValues(alpha: 0.04);
    // v69: Derive tint from the authoritative category when available.
    if (widget.category != null) {
      final color = KinshipEdgeStyleResolver.styleForCategory(widget.category!).color;
      return color.withValues(alpha: 0.04);
    }
    return KinshipEdgeStyleResolver.styleFor(widget.relationshipKey ?? '').color.withValues(alpha: 0.04);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Accessibility: reduced motion & high contrast
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // v60: Use local variable for build, but also set the field for
    // helper getters that reference _highContrast.
    final highContrast = MediaQuery.of(context).highContrast;
    _highContrast = highContrast;

    // Update animation durations for reduced motion
    if (reduceMotion) {
      _pulseController.stop();
      _shimmerController.stop();
      _errorPulseController.stop();
      _expandRotateController.stop();
    }

    final effectiveOpacity =
        widget.isDeceased ? 0.4 * widget.opacity : widget.opacity;

    // Accessibility: Expose the node as a single semantic button with a
    // descriptive label. Screen-reader users hear "[Name], [Relation],
    // Generation N." instead of "button, button, text, text".
    return Semantics(
      label: _buildSemanticLabel(),
      button: true,
      child: Opacity(
        opacity: effectiveOpacity,
        // v72 FIX: The parent FamilyGraphEngineView now does geometric
        // hit-testing for tap/long-press (see _handleNodeTapDown /
        // _handleNodeLongPress). This child RawGestureDetector is kept
        // for backward compatibility but uses HitTestBehavior.translucent
        // so it doesn't swallow events that the parent needs to handle.
        //
        // The previous `opaque` setting intercepted all touch events,
        // preventing the parent's GestureDetector from receiving them —
        // which meant on web (where the parent's scale recognizer wins
        // the arena), node taps never fired.
        child: RawGestureDetector(
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (instance) {
                instance.onTap = widget.onTap;
              },
            ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(),
              (instance) {
                instance.onLongPress = widget.onLongPress;
              },
            ),
          },
          behavior: HitTestBehavior.translucent,
          child: _buildAnimatedNode(reduceMotion: reduceMotion),
        ),
      ),
    );
  }

  // ── Semantic Label ─────────────────────────────────────────────────

  String _buildSemanticLabel() {
    if (widget.isAnonymous) {
      return 'Anonymous family member';
    }

    final name = widget.isDeceased ? 'Late ${widget.name}' : widget.name;

    final parts = <String>[
      name,
      widget.relationLabel,
      'Generation ${widget.generationIndex}',
    ];

    if (widget.nodeState == NodeState.expanded) {
      parts.add('Expanded');
    }

    return '${parts.join(', ')}.';
  }

  // ── Animated Node Builder ──────────────────────────────────────────

  Widget _buildAnimatedNode({bool reduceMotion = false}) {
    // 2.5D depth: ancestor nodes get a 1.5px upward visual offset to
    // reinforce the "floating higher" effect from the elevation shadow.
    // This is a static transform (no animation), applied to all states.
    final yOffset = widget.generationIndex < 0 && !widget.isAnchor ? -1.5 : 0.0;

    // Focused state: pulsing glow
    if (widget.nodeState == NodeState.focused) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, yOffset),
            child: Transform.scale(
              scale: _pulseAnimation.value,
              child: child,
            ),
          );
        },
        child: _buildNodeContent(),
      );
    }

    // Hover state: scale up 7%
    if (widget.nodeState == NodeState.hover) {
      return Transform.translate(
        offset: Offset(0, yOffset),
        child: Transform.scale(
          scale: 1.07,
          child: _buildNodeContent(),
        ),
      );
    }

    // Error state: red border pulse
    if (widget.nodeState == NodeState.error) {
      return AnimatedBuilder(
        animation: _errorPulseAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, yOffset),
            child: Opacity(
              opacity: _errorPulseAnimation.value,
              child: child,
            ),
          );
        },
        child: _buildNodeContent(),
      );
    }

    // Normal/selected/expanded/loading: static offset for ancestors
    if (yOffset != 0) {
      return Transform.translate(
        offset: Offset(0, yOffset),
        child: _buildNodeContent(),
      );
    }

    return _buildNodeContent();
  }

  // ── Node Content ───────────────────────────────────────────────────

  Widget _buildNodeContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Circle Node ───────────────────────────────────────────
        _buildCircleNode(),

        const SizedBox(height: 6.0),

        // ── Name below circle ─────────────────────────────────────
        // Wrap in FittedBox(scaleDown) so long names shrink to fit instead
        // of clipping. maxLines:1 + ellipsis remains as the final fallback
        // when scaling would make the text unreadably small.
        if (!widget.isAnonymous)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.name,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
                letterSpacing: 0.15, // §5: subtle letter-spacing for hierarchy
                shadows: const [ // §5: text-shadow for legibility over busy bg
                  Shadow(blurRadius: 4, color: Colors.black54),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // ── Relation label below name ─────────────────────────────
        // Same FittedBox treatment for the relationship label so localized
        // strings (Arabic, Hindi, etc.) don't clip in narrow nodes.
        //
        // v67 (BUG-20 FIX): The viewer's "You" label should always use
        // the teal self color, even when the viewer is not the anchor.
        // Previously the label used _borderColor which could be a
        // non-teal relationship color when isAnchor==false.
        //
        // v93 (ZOOM FIX): Hide the relation label when
        // showRelationLabel is false (low-zoom clutter reduction).
        // The primary member name above is ALWAYS visible.
        if (!widget.isAnonymous &&
            widget.relationLabel.isNotEmpty &&
            widget.showRelationLabel)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.relationLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
                color: widget.relationLabel == 'You'
                    ? KinshipEdgeColors.self
                    : _borderColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // ── Circle Node Builder ────────────────────────────────────────────
  // ── Circle Node Builder (Pseudo-3D) ─────────────────────────────────

  Widget _buildCircleNode() {
    final diameter = widget.nodeSize;

    // Anonymous node: gray, no avatar, no name (unchanged)
    if (widget.isAnonymous) {
      return Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: KinrelColors.darkElevated,
          border: Border.all(
            color: KinrelColors.textDim,
            width: 2.0,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.person_outline,
            size: diameter * 0.4,
            color: KinrelColors.textDim,
          ),
        ),
      );
    }

    // Pseudo-3D node: all 6 layers painted by a single CustomPainter.
    final nodeParams = _Pseudo3DParams(
      diameter: diameter,
      borderColor: widget.isAnchor ? KinshipEdgeColors.self : _borderColor,
      borderWidth: widget.isAnchor ? 3.0 : _borderWidth,
      generationIndex: widget.generationIndex,
      isAnchor: widget.isAnchor,
      nodeState: widget.nodeState,
      tintColor: _tintColor,
      showTint: widget.nodeState == NodeState.selected ||
          widget.nodeState == NodeState.hover,
    );

    final extraPad = widget.isAnchor ? 16.0 : 12.0;

    return SizedBox(
      width: diameter + extraPad,
      height: diameter + extraPad,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Layers 1-6: CustomPainter renders the entire pseudo-3D node
          Positioned.fill(
            child: CustomPaint(
              painter: _Pseudo3DNodePainter(nodeParams),
            ),
          ),
          // Content layer (initials/photo) clipped to the circle
          Positioned(
            left: extraPad / 2,
            top: extraPad / 2,
            width: diameter,
            height: diameter,
            child: ClipOval(
              child: Stack(
                children: [
                  if (nodeParams.showTint)
                    Positioned.fill(child: Container(color: nodeParams.tintColor)),
                  _buildCircleContent(diameter),
                  if (widget.nodeState == NodeState.loading)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _shimmerAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _ShimmerPainter(_shimmerAnimation.value),
                          );
                        },
                      ),
                    ),
                  if (widget.nodeState == NodeState.error)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.error,
                        ),
                        child: Icon(Icons.error_outline,
                            size: diameter * 0.25, color: KinrelColors.textWhite),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Private lock
          if (widget.isPrivate)
            Positioned(
              right: extraPad / 2 - 2, top: extraPad / 2 - 2,
              child: Container(
                padding: const EdgeInsets.all(2.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: KinrelColors.darkCard,
                  border: Border.all(color: KinrelColors.amber, width: 1.0),
                ),
                child: Icon(Icons.lock, size: diameter * 0.12, color: KinrelColors.amber),
              ),
            ),
          // Pending badge
          if (widget.isUnclaimed)
            Positioned(
              right: extraPad / 2 - 2, bottom: extraPad / 2 - 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: KinrelColors.amber, borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Pending',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: KinrelColors.darkCard)),
              ),
            ),
          // Role glyph — uses _NodeRoleGlyphBadge which handles the
          // provider lookup internally (familyId → role → badge)
          if (widget.familyId != null && kEnableKinrel)
            Positioned(
              right: extraPad / 2 - 4, bottom: extraPad / 2 - 4,
              child: _NodeRoleGlyphBadge(
                familyId: widget.familyId!,
                memberId: widget.personId,
                diameter: diameter * 0.3,
              ),
            ),
          // Expand indicator
          if (widget.relationshipKey != null &&
              ExpandIndicators.expandLabelFor(widget.relationshipKey) != null)
            Positioned(
              right: extraPad / 2 - 4, top: extraPad / 2 - 4,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.all(2.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: KinrelColors.darkCard,
                    border: Border.all(color: _borderColor, width: 1.0),
                  ),
                  child: AnimatedBuilder(
                    animation: _expandRotateController,
                    builder: (context, child) =>
                        Transform.rotate(angle: _expandRotateController.value * pi, child: child),
                    child: widget.nodeState == NodeState.expanded
                        ? Icon(Icons.expand_less, size: diameter * 0.2, color: _borderColor)
                        : Icon(Icons.expand_more, size: diameter * 0.2, color: _borderColor),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }


  /// Border width varies by state. Doubled in high contrast mode
  /// per V2.1 Blueprint §19 (WCAG AA minimum contrast 4.5:1).
  double get _borderWidth {
    final base = switch (widget.nodeState) {
      NodeState.selected => 3.5,
      NodeState.focused => 3.0,
      NodeState.hover => 2.5,
      NodeState.error => 3.0,
      _ => 2.5,
    };
    return _highContrast ? base * 2.0 : base;
  }

  // ── Generation-Based Elevation (2.5D depth) ────────────────────────
  //
  // Subtle Material-style elevation driven by generationIndex:
  //   Ancestors (gen < 0): larger blur + slight upward offset → "floating higher"
  //   Anchor   (gen == 0, isAnchor): most pronounced → "closest to viewer"
  //   Descendants (gen > 0): smaller, tighter shadow → "flush/lower"
  //
  // Includes a paired highlight shadow (white, low alpha, opposite offset)
  // so the dark drop shadow has something to contrast against on the
  // near-black canvas background — without this, a black shadow on a
  // near-black background is invisible (contrast bug).
  //
  // These are STATIC per node (computed once from generationIndex + state),
  // NOT recalculated every frame. No BackdropFilter, no saveLayer — just
  // standard BoxShadow via BoxDecoration.

  List<BoxShadow> get _elevationShadows {
    final gen = widget.generationIndex;
    final isAnchor = widget.isAnchor;

    // Base elevation shadow (generation-driven)
    BoxShadow base;
    if (isAnchor) {
      // Anchor: most pronounced — closest to viewer
      base = BoxShadow(
        color: Colors.black.withValues(alpha: 0.40),
        blurRadius: 16,
        offset: const Offset(0, 6),
        spreadRadius: 0,
      );
    } else if (gen < 0) {
      // Ancestors: float higher — larger blur, slight upward offset
      base = BoxShadow(
        color: Colors.black.withValues(alpha: 0.30),
        blurRadius: 12,
        offset: const Offset(0, -2), // upward offset
        spreadRadius: 0,
      );
    } else {
      // Descendants: flush/lower — tighter shadow
      base = BoxShadow(
        color: Colors.black.withValues(alpha: 0.20),
        blurRadius: 6,
        offset: const Offset(0, 2),
        spreadRadius: 0,
      );
    }

    // Highlight shadow — opposite direction from base, gives the eye
    // something to contrast against on the near-black canvas.
    final highlight = BoxShadow(
      color: Colors.white.withValues(alpha: isAnchor ? 0.08 : 0.05),
      blurRadius: 4,
      offset: const Offset(0, -1.5),
      spreadRadius: -1,
    );

    // State-driven additive shadows (selected/focused glow)
    // These COMBINE with the base elevation + highlight, not replace it.
    if (widget.nodeState == NodeState.selected) {
      return [
        base,
        highlight,
        BoxShadow(
          color: _borderColor.withValues(alpha: 0.40),
          blurRadius: 14,
          spreadRadius: 2,
        ),
      ];
    }
    if (widget.nodeState == NodeState.focused) {
      return [
        base,
        highlight,
        BoxShadow(
          color: _borderColor.withValues(alpha: 0.35),
          blurRadius: 10,
          spreadRadius: 3,
        ),
      ];
    }
    // Hover: increase shadow on top of base elevation + highlight
    if (widget.nodeState == NodeState.hover) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: isAnchor ? 0.50 : (gen < 0 ? 0.40 : 0.30)),
          blurRadius: isAnchor ? 20 : (gen < 0 ? 16 : 10),
          offset: isAnchor
              ? const Offset(0, 8)
              : (gen < 0 ? const Offset(0, -3) : const Offset(0, 3)),
        ),
        highlight,
      ];
    }

    // Normal/error/loading/expanded: base elevation + highlight
    return [base, highlight];
  }

  // ── Circle Content (initials or photo) ─────────────────────────────

  Widget _buildCircleContent(double diameter) {
    // v62: Use CachedAvatar instead of raw Image.network.
    // CachedAvatar provides disk caching, shimmer placeholder, and
    // memory-optimized memCacheWidth — critical for families with
    // many photo URLs (avoids repeated network requests + flicker).
    if (widget.photoUrl != null &&
        widget.photoUrl!.isNotEmpty &&
        !widget.isAnonymous) {
      return ClipOval(
        child: CachedAvatar(
          imageUrl: widget.photoUrl,
          radius: diameter / 2,
          fit: BoxFit.cover,
          backgroundColor: KinrelColors.darkCard,
          placeholder: _buildInitialsContent(diameter),
          errorWidget: _buildInitialsContent(diameter),
        ),
      );
    }

    // Fallback: initials
    return _buildInitialsContent(diameter);
  }

  Widget _buildInitialsContent(double diameter) {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: diameter * 0.28,
          fontWeight: FontWeight.bold,
          color: widget.isAnonymous
              ? KinrelColors.textDim
              : KinrelColors.textWhite,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHIMMER PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that renders a shimmer gradient sweep for the loading state.
class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(value - 1, 0),
        end: Alignment(value, 0),
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

/// Kinrel role glyph badge for a single [GraphNode]. Watches
/// [memberRoleGlyphProvider] for the (familyId, memberId) pair and
/// renders nothing if Kinrel hasn't been computed or the member has no
/// role row yet — keeps the existing node visuals untouched.
class _NodeRoleGlyphBadge extends ConsumerWidget {
  const _NodeRoleGlyphBadge({
    required this.familyId,
    required this.memberId,
    required this.diameter,
  });

  final String familyId;
  final String memberId;
  final double diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(
      memberRoleGlyphProvider(memberRoleKey(familyId, memberId)),
    );
    if (role == null) return const SizedBox.shrink();
    // Badge size scales with the node: 35% of the diameter, clamped to
    // 14–22px so it's visible on compact nodes without crowding large ones.
    final size = (diameter * 0.35).clamp(14.0, 22.0);
    return RoleGlyphBadge(role: role, size: size);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PSEUDO-3D NODE PAINTER
// ═══════════════════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════════════════
// PREMIUM OBSIDIAN GLASS MEDALLION — Pseudo-3D Node System v3
// ═══════════════════════════════════════════════════════════════════════
//
// ROOT CAUSE of previous "glowing circle" look:
//   1. Side wall circle (radius=r) was same size as face (radius=r-1.25).
//      Face covered 95% of wall. The 5px crescent that showed was painted
//      at 85% black — invisible against #131416 background.
//   2. Anchor had a solid teal ring at radius+5 (alpha 0.15) = neon halo.
//   3. Face TL had 6% white lift — read as a light bulb, not dark glass.
//   4. Rim reflection at 0.08-0.15 alpha flooded the entire face with colour.
//
// FIX v3:
//   - Wall is LARGER than face (r + extrusion*0.3) and offset further
//   - Wall uses LIGHTER dark colors so crescent is visible against bg
//   - No anchor halo at all — depth comes from elevation, not glow
//   - Face TL lift reduced to 3% — reads as dark glass, not light source
//   - Rim reflection reduced to 0.03-0.05 — barely-there edge tint
//   - Specular arc made wider and more visible
//   - Bevel dark inset stronger, TL highlight brighter

class _Pseudo3DParams {
  const _Pseudo3DParams({
    required this.diameter,
    required this.borderColor,
    required this.borderWidth,
    required this.generationIndex,
    required this.isAnchor,
    required this.nodeState,
    required this.tintColor,
    required this.showTint,
  });

  final double diameter;
  final Color borderColor;
  final double borderWidth;
  final int generationIndex;
  final bool isAnchor;
  final NodeState nodeState;
  final Color tintColor;
  final bool showTint;

  double get _scale => diameter / 72.0;

  /// Extrusion depth: 7-9% of diameter, clamped.
  double get extrusionDepth => (diameter * 0.08).clamp(4.0, 9.0);

  double get bevelWidth => (diameter * 0.025).clamp(1.5, 3.0);
  double get specularThickness => (diameter * 0.06).clamp(2.5, 5.0);

  double get shadowBlur {
    final base = diameter * 0.15;
    if (isAnchor) return base + 3.0;
    if (generationIndex < 0) return base + 2.0;
    if (generationIndex > 0) return base * 0.65;
    return base;
  }

  /// Shadow offset: down-right, scaled.
  Offset get shadowOffset {
    final s = _scale;
    final depth = extrusionDepth;
    if (isAnchor) return Offset(depth * 0.4, depth * 0.9);
    if (generationIndex < 0) return Offset(depth * 0.3, depth * 0.4);
    if (generationIndex > 0) return Offset(depth * 0.3, depth * 0.6);
    return Offset(depth * 0.35, depth * 0.7);
  }

  double get shadowAlpha {
    if (isAnchor) return 0.45;
    if (generationIndex < 0) return 0.30;
    if (generationIndex > 0) return 0.20;
    return 0.35;
  }

  /// Specular: stronger than v2, visible at 1:1 phone size.
  double get specularAlpha {
    if (isAnchor) return 0.18;
    if (generationIndex < 0) return 0.14;
    if (generationIndex > 0) return 0.08;
    return 0.12;
  }

  double get glowAlpha {
    switch (nodeState) {
      case NodeState.selected: return 0.25;
      case NodeState.focused: return 0.20;
      default: return 0.0;
    }
  }

  double get glowBlur => diameter * 0.12;

  /// Rim reflection: very subtle, barely visible edge tint.
  double get rimReflectionAlpha => isAnchor ? 0.05 : 0.03;
}

class _Pseudo3DNodePainter extends CustomPainter {
  const _Pseudo3DNodePainter(this.params);

  final _Pseudo3DParams params;

  @override
  void paint(Canvas canvas, Size size) {
    final d = params.diameter;
    final center = Offset(size.width / 2, size.height / 2);
    final r = d / 2;
    final bw = params.borderWidth;
    final faceR = r - bw * 0.5;
    final extrusion = params.extrusionDepth;

    // ══ LAYER 1: Contact + ambient shadow ══════════════════════════
    // Neutral dark shadow, offset down-right. NOT coloured.
    canvas.drawCircle(
      center + params.shadowOffset,
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: params.shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, params.shadowBlur),
    );

    // ══ LAYER 2: Extruded side wall ════════════════════════════════
    // KEY FIX: Wall circle is LARGER than face (r + extrusion*0.25)
    // and offset further down-right. This makes a visible crescent
    // of wall material on the bottom-right that the face doesn't cover.
    //
    // Wall colors are LIGHTER than v2 (darkCard base, not lerp-to-black)
    // so the crescent is visible against the #131416 background.
    final wallOffset = Offset(extrusion * 0.4, extrusion * 0.85);
    final wallCenter = center + wallOffset;
    final wallR = r + extrusion * 0.2; // LARGER than face radius
    final wallRect = Rect.fromCircle(center: wallCenter, radius: wallR);

    // Wall gradient: TL side lighter (catches reflected light from face),
    // BR side darkest (in shadow). Use darkElevated as base so it's
    // visibly lighter than the background.
    canvas.drawCircle(wallCenter, wallR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [
            KinrelColors.darkElevated,                              // TL: catches light
            KinrelColors.darkCard,                                   // mid
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.4)!,   // BR: shadowed
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(wallRect),
    );

    // Subtle relationship colour bounce on the wall's BR (visible crescent).
    // Very weak — just a hint of colour on the physical edge.
    canvas.drawCircle(wallCenter, wallR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.4, 0.5), // BR of wall
          radius: 0.35,
          colors: [
            params.borderColor.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 1.0],
        ).createShader(wallRect),
    );

    // ══ LAYER 3: Curved dark glass face ════════════════════════════
    // FIX: Reduced TL lift from 6% to 3% white. Center stays at darkCard.
    // BR goes to 35% darker. Edge vignette at 55% darker.
    // The face must read as DARK NEUTRAL GLASS, not a light source.
    final faceRect = Rect.fromCircle(center: center, radius: faceR);
    canvas.drawCircle(center, faceR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.85,
          colors: [
            Color.lerp(KinrelColors.darkCard, Colors.white, 0.03)!, // TL: barely lighter
            KinrelColors.darkCard,                                    // center: neutral dark
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.35)!,  // BR: darker
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.55)!,  // edge: vignette
          ],
          stops: const [0.0, 0.35, 0.75, 1.0],
        ).createShader(faceRect),
    );

    // ══ LAYER 4: Relationship colour edge-reflection ═══════════════
    // FIX: Reduced from 0.08-0.15 to 0.03-0.05. Barely visible tint
    // at the extreme edge only. Centre 70%+ of face stays neutral dark.
    if (params.rimReflectionAlpha > 0) {
      canvas.drawCircle(center, faceR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.3),
            radius: 0.45,
            colors: [
              Colors.transparent,
              Colors.transparent,
              params.borderColor.withValues(alpha: params.rimReflectionAlpha),
            ],
            stops: const [0.0, 0.72, 1.0],
          ).createShader(faceRect),
      );
    }

    // Tint overlay for selected/hover
    if (params.showTint) {
      canvas.drawCircle(center, faceR, Paint()..color = params.tintColor);
    }

    // ══ LAYER 5: Outer rim (directional bezel) ═════════════════════
    // SweepGradient: brighter TL arc, darker BR arc.
    final rimRect = Rect.fromCircle(center: center, radius: r - bw * 0.5);
    final borderBright = params.borderColor;
    final borderDark = Color.lerp(params.borderColor, Colors.black, 0.55)!;

    canvas.drawCircle(center, r - bw * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0.0,
          endAngle: 2 * pi,
          colors: [borderBright, borderDark, borderDark, borderBright],
          stops: const [0.0, 0.25, 0.75, 1.0],
          transform: GradientRotation(-pi * 0.75),
        ).createShader(rimRect),
    );

    // ══ LAYER 6: Inner bevel (directional) ═════════════════════════
    // FIX: Dark inset stronger (0.5 alpha), TL highlight brighter (0.12).
    // Dark inset: full circle, thin
    final bevelR = faceR - params.bevelWidth;
    final bevelRect = Rect.fromCircle(center: center, radius: bevelR);

    canvas.drawCircle(center, faceR - params.bevelWidth * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = params.bevelWidth
        ..color = Colors.black.withValues(alpha: 0.50),
    );

    // TL bevel highlight: arc only, brighter
    canvas.drawArc(bevelRect, pi * 0.9, pi * 0.5, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = params.bevelWidth * 0.7
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // BR bevel shadow: arc only, darker (reinforces depth)
    canvas.drawArc(bevelRect, 0, pi * 0.4, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = params.bevelWidth * 0.7
        ..color = Colors.black.withValues(alpha: 0.30),
    );

    // ══ LAYER 7: Specular reflection ═══════════════════════════════
    // FIX: Wider arc (0.4π instead of 0.3π), higher alpha, thicker stroke.
    // Must be visible at 1:1 phone size without zooming.
    final specAlpha = params.specularAlpha;
    if (specAlpha > 0) {
      final specR = r * 0.68;
      final specRect = Rect.fromCircle(
        center: Offset(center.dx - r * 0.1, center.dy - r * 0.15),
        radius: specR,
      );
      // Main specular arc — curved crescent in upper-left
      canvas.drawArc(specRect, pi * 1.05, pi * 0.4, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = params.specularThickness
          ..strokeCap = StrokeCap.round
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.5,
            colors: [
              Colors.white.withValues(alpha: specAlpha),
              Colors.white.withValues(alpha: specAlpha * 0.4),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(specRect),
      );

      // Micro-highlight spot near top edge
      canvas.drawCircle(
        Offset(center.dx - r * 0.03, center.dy - r * 0.42),
        params.specularThickness * 0.35,
        Paint()
          ..color = Colors.white.withValues(alpha: specAlpha * 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }

    // ══ LAYER 8: Contact glow (selected/focused ONLY) ══════════════
    // Tight, behind the object, never washes across face.
    if (params.glowAlpha > 0) {
      canvas.drawCircle(center, r + 1.5,
        Paint()
          ..color = params.borderColor.withValues(alpha: params.glowAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, params.glowBlur)
          ..style = PaintingStyle.fill,
      );
    }

    // NOTE: No anchor halo. Anchor prominence comes from:
    //   - Slightly larger extrusion (extrusionDepth unchanged but shadowBlur +3)
    //   - Stronger specular (specularAlpha 0.18 vs 0.12)
    //   - Teal rim + 0.05 edge reflection
    //   - NOT from a giant teal spread ring.
  }

  @override
  bool shouldRepaint(covariant _Pseudo3DNodePainter old) {
    return old.params.diameter != params.diameter ||
        old.params.borderColor != params.borderColor ||
        old.params.borderWidth != params.borderWidth ||
        old.params.generationIndex != params.generationIndex ||
        old.params.isAnchor != params.isAnchor ||
        old.params.nodeState != params.nodeState ||
        old.params.showTint != params.showTint;
  }
}
