// lib/features/family_map/widgets/household_cluster_overlay.dart
//
// DAXELO KINREL — P10.4 Household Cluster Overlay.
//
// Renders [HouseholdClusterMarkerWidget] for each multi-member
// household, positioned via [MapController.toScreenLocation] on every
// frame.
//
// Extracted from `family_map_screen.dart` (originally the private
// `_HouseholdClusterOverlay` widget) as part of the file
// decomposition. The public class is named [HouseholdClusterOverlay].

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre/maplibre.dart';

import '../config/map_visual_constants.dart';
import '../providers/family_map_provider.dart';
import 'household_cluster_marker.dart';

/// Renders [HouseholdClusterMarkerWidget]s for each multi-member
/// household.
///
/// Polls the [mapController] for each household's screen position on
/// every ticker frame and repositions the markers as the camera
/// moves.
class HouseholdClusterOverlay extends StatefulWidget {
  const HouseholdClusterOverlay({
    super.key,
    required this.mapController,
    required this.households,
    required this.expandedHouseholdId,
    required this.reducedMotion,
    required this.onClusterTap,
    required this.onClusterLongPress,
  });

  final MapController? mapController;
  final List<Household> households;
  final String? expandedHouseholdId;
  final bool reducedMotion;
  final void Function(Household) onClusterTap;
  final void Function(Household) onClusterLongPress;

  @override
  State<HouseholdClusterOverlay> createState() =>
      _HouseholdClusterOverlayState();
}

class _HouseholdClusterOverlayState extends State<HouseholdClusterOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<String, Offset> _positions = {};

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final controller = widget.mapController;
    if (controller == null) return;
    bool changed = false;
    for (final h in widget.households) {
      try {
        final screen =
            controller.toScreenLocation(Geographic(lon: h.lng, lat: h.lat));
        if (_positions[h.id] != screen) {
          _positions[h.id] = screen;
          changed = true;
        }
      } catch (_) {
        // ignore
      }
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final h in widget.households)
          _buildPositioned(h),
      ],
    );
  }

  Widget _buildPositioned(Household h) {
    final pos = _positions[h.id];
    if (pos == null) return const SizedBox.shrink();
    final size = MapVisualConstants.clusterMarkerSize;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      child: HouseholdClusterMarkerWidget(
        household: h,
        reducedMotion: widget.reducedMotion,
        onTap: () => widget.onClusterTap(h),
        onLongPress: () => widget.onClusterLongPress(h),
      ),
    );
  }
}
