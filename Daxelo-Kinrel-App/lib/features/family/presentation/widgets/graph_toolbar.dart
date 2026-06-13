// lib/features/family/presentation/widgets/graph_toolbar.dart
//
// DAXELO KINREL — Graph Toolbar (V2.1 K-Graph Blueprint)
//
// A floating bottom-center toolbar with zoom controls and action buttons
// for the family graph screen.

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// GRAPH TOOLBAR
// ═══════════════════════════════════════════════════════════════════════

/// A floating bottom-center toolbar providing zoom controls and graph actions.
///
/// Includes zoom in/out with a percentage display, a center/reset button,
/// and an optional add-member button.
///
/// Usage:
/// ```dart
/// GraphToolbar(
///   zoomLevel: 1.0,
///   onZoomIn: _zoomIn,
///   onZoomOut: _zoomOut,
///   onZoomReset: _resetZoom,
///   onCenterGraph: _centerGraph,
///   onAddMember: _addMember,
/// )
/// ```
class GraphToolbar extends StatelessWidget {
  /// Creates a [GraphToolbar].
  const GraphToolbar({
    super.key,
    required this.zoomLevel,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onCenterGraph,
    this.onAddMember,
  });

  /// Current zoom level where 1.0 = 100%.
  final double zoomLevel;

  /// Callback for zoom-in action.
  final VoidCallback onZoomIn;

  /// Callback for zoom-out action.
  final VoidCallback onZoomOut;

  /// Callback for zoom-reset action.
  final VoidCallback onZoomReset;

  /// Callback for center-graph action.
  final VoidCallback onCenterGraph;

  /// Optional callback for add-member action.
  /// If `null`, the add-member button is hidden.
  final VoidCallback? onAddMember;

  /// Formats the zoom level as a percentage string (e.g., "100%").
  String get _zoomLabel => '${(zoomLevel * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2A2A3D),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom out
                _ToolbarIconButton(
                  icon: Icons.zoom_out,
                  onPressed: onZoomOut,
                ),

                // Zoom percentage
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _zoomLabel,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: KinrelColors.textSilver,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),

                // Zoom in
                _ToolbarIconButton(
                  icon: Icons.zoom_in,
                  onPressed: onZoomIn,
                ),

                // Divider
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: const Color(0xFF2A2A3D),
                ),

                // Center / reset
                _ToolbarIconButton(
                  icon: Icons.center_focus_strong,
                  onPressed: onCenterGraph,
                ),

                // Add member (conditional)
                if (onAddMember != null) ...[
                  Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: const Color(0xFF2A2A3D),
                  ),
                  _ToolbarIconButton(
                    icon: Icons.person_add_outlined,
                    onPressed: onAddMember,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TOOLBAR ICON BUTTON (private)
// ═══════════════════════════════════════════════════════════════════════

/// A single icon button within the graph toolbar.
///
/// Shows a 40×40 touch target with a 20px silver icon that turns orange
/// on hover. The splash color is orange at 10% opacity.
class _ToolbarIconButton extends StatefulWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends State<_ToolbarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          onPressed: widget.onPressed,
          icon: Icon(
            widget.icon,
            size: 20,
            color: _isHovered
                ? KinrelColors.orange
                : KinrelColors.textSilver,
          ),
          splashColor: KinrelColors.orange.withValues(alpha: 0.10),
          highlightColor: KinrelColors.orange.withValues(alpha: 0.10),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
        ),
      ),
    );
  }
}
