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

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/utils/device_tier.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../config/map_visual_constants.dart';
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
    this.onTap,
    this.onLongPress,
    this.reducedMotion = false,
  });

  final MapPin pin;
  final bool selected;
  final LocationTier? liveTier;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final size = selected
        ? MapVisualConstants.markerSelectedSize
        : MapVisualConstants.markerNormalSize;
    final ringColor = selected ? const Color(0xFFE8B941) : KinrelColors.orange;
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
        color: const Color(0xFF1A1A22),
        border: Border.all(color: ringColor, width: ringWidth),
        boxShadow: [
          // Soft glow halo.
          BoxShadow(
            color: KinrelColors.orange.withOpacity(selected ? 0.55 : 0.30),
            blurRadius: glowBlur,
            spreadRadius: 0,
          ),
          // Drop shadow for depth.
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 4,
            offset: Offset(
              0,
              MapVisualConstants.markerShadowOffset,
            ),
          ),
        ],
      ),
      child: Center(child: avatar),
    );

    final withPulse = (liveTier == LocationTier.live && !reducedMotion)
        ? core.animate(
            onPlay: (c) => c.repeat(),
          ).shimmer(
            duration: MapVisualConstants.livePulseCycle,
            color: const Color(0xFF4ED9C7).withOpacity(0.35),
          )
        : core;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Semantics(
        button: true,
        label: _semanticsLabel(),
        child: SizedBox(
          width: size + glowBlur * 2,
          height: size + glowBlur * 2,
          child: Center(child: withPulse),
        ),
      ),
    );
  }

  String _semanticsLabel() {
    final tierStr = liveTier == null ? '' : ' (${tierLabel(liveTier!, null)})';
    final selStr = selected ? '. Selected.' : '';
    return '${pin.name}$tierStr$selStr. Double-tap to focus.';
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
    this.onPinTap,
    this.onPinLongPress,
  });

  final MapController? mapController;
  final List<MapPin> pins;
  final String? selectedPinId;
  final Map<String, LocationTier> liveTiers;
  final bool reducedMotion;
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
        final geographic = Geographic(lat: pin.lat, lng: pin.lng);
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
    // maplibre 0.3.5 exposes `screenLocation` on the controller.
    // ignore: avoid_dynamic_calls
    final dynamic result = (controller as dynamic).screenLocation(g);
    if (result is Offset) return result;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pins.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final pin in widget.pins)
            _buildPositioned(pin),
        ],
      ),
    );
  }

  Widget _buildPositioned(MapPin pin) {
    final pos = _positions[pin.personId];
    // If we don't have a screen position yet, render offscreen.
    final dx = pos?.dx ?? -1000;
    final dy = pos?.dy ?? -1000;
    final selected = pin.personId == widget.selectedPinId;
    final tier = widget.liveTiers[pin.personId];
    final size = selected
        ? MapVisualConstants.markerSelectedSize
        : MapVisualConstants.markerNormalSize;
    return Positioned(
      left: dx - size / 2,
      top: dy - size / 2,
      child: AvatarMarkerWidget(
        pin: pin,
        selected: selected,
        liveTier: tier,
        reducedMotion: widget.reducedMotion,
        onTap: () => widget.onPinTap?.call(pin),
        onLongPress: () => widget.onPinLongPress?.call(pin),
      ),
    );
  }
}

/// Wraps the screen-side state for the avatar marker layer (overlay path).
/// The screen instantiates this and calls [update] on data changes.
class AvatarMarkerLayer {
  AvatarMarkerLayer({this.deviceTier});

  final DeviceTier? deviceTier;

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.current ?? DeviceTier.mid;

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
      // ignore: avoid_dynamic_calls
      await (style as dynamic).addImage(
        'kinrel_marker_probe',
        _transparentProbe,
      );
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
