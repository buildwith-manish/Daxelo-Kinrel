// lib/graph/widgets/empty_state.dart
//
// DAXELO KINREL — Empty State Widget
//
// State-dependent rendering for 0-member through 15+ member states.
//
// Design principle: "Every empty state is an opportunity to guide,
// not a failure." Transitions from empty to populated feel rewarding,
// not corrective. Animated transitions between states.
//
// States:
//   0 members: Illustrated welcome with family icon and tagline.
//     Primary: "Add Yourself" button.
//     Secondary: "Import contacts", "Invite family"
//   1 member (self): Single node (teal glow) centered, subtle pulse.
//     Primary: "Add Parent" / "Add Spouse" quick-action chips.
//     Secondary: "Import contacts", "Share invite"
//   2-3 members: Small graph with 2-3 nodes/edges.
//     Primary: "Add more family" tooltip.
//     Secondary: dismissible contextual banner
//   4-14 members: Standard Level 1 graph. Legend auto-opens 5s on first visit.
//   15+ members: Full Level 1. All features. No onboarding.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import 'graph_node.dart';

// ═══════════════════════════════════════════════════════════════════════
// EMPTY STATE WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// State-dependent empty state widget for the family graph.
///
/// Renders different content based on [memberCount]:
/// - 0: Illustrated welcome screen with "Add Yourself" CTA
/// - 1: Single centered node with quick-action chips
/// - 2-3: Small graph with "Add more family" tooltip
/// - 4+: No empty state shown (graph takes over)
///
/// Usage:
/// ```dart
/// EmptyState(
///   familyId: 'family-123',
///   memberCount: 0,
///   onAddMember: () => navigateToAddMember(),
/// )
/// ```
class EmptyState extends ConsumerStatefulWidget {
  const EmptyState({
    super.key,
    required this.familyId,
    required this.memberCount,
    required this.onAddMember,
  });

  /// The family ID for context.
  final String familyId;

  /// Current member count — determines which empty state to show.
  final int memberCount;

  /// Callback when the user taps "Add" actions.
  final VoidCallback onAddMember;

  @override
  ConsumerState<EmptyState> createState() => _EmptyStateWidgetState();
}

class _EmptyStateWidgetState extends ConsumerState<EmptyState>
    with TickerProviderStateMixin {
  // ── Animation Controllers ───────────────────────────────────────────

  late final AnimationController _pulseController;
  late final AnimationController _fadeController;

  late final Animation<double> _pulseAnimation;
  late final Animation<double> _fadeAnimation;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Pulse animation for the single-node state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade-in animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _pulseController.repeat(reverse: true);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 4+ members: no empty state needed
    if (widget.memberCount >= 4) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: widget.memberCount == 0
            ? _buildZeroMembers()
            : widget.memberCount == 1
                ? _buildOneMember()
                : _buildTwoToThreeMembers(),
      ),
    );
  }

  // ── 0 Members: Illustrated Welcome ─────────────────────────────────

  Widget _buildZeroMembers() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Illustrated family icon
          _buildFamilyIcon(),

          const SizedBox(height: 32.0),

          // Tagline
          Text(
            'Start your family tree.',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24.0,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12.0),

          // Subtitle
          Text(
            'Build your family graph by adding yourself first.',
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15.0,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32.0),

          // Primary CTA: Add Yourself
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onAddMember,
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: KinrelColors.textWhite,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.0),
                ),
                elevation: 0,
              ),
              child: Text(
                'Add Yourself',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12.0),

          // Secondary actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Import contacts flow
                  },
                  icon: const Icon(Icons.contacts_outlined, size: 18.0),
                  label: const Text(
                    'Import contacts',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13.0,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.textSilver,
                    side: const BorderSide(color: KinrelColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Invite family flow
                  },
                  icon: const Icon(Icons.person_add_outlined, size: 18.0),
                  label: const Text(
                    'Invite family',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13.0,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.textSilver,
                    side: const BorderSide(color: KinrelColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 1 Member: Single Centered Node ────────────────────────────────

  Widget _buildOneMember() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Single node with teal glow and subtle pulse
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: child,
              );
            },
            child: Container(
              width: 88.0,
              height: 88.0,
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
                  BoxShadow(
                    color: RelationshipColors.self.withValues(alpha: 0.15),
                    blurRadius: 20.0,
                    spreadRadius: 12.0,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.person,
                  size: 36.0,
                  color: RelationshipColors.self,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8.0),

          Text(
            'You',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),

          const SizedBox(height: 28.0),

          // Primary quick-action chips
          Text(
            'Add your first family member',
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14.0,
              color: KinrelColors.textSilver,
            ),
          ),

          const SizedBox(height: 16.0),

          // Quick-action chips row
          Wrap(
            spacing: 10.0,
            runSpacing: 10.0,
            alignment: WrapAlignment.center,
            children: [
              _buildActionChip(
                label: 'Add Parent',
                icon: Icons.arrow_upward,
                color: RelationshipColors.parent,
                onTap: widget.onAddMember,
              ),
              _buildActionChip(
                label: 'Add Spouse',
                icon: Icons.favorite_outline,
                color: RelationshipColors.spouse,
                onTap: widget.onAddMember,
              ),
              _buildActionChip(
                label: 'Add Sibling',
                icon: Icons.people_outline,
                color: RelationshipColors.sibling,
                onTap: widget.onAddMember,
              ),
            ],
          ),

          const SizedBox(height: 20.0),

          // Secondary actions
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTextButton('Import contacts', Icons.contacts_outlined),
              const SizedBox(width: 16.0),
              _buildTextButton('Share invite', Icons.share_outlined),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2-3 Members: Small Graph with Tooltip ──────────────────────────

  Widget _buildTwoToThreeMembers() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Small graph illustration
          _buildSmallGraphIllustration(),

          const SizedBox(height: 24.0),

          // "Add more family" tooltip
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 18.0,
                  color: KinrelColors.orange,
                ),
                const SizedBox(width: 8.0),
                Text(
                  'Add more family members',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12.0),

          // Contextual banner (dismissible)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16.0,
                  color: KinrelColors.orange,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Tap any node to see details, or tap + to add members.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.0,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Illustrations ──────────────────────────────────────────────────

  /// Illustrated family icon for the 0-member state.
  Widget _buildFamilyIcon() {
    return Container(
      width: 120.0,
      height: 120.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.orange.withValues(alpha: 0.08),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
          width: 2.0,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.family_restroom,
          size: 56.0,
          color: KinrelColors.orange.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  /// Small graph illustration for the 2-3 member state.
  Widget _buildSmallGraphIllustration() {
    return SizedBox(
      width: 200.0,
      height: 100.0,
      child: CustomPaint(
        painter: _SmallGraphIllustrationPainter(
          nodeCount: widget.memberCount,
        ),
      ),
    );
  }

  // ── Helper Widgets ─────────────────────────────────────────────────

  /// Builds a quick-action chip with colored icon.
  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16.0, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13.0,
          fontWeight: FontWeight.w500,
          color: KinrelColors.textWhite,
        ),
      ),
      backgroundColor: KinrelColors.darkElevated,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
    );
  }

  /// Builds a text button for secondary actions.
  Widget _buildTextButton(String label, IconData icon) {
    return TextButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 16.0, color: KinrelColors.textDim),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13.0,
          color: KinrelColors.textDim,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SMALL GRAPH ILLUSTRATION PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that draws a simplified graph illustration for the
/// 2-3 member empty state.
class _SmallGraphIllustrationPainter extends CustomPainter {
  _SmallGraphIllustrationPainter({required this.nodeCount});

  final int nodeCount;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeRadius = 16.0;
    final center = Offset(size.width / 2, size.height / 2);

    // Paints
    final linePaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = KinrelColors.darkElevated
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = RelationshipColors.self
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (nodeCount >= 2) {
      // Node 1: center (self)
      final node1 = center;

      // Node 2: above (parent/spouse)
      final node2 = Offset(center.dx, center.dy - 50.0);

      // Draw connecting line
      canvas.drawLine(
        Offset(node1.dx, node1.dy - nodeRadius),
        Offset(node2.dx, node2.dy + nodeRadius),
        linePaint,
      );

      // Draw node 2
      canvas.drawCircle(node2, nodeRadius, nodePaint);
      canvas.drawCircle(
        node2,
        nodeRadius,
        Paint()
          ..color = RelationshipColors.parent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // Draw node 1 (self — teal)
      canvas.drawCircle(node1, nodeRadius, nodePaint);
      canvas.drawCircle(node1, nodeRadius, borderPaint);
    }

    if (nodeCount >= 3) {
      // Node 3: to the right (sibling/spouse)
      final node3 = Offset(center.dx + 60.0, center.dy - 25.0);

      // Draw connecting line from node 1 to node 3
      canvas.drawLine(
        Offset(center.dx + nodeRadius, center.dy),
        Offset(node3.dx - nodeRadius, node3.dy),
        linePaint,
      );

      // Draw node 3
      canvas.drawCircle(node3, nodeRadius, nodePaint);
      canvas.drawCircle(
        node3,
        nodeRadius,
        Paint()
          ..color = RelationshipColors.sibling
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // Always draw self node last (on top)
    if (nodeCount >= 2) {
      canvas.drawCircle(center, nodeRadius, nodePaint);
      canvas.drawCircle(center, nodeRadius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmallGraphIllustrationPainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount;
  }
}
