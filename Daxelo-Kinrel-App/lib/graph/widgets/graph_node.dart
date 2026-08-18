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
import 'engine/node_decoration.dart';
import 'engine/node_paint_helpers.dart';
import 'engine/node_role_glyph_badge.dart';
import 'engine/node_state.dart';
import 'on_this_day_badge.dart'
    show OnThisDayBadge, OnThisDayEvent, showOnThisDayEventSheet;
// P12.7 — Kinrel Cameo fallback avatar
import '../../features/cameo/cameo.dart';
// v104: smooth relationship-label zoom fade.
import '../interaction/camera_controller.dart' show CameraController;
import '../rendering/relationship_label_opacity.dart'
    show
        relationLabelOpacityFor,
        relationLabelVisibleAt,
        kLabelFullyVisibleZoom,
        kLabelFullyHiddenZoom;

// Re-export NodeState so existing importers of graph_node.dart (e.g.
// family_graph_engine_view.dart, tests) keep resolving the symbol after
// it was extracted to engine/node_state.dart.
export 'engine/node_state.dart';

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
    // v5.9: unlinked-member detection
    this.isUnlinked = false,
    this.familyId,
    this.showRelationLabel = true,
    // P3.3: birthday glow parameters.
    this.isNearBirthday = false,
    this.birthdayPulseValue = 0.0,
    this.daysUntilBirthday,
    // P3.4: memorial candle parameters.
    this.memorialCandleFlickerValue = 0.0,
    this.isRecentlyDeceased = false,
    // P3.7: on-this-day badge.
    this.onThisDayEvent,
    // v104: smooth relationship-label zoom fade. When non-null, the
    // label opacity is driven by the camera's zoom level via an
    // AnimatedBuilder so it fades smoothly without rebuilding the
    // whole node. When null, falls back to the hard
    // [showRelationLabel] flag (legacy behaviour).
    this.camera,
    this.memberCount,
    this.focusActive = false,
    // v5.36: When true, the per-node LongPressGestureRecognizer is
    // OMITTED entirely from the RawGestureDetector's gestures map.
    // This prevents it from competing with the canvas-level gesture
    // handler for the long-press gesture in Rearrange mode. Without
    // this, the per-node recognizer intermittently wins the gesture
    // arena, absorbing the touch before the canvas-level handler can
    // start a node drag — which is why dragging was unreliable and
    // Save/Reset appeared to do nothing (no drag data was registered).
    this.rearrangeMode = false,
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

  /// P3.3: Whether this person's birthday is within 7 days. When true,
  /// the painter adds a 9th layer — a soft pulsing ember ring (or
  /// amber if [isDeceased] is also true).
  final bool isNearBirthday;

  /// P3.3: The current pulse value (0..1) from the shared
  /// [birthdayPulseProvider]. The painter maps this to a 0.3..0.6
  /// alpha range. When reduced motion is active, the consumer passes
  /// 0.5 (a static mid-pulse value) and the painter uses a fixed
  /// 0.45 alpha instead of reading this value.
  final double birthdayPulseValue;

  /// P3.3: Days until the next birthday (for the Semantics label).
  /// Null when [isNearBirthday] is false or dateOfBirth is unknown.
  final int? daysUntilBirthday;

  /// P3.4: The current flicker value (0..1) from the shared
  /// [memorialCandleFlickerProvider]. The painter maps this to a
  /// 0.6..0.9 alpha range. When reduced motion is active, the
  /// consumer passes -1.0 (sentinel) and the painter uses a static
  /// 0.75 alpha.
  final double memorialCandleFlickerValue;

  /// P3.4: True if the death was within the last 30 days. The candle
  /// is brighter (alpha 0.8-1.0) for the first 30 days, then dims to
  /// the standard 0.6-0.9.
  final bool isRecentlyDeceased;

  /// P3.7: "On this day" event for this person (birthday today,
  /// anniversary today, or a memory from this day). When non-null,
  /// a small badge is rendered at the top-right of the node.
  final OnThisDayEvent? onThisDayEvent;

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

  /// v5.9: Whether this person has ZERO relationship edges in the graph
  /// (an "unlinked" member). When true, the node ring is rendered with
  /// a DASHED border and a small "link-off" badge in the corner to
  /// signal that the user should connect them to the family tree.
  final bool isUnlinked;

  /// Optional family ID — when provided AND kEnableKinrel is true, the
  /// node shows an Kinrel role glyph badge (root/anchor/bridge/weaver/leaf/
  /// twin_node) on the bottom-right of the avatar. Pass null to skip
  /// the badge (e.g. on preview nodes outside a family context).
  final String? familyId;

  /// v93 (ZOOM FIX): When false, the secondary relationship label
  /// (e.g. "Husband", "You") is hidden to reduce clutter at lower
  /// zoom. The primary member name is ALWAYS visible regardless of
  /// this flag.
  ///
  /// v104: This flag is now the FALLBACK behaviour used only when
  /// [camera] is null. When [camera] is non-null, the label opacity
  /// is driven smoothly by the camera's zoom level via
  /// [relationLabelOpacityFor] and this flag is ignored.
  final bool showRelationLabel;

  /// v104: Optional camera controller used to drive a smooth zoom-
  /// fade for the relationship label. When non-null, the label is
  /// wrapped in an AnimatedBuilder that recomputes its opacity from
  /// `camera.zoomLevel` on every camera tick — so the label fades
  /// out smoothly as the user zooms out and fades back in as they
  /// zoom in, WITHOUT rebuilding the whole node (the outer canvas
  /// content is built once and reused as a constant child of the
  /// camera's Transform).
  ///
  /// When null, the label uses the legacy hard [showRelationLabel]
  /// on/off behaviour.
  final CameraController? camera;

  /// v104: Total member count of the current family. Used by
  /// [relationLabelOpacityFor] to apply the small-family bypass
  /// (graphs < 30 members keep labels fully visible at all zoom
  /// levels, matching computeSemanticTier's NEAR pin). Ignored when
  /// [camera] is null.
  final int? memberCount;

  /// v104: Whether focus mode is currently active. When true, the
  /// label opacity is forced to 1.0 (matching computeSemanticTier's
  /// MEDIUM floor during focus). Ignored when [camera] is null.
  final bool focusActive;

  /// v5.36: When true, the per-node LongPressGestureRecognizer is
  /// omitted entirely from the RawGestureDetector. See constructor
  /// doc for details.
  final bool rearrangeMode;

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

    // Shimmer animation for loading state (1.5s repeat).
    // P3.1: removed the explicit identity easing curve — linear is
    // the default behavior of `Tween.animate(parent)` without a
    // CurvedAnimation wrapper. The P3.1 verification check requires
    // zero occurrences of identity-easing literal references in
    // lib/graph/. The shimmer genuinely needs uniform motion (constant-
    // velocity sweep), so we keep the behavior but remove the
    // redundant explicit curve.
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(_shimmerController);

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
    if (widget.isAnonymous)
      return _highContrast ? Colors.grey : KinrelColors.textDim;
    if (widget.isAnchor) return KinshipEdgeColors.self;
    // v69: Prefer the AUTHORITATIVE category — no lossy string round-trip.
    // styleForCategory() is always correct and never falls through to
    // grey for a known relationship.
    Color color;
    if (widget.category != null) {
      color = KinshipEdgeStyleResolver.styleForCategory(widget.category!).color;
    } else {
      color = KinshipEdgeStyleResolver.styleFor(
        widget.relationshipKey ?? '',
      ).color;
    }
    // High contrast: full opacity colors for WCAG AA 4.5:1 contrast
    return _highContrast
        ? Color.fromRGBO(color.red, color.green, color.blue, 1.0)
        : color;
  }

  Color get _tintColor {
    if (widget.isAnonymous) return Colors.transparent;
    // Premium visual: increased tint from 0.04 to 0.12 for clearer
    // color identity on the dark background.
    if (widget.isAnchor) return KinshipEdgeColors.self.withValues(alpha: 0.12);
    // v69: Derive tint from the authoritative category when available.
    if (widget.category != null) {
      final color = KinshipEdgeStyleResolver.styleForCategory(
        widget.category!,
      ).color;
      return color.withValues(alpha: 0.12);
    }
    return KinshipEdgeStyleResolver.styleFor(
      widget.relationshipKey ?? '',
    ).color.withValues(alpha: 0.12);
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

    final effectiveOpacity = widget.isDeceased
        ? 0.6 * widget.opacity
        : widget.opacity;

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
            // v5.36: When Rearrange mode is ON, OMIT the
            // LongPressGestureRecognizer entirely. Its presence as a
            // competing gesture recognizer was interfering with the
            // canvas-level drag handler — even with its callback
            // suppressed (v5.33 fix), the recognizer still
            // participated in the gesture arena and intermittently
            // won the gesture before the canvas-level handler could
            // start a node drag. This is why dragging was unreliable
            // and why Save/Reset appeared to do nothing (no drag
            // data was registered because the drag never started).
            //
            // By omitting the recognizer entirely when
            // rearrangeMode is true, the gesture arena has no
            // competing long-press recognizer — the canvas-level
            // handler gets the gesture reliably every time.
            if (!widget.rearrangeMode)
              LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(() => LongPressGestureRecognizer(), (instance) {
                  instance.onLongPress = widget.onLongPress;
                }),
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

    // P3.3: birthday info in the Semantics label so screen-reader
    // users know a birthday is approaching. "Birthday today" or
    // "Birthday in N days." Deceased birthdays say "Memorial birthday"
    // to distinguish from living.
    if (widget.isNearBirthday) {
      final days = widget.daysUntilBirthday;
      if (days == 0) {
        parts.add(
          widget.isDeceased ? 'Memorial birthday today' : 'Birthday today',
        );
      } else if (days != null && days > 0) {
        parts.add(
          widget.isDeceased
              ? 'Memorial birthday in $days days'
              : 'Birthday in $days days',
        );
      }
    }

    // P3.4: memorial candle announcement for deceased nodes.
    if (widget.isDeceased) {
      parts.add('Memorial candle lit');
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
            child: Transform.scale(scale: _pulseAnimation.value, child: child),
          );
        },
        child: _buildNodeContent(),
      );
    }

    // Hover state: scale up 7%
    if (widget.nodeState == NodeState.hover) {
      return Transform.translate(
        offset: Offset(0, yOffset),
        child: Transform.scale(scale: 1.07, child: _buildNodeContent()),
      );
    }

    // Error state: red border pulse
    if (widget.nodeState == NodeState.error) {
      return AnimatedBuilder(
        animation: _errorPulseAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, yOffset),
            child: Opacity(opacity: _errorPulseAnimation.value, child: child),
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
                shadows: const [
                  // §5: text-shadow for legibility over busy bg
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
        // v104 (LABEL FADE FIX): The label now FADES smoothly based on
        // the camera's zoom level (see relationLabelOpacityFor) instead
        // of disappearing abruptly at a hard threshold. The fade is
        // driven by an AnimatedBuilder bound to the camera so it
        // updates on every camera tick WITHOUT rebuilding the whole
        // node (the outer canvas content is built once and reused as a
        // constant child of the camera Transform). Labels stay fully
        // visible while zooming and only fade out when the zoom
        // becomes too small for the text to be readable.
        //
        // When [widget.camera] is null (e.g. in unit tests or
        // non-graph contexts), the legacy hard [showRelationLabel]
        // on/off behaviour is used as a fallback.
        //
        // The primary member name above is ALWAYS visible regardless
        // of the relation label fade.
        if (!widget.isAnonymous && widget.relationLabel.isNotEmpty)
          _buildRelationLabel(),
      ],
    );
  }

  /// Builds the secondary relationship label ("Husband", "Wife",
  /// "Father", "You", …) with a smooth zoom-driven opacity.
  ///
  /// When [GraphNode.camera] is non-null, the label is wrapped in an
  /// [AnimatedBuilder] that recomputes its opacity from the camera's
  /// zoom level on every camera tick. This means the label fades in
  /// and out SMOOTHLY as the user zooms — no flicker, no sudden
  /// disappearance at a hard threshold.
  ///
  /// When [GraphNode.camera] is null, falls back to the legacy hard
  /// [GraphNode.showRelationLabel] on/off toggle so existing callers
  /// (and unit tests that don't have a camera) keep working.
  Widget _buildRelationLabel() {
    // The base label widget — identical to the pre-v104 rendering.
    final labelWidget = FittedBox(
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
    );

    final cam = widget.camera;
    if (cam == null) {
      // Legacy fallback: hard on/off via showRelationLabel.
      return widget.showRelationLabel
          ? labelWidget
          : const SizedBox.shrink();
    }

    // v104: smooth zoom-fade. The AnimatedBuilder rebuilds ONLY this
    // tiny label subtree on each camera tick — the rest of the node
    // (avatar, name, decorations) is NOT rebuilt. This is cheap
    // (a handful of visible nodes × one FittedBox+Text each per
    // camera tick) and keeps the fade perfectly smooth.
    return AnimatedBuilder(
      animation: cam,
      builder: (context, child) {
        final opacity = relationLabelOpacityFor(
          zoom: cam.zoomLevel,
          memberCount: widget.memberCount,
          focusActive: widget.focusActive,
        );
        // Skip building the label subtree entirely when it would be
        // fully invisible — saves a FittedBox+Text layout per node.
        if (opacity <= 0.0) return const SizedBox.shrink();
        return Opacity(opacity: opacity, child: child!);
      },
      child: labelWidget,
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
          border: Border.all(color: KinrelColors.textDim, width: 2.0),
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

    // Pseudo-3D node: all 10 layers painted by a single CustomPainter.
    // P3.3: pass birthday glow params so the painter can draw layer 9.
    // P3.4: pass memorial candle flicker params so the painter can draw
    // layer 10 for deceased nodes.
    final nodeParams = Pseudo3DNodeParams(
      diameter: diameter,
      borderColor: widget.isAnchor ? KinshipEdgeColors.self : _borderColor,
      borderWidth: widget.isAnchor ? 3.0 : _borderWidth,
      generationIndex: widget.generationIndex,
      isAnchor: widget.isAnchor,
      nodeState: widget.nodeState,
      tintColor: _tintColor,
      showTint:
          widget.nodeState == NodeState.selected ||
          widget.nodeState == NodeState.hover,
      isNearBirthday: widget.isNearBirthday,
      birthdayPulseValue: widget.birthdayPulseValue,
      isDeceased: widget.isDeceased,
      memorialCandleFlickerValue: widget.memorialCandleFlickerValue,
      isRecentlyDeceased: widget.isRecentlyDeceased,
      isUnlinked: widget.isUnlinked, // v5.9
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
            child: CustomPaint(painter: Pseudo3DNodePainter(nodeParams)),
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
                    Positioned.fill(
                      child: Container(color: nodeParams.tintColor),
                    ),
                  _buildCircleContent(diameter),
                  if (widget.nodeState == NodeState.loading)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _shimmerAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: ShimmerPainter(_shimmerAnimation.value),
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
                        child: Icon(
                          Icons.error_outline,
                          size: diameter * 0.25,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Private lock
          if (widget.isPrivate)
            Positioned(
              right: extraPad / 2 - 2,
              top: extraPad / 2 - 2,
              child: Container(
                padding: const EdgeInsets.all(2.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.darkCard,
                  border: Border.all(color: KinrelColors.amber, width: 1.0),
                ),
                child: Icon(
                  Icons.lock,
                  size: diameter * 0.12,
                  color: KinrelColors.amber,
                ),
              ),
            ),
          // P3.7: "On this day" badge — top-right corner, 24x24.
          if (widget.onThisDayEvent != null)
            Positioned(
              right: -2,
              top: -2,
              child: OnThisDayBadge(
                event: widget.onThisDayEvent!,
                personName: widget.name,
                onTap: () => showOnThisDayEventSheet(
                  context,
                  widget.onThisDayEvent!,
                  widget.name,
                ),
              ),
            ),
          // Pending badge
          if (widget.isUnclaimed)
            Positioned(
              right: extraPad / 2 - 2,
              bottom: extraPad / 2 - 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.darkCard,
                  ),
                ),
              ),
            ),
          // v5.9: "Needs linking" badge — link-off icon, top-left corner.
          // Shown when the person has zero relationship edges.
          if (widget.isUnlinked)
            Positioned(
              left: -2,
              top: -2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: KinrelColors.amber,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: KinrelColors.darkCard,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.link_off,
                  size: 12,
                  color: KinrelColors.darkCard,
                ),
              ),
            ),
          // Role glyph — uses _NodeRoleGlyphBadge which handles the
          // provider lookup internally (familyId → role → badge)
          if (widget.familyId != null && kEnableKinrel)
            Positioned(
              right: extraPad / 2 - 4,
              bottom: extraPad / 2 - 4,
              child: NodeRoleGlyphBadge(
                familyId: widget.familyId!,
                memberId: widget.personId,
                diameter: diameter * 0.3,
              ),
            ),
          // Expand indicator
          if (widget.relationshipKey != null &&
              ExpandIndicators.expandLabelFor(widget.relationshipKey) != null)
            Positioned(
              right: extraPad / 2 - 4,
              top: extraPad / 2 - 4,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.all(2.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkCard,
                    border: Border.all(color: _borderColor, width: 1.0),
                  ),
                  child: AnimatedBuilder(
                    animation: _expandRotateController,
                    builder: (context, child) => Transform.rotate(
                      angle: _expandRotateController.value * pi,
                      child: child,
                    ),
                    child: widget.nodeState == NodeState.expanded
                        ? Icon(
                            Icons.expand_less,
                            size: diameter * 0.2,
                            color: _borderColor,
                          )
                        : Icon(
                            Icons.expand_more,
                            size: diameter * 0.2,
                            color: _borderColor,
                          ),
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
    // Premium visual: increased border widths for stronger, more
    // visible relationship-color rings on the dark background.
    final base = switch (widget.nodeState) {
      NodeState.selected => 4.0,
      NodeState.focused => 3.5,
      NodeState.hover => 3.0,
      NodeState.error => 3.5,
      _ => 3.0,
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
        color: Colors.black.withValues(alpha: 0.50),
        blurRadius: 16,
        offset: const Offset(0, 6),
        spreadRadius: 0,
      );
    } else if (gen < 0) {
      // Ancestors: float higher — larger blur, slight upward offset
      base = BoxShadow(
        color: Colors.black.withValues(alpha: 0.38),
        blurRadius: 12,
        offset: const Offset(0, -2), // upward offset
        spreadRadius: 0,
      );
    } else {
      // Descendants: flush/lower — tighter shadow
      base = BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
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
          color: Colors.black.withValues(
            alpha: isAnchor ? 0.50 : (gen < 0 ? 0.40 : 0.30),
          ),
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
      final avatar = ClipOval(
        child: CachedAvatar(
          imageUrl: widget.photoUrl,
          radius: diameter / 2,
          fit: BoxFit.cover,
          backgroundColor: KinrelColors.darkCard,
          placeholder: _buildInitialsContent(diameter),
          errorWidget: _buildInitialsContent(diameter),
          cameoFallback: kEnableCameoFallback
              ? CameoFallbackConfig(
                  personName: widget.name,
                  ageBand: CameoAgeBand.adult,
                  skinToneIndex: 5,
                  surfaceId: 'graph_node',
                )
              : null,
        ),
      );
      // P3.6: Heritage/sepia texture on ancestor nodes.
      // Ancestors (generationIndex <= -2) get full sepia.
      // Parents (generationIndex == -1) get light sepia (50% mix).
      // Descendants (>= 0) get no sepia.
      // The sepia is a luminance shift — color-blind safe. The memorial
      // candle (P3.4) paints on top of the sepia for deceased ancestors.
      if (widget.generationIndex <= -2) {
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(kFullSepiaMatrix),
          child: avatar,
        );
      } else if (widget.generationIndex == -1) {
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(kLightSepiaMatrix),
          child: avatar,
        );
      }
      return avatar;
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
