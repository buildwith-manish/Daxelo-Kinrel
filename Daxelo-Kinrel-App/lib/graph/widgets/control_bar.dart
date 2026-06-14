// lib/graph/widgets/control_bar.dart
//
// DAXELO KINREL — Graph Control Bar (V2.1 Blueprint §§9.3, 9.4, 17)
//
// A bottom control bar for graph actions including:
//   - Fit to View, Zoom In/Out, Center on Self
//   - Filter button (with badge when filters active)
//   - Legend toggle button
//   - Engine Tier indicator (only when NOT on Tier 1)
//   - Offline badge (when connectivity is lost)
//
// Pill-shaped container with dark semi-transparent background.
// Wrapped in RepaintBoundary for rendering isolation.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../engine/fallback_manager.dart';
import 'filter_panel.dart';

// ═══════════════════════════════════════════════════════════════════════
// CONNECTIVITY PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Provider that watches connectivity status via connectivity_plus.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Provider that returns true when the device is online.
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (results) => results.any((r) => r != ConnectivityResult.none),
    loading: () => true, // Assume online until we know otherwise
    error: (_, __) => true,
  );
});

// ═══════════════════════════════════════════════════════════════════════
// GRAPH CONTROL BAR
// ═══════════════════════════════════════════════════════════════════════

/// A bottom control bar for graph actions.
///
/// Provides camera controls, filter toggle, legend toggle, engine tier
/// indicator, and offline status badge. Pill-shaped floating container
/// with dark semi-transparent background.
class GraphControlBar extends ConsumerWidget {
  /// Creates a graph control bar.
  const GraphControlBar({
    super.key,
    required this.cameraController,
    required this.onFilterTap,
    required this.onLegendTap,
    required this.isFilterActive,
    required this.currentTier,
  });

  /// The camera controller for zoom/fit/focus operations.
  final dynamic cameraController;

  /// Callback when the filter button is tapped.
  final VoidCallback onFilterTap;

  /// Callback when the legend button is tapped.
  final VoidCallback onLegendTap;

  /// Whether any filter is currently active (shows badge).
  final bool isFilterActive;

  /// The current engine tier.
  final EngineTier currentTier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final showTierIndicator = currentTier != EngineTier.force;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;

    return RepaintBoundary(
      child: Positioned(
        bottom: isCompact
            ? MediaQuery.of(context).padding.bottom + 8
            : MediaQuery.of(context).padding.bottom + 16,
        left: 16,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: KinrelColors.border.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fit to View
              _buildButton(
                icon: Icons.fit_screen_outlined,
                label: 'Fit',
                onTap: () => _fitToView(),
              ),

              // Zoom In
              _buildButton(
                icon: Icons.add,
                label: 'In',
                onTap: () => _zoomIn(),
              ),

              // Zoom Out
              _buildButton(
                icon: Icons.remove,
                label: 'Out',
                onTap: () => _zoomOut(),
              ),

              // Center on Self
              _buildButton(
                icon: Icons.my_location_outlined,
                label: 'Self',
                onTap: () => _focusOnSelf(),
              ),

              // Divider
              Container(
                width: 1,
                height: 24,
                color: KinrelColors.border,
              ),

              // Filter
              _buildFilterButton(),

              // Legend
              _buildButton(
                icon: Icons.help_outline,
                label: 'Legend',
                onTap: onLegendTap,
              ),

              // Engine Tier indicator (only when not on Tier 1)
              if (showTierIndicator) ...[
                Container(
                  width: 1,
                  height: 24,
                  color: KinrelColors.border,
                ),
                _buildTierChip(),
              ],

              // Offline badge
              if (!isOnline) ...[
                Container(
                  width: 1,
                  height: 24,
                  color: KinrelColors.border,
                ),
                _buildOfflineBadge(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Button Builder ───────────────────────────────────────────────────

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          icon: Icon(icon, size: 18, color: KinrelColors.textSilver),
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          splashRadius: 18,
        ),
      ),
    );
  }

  // ── Filter Button (with badge) ───────────────────────────────────────

  Widget _buildFilterButton() {
    return Tooltip(
      message: 'Filter',
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                size: 18,
                color: isFilterActive
                    ? const Color(0xFF0D9488)
                    : KinrelColors.textSilver,
              ),
              onPressed: onFilterTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              splashRadius: 18,
            ),
            if (isFilterActive)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D9488),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Engine Tier Chip ─────────────────────────────────────────────────

  Widget _buildTierChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D9488).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF0D9488).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        currentTier.label,
        style: const TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0D9488),
        ),
      ),
    );
  }

  // ── Offline Badge ────────────────────────────────────────────────────

  Widget _buildOfflineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: KinrelColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: KinrelColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 12,
            color: KinrelColors.warning,
          ),
          const SizedBox(width: 4),
          const Text(
            'Offline · cached',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: KinrelColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  // ── Camera Actions ───────────────────────────────────────────────────

  void _fitToView() {
    try {
      (cameraController as dynamic).fitToView();
    } catch (_) {
      // Camera controller may not implement fitToView in all contexts
    }
  }

  void _zoomIn() {
    try {
      (cameraController as dynamic).zoomIn();
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      (cameraController as dynamic).zoomOut();
    } catch (_) {}
  }

  void _focusOnSelf() {
    try {
      (cameraController as dynamic).focusOnSelf();
    } catch (_) {}
  }
}
