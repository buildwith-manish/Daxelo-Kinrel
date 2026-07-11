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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/constants/feature_flags.dart';
import '../../core/kinship/kinship_edge_style.dart';
import '../../core/widgets/cached_avatar.dart';
import '../../features/kinrel_intelligence/providers/kinrel_provider.dart';
import '../../features/kinrel_intelligence/widgets/role_glyph_badge.dart';

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

  // ── Resolution — SINGLE SOURCE OF TRUTH ─────────────────────────────
  //
  // Node border colors and tints are resolved via KinshipEdgeStyleResolver
  // — the SAME resolver used by the edge painter. This ensures node ring
  // colors ALWAYS match edge line colors, because both use the same
  // KinshipEdgeClassifier.classify() → KinshipEdgeStyle pipeline.
  //
  // Previous architecture had a DUPLICATE color system with its own
  // _borderColorMap (35 entries), _tintColorMap (35 entries),
  // _categoryColorFromEdgeCategory, _kinshipCategoryFor, and
  // _categoryBorderColor. These could fall out of sync with the edge
  // painter's KinshipEdgeStyleResolver, causing mismatched colors.
  //
  // All duplicate maps and methods have been REMOVED. The only color
  // resolution path is now:
  //   relationshipKey → KinshipEdgeClassifier.classify()
  //                   → KinshipEdgeStyleResolver.styleForCategory()
  //                   → KinshipEdgeStyle.color
  //
  // This handles ALL 5,350+ kinship terms via comprehensive regex
  // patterns — no hardcoded maps, no kinship dataset dependency.

  /// Resolves the border color for a relationship key.
  /// Delegates to KinshipEdgeStyleResolver (same as edge painter).
  static Color borderColorFor(String? relationshipKey) {
    if (relationshipKey == null || relationshipKey.isEmpty) {
      return extended;
    }
    final style = KinshipEdgeStyleResolver.styleFor(relationshipKey);
    return style.color ?? extended;
  }

  /// Resolves the background tint for a relationship key.
  /// Derives tint from the same color as borderColorFor.
  static Color tintFor(String? relationshipKey) {
    if (relationshipKey == null || relationshipKey.isEmpty) {
      return extendedTint;
    }
    final color = borderColorFor(relationshipKey);
    return color.withValues(alpha: 0.04);
  }
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
    this.category,
    required this.relationLabel,
    this.nodeState = NodeState.normal,
    this.opacity = 1.0,
    this.nodeSize = 72.0,
    this.isPrivate = false,
    this.isUnclaimed = false,
    this.familyId,
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
    if (widget.isAnchor) return RelationshipColors.self;
    // v69: Prefer the AUTHORITATIVE category — no lossy string round-trip.
    // styleForCategory() is always correct and never falls through to
    // grey for a known relationship.
    Color color;
    if (widget.category != null) {
      color = KinshipEdgeStyleResolver.styleForCategory(widget.category!).color;
    } else {
      color = RelationshipColors.borderColorFor(widget.relationshipKey);
    }
    // High contrast: full opacity colors for WCAG AA 4.5:1 contrast
    return _highContrast ? Color.fromRGBO(color.red, color.green, color.blue, 1.0) : color;
  }

  Color get _tintColor {
    if (widget.isAnonymous) return Colors.transparent;
    if (widget.isAnchor) return RelationshipColors.selfTint;
    // v69: Derive tint from the authoritative category when available.
    if (widget.category != null) {
      final color = KinshipEdgeStyleResolver.styleForCategory(widget.category!).color;
      return color.withValues(alpha: 0.04);
    }
    return RelationshipColors.tintFor(widget.relationshipKey);
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
        if (!widget.isAnonymous && widget.relationLabel.isNotEmpty)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.relationLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
                color: widget.relationLabel == 'You'
                    ? RelationshipColors.self
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
    // with generation-based elevation shadow (most pronounced — closest
    // to viewer).
    if (widget.isAnchor) {
      return SizedBox(
        width: diameter + 16.0,
        height: diameter + 16.0,
        child: Center(
          child: Container(
            width: diameter,
            height: diameter,
            clipBehavior: Clip.none,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                radius: 0.9,
                colors: [
                  KinrelColors.darkElevated,
                  KinrelColors.darkCard,
                  Color.lerp(KinrelColors.darkCard, Colors.black, 0.4)!,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
              border: Border.all(
                color: RelationshipColors.self,
                width: 3.0,
              ),
              boxShadow: [
                // Teal spread glow (existing anchor ring)
                BoxShadow(
                  color: RelationshipColors.self.withValues(alpha: 0.25),
                  blurRadius: 0.0,
                  spreadRadius: 8.0,
                ),
                // 2.5D elevation shadow (generation-driven)
                ..._elevationShadows,
              ],
            ),
            child: _buildCircleContent(diameter),
          ),
        ),
      );
    }

    // Standard node with relationship-colored ring
    // 2.5D depth: elevation shadow is computed once from generationIndex
    // + state via _elevationShadows getter — no per-frame recomputation.
    // clipBehavior: Clip.none allows the BoxShadow to render OUTSIDE the
    // Container bounds — without this, the shadow is clipped and invisible.
    return Container(
      width: diameter,
      height: diameter,
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [
            KinrelColors.darkElevated,
            KinrelColors.darkCard,
            Color.lerp(KinrelColors.darkCard, Colors.black, 0.4)!,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        border: Border.all(
          color: _borderColor,
          width: _borderWidth,
        ),
        boxShadow: _elevationShadows,
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
          // Unclaimed Person: "Pending" badge (bottom-left)
          if (widget.isUnclaimed)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: KinrelColors.orange,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: KinrelColors.darkCard,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: diameter * 0.13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // Kinrel role glyph badge (top-right) — shows the member's role
          // within the family Kinrel (root/anchor/bridge/weaver/leaf/twin_node).
          // Rendered only when the feature flag is on AND a familyId is
          // provided AND the provider has a role for this member.
          if (kEnableKinrel && widget.familyId != null)
            Positioned(
              right: 0,
              top: 0,
              child: _NodeRoleGlyphBadge(
                familyId: widget.familyId!,
                memberId: widget.personId,
                diameter: diameter,
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
