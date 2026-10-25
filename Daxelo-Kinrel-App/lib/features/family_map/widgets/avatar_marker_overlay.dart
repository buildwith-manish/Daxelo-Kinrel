// lib/features/family_map/widgets/avatar_marker_overlay.dart
//
// P10.3 — Flutter overlay fallback for premium avatar markers.
//
// Used when MapLibre's SymbolLayer.addImage is unavailable on a platform
// (Rule 12). Renders avatar markers as Flutter [Positioned] widgets
// over the map at each pin's screen position. The screen calls
// [AvatarMarkerOverlay.update] whenever the camera moves so positions
// stay in sync.
//
// This file is also used as the primary marker layer on platforms where
// the SymbolLayer path is known to be unreliable (e.g., web without
// WebGL image registration). The screen chooses one path or the other
// based on Rule 11 + Rule 12 verification.
//
// Performance (Rule 13): Only markers in the current viewport are
// rendered. Markers off-screen are skipped. On low-tier devices, the
// glow blur radius is reduced.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/utils/device_tier.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../core/theme/kinrel_fx.dart';
import '../../../l10n/app_localizations.dart';
import '../config/map_visual_constants.dart';
import '../helpers/distance_helper.dart';
import '../providers/family_map_provider.dart';
import '../providers/live_location_provider.dart';
import 'avatar_marker_generator.dart';

/// A single avatar marker rendered as a Flutter widget. Used by the
/// overlay fallback path (Rule 12).
class AvatarMarkerWidget extends StatelessWidget {
  const AvatarMarkerWidget({
    super.key,
    required this.pin,
    required this.selected,
    this.liveTier,
    this.liveLocation,
    this.viewerLat,
    this.viewerLng,
    this.isSelf = false,
    this.onTap,
    this.onLongPress,
    this.reducedMotion = false,
  });

  final MapPin pin;
  final bool selected;
  final LocationTier? liveTier;

  /// The member's live/last-known location. Used to compute distance
  /// from the viewer for the per-pin distance badge. Null when the
  /// member has never shared — no badge renders in that case.
  final LiveLocation? liveLocation;

  /// The viewer's current GPS position. Null when the viewer isn't
  /// sharing their own location — distance badge is hidden but tier
  /// dot still renders.
  final double? viewerLat;
  final double? viewerLng;

  /// True when this pin represents the viewer's own Person. Forces the
  /// distance label to "Live • now" (no point computing self-distance).
  final bool isSelf;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final size = selected
        ? MapVisualConstants.markerSelectedSize
        : MapVisualConstants.markerNormalSize;
    final ringColor = selected ? MapVisualConstants.markerSelectedRingColor : KinrelColors.orange;
    final ringWidth = selected
        ? MapVisualConstants.markerRingWidthSelected
        : MapVisualConstants.markerRingWidthNormal;
    final glowBlur = selected
        ? MapVisualConstants.markerGlowBlurSelected
        : MapVisualConstants.markerGlowBlurNormal;

    final avatar = CachedAvatar(
      imageUrl: pin.photoUrl,
      radius: (size - (ringWidth * 2)) / 2,
    );

    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // On-brand: use KinrelColors.darkCard (#191B2C) instead of the
        // previous hardcoded #1A1A22 — keeps the avatar background aligned
        // with the app's card surface token so pins read as native UI.
        color: KinrelColors.darkCard,
        border: Border.all(color: ringColor, width: ringWidth),
        boxShadow: KinrelFx.shadows([
          // Soft glow halo.
          BoxShadow(
            color: KinrelColors.orange.withValues(
              alpha: selected
                  ? MapVisualConstants.markerGlowAlphaSelected
                  : MapVisualConstants.markerGlowAlphaNormal,
            ),
            blurRadius: glowBlur,
            spreadRadius: 0,
          ),
          // Drop shadow for depth.
          BoxShadow(
            color: Colors.black.withValues(
              alpha: MapVisualConstants.markerShadowOpacity,
            ),
            blurRadius: 4,
            offset: const Offset(0, MapVisualConstants.markerShadowOffset),
          ),
        ]),
      ),
      child: Center(child: avatar),
    );

    final withPulse = (liveTier == LocationTier.live && !reducedMotion)
        ? core
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: MapVisualConstants.livePulseCycle,
                color: MapVisualConstants.livePulseRingColor.withValues(
                  alpha: MapVisualConstants.livePulseShimmerOpacity,
                ),
              )
        : core;

    // ── Per-pin distance badge ───────────────────────────────────────
    // Rendered ABOVE the avatar circle when the viewer is sharing their
    // own location AND the member has a LiveLocation. Shows the great-
    // circle distance as "X km away" / "X m away" / "Live • now".
    //
    // When the viewer isn't sharing, the badge is hidden (no point
    // computing distance from an unknown viewer position).
    final distanceLabel = _buildDistanceLabel();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Tooltip(
        message: _semanticsLabel(context),
        child: Semantics(
          button: true,
          label: _semanticsLabel(context),
          child: SizedBox(
            // Extra room above the avatar for the distance badge
            // (16px label + 4px gap + avatar with glow).
            width: size + glowBlur * 2,
            height: size + glowBlur * 2 + (distanceLabel != null ? 24 : 0),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Distance badge above the avatar circle.
                if (distanceLabel != null)
                  Positioned(
                    bottom: size + glowBlur + 2,
                    child: distanceLabel,
                  ),
                Center(child: withPulse),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the small distance badge if we have enough info to compute
  /// one; otherwise returns null (badge hidden).
  Widget? _buildDistanceLabel() {
    final loc = liveLocation;
    if (loc == null) return null;

    final hasViewerPos = viewerLat != null && viewerLng != null;
    if (!hasViewerPos && !isSelf) {
      // Viewer isn't sharing their own location — no distance to compute.
      // Still show a small tier indicator dot so other members can see
      // this person is "live" even without the viewer's own GPS.
      return _TierOnlyBadge(tier: loc.tier);
    }

    final distanceText = isSelf
        ? 'Live • now'
        : formatDistanceBetween(
            lat1: viewerLat!,
            lng1: viewerLng!,
            lat2: loc.lat,
            lng2: loc.lng,
            isSelf: false,
          );

    return _DistanceBadge(
      text: distanceText,
      tier: loc.tier,
    );
  }

  /// §10 / §19 — Localized semantic label for the avatar marker.
  /// Includes the member's name, optional tier freshness (localized),
  /// and a "Double-tap to focus" hint. Adds a "Selected." suffix when
  /// the marker is the current focus target.
  String _semanticsLabel(BuildContext context) {
    final l10n = S.of(context);
    final tierStr = liveTier == null
        ? ''
        : ' (${tierLabelLocalized(liveTier!, null, l10n)})';
    final name = pin.name;
    if (l10n == null) {
      // Fallback for tests / pre-localization bootstrap.
      final selStr = selected ? '. Selected.' : '';
      return '$name$tierStr$selStr. Double-tap to focus.';
    }
    final selStr = selected ? ' ${l10n.familyMapAvatarSelectedSuffix}' : '';
    return '${l10n.familyMapAvatarPinLabel(name, tierStr)}$selStr';
  }
}

/// Small pill that shows ONLY the tier dot (no distance text). Used
/// when the viewer isn't sharing their own location — the badge is
/// still useful because it tells the user this member is currently
/// live.
class _TierOnlyBadge extends StatelessWidget {
  const _TierOnlyBadge({required this.tier});
  final LocationTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: KinrelColors.textDim.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TierDot(tier: tier),
        ],
      ),
    );
  }
}

/// Pill-shaped distance label + tier dot. Positioned above each pin
/// when the viewer is sharing their own location. Background is semi-
/// transparent dark so it reads against any map tile.
class _DistanceBadge extends StatelessWidget {
  const _DistanceBadge({required this.text, required this.tier});
  final String text;
  final LocationTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tier == LocationTier.live
              ? KinrelColors.orange.withValues(alpha: 0.6)
              : KinrelColors.textDim.withValues(alpha: 0.3),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TierDot(tier: tier),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: tier == LocationTier.live
                  ? KinrelColors.orange
                  : KinrelColors.textSilver,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small colored dot that visually distinguishes the staleness tier.
class _TierDot extends StatelessWidget {
  const _TierDot({required this.tier});
  final LocationTier tier;

  @override
  Widget build(BuildContext context) {
    final color = switch (tier) {
      LocationTier.live => const Color(0xFF00E5C7), // teal
      LocationTier.recent => KinrelColors.orange,
      LocationTier.stale => KinrelColors.orange.withValues(alpha: 0.5),
      LocationTier.cityFallback => KinrelColors.textDim,
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: tier == LocationTier.live
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Manages a stack of [AvatarMarkerWidget]s positioned over the map.
/// Listens to map camera moves and re-positions the markers via the
/// [MapController.pointToScreen] API.
class AvatarMarkerOverlay extends StatefulWidget {
  const AvatarMarkerOverlay({
    super.key,
    required this.mapController,
    required this.pins,
    required this.selectedPinId,
    required this.liveTiers,
    required this.reducedMotion,
    this.liveLocations = const {},
    this.viewerLat,
    this.viewerLng,
    this.viewerPersonId,
    this.onPinTap,
    this.onPinLongPress,
  });

  final MapController? mapController;
  final List<MapPin> pins;
  final String? selectedPinId;
  final Map<String, LocationTier> liveTiers;
  final bool reducedMotion;

  /// Map of personId → member's live/last-known location (from
  /// [LiveLocationNotifier]). Used by [AvatarMarkerWidget] to compute
  /// + render the per-pin distance badge.
  ///
  /// Optional — if empty, no badges render. Pins still show with their
  /// tier ring only.
  final Map<String, LiveLocation> liveLocations;

  /// The viewer's current GPS position. Used for distance computation.
  /// Null when the viewer isn't sharing their own location — badges
  /// fall back to tier-only indicator.
  final double? viewerLat;
  final double? viewerLng;

  /// The viewer's own Person.id. Used to mark their own pin with
  /// isSelf=true so the badge shows "Live • now" instead of computing
  /// self-distance.
  final String? viewerPersonId;

  final void Function(MapPin pin)? onPinTap;
  final void Function(MapPin pin)? onPinLongPress;

  @override
  State<AvatarMarkerOverlay> createState() => _AvatarMarkerOverlayState();
}

class _AvatarMarkerOverlayState extends State<AvatarMarkerOverlay>
    with SingleTickerProviderStateMixin {
  /// Map of personId → current screen offset. Recomputed on every camera move.
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
    bool changed = false;
    for (final pin in widget.pins) {
      try {
        // The maplibre API: pointToScreen returns Offset.
        // Some builds expose it as a method, some as a function; both are
        // wrapped in try/catch so we degrade to no-overlay (Rule 12).
        final geographic = Geographic(lon: pin.lng, lat: pin.lat);
        final screen = _pointToScreen(controller, geographic);
        if (screen != null && _positions[pin.personId] != screen) {
          _positions[pin.personId] = screen;
          changed = true;
        }
      } catch (_) {
        // ignore — marker stays at its last known position.
      }
    }
    if (changed && mounted) setState(() {});
  }

  Offset? _pointToScreen(MapController controller, Geographic g) {
    // maplibre 0.3.5 exposes `toScreenLocation(Geographic)` on MapController.
    try {
      return controller.toScreenLocation(g);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pins.isEmpty) return const SizedBox.shrink();
    // Performance: get the viewport bounds for off-screen culling.
    // During pan/zoom, pins that are off-screen don't need to be built
    // or painted — this is the single biggest win for large families
    // (50+ pins). Without this, every frame rebuilds Positioned +
    // AvatarMarkerWidget + CachedAvatar for ALL pins, even those far
    // outside the visible viewport.
    //
    // Uses MediaQuery.of(context).size (same pattern as
    // place_callout_overlay.dart:195) rather than controller.camera.size
    // — the MediaQuery approach is more reliable across maplibre versions
    // and matches the existing culling code in the codebase.
    final viewSize = MediaQuery.maybeOf(context)?.size;
    final cullMargin = MapVisualConstants.markerSelectedSize; // generous margin so pins fade out smoothly
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final pin in widget.pins) _buildPositioned(pin, viewSize, cullMargin),
        ],
      ),
    );
  }

  Widget _buildPositioned(MapPin pin, Size? viewSize, double cullMargin) {
    final pos = _positions[pin.personId];
    // If we don't have a screen position yet, render offscreen.
    final dx = pos?.dx ?? -1000;
    final dy = pos?.dy ?? -1000;

    // Performance: off-screen culling. If the pin is well outside the
    // viewport (beyond the cull margin), don't build its widget subtree
    // at all. This skips the CachedAvatar network-image lookup, the
    // BoxDecoration construction, and the flutter_animate shimmer for
    // live pins — all of which are wasted work for off-screen pins.
    if (viewSize != null && pos != null) {
      if (dx < -cullMargin || dx > viewSize.width + cullMargin ||
          dy < -cullMargin || dy > viewSize.height + cullMargin) {
        return const SizedBox.shrink();
      }
    }

    final selected = pin.personId == widget.selectedPinId;
    final tier = widget.liveTiers[pin.personId];
    final liveLoc = widget.liveLocations[pin.personId];
    final isSelf = widget.viewerPersonId != null &&
        pin.personId == widget.viewerPersonId;
    final size = selected
        ? MapVisualConstants.markerSelectedSize
        : MapVisualConstants.markerNormalSize;
    // Performance: RepaintBoundary isolates each pin's repaint from its
    // siblings. Without this, a setState in the parent (which fires every
    // frame during pan/zoom) causes Flutter to repaint the ENTIRE Stack
    // of pins. With RepaintBoundary, only the pins whose own state changed
    // repaint — the rest are cached as bitmaps by the Flutter compositor.
    return Positioned(
      left: dx - size / 2,
      top: dy - size / 2,
      child: RepaintBoundary(
        child: AvatarMarkerWidget(
          pin: pin,
          selected: selected,
          liveTier: tier,
          liveLocation: liveLoc,
          viewerLat: widget.viewerLat,
          viewerLng: widget.viewerLng,
          isSelf: isSelf,
          reducedMotion: widget.reducedMotion,
          onTap: () => widget.onPinTap?.call(pin),
          onLongPress: () => widget.onPinLongPress?.call(pin),
        ),
      ),
    );
  }
}

/// Wraps the screen-side state for the avatar marker layer (overlay path).
/// The screen instantiates this and calls [update] on data changes.
class AvatarMarkerLayer {
  AvatarMarkerLayer({this.deviceTier});

  final DeviceTier? deviceTier;

  /// True when the Flutter overlay path should be used (Rule 12 fallback).
  /// Determined at runtime by the screen via [verifySymbolLayerSupport].
  bool useOverlay = false;

  /// Cache for the SymbolLayer path (when [useOverlay] is false).
  final AvatarMarkerCache cache = AvatarMarkerCache.instance;

  /// Verifies that maplibre 0.3.5 supports the SymbolLayer + addImage path.
  /// Called once on first style load. Sets [useOverlay] accordingly.
  ///
  /// Implementation note: we attempt a tiny no-op `style.addImage` call.
  /// If it throws, we fall back to the Flutter overlay. This is the most
  /// reliable runtime check (Rule 11 — verify against installed version).
  Future<void> verifySymbolLayerSupport(StyleController? style) async {
    if (style == null) {
      useOverlay = true;
      return;
    }
    try {
      // Generate a 1x1 transparent PNG and try to add it. If the API
      // throws, we know SymbolLayer won't work either.
      await style.addImage('kinrel_marker_probe', _transparentProbe);
      useOverlay = false;
    } catch (_) {
      useOverlay = true;
    }
  }

  /// 1x1 transparent PNG bytes (used by the SymbolLayer probe).
  static final Uint8List _transparentProbe = _decodeProbe();

  static Uint8List _decodeProbe() {
    const hex =
        '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4'
        '890000000d49444154789c636000000000020001e221bc330000000049454e44ae426082';
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// P12.2 — DIRECTIONAL SPOTLIGHT CONE
// ═══════════════════════════════════════════════════════════════════════
//
// A CustomPainter widget that renders a translucent cone of light
// emanating from the "Me" marker, pointing in the user's heading
// direction. Creates the "spotlight" effect from the Snap Map
// reference, in Kinrel's warm gold gradient.
//
// Rendered as a Flutter overlay (NOT a map layer) so it can use
// BlendMode.screen + radial gradients for the cinematic glow that
// MapLibre's fill-extrusion can't reproduce.
//
// Reduced motion: the cone is rendered statically (no pulse).
// Low-tier devices: the cone is skipped entirely (just the marker).

/// Widget that renders the directional spotlight cone under the "Me"
/// avatar marker. Place it as a sibling of [AvatarMarkerWidget] in the
/// overlay stack, at the same screen position.
///
/// Pass [headingDegrees] = 0 for north, 90 for east, 180 for south,
/// 270 for west. When null or when [reducedMotion] is true on a
/// low-tier device, the cone is not rendered.
class DirectionalSpotlightCone extends StatelessWidget {
  const DirectionalSpotlightCone({
    super.key,
    this.headingDegrees,
    this.reducedMotion = false,
    this.deviceTier,
    this.size = 44.0,
  });

  /// Heading in degrees (0 = north, clockwise). Null = no heading
  /// available → cone not rendered.
  final double? headingDegrees;

  /// When true, the cone is rendered statically (no pulse animation).
  final bool reducedMotion;

  /// Device tier — when low, the cone is skipped for performance.
  final DeviceTier? deviceTier;

  /// The marker size (used to size the cone origin). Should match
  /// [MapVisualConstants.markerNormalSize] for consistency.
  final double size;

  DeviceTier get _effectiveTier => deviceTier ?? DeviceTierCache.instance.tier;

  @override
  Widget build(BuildContext context) {
    // Skip when no heading, or on low-tier devices.
    if (headingDegrees == null) return const SizedBox.shrink();
    if (_effectiveTier == DeviceTier.low) return const SizedBox.shrink();

    final coneRadius = size * 4.0; // cone extends 4x the marker size
    return IgnorePointer(
      child: SizedBox(
        width: coneRadius * 2,
        height: coneRadius * 2,
        child: CustomPaint(
          painter: _SpotlightConePainter(
            headingDegrees: headingDegrees!,
            coneRadius: coneRadius,
            reducedMotion: reducedMotion,
          ),
        ),
      ),
    );
  }
}

/// CustomPainter that draws the directional spotlight cone.
///
/// The cone is a radial gradient pie slice centered on the
/// marker, spanning ±25° around the heading direction. Colors fade
/// from Kinrel gold (#E8B941) at the origin to transparent at the
/// edge, using BlendMode.screen for the cinematic "lit" effect.
class _SpotlightConePainter extends CustomPainter {
  const _SpotlightConePainter({
    required this.headingDegrees,
    required this.coneRadius,
    required this.reducedMotion,
  });

  final double headingDegrees;
  final double coneRadius;
  final bool reducedMotion;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final center = ui.Offset(size.width / 2, size.height / 2);
    final headingRad = headingDegrees * math.pi / 180.0;

    // Cone spans ±25° around the heading (50° total aperture).
    const halfAperture = 25.0 * math.pi / 180.0;

    // Build the cone path: a pie slice from center.
    final path = ui.Path();
    path.moveTo(center.dx, center.dy);
    // Sweep from (heading - halfAperture) to (heading + halfAperture).
    // In screen coordinates, 0° = east (right), positive = clockwise.
    // We convert heading (0=north, clockwise) to screen radians:
    // screenAngle = heading - 90° (so 0° north → -90° = up).
    final startAngle = headingRad - math.pi / 2 - halfAperture;
    final endAngle = headingRad - math.pi / 2 + halfAperture;
    path.arcTo(
      ui.Rect.fromCircle(center: center, radius: coneRadius),
      startAngle,
      endAngle - startAngle,
      false,
    );
    path.close();

    // Radial gradient: gold at origin → transparent at edge.
    // NOTE: RadialGradient + Alignment are Flutter framework classes
    // (painting.dart / material.dart), NOT dart:ui — do not prefix with ui.
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        const ui.Color(0xFFE8B941).withValues(alpha: 0.35), // Kinrel gold
        const ui.Color(0xFFE8612A).withValues(alpha: 0.15), // Kinrel orange
        const ui.Color(0x00E8612A), // transparent
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = ui.Paint()
      ..shader = gradient.createShader(
        ui.Rect.fromCircle(center: center, radius: coneRadius),
      )
      ..blendMode = ui.BlendMode.screen;

    canvas.drawPath(path, paint);

    // Draw a thin bright edge along the heading direction (the
    // "spotlight beam" line).
    final beamEnd = ui.Offset(
      center.dx + math.cos(headingRad - math.pi / 2) * coneRadius,
      center.dy + math.sin(headingRad - math.pi / 2) * coneRadius,
    );
    final beamPaint = ui.Paint()
      ..color = const ui.Color(0xFFE8B941).withValues(alpha: 0.25)
      ..strokeWidth = 1.5
      ..blendMode = ui.BlendMode.screen;
    canvas.drawLine(center, beamEnd, beamPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightConePainter old) {
    return old.headingDegrees != headingDegrees ||
        old.coneRadius != coneRadius ||
        old.reducedMotion != reducedMotion;
  }
}
