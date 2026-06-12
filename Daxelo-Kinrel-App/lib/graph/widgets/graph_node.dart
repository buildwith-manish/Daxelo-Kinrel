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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';

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

/// Defines the color system for each relationship type in the graph.
class RelationshipColors {
  RelationshipColors._();

  // ── Border Colors ───────────────────────────────────────────────────

  /// Self — Teal #0D9488
  static const Color self = Color(0xFF0D9488);

  /// Parent — Blue #3B82F6
  static const Color parent = Color(0xFF3B82F6);

  /// Sibling — Purple #8B5CF6
  static const Color sibling = Color(0xFF8B5CF6);

  /// Child — Pink #EC4899
  static const Color child = Color(0xFFEC4899);

  /// Spouse — Orange #F97316
  static const Color spouse = Color(0xFFF97316);

  /// Grandparent — Indigo #6366F1
  static const Color grandparent = Color(0xFF6366F1);

  /// Aunt/Uncle — Cyan #06B6D4
  static const Color auntUncle = Color(0xFF06B6D4);

  /// Cousin — Emerald #10B981
  static const Color cousin = Color(0xFF10B981);

  /// In-Law — Amber #F59E0B
  static const Color inLaw = Color(0xFFF59E0B);

  /// Extended — Slate #64748B
  static const Color extended = Color(0xFF64748B);

  // ── Background Tint (4% alpha) ──────────────────────────────────────

  /// Self background tint — teal 4%
  static const Color selfTint = Color(0x0A0D9488);

  /// Parent background tint — blue 4%
  static const Color parentTint = Color(0x0A3B82F6);

  /// Sibling background tint — purple 4%
  static const Color siblingTint = Color(0x0A8B5CF6);

  /// Child background tint — pink 4%
  static const Color childTint = Color(0x0AEC4899);

  /// Spouse background tint — orange 4%
  static const Color spouseTint = Color(0x0AF97316);

  /// Grandparent background tint — indigo 4%
  static const Color grandparentTint = Color(0x0A6366F1);

  /// Aunt/Uncle background tint — cyan 4%
  static const Color auntUncleTint = Color(0x0A06B6D4);

  /// Cousin background tint — emerald 4%
  static const Color cousinTint = Color(0x0A10B981);

  /// In-Law background tint — amber 4%
  static const Color inLawTint = Color(0x0AF59E0B);

  /// Extended background tint — slate 4%
  static const Color extendedTint = Color(0x0A64748B);

  // ── Resolution ──────────────────────────────────────────────────────

  /// Returns the border color for a given relationship key.
  static Color borderColorFor(String? relationshipKey) {
    if (relationshipKey == null) return extended;
    return _borderColorMap[relationshipKey] ?? extended;
  }

  /// Returns the background tint for a given relationship key.
  static Color tintFor(String? relationshipKey) {
    if (relationshipKey == null) return extendedTint;
    return _tintColorMap[relationshipKey] ?? extendedTint;
  }

  /// Map of relationship key → border color.
  static const Map<String, Color> _borderColorMap = {
    // Self
    'self': self,
    // Parent
    'parent': parent,
    'father': parent,
    'mother': parent,
    // Sibling
    'sibling': sibling,
    'brother': sibling,
    'sister': sibling,
    // Child
    'child': child,
    'son': child,
    'daughter': child,
    // Spouse
    'spouse': spouse,
    'husband': spouse,
    'wife': spouse,
    'partner': spouse,
    // Grandparent
    'grandparent': grandparent,
    'grandfather': grandparent,
    'grandmother': grandparent,
    // Aunt/Uncle
    'aunt': auntUncle,
    'uncle': auntUncle,
    'paternal_uncle': auntUncle,
    'paternal_aunt': auntUncle,
    'maternal_uncle': auntUncle,
    'maternal_aunt': auntUncle,
    // Cousin
    'cousin': cousin,
    'cousin_brother': cousin,
    'cousin_sister': cousin,
    // In-Law
    'father_in_law': inLaw,
    'mother_in_law': inLaw,
    'son_in_law': inLaw,
    'daughter_in_law': inLaw,
    'brother_in_law': inLaw,
    'sister_in_law': inLaw,
    // Extended
    'stepfather': extended,
    'stepmother': extended,
    'stepson': extended,
    'stepdaughter': extended,
    'stepbrother': extended,
    'stepsister': extended,
    'half_brother': extended,
    'half_sister': extended,
  };

  /// Map of relationship key → background tint.
  static const Map<String, Color> _tintColorMap = {
    'self': selfTint,
    'parent': parentTint,
    'father': parentTint,
    'mother': parentTint,
    'sibling': siblingTint,
    'brother': siblingTint,
    'sister': siblingTint,
    'child': childTint,
    'son': childTint,
    'daughter': childTint,
    'spouse': spouseTint,
    'husband': spouseTint,
    'wife': spouseTint,
    'partner': spouseTint,
    'grandparent': grandparentTint,
    'grandfather': grandparentTint,
    'grandmother': grandparentTint,
    'aunt': auntUncleTint,
    'uncle': auntUncleTint,
    'paternal_uncle': auntUncleTint,
    'paternal_aunt': auntUncleTint,
    'maternal_uncle': auntUncleTint,
    'maternal_aunt': auntUncleTint,
    'cousin': cousinTint,
    'cousin_brother': cousinTint,
    'cousin_sister': cousinTint,
    'father_in_law': inLawTint,
    'mother_in_law': inLawTint,
    'son_in_law': inLawTint,
    'daughter_in_law': inLawTint,
    'brother_in_law': inLawTint,
    'sister_in_law': inLawTint,
    'stepfather': extendedTint,
    'stepmother': extendedTint,
    'stepson': extendedTint,
    'stepdaughter': extendedTint,
    'stepbrother': extendedTint,
    'stepsister': extendedTint,
    'half_brother': extendedTint,
    'half_sister': extendedTint,
  };
}

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
    required this.relationLabel,
    this.nodeState = NodeState.normal,
    this.opacity = 1.0,
    this.nodeSize = 72.0,
    this.isPrivate = false,
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
    final parts = widget.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return '?';
  }

  // ── Relationship Color ─────────────────────────────────────────────

  Color get _borderColor {
    if (widget.isAnonymous) return KinrelColors.textDim;
    if (widget.isAnchor) return RelationshipColors.self;
    return RelationshipColors.borderColorFor(widget.relationshipKey);
  }

  Color get _tintColor {
    if (widget.isAnonymous) return Colors.transparent;
    if (widget.isAnchor) return RelationshipColors.selfTint;
    return RelationshipColors.tintFor(widget.relationshipKey);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity =
        widget.isDeceased ? 0.4 * widget.opacity : widget.opacity;

    return Opacity(
      opacity: effectiveOpacity,
      child: Semantics(
        label: _buildSemanticLabel(),
        button: true,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onDoubleTap: widget.onDoubleTap,
          child: _buildAnimatedNode(),
        ),
      ),
    );
  }

  // ── Semantic Label ─────────────────────────────────────────────────

  String _buildSemanticLabel() {
    if (widget.isAnonymous) {
      return 'Anonymous, Generation ${widget.generationIndex}';
    }

    final parts = <String>[
      widget.name,
      widget.relationLabel,
      'Generation ${widget.generationIndex}',
    ];

    if (widget.nodeState == NodeState.expanded) {
      parts.add('Expanded');
    }

    return '${parts.join(', ')}.';
  }

  // ── Animated Node Builder ──────────────────────────────────────────

  Widget _buildAnimatedNode() {
    // Focused state: pulsing glow
    if (widget.nodeState == NodeState.focused) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: child,
          );
        },
        child: _buildNodeContent(),
      );
    }

    // Hover state: scale up 7%
    if (widget.nodeState == NodeState.hover) {
      return Transform.scale(
        scale: 1.07,
        child: _buildNodeContent(),
      );
    }

    // Error state: red border pulse
    if (widget.nodeState == NodeState.error) {
      return AnimatedBuilder(
        animation: _errorPulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _errorPulseAnimation.value,
            child: child,
          );
        },
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
        if (!widget.isAnonymous)
          Text(
            widget.name,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

        // ── Relation label below name ─────────────────────────────
        if (!widget.isAnonymous && widget.relationLabel.isNotEmpty)
          Text(
            widget.relationLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 11.0,
              fontWeight: FontWeight.w500,
              color: _borderColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  // ── Circle Node Builder ────────────────────────────────────────────

  Widget _buildCircleNode() {
    final diameter = widget.nodeSize;

    // Anonymous node: gray, no avatar, no name
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

    // Anchor node: double-ring (outer teal 88dp glow, inner 72dp solid)
    if (widget.isAnchor) {
      return SizedBox(
        width: diameter + 16.0,
        height: diameter + 16.0,
        child: Center(
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.darkCard,
              border: Border.all(
                color: RelationshipColors.self,
                width: 3.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: RelationshipColors.self.withValues(alpha: 0.25),
                  blurRadius: 0.0,
                  spreadRadius: 8.0,
                ),
                // Selected state: additional glow
                if (widget.nodeState == NodeState.selected)
                  BoxShadow(
                    color:
                        RelationshipColors.self.withValues(alpha: 0.4),
                    blurRadius: 12.0,
                    spreadRadius: 4.0,
                  ),
              ],
            ),
            child: _buildCircleContent(diameter),
          ),
        ),
      );
    }

    // Standard node with relationship-colored ring
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.darkCard,
        border: Border.all(
          color: _borderColor,
          width: _borderWidth,
        ),
        boxShadow: [
          // Selected: accent border glow
          if (widget.nodeState == NodeState.selected)
            BoxShadow(
              color: _borderColor.withValues(alpha: 0.4),
              blurRadius: 12.0,
              spreadRadius: 2.0,
            ),
          // Hover: elevated shadow
          if (widget.nodeState == NodeState.hover)
            BoxShadow(
              color: _borderColor.withValues(alpha: 0.3),
              blurRadius: 8.0,
              spreadRadius: 2.0,
            ),
        ],
      ),
      child: Stack(
        children: [
          // Background tint
          if (widget.nodeState == NodeState.selected ||
              widget.nodeState == NodeState.hover)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _tintColor,
                ),
              ),
            ),
          // Circle content (initials or photo)
          _buildCircleContent(diameter),
          // Loading: shimmer overlay
          if (widget.nodeState == NodeState.loading)
            Positioned.fill(
              child: ClipOval(
                child: AnimatedBuilder(
                  animation: _shimmerAnimation,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ShimmerPainter(_shimmerAnimation.value),
                    );
                  },
                ),
              ),
            ),
          // Error: error icon overlay
          if (widget.nodeState == NodeState.error)
            Center(
              child: Container(
                padding: const EdgeInsets.all(4.0),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.error,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: diameter * 0.25,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          // Private relationship: lock icon
          if (widget.isPrivate)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(2.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.darkCard,
                  border: Border.all(
                    color: KinrelColors.amber,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: diameter * 0.2,
                  color: KinrelColors.amber,
                ),
              ),
            ),
          // Expand indicator
          if (widget.nodeState == NodeState.expanded ||
              widget.nodeState == NodeState.loading)
            Positioned(
              right: 0,
              bottom: 0,
              child: RotationTransition(
                turns: _expandRotateController,
                child: Container(
                  padding: const EdgeInsets.all(3.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkCard,
                    border: Border.all(
                      color: _borderColor,
                      width: 1.5,
                    ),
                  ),
                  child: widget.nodeState == NodeState.loading
                      ? SizedBox(
                          width: diameter * 0.18,
                          height: diameter * 0.18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_borderColor),
                          ),
                        )
                      : Icon(
                          Icons.expand_more,
                          size: diameter * 0.2,
                          color: _borderColor,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Border width varies by state.
  double get _borderWidth {
    switch (widget.nodeState) {
      case NodeState.selected:
        return 3.5;
      case NodeState.focused:
        return 3.0;
      case NodeState.hover:
        return 2.5;
      case NodeState.error:
        return 3.0;
      default:
        return 2.5;
    }
  }

  // ── Circle Content (initials or photo) ─────────────────────────────

  Widget _buildCircleContent(double diameter) {
    // If photo URL is available and not anonymous, show photo in ClipOval
    if (widget.photoUrl != null &&
        widget.photoUrl!.isNotEmpty &&
        !widget.isAnonymous) {
      return ClipOval(
        child: Image.network(
          widget.photoUrl!,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildInitialsContent(diameter),
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
