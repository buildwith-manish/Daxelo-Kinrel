// lib/features/family/presentation/widgets/stats_panel.dart
//
// DAXELO KINREL — Stats Panel (V2.1 K-Graph Blueprint)
//
// A small bottom-left stats panel showing graph metrics: member count,
// connection count, generation count, and an optional truncation warning.

import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/utils/device_tier.dart';

// ═══════════════════════════════════════════════════════════════════════
// STATS PANEL
// ═══════════════════════════════════════════════════════════════════════

/// A compact bottom-left stats panel displaying graph metrics.
///
/// Shows total members, connections (links), and generations. When the
/// graph is truncated (too many nodes to render), a "TRUNCATED" warning
/// is displayed in amber.
///
/// Usage:
/// ```dart
/// Positioned(
///   left: 16,
///   bottom: 80,
///   child: StatsPanel(
///     totalMembers: 42,
///     totalConnections: 58,
///     totalGenerations: 4,
///     isTruncated: false,
///   ),
/// )
/// ```
class StatsPanel extends StatelessWidget {
  /// Creates a [StatsPanel].
  const StatsPanel({
    super.key,
    required this.totalMembers,
    required this.totalConnections,
    required this.totalGenerations,
    required this.fullFamilyMembers,
    this.isTruncated = false,
    this.onViewAllMembers,
    this.familyId,
  });

  /// Number of members currently expanded/visible in the graph view.
  /// Used for the MEMBERS stat row. Changes as branches are
  /// expanded or collapsed.
  final int totalMembers;

  /// Number of connections (edges) currently visible — both endpoints
  /// in the disclosed set. Used for the LINKS stat row.
  final int totalConnections;

  /// Number of distinct generations among the disclosed members.
  /// Used for the GENS stat row.
  final int totalGenerations;

  /// v5.x (stats-panel fix): The TOTAL number of members in the entire
  /// family (all 714, regardless of how much of the tree is currently
  /// expanded on screen). Used ONLY for the "View all X" button label.
  /// This is distinct from [totalMembers] (which is the disclosed
  /// count) so the button always shows the grand total while the stat
  /// rows show the currently-visible count.
  final int fullFamilyMembers;

  /// Whether the graph is truncated (too many nodes to display fully).
  final bool isTruncated;

  /// v5.114: Callback when the user taps "View all members".
  /// Opens the full-family list/search view.
  final VoidCallback? onViewAllMembers;

  /// v5.114: The family ID, used for navigation to the list view.
  final String? familyId;

  @override
  Widget build(BuildContext context) {
    // v42 FIX: Removed Material(color: Colors.transparent) wrapper.
    // Material with transparent color creates a broken compositing layer
    // on Android that can hide the child. The Container already has an
    // explicit opaque color (KinrelColors.darkCard) and its own decoration,
    // so no Material wrapper is needed.
    // PERF (Part E3): read lowRam ONCE per build. Strong phones
    // (lowRam == false) get the ORIGINAL frosted-glass look
    // (BackdropFilter sigma 16 + alpha 0.55). Low-RAM phones keep
    // the solid look from PR 82 (alpha 0.9, no blur). Per the
    // QUALITY RULE, this is the only place where the look differs.
    //
    // PERF (raster audit Tier A1): on Flutter Web the BackdropFilter
    // re-rasterizes the entire backdrop on every parent repaint —
    // measured at 151.7 ms/frame on the Family Insights modal. Web
    // now skips the blur entirely and uses an opaque solid color
    // (alpha 0.92) which is visually equivalent at the panel's small
    // size and ~0 ms raster cost. Native keeps the original branch.
    final bool lowRam = DeviceTierCache.instance.lowRam;
    final bool skipBlur = lowRam || kIsWeb;
    // §3: Frosted glass panel instead of flat navy box (strong-phone branch)
    final Widget content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard
            .withValues(alpha: skipBlur ? 0.92 : 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            // PERF (Tier A2): clamp blur radius on web — large blur
            // triggers saveLayer per shadow. 8 px is visually
            // equivalent at 1x DPR and ~3x cheaper to rasterize.
            blurRadius: kIsWeb ? 8 : 20,
            offset: kIsWeb ? const Offset(0, 4) : const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(label: 'MEMBERS', value: '$totalMembers'),
          const SizedBox(height: 6),
          _StatRow(label: 'LINKS', value: '$totalConnections'),
          const SizedBox(height: 6),
          _StatRow(label: 'GENS', value: '$totalGenerations'),
          if (isTruncated) ...[
            const SizedBox(height: 8),
            _TruncatedWarning(),
          ],
          // v5.114: "View all members" button — opens the full-family
          // list/search view. This is where "show me everyone" goes.
          if (onViewAllMembers != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onViewAllMembers,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt,
                        size: 12, color: KinrelColors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'View all $fullFamilyMembers',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.orange,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      // PERF (Part E3): on strong phones (lowRam == false), wrap the
      // panel in a BackdropFilter with sigma 16 — restoring the original
      // frosted-glass look from BEFORE PR 82. On low-RAM phones, skip the
      // BackdropFilter entirely (PR 82 look) since the blur is the
      // heaviest raster cost on this panel.
      //
      // PERF (Tier A1): on Flutter Web, also skip the BackdropFilter —
      // it forces a per-frame saveLayer + backdrop sample and shows up
      // as 151.7 ms/frame in DevTools. Web uses an opaque Container
      // (alpha 0.92) which is visually equivalent at small panel sizes.
      child: skipBlur
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: content,
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STAT ROW (private)
// ═══════════════════════════════════════════════════════════════════════

/// A single row of the stats panel with a label and right-aligned value.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label — 9px, semibold, muted, uppercase, wide tracking.
        // v5.123 (RENDERFLEX FIX): plain Text, NOT Expanded — the panel
        // is content-sized (Positioned with only left+bottom inside the
        // graph Stack gives unbounded width), and an Expanded child
        // under unbounded width throws
        // "RenderFlex children have non-zero flex but incoming width
        // constraints are unbounded" in debug builds. In release builds
        // the Expanded degrades to intrinsic sizing anyway (label then
        // value inline), so this matches the shipped visual exactly.
        Text(
          label,
          style: const TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textDim,
            letterSpacing: 0.15 * 9, // 0.15em at 9px = ~1.35
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(width: 12),
        // Value — 14px, bold, primary, tabular figures
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textPrimary.withValues(alpha: 0.9),
            fontFeatures: const [FontFeature.tabularFigures()],
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TRUNCATED WARNING (private)
// ═══════════════════════════════════════════════════════════════════════

/// An amber "TRUNCATED" warning indicator shown when the graph is truncated.
class _TruncatedWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: KinrelColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: KinrelColors.warning,
          ),
          SizedBox(width: 4),
          Text(
            'TRUNCATED',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: KinrelColors.warning,
              letterSpacing: 1.35, // 0.15em at 9px
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
