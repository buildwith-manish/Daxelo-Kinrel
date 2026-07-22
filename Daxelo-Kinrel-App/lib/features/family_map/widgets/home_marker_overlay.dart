// lib/features/family_map/widgets/home_marker_overlay.dart
//
// DAXELO KINREL — Highlighted Home Marker.
//
// P13 — A special "home" pin rendered above the family's primary home
// (currentHome place type). Matches the reference's highlighted home
// location: a warm-orange dot inside a pulsing gold ring with a soft
// glow halo. The pulse animation is gentle (2.4s cycle) and respects
// the user's reduced-motion preference.
//
// Behavior:
//   • The home marker is rendered as a Flutter overlay widget
//     (positioned via MapController.toScreenLocation).
//   • The ring pulses outward continuously (when not in reduced motion).
//   • On tap, the camera flies to the home location at focus-mode
//     zoom + pitch, where 3D buildings are clearly visible.
//
// Identification:
//   • The parent screen identifies the home [FamilyPlace] (the first
//     place with placeType == currentHome) and passes it in.
//   • If no currentHome place exists, this overlay is invisible.
//
// Performance (Rule 13):
//   • Position updates are throttled to once per frame via a Ticker.
//   • The pulse uses a single AnimationController (no shimmer).
//   • The widget is skipped when off-screen.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';

/// Highlighted home marker — a pulsing gold ring + warm orange dot.
class HomeMarkerOverlay extends StatefulWidget {
  const HomeMarkerOverlay({
    super.key,
    required this.mapController,
    required this.home,
    required this.reducedMotion,
    this.onTap,
  });

  /// The maplibre controller used for screen-position lookup.
  final MapController? mapController;

  /// The family place to highlight (placeType == currentHome).
  final FamilyPlace home;

  /// True when the user has enabled reduced motion.
  final bool reducedMotion;

  /// Optional tap handler — typically flies the camera to the home.
  final VoidCallback? onTap;

  @override
  State<HomeMarkerOverlay> createState() => _HomeMarkerOverlayState();
}

class _HomeMarkerOverlayState extends State<HomeMarkerOverlay>
    with TickerProviderStateMixin {
  Offset? _position;
  late final Ticker _ticker;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
    _pulse = AnimationController(
      vsync: this,
      duration: MapVisualConstants.homeMarkerPulseCycle,
    );
    if (!widget.reducedMotion) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final controller = widget.mapController;
    if (controller == null) return;
    try {
      final g = Geographic(lon: widget.home.lng, lat: widget.home.lat);
      final screen = controller.toScreenLocation(g);
      if (screen != null && _position != screen) {
        if (mounted) setState(() => _position = screen);
      }
    } catch (_) {
      // ignore — stays at last known position
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    if (pos == null) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    // Off-screen cull.
    if (pos.dx < -100 ||
        pos.dx > size.width + 100 ||
        pos.dy < -100 ||
        pos.dy > size.height + 100) {
      return const SizedBox.shrink();
    }

    final ringSize = MapVisualConstants.homeMarkerRingSize;
    final dotSize = MapVisualConstants.homeMarkerDotSize;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            label: 'Home: ${widget.home.name}',
            child: SizedBox(
              width: ringSize + 16,
              height: ringSize + 16,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // ── Outer pulsing ring ──────────────────────────────
                  if (!widget.reducedMotion)
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final t = _pulse.value;
                        // Two-phase: expand + fade out, then reset.
                        final scale = 1.0 +
                            (MapVisualConstants.homeMarkerPulseMaxScale -
                                    1.0) *
                                t;
                        final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.7;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: ringSize,
                            height: ringSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: MapVisualConstants.homeMarkerRingColor
                                    .withValues(alpha: opacity),
                                width: 2.0,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: MapVisualConstants.homeMarkerRingColor
                              .withValues(alpha: 0.7),
                          width: 2.0,
                        ),
                      ),
                    ),

                  // ── Inner solid ring (always visible) ───────────────
                  Container(
                    width: ringSize,
                    height: ringSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkCard.withValues(alpha: 0.55),
                      border: Border.all(
                        color: MapVisualConstants.homeMarkerRingColor,
                        width: 2.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MapVisualConstants.homeMarkerFillColor
                              .withValues(alpha: 0.55),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: dotSize,
                        height: dotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MapVisualConstants.homeMarkerFillColor,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: MapVisualConstants.homeMarkerFillColor
                                  .withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.home_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: widget.reducedMotion ? 1.ms : 480.ms);
  }
}
