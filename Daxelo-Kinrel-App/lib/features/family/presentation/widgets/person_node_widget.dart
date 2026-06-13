// lib/features/family/presentation/widgets/person_node_widget.dart
//
// DAXELO KINREL — Person Node Widget (V2.1 K-Graph Blueprint)
//
// A richly animated, relationship-colored person node for the family graph.
//
// Widget Layers (bottom → top):
//   Layer 1: Glow — RadialGradient pulse (self/selected/hovered)
//   Layer 2: Rotating Dashed Ring — DashedCirclePainter (selected)
//   Layer 3: Main Node Circle — Gradient fill, colored border, avatar
//   Layer 4: Self Badge — Teal ★ indicator (isSelf)
//   Layer 5: Deceased Indicator — Cloud icon (isDeceased)
//   Layer 6: Labels — Relationship key, name, Hindi kinship term
//   Layer 7: Info Card — MemberInfoCard (isSelected)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/animation_constants.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/graph_canvas_config.dart';
import '../../../../shared/utils/node_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// PERSON NODE WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A single person node in the K-Graph canvas, per the V2.1 Blueprint.
///
/// Supports glow, dashed-ring rotation, self badge, deceased indicator,
/// relationship labels, and an expandable info card.
class PersonNodeWidget extends ConsumerStatefulWidget {
  const PersonNodeWidget({
    super.key,
    required this.memberId,
    required this.name,
    this.avatarUrl,
    this.gender,
    this.relationshipKey,
    this.relationLabel,
    this.hindiLabel,
    this.username,
    required this.generationIndex,
    this.isSelf = false,
    this.isAnchor = false,
    this.isDeceased = false,
    required this.position,
    this.isSelected = false,
    this.isHovered = false,
    this.isDimmed = false,
    this.onTap,
    this.onHover,
    this.entryDelay,
  });

  final String memberId;
  final String name;
  final String? avatarUrl;
  final String? gender;
  final String? relationshipKey;
  final String? relationLabel;
  final String? hindiLabel;
  final String? username;
  final int generationIndex;
  final bool isSelf;
  final bool isAnchor;
  final bool isDeceased;
  final Offset position;
  final bool isSelected;
  final bool isHovered;
  final bool isDimmed;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final int? entryDelay;

  @override
  ConsumerState<PersonNodeWidget> createState() => _PersonNodeWidgetState();
}

class _PersonNodeWidgetState extends ConsumerState<PersonNodeWidget>
    with TickerProviderStateMixin {
  // ── Animation Controllers ─────────────────────────────────────────────

  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final AnimationController _entryController;

  // ── Derived Animations ────────────────────────────────────────────────

  late final Animation<double> _pulseAnimation;
  late final Animation<double> _entryFadeAnimation;
  late final Animation<Offset> _entrySlideAnimation;
  late final Animation<double> _entryScaleAnimation;

  // ── Info Card Animation ───────────────────────────────────────────────

  late final AnimationController _infoCardController;
  late final Animation<double> _infoFadeAnimation;
  late final Animation<Offset> _infoSlideAnimation;
  late final Animation<double> _infoScaleAnimation;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Pulse controller — 2500ms repeat reverse
    _pulseController = AnimationController(
      vsync: this,
      duration: GraphAnimations.selectedGlowPulseDuration,
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: GraphAnimations.pulseCurve,
      ),
    );

    // Rotation controller — 8000ms repeat
    _rotationController = AnimationController(
      vsync: this,
      duration: GraphAnimations.rotatingRingDuration,
    );

    // Entry controller — 600ms forward
    _entryController = AnimationController(
      vsync: this,
      duration: GraphAnimations.nodeEntryDuration,
    );
    _entryFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: GraphAnimations.entryCurve,
      ),
    );
    _entrySlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: GraphAnimations.entryCurve,
      ),
    );
    _entryScaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: GraphAnimations.entryCurve,
      ),
    );

    // Info card controller
    _infoCardController = AnimationController(
      vsync: this,
      duration: GraphAnimations.infoCardEntry,
    );
    _infoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _infoCardController,
        curve: GraphAnimations.infoCardCurve,
      ),
    );
    _infoSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _infoCardController,
        curve: GraphAnimations.infoCardCurve,
      ),
    );
    _infoScaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _infoCardController,
        curve: GraphAnimations.infoCardCurve,
      ),
    );

    // Start pulse for self or selected
    if (widget.isSelf || widget.isSelected) {
      _pulseController.repeat(reverse: true);
    }

    // Start rotation for selected
    if (widget.isSelected) {
      _rotationController.repeat();
      _infoCardController.forward();
    }

    // Stagger entry
    Future.delayed(
      Duration(milliseconds: widget.entryDelay ?? 0),
      () {
        if (mounted) _entryController.forward();
      },
    );
  }

  @override
  void didUpdateWidget(covariant PersonNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Pulse management
    final shouldPulse = widget.isSelf || widget.isSelected || widget.isHovered;
    final wasPulsing = oldWidget.isSelf || oldWidget.isSelected || oldWidget.isHovered;
    if (shouldPulse && !wasPulsing) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && wasPulsing) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }

    // Rotation management
    if (widget.isSelected && !oldWidget.isSelected) {
      _rotationController.repeat();
      _infoCardController.forward();
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _rotationController.stop();
      _rotationController.value = 0.0;
      _infoCardController.reverse();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _entryController.dispose();
    _infoCardController.dispose();
    super.dispose();
  }

  // ── Computed Values ───────────────────────────────────────────────────

  double get _nodeSize =>
      widget.isSelf || widget.isAnchor
          ? GraphCanvasConfig.selfNodeSize
          : GraphCanvasConfig.defaultNodeSize;

  NodeColorSet get _colors =>
      getNodeColors(relationshipTypeFromKey(widget.relationshipKey ?? '') ?? RelationshipType.extended);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final nodeSize = _nodeSize;

    return FadeTransition(
      opacity: _entryFadeAnimation,
      child: SlideTransition(
        position: _entrySlideAnimation,
        child: ScaleTransition(
          scale: _entryScaleAnimation,
          child: Opacity(
            opacity: widget.isDimmed ? 0.25 : 1.0,
            child: Material(
              color: Colors.transparent,
              child: MouseRegion(
                onEnter: (_) => widget.onHover?.call(true),
                onExit: (_) => widget.onHover?.call(false),
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // ── Node Circle Stack ────────────────────────────
                    SizedBox(
                      width: nodeSize + GraphCanvasConfig.glowExtent * 2,
                      height: nodeSize + GraphCanvasConfig.glowExtent * 2,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Layer 1: Glow
                          if (widget.isSelected ||
                              widget.isHovered ||
                              widget.isSelf)
                            _buildGlow(nodeSize, colors),

                          // Layer 2: Rotating Dashed Ring
                          if (widget.isSelected)
                            _buildDashedRing(nodeSize, colors),

                          // Layer 3: Main Node Circle
                          _buildMainCircle(nodeSize, colors),

                          // Layer 4: Self Badge
                          if (widget.isSelf)
                            _buildSelfBadge(nodeSize),

                          // Layer 5: Deceased Indicator
                          if (widget.isDeceased) _buildDeceasedBadge(nodeSize),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4.0),

                    // Layer 6: Labels
                    _buildLabels(colors),

                    // Layer 7: Info Card
                    if (widget.isSelected)
                      _MemberInfoCard(
                        name: widget.name,
                        username: widget.username,
                        avatarUrl: widget.avatarUrl,
                        gender: widget.gender,
                        relationLabel: widget.relationLabel,
                        hindiLabel: widget.hindiLabel,
                        generationIndex: widget.generationIndex,
                        isDeceased: widget.isDeceased,
                        ringColor: colors.ring,
                        fadeAnimation: _infoFadeAnimation,
                        slideAnimation: _infoSlideAnimation,
                        scaleAnimation: _infoScaleAnimation,
                        onTapProfile: widget.onTap,
                      ),
                  ], // Column children
                ), // Column
              ), // GestureDetector
            ), // MouseRegion
          ), // Material
        ), // Opacity
      ), // ScaleTransition
    ), // SlideTransition
    ); // FadeTransition
  }

  // ── Layer 1: Glow ─────────────────────────────────────────────────────

  Widget _buildGlow(double nodeSize, NodeColorSet colors) {
    final glowSize = nodeSize + 32.0;
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _pulseAnimation.value,
          child: Container(
            width: glowSize,
            height: glowSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colors.glow,
                  Colors.transparent,
                ],
                radius: 0.6,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Layer 2: Rotating Dashed Ring ─────────────────────────────────────

  Widget _buildDashedRing(double nodeSize, NodeColorSet colors) {
    final ringSize = nodeSize + 12.0;
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationController.value * 2 * math.pi,
          child: child,
        );
      },
      child: SizedBox(
        width: ringSize,
        height: ringSize,
        child: CustomPaint(
          painter: DashedCirclePainter(
            color: colors.ring.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashRatio: 0.25,
          ),
        ),
      ),
    );
  }

  // ── Layer 3: Main Node Circle ─────────────────────────────────────────

  Widget _buildMainCircle(double nodeSize, NodeColorSet colors) {
    final borderColor = widget.isSelected
        ? colors.ring
        : widget.isHovered
            ? colors.ring
            : colors.ring.withValues(alpha: 0.5);
    final borderWidth = widget.isSelected
        ? GraphCanvasConfig.selectedRingWidth
        : widget.isHovered
            ? GraphCanvasConfig.hoveredRingWidth
            : GraphCanvasConfig.defaultRingWidth;

    return Container(
      width: nodeSize,
      height: nodeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.background.withValues(alpha: 0.15),
            const Color(0xFF13141E),
          ],
        ),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: [
          // Glow shadow
          BoxShadow(
            color: colors.glow,
            blurRadius: 12.0,
            spreadRadius: 2.0,
          ),
          // Dark depth shadow
          const BoxShadow(
            color: Colors.black38,
            blurRadius: 8.0,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: _buildAvatarContent(nodeSize, colors),
    );
  }

  Widget _buildAvatarContent(double nodeSize, NodeColorSet colors) {
    if (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          widget.avatarUrl!,
          width: nodeSize,
          height: nodeSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildPlaceholderAvatar(colors),
        ),
      );
    }
    return _buildPlaceholderAvatar(colors);
  }

  Widget _buildPlaceholderAvatar(NodeColorSet colors) {
    return Center(
      child: Icon(
        Icons.person,
        size: _nodeSize * 0.4,
        color: colors.ring.withValues(alpha: 0.7),
      ),
    );
  }

  // ── Layer 4: Self Badge ───────────────────────────────────────────────

  Widget _buildSelfBadge(double nodeSize) {
    const badgeSize = GraphCanvasConfig.badgeSize;
    return Positioned(
      right: 0,
      bottom: 0,
      child: Container(
        width: badgeSize,
        height: badgeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF0D9488), Color(0xFF0f766e)],
          ),
          border: Border.all(
            color: const Color(0xFF13141E),
            width: GraphCanvasConfig.badgeBorderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D9488).withValues(alpha: 0.4),
              blurRadius: 8.0,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          '★',
          style: TextStyle(
            fontSize: 10.0,
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  // ── Layer 5: Deceased Indicator ────────────────────────────────────────

  Widget _buildDeceasedBadge(double nodeSize) {
    return Positioned(
      left: 0,
      top: 0,
      child: Container(
        width: 14.0,
        height: 14.0,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: KinrelColors.darkElevated,
          border: Border.all(
            color: KinrelColors.border,
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.cloud_outlined,
          size: 8.0,
          color: KinrelColors.textDim,
        ),
      ),
    );
  }

  // ── Layer 6: Labels ───────────────────────────────────────────────────

  Widget _buildLabels(NodeColorSet colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Relationship key label
        if (widget.relationshipKey != null &&
            widget.relationshipKey!.isNotEmpty)
          Text(
            widget.relationshipKey!.toUpperCase().replaceAll('_', ' '),
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10.0,
              fontWeight: FontWeight.bold,
              color: colors.ring,
              letterSpacing: 0.5,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 2.0),
        // Name
        Text(
          widget.name,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10.0,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textWhite.withValues(alpha: 0.6),
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Hindi label
        if (widget.hindiLabel != null && widget.hindiLabel!.isNotEmpty) ...[
          const SizedBox(height: 2.0),
          Text(
            widget.hindiLabel!,
            style: TextStyle(
              fontFamily: 'NotoSansDevanagari',
              fontSize: 9.0,
              fontWeight: FontWeight.w400,
              color: KinrelColors.textWhite.withValues(alpha: 0.25),
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DASHED CIRCLE PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that draws a dashed circle.
///
/// [dashRatio] defines what fraction of the circumference each dash
/// occupies. The gap fraction is `1 - dashRatio`.
class DashedCirclePainter extends CustomPainter {
  DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashRatio,
  });

  final Color color;
  final double strokeWidth;
  final double dashRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Calculate number of dashes from dashRatio
    // Each dash + gap = 1 unit; dash = dashRatio, gap = 1 - dashRatio
    // We want the dashes to tile the full circumference
    final dashCount = (2 * math.pi * radius * dashRatio / (strokeWidth * 2))
        .floor()
        .clamp(4, 60);
    final totalAngle = 2 * math.pi;
    final dashAngle = totalAngle * dashRatio / dashCount;
    final gapAngle = totalAngle * (1 - dashRatio) / dashCount;

    final path = Path();
    double startAngle = 0.0;

    for (int i = 0; i < dashCount; i++) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      path.addArc(rect, startAngle, dashAngle);
      startAngle += dashAngle + gapAngle;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DashedCirclePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashRatio != dashRatio;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MEMBER INFO CARD (Layer 7)
// ═══════════════════════════════════════════════════════════════════════

/// Expandable info card shown below the labels when a node is selected.
///
/// Displays avatar, name, username, relationship info, generation,
/// deceased status, and action buttons.
class _MemberInfoCard extends StatelessWidget {
  const _MemberInfoCard({
    required this.name,
    this.username,
    this.avatarUrl,
    this.gender,
    this.relationLabel,
    this.hindiLabel,
    required this.generationIndex,
    required this.isDeceased,
    required this.ringColor,
    required this.fadeAnimation,
    required this.slideAnimation,
    required this.scaleAnimation,
    this.onTapProfile,
  });

  final String name;
  final String? username;
  final String? avatarUrl;
  final String? gender;
  final String? relationLabel;
  final String? hindiLabel;
  final int generationIndex;
  final bool isDeceased;
  final Color ringColor;
  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final Animation<double> scaleAnimation;
  final VoidCallback? onTapProfile;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: ScaleTransition(
          scale: scaleAnimation,
          child: SizedBox(
            width: 220.0,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Arrow at top center
                Positioned(
                  top: -6.0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(
                        width: 12.0,
                        height: 12.0,
                        decoration: BoxDecoration(
                          color: const Color(0xFF131424).withValues(alpha: 0.97),
                          border: Border(
                            top: BorderSide(
                              color: ringColor.withValues(alpha: 0.2),
                              width: 1.0,
                            ),
                            left: BorderSide(
                              color: ringColor.withValues(alpha: 0.2),
                              width: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Card body
                Container(
                  margin: const EdgeInsets.only(top: 6.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131424).withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: ringColor.withValues(alpha: 0.2),
                      width: 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xB3000000), // rgba(0,0,0,0.7)
                        blurRadius: 48.0,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x08FFFFFF), // inset 0 1px 0 rgba(255,255,255,0.03)
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Avatar + Name Row ─────────────────────
                          Row(
                            children: [
                              _buildMiniAvatar(),
                              const SizedBox(width: 10.0),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                        color: KinrelColors.textWhite,
                                        decoration: TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (username != null &&
                                        username!.isNotEmpty)
                                      Text(
                                        '@$username',
                                        style: TextStyle(
                                          fontFamily:
                                              KinrelTypography.monoFont,
                                          fontSize: 10.0,
                                          fontWeight: FontWeight.w400,
                                          color: KinrelColors.textDim,
                                          decoration: TextDecoration.none,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10.0),

                          // ── Divider ────────────────────────────────
                          Container(
                            height: 1.0,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),

                          const SizedBox(height: 10.0),

                          // ── Relationship Row ──────────────────────
                          if (relationLabel != null)
                            Row(
                              children: [
                                Container(
                                  width: 8.0,
                                  height: 8.0,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ringColor,
                                  ),
                                ),
                                const SizedBox(width: 8.0),
                                Expanded(
                                  child: Text(
                                    hindiLabel != null
                                        ? '$relationLabel · $hindiLabel'
                                        : relationLabel!,
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w400,
                                      color: KinrelColors.textSilver,
                                      decoration: TextDecoration.none,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 8.0),

                          // ── Generation Row ─────────────────────────
                          Row(
                            children: [
                              Icon(
                                Icons.cake_outlined,
                                size: 14.0,
                                color: KinrelColors.textDim,
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                'Gen $generationIndex',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w400,
                                  color: KinrelColors.textDim,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),

                          // ── Deceased Row ───────────────────────────
                          if (isDeceased) ...[
                            const SizedBox(height: 8.0),
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_outlined,
                                  size: 14.0,
                                  color: KinrelColors.textDim,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Deceased',
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w400,
                                    color: KinrelColors.textDim,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 12.0),

                          // ── Action Buttons ─────────────────────────
                          Row(
                            children: [
                              _ActionButton(
                                label: 'View Profile',
                                color: KinrelColors.orange,
                                onTap: onTapProfile,
                              ),
                              const SizedBox(width: 16.0),
                              _ActionButton(
                                label: 'Edit',
                                color: KinrelColors.textDim,
                                onTap: () {
                                  context.push('/member/${widget.memberId}');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniAvatar() {
    const double size = 24.0;
    final borderColor = gender == 'male'
        ? KinrelColors.blue
        : gender == 'female'
            ? KinrelColors.coral
            : KinrelColors.textDim;

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            avatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildInitialsAvatar(size, borderColor),
          ),
        ),
      );
    }

    return _buildInitialsAvatar(size, borderColor);
  }

  Widget _buildInitialsAvatar(double size, Color borderColor) {
    final initials = _getInitials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.darkElevated,
        border: Border.all(
          color: borderColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 9.0,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textWhite,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  static String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ACTION BUTTON (inside Info Card)
// ═══════════════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11.0,
          fontWeight: FontWeight.w600,
          color: color,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
