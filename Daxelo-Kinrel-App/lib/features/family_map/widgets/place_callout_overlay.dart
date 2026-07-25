// lib/features/family_map/widgets/place_callout_overlay.dart
//
// DAXELO KINREL — Place Callout Overlay.
//
// P13 — Floating icon+text "callout" chips that appear above family
// place buildings on the map. Each chip is a small glass pill with a
// category-colored leading icon and an elegant place name, matching
// the reference's labeled-landmark aesthetic.
//
// Visibility rules:
//   • Callouts only render when map zoom >= [calloutMinZoom] (12.0).
//     Below that zoom, the world view is too zoomed-out for chip labels
//     to be readable; buildings render as colored dots instead.
//   • Callouts are limited to [maxVisibleCallouts] (8) at a time. The
//     N closest to the screen center are shown; the rest are skipped.
//     This prevents clutter when a city has 50+ family places.
//   • Callouts respect the user's reduced-motion preference (no
//     staggered fade-in).
//
// Performance (Rule 13):
//   • Position update is throttled to once per frame via a Ticker.
//   • Off-screen callouts are skipped (no Positioned widget built).
//   • The chip itself is a lightweight Container — no heavy painters.
//
// Localization: the place name comes from [FamilyPlace.name]. The chip
// does NOT append the place type label (the icon communicates that).
//
// Integration: the parent screen passes the [FamilyPlace] list and the
// map controller. The screen decides whether callouts are enabled
// (via the [MapControlLayer.callouts] toggle on the Layers popover).

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';

/// A single floating callout chip rendered above a family place.
class _PlaceCalloutChip extends StatelessWidget {
  const _PlaceCalloutChip({required this.place});

  final FamilyPlace place;

  @override
  Widget build(BuildContext context) {
    final meta = _calloutMeta(place.placeType);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: MapVisualConstants.calloutChipPaddingH,
        vertical: MapVisualConstants.calloutChipPaddingV,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: meta.color.withValues(alpha: 0.85),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: meta.color.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: MapVisualConstants.calloutIconSize,
              color: meta.color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: MapVisualConstants.calloutFontSize,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
                height: 1.1,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manages a stack of [_PlaceCalloutChip]s positioned over the map.
/// Listens to map camera moves and re-positions chips via the
/// [MapController.toScreenLocation] API.
class PlaceCalloutOverlay extends StatefulWidget {
  const PlaceCalloutOverlay({
    super.key,
    required this.mapController,
    required this.places,
    required this.reducedMotion,
    this.selectedPlaceId,
    this.onTap,
  });

  /// The maplibre controller (null while the map is loading).
  final MapController? mapController;

  /// Family places to label. The parent screen is responsible for
  /// timeline filtering before passing them in.
  final List<FamilyPlace> places;

  /// True when the user has enabled reduced motion.
  final bool reducedMotion;

  /// Optional — the place currently selected. Gets a brighter highlight.
  final String? selectedPlaceId;

  /// Optional tap handler. Receives the place that was tapped.
  final void Function(FamilyPlace place)? onTap;

  @override
  State<PlaceCalloutOverlay> createState() => _PlaceCalloutOverlayState();
}

class _PlaceCalloutOverlayState extends State<PlaceCalloutOverlay> {
  /// Map of placeId → current screen offset. Recomputed on every camera move.
  final Map<String, Offset> _positions = <String, Offset>{};

  late final Ticker _ticker;

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
    final zoom = controller.camera?.zoom ?? 0.0;
    // Below the dot min zoom, clear all positions so callouts disappear.
    if (zoom < MapVisualConstants.calloutDotMinZoom) {
      if (_positions.isNotEmpty) {
        _positions.clear();
        if (mounted) setState(() {});
      }
      return;
    }
    bool changed = false;
    for (final place in widget.places) {
      try {
        final g = Geographic(lon: place.lng, lat: place.lat);
        final screen = controller.toScreenLocation(g);
        if (screen != null && _positions[place.id] != screen) {
          _positions[place.id] = screen;
          changed = true;
        }
      } catch (_) {
        // ignore — callout stays at its last known position
      }
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.mapController;
    final zoom = controller?.camera?.zoom ?? 0.0;
    // Below the absolute minimum — render nothing.
    if (zoom < MapVisualConstants.calloutDotMinZoom) {
      return const SizedBox.shrink();
    }
    if (widget.places.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);

    // ── Low-zoom compact dots ──────────────────────────────────────
    // Between calloutDotMinZoom and calloutMinZoom, render small
    // category-colored dots (no text). Places within
    // calloutClusterEpsilon degrees of each other collapse into a
    // single dot to declutter the world view.
    if (zoom < MapVisualConstants.calloutMinZoom) {
      return _buildLowZoomDots(size, center);
    }

    // ── Full chip callouts ─────────────────────────────────────────
    // Pick the N callouts closest to the screen center.
    final visible = <_VisibleCallout>[];
    for (final place in widget.places) {
      final pos = _positions[place.id];
      if (pos == null) continue;
      // Skip off-screen callouts.
      if (pos.dx < -100 ||
          pos.dx > size.width + 100 ||
          pos.dy < -100 ||
          pos.dy > size.height + 100) {
        continue;
      }
      final dist = (pos - center).distance;
      visible.add(_VisibleCallout(place: place, position: pos, dist: dist));
    }
    visible.sort((a, b) => a.dist.compareTo(b.dist));
    final capped = visible.take(MapVisualConstants.maxVisibleCallouts).toList();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < capped.length; i++)
          _buildPositioned(capped[i], i),
      ],
    );
  }

  /// P13.1 — Builds the low-zoom compact dot cluster.
  ///
  /// Places are bucketed into a coarse grid (calloutClusterEpsilon
  /// degrees) so that places in the same city collapse into a single
  /// dot. The dot's color is the most prominent place type in the
  /// bucket (priority: currentHome > wedding > memorial > ancestral >
  /// childhoodHome > grandparentsHome > birthplace > school >
  /// familyBusiness > familyTemple > vacationHome > importantPlace).
  /// The dot's tap handler flies the camera to the closest place in
  /// the bucket.
  Widget _buildLowZoomDots(Size size, Offset center) {
    final buckets = <String, _DotBucket>{};
    final epsilon = MapVisualConstants.calloutClusterEpsilon;
    for (final place in widget.places) {
      final pos = _positions[place.id];
      if (pos == null) continue;
      // Skip off-screen dots.
      if (pos.dx < -50 ||
          pos.dx > size.width + 50 ||
          pos.dy < -50 ||
          pos.dy > size.height + 50) {
        continue;
      }
      final latKey = (place.lat / epsilon).round();
      final lngKey = (place.lng / epsilon).round();
      final key = '$latKey:$lngKey';
      final bucket = buckets.putIfAbsent(
        key,
        () => _DotBucket(latKey: latKey, lngKey: lngKey),
      );
      bucket.places.add(place);
      bucket.positions.add(pos);
    }

    // Convert to list + sort by distance to center.
    final bucketList = buckets.values.toList();
    for (final b in bucketList) {
      b.dist = (b.averagePosition() - center).distance;
    }
    bucketList.sort((a, b) => a.dist.compareTo(b.dist));
    final capped = bucketList.take(MapVisualConstants.maxVisibleCalloutDots).toList();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < capped.length; i++)
          _buildDotPositioned(capped[i], i),
      ],
    );
  }

  Widget _buildDotPositioned(_DotBucket bucket, int index) {
    final meta = _calloutMeta(bucket.dominantPlaceType());
    final dotSize = MapVisualConstants.calloutDotSize;
    final pos = bucket.averagePosition();
    final isSel = widget.selectedPlaceId != null &&
        bucket.places.any((p) => p.id == widget.selectedPlaceId);

    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: meta.color,
        border: Border.all(
          color: Colors.white.withValues(alpha: isSel ? 0.95 : 0.55),
          width: isSel ? 1.6 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: meta.color.withValues(alpha: 0.65),
            blurRadius: MapVisualConstants.calloutDotGlowBlur,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );

    // If the bucket has 2+ places, add a small "+N" badge.
    final withBadge = bucket.places.length > 1
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              dot,
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                      color: meta.color,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '${bucket.places.length}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: meta.color,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          )
        : dot;

    final animated = widget.reducedMotion
        ? withBadge
        : withBadge
            .animate(onPlay: (c) => c.forward())
            .fadeIn(
              duration: 280.ms,
              delay: (index * 18).ms,
            )
            .scale(
              begin: const Offset(0.6, 0.6),
              end: const Offset(1.0, 1.0),
              duration: 240.ms,
              curve: Curves.easeOutCubic,
            );

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: widget.onTap == null
              ? null
              : () => widget.onTap!(bucket.closestPlace()),
          child: MouseRegion(
            cursor: widget.onTap == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: animated,
          ),
        ),
      ),
    );
  }

  Widget _buildPositioned(_VisibleCallout v, int index) {
    final isSel = widget.selectedPlaceId == v.place.id;
    final chip = Opacity(
      opacity: isSel ? 1.0 : 0.92,
      child: _PlaceCalloutChip(place: v.place),
    );
    final animated = widget.reducedMotion
        ? chip
        : chip
            .animate(onPlay: (c) => c.forward())
            .fadeIn(
              duration: 320.ms,
              delay: (index * MapVisualConstants.calloutStaggerDelay.inMilliseconds).ms,
            )
            .slideY(
              begin: 0.18,
              end: 0,
              duration: 280.ms,
              curve: Curves.easeOutCubic,
            );
    return Positioned(
      left: v.position.dx,
      top: v.position.dy - MapVisualConstants.calloutVerticalOffset,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1.0),
        child: GestureDetector(
          onTap: widget.onTap == null ? null : () => widget.onTap!(v.place),
          child: MouseRegion(
            cursor: widget.onTap == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: animated,
          ),
        ),
      ),
    );
  }
}

class _VisibleCallout {
  const _VisibleCallout({
    required this.place,
    required this.position,
    required this.dist,
  });

  final FamilyPlace place;
  final Offset position;
  final double dist;
}

/// Visual metadata for a place type callout. The icon + color match
/// the building's emotional lighting so the callout "reads" as the
/// building's label.
_CalloutMeta _calloutMeta(PlaceType type) {
  switch (type) {
    case PlaceType.currentHome:
      return const _CalloutMeta(
        icon: Icons.home_rounded,
        color: Color(0xFFE8612A),
      );
    case PlaceType.childhoodHome:
      return const _CalloutMeta(
        icon: Icons.bungalow_rounded,
        color: Color(0xFFF59240),
      );
    case PlaceType.ancestralHome:
      return const _CalloutMeta(
        icon: Icons.account_balance_rounded,
        color: Color(0xFFB8901F),
      );
    case PlaceType.birthplace:
      return const _CalloutMeta(
        icon: Icons.child_care_rounded,
        color: Color(0xFFF5B841),
      );
    case PlaceType.wedding:
      return const _CalloutMeta(
        icon: Icons.favorite_rounded,
        color: Color(0xFFE8612A),
      );
    case PlaceType.memorial:
      return const _CalloutMeta(
        icon: Icons.local_florist_rounded,
        color: Color(0xFFF59240),
      );
    case PlaceType.familyBusiness:
      return const _CalloutMeta(
        icon: Icons.storefront_rounded,
        color: Color(0xFFD85720),
      );
    case PlaceType.school:
      return const _CalloutMeta(
        icon: Icons.school_rounded,
        color: Color(0xFF4E6984),
      );
    case PlaceType.vacationHome:
      return const _CalloutMeta(
        icon: Icons.beach_access_rounded,
        color: Color(0xFF4E6984),
      );
    case PlaceType.familyTemple:
      return const _CalloutMeta(
        icon: Icons.temple_buddhist_rounded,
        color: Color(0xFFE8612A),
      );
    case PlaceType.grandparentsHome:
      return const _CalloutMeta(
        icon: Icons.elderly_rounded,
        color: Color(0xFFF59240),
      );
    case PlaceType.importantPlace:
      return const _CalloutMeta(
        icon: Icons.star_rounded,
        color: Color(0xFFE8612A),
      );
  }
}

class _CalloutMeta {
  const _CalloutMeta({required this.icon, required this.color});
  final IconData icon;
  final Color color;
}

/// P13.1 — A cluster of family places that share a coarse grid cell at
/// low zoom. Used by [_PlaceCalloutOverlayState._buildLowZoomDots].
class _DotBucket {
  _DotBucket({required this.latKey, required this.lngKey});

  final int latKey;
  final int lngKey;
  final List<FamilyPlace> places = <FamilyPlace>[];
  final List<Offset> positions = <Offset>[];
  double dist = double.infinity;

  /// Average screen position of all places in the bucket.
  Offset averagePosition() {
    if (positions.isEmpty) return Offset.zero;
    double dx = 0, dy = 0;
    for (final p in positions) {
      dx += p.dx;
      dy += p.dy;
    }
    return Offset(dx / positions.length, dy / positions.length);
  }

  /// The "most prominent" place type in the bucket — used to pick the
  /// dot color. Priority: homes > weddings > memorials > ancestral >
  /// other. This ensures the dot color reflects the most emotionally
  /// significant place in the cluster (e.g., a city with a currentHome
  /// + a school shows the warm orange home color, not the cool school
  /// color).
  PlaceType dominantPlaceType() {
    final priority = <PlaceType>[
      PlaceType.currentHome,
      PlaceType.wedding,
      PlaceType.memorial,
      PlaceType.ancestralHome,
      PlaceType.childhoodHome,
      PlaceType.grandparentsHome,
      PlaceType.birthplace,
      PlaceType.familyTemple,
      PlaceType.familyBusiness,
      PlaceType.school,
      PlaceType.vacationHome,
      PlaceType.importantPlace,
    ];
    for (final t in priority) {
      for (final p in places) {
        if (p.placeType == t) return t;
      }
    }
    return places.first.placeType;
  }

  /// The place in the bucket whose screen position is closest to the
  /// bucket's average position. Used as the tap target.
  FamilyPlace closestPlace() {
    if (places.length == 1) return places.first;
    final avg = averagePosition();
    FamilyPlace best = places.first;
    double bestDist = double.infinity;
    for (var i = 0; i < places.length; i++) {
      final d = (positions[i] - avg).distance;
      if (d < bestDist) {
        bestDist = d;
        best = places[i];
      }
    }
    return best;
  }
}
