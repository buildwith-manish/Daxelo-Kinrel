// lib/graph/widgets/graph_tutorial_overlay.dart
//
// DAXELO KINREL — First-Launch Graph Tutorial Overlay
//
// Shows a one-time overlay on first graph view explaining:
//   1. Pinch to zoom
//   2. Drag to pan
//   3. Tap a person for details
//   4. Long-press for quick actions
//   5. Use the search icon to find people
//
// Dismissed globally (not per-family) via SharedPreferences key
// 'graph_tutorial_shown'. Once dismissed, never shows again on any
// family — existing or future.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';

/// One-time tutorial overlay shown on the first graph view.
///
/// Checks SharedPreferences for 'graph_tutorial_shown'. If absent,
/// shows a semi-transparent overlay with 4 gesture hints. Tapping
/// "Got it" persists the flag and never shows again.
class GraphTutorialOverlay extends StatefulWidget {
  const GraphTutorialOverlay({
    super.key,
    required this.child,
  });

  /// The graph widget tree to overlay on top of.
  final Widget child;

  @override
  State<GraphTutorialOverlay> createState() => _GraphTutorialOverlayState();
}

class _GraphTutorialOverlayState extends State<GraphTutorialOverlay> {
  static const _prefKey = 'graph_tutorial_shown';
  bool _visible = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool(_prefKey) ?? false;
      if (mounted && !shown) {
        setState(() {
          _visible = true;
          _loaded = true;
        });
      } else {
        if (mounted) _loaded = true;
      }
    } catch (_) {
      // If SharedPreferences fails, don't show the tutorial.
      if (mounted) _loaded = true;
    }
  }

  Future<void> _dismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {
      // Best-effort — even if persisting fails, dismiss the UI.
    }
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Family Graph',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quick guide to get started',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    color: KinrelColors.textSilver,
                  ),
                ),
                const SizedBox(height: 32),
                _buildTip(
                  Icons.pinch_rounded,
                  'Pinch to zoom',
                  'Zoom in to see details, zoom out to see the whole family.',
                ),
                const SizedBox(height: 20),
                _buildTip(
                  Icons.pan_tool_rounded,
                  'Drag to pan',
                  'Move around the canvas by dragging with one finger.',
                ),
                const SizedBox(height: 20),
                _buildTip(
                  Icons.touch_app_rounded,
                  'Tap a person',
                  'See their details, relationships, and quick actions.',
                ),
                const SizedBox(height: 20),
                _buildTip(
                  Icons.search_rounded,
                  'Search',
                  'Use the search icon in the top bar to find anyone by name.',
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _dismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KinrelColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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

  Widget _buildTip(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.orange.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: KinrelColors.orange, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
