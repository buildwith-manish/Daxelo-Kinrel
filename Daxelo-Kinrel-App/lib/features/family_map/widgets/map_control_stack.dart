// lib/features/family_map/widgets/map_control_stack.dart
//
// DAXELO KINREL — Right-side Map Control Stack.
//
// P13 — Premium vertical control stack pinned to the right edge of the
// family map. Matches the reference's floating control cluster:
//
//   • Locate / recenter  (GPS fly-to-current-position)
//   • Zoom in            (+)
//   • Zoom out           (−)
//   • Layers / filters   (opens a layers popover)
//   • Map mode toggle    (dark ↔ light)
//
// Each button is a circular glass surface with a soft border, subtle
// shadow, hover/tap scale spring, and a localized tooltip. The stack
// uses IgnorePointer(false) so map gestures pass through gaps between
// buttons but the buttons themselves remain tappable.
//
// Design language: matches the existing MapLegendWidget — same dark
// glass card, same border color (KinrelColors.darkElevated), same
// rounded corners. Buttons render with `flutter_animate` for the
// entrance stagger (rule 11.6 — premium polish).
//
// Platform: pure Flutter (works on iOS, Android, web). Uses
// `MapController` from maplibre 0.3.5 for camera control + the
// `liveLocationProvider` for the user's current GPS position.
//
// Rule 14 — every visual value is sourced from MapVisualConstants.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../l10n/app_localizations.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';

/// A single circular glass button in the control stack.
class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.toggled = false,
    this.toggledColor,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool toggled;
  final Color? toggledColor;
  final bool disabled;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.disabled) return;
    await HapticFeedback.selectionClick();
    await _spring.forward(from: 0.78);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final size = MapVisualConstants.controlButtonSize;
    final bgColor = widget.toggled
        ? (widget.toggledColor ?? KinrelColors.orange).withValues(alpha: 0.22)
        : KinrelColors.darkCard.withValues(alpha: 0.82);
    final iconColor = widget.toggled
        ? (widget.toggledColor ?? KinrelColors.orange)
        : KinrelColors.textWhite;
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 380),
      showDuration: const Duration(seconds: 2),
      child: Semantics(
        button: true,
        enabled: !widget.disabled,
        label: widget.label,
        child: ScaleTransition(
          scale: _spring.drive(
            Tween<double>(begin: 1.0, end: 0.88).chain(
              CurveTween(curve: Curves.easeOutCubic),
            ),
          ),
          child: GestureDetector(
            onTap: _handleTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.toggled
                      ? (widget.toggledColor ?? KinrelColors.orange)
                            .withValues(alpha: 0.85)
                      : KinrelColors.darkElevated,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                  if (widget.toggled)
                    BoxShadow(
                      color: (widget.toggledColor ?? KinrelColors.orange)
                          .withValues(alpha: 0.30),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: widget.disabled ? KinrelColors.textDim : iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// P13 — Right-side premium control stack for the family map.
///
/// Renders five (or six, on mid/high-tier devices) vertically-stacked
/// circular buttons above the bottom legend panel. Buttons: locate,
/// zoom+, zoom−, layers, mode toggle, and (when 3D is supported) a
/// "3D Buildings" toggle. The layers button opens a popover with
/// category filter switches.
class MapControlStack extends StatelessWidget {
  const MapControlStack({
    super.key,
    required this.mapController,
    required this.isLightMap,
    required this.onToggleMapMode,
    required this.onToggleLayer,
    required this.layerStates,
    required this.reducedMotion,
    this.buildings3DEnabled = false,
    this.canToggle3D = false,
    this.onToggleBuildings3D,
  });

  /// The maplibre controller used for camera animations.
  final MapController? mapController;

  /// True when the map is currently in light (Snapchat) mode.
  final bool isLightMap;

  /// Callback when the dark/light mode toggle is tapped.
  final VoidCallback onToggleMapMode;

  /// Callback when any layer filter toggle changes.
  /// Receives the [MapControlLayer] that was toggled + its new value.
  final void Function(MapControlLayer layer, bool value) onToggleLayer;

  /// Current on/off state for each category layer.
  final Map<MapControlLayer, bool> layerStates;

  /// True when the user has enabled reduced motion.
  final bool reducedMotion;

  /// Part 1 — Whether 3D building extrusion is currently enabled.
  /// Drives the "3D Buildings" toggle button's toggled state.
  final bool buildings3DEnabled;

  /// Part 1 — Whether the device supports 3D building extrusion at all
  /// (mid/high tier). When false, the "3D Buildings" toggle button is
  /// NOT rendered — low-tier devices force 2D mode with no opt-in.
  final bool canToggle3D;

  /// Part 1 — Callback when the "3D Buildings" toggle is tapped.
  /// Null when [canToggle3D] is false (defensive — the button is not
  /// rendered in that case).
  final VoidCallback? onToggleBuildings3D;

  /// Categories the user can toggle on/off via the Layers popover.
  /// Each maps to a family-place category or status tier.
  static const List<MapControlLayer> _allLayers = MapControlLayer.values;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: MapVisualConstants.controlStackRightInset,
      bottom: MapVisualConstants.controlStackBottomInset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ControlButton(
            icon: Icons.my_location_rounded,
            label: S.of(context)?.familyMapControlLocate ??
                'Locate me',
            onPressed: () => _locate(context),
          ),
          SizedBox(height: MapVisualConstants.controlButtonGap),
          _ControlButton(
            icon: Icons.add_rounded,
            label: S.of(context)?.familyMapControlZoomIn ?? 'Zoom in',
            onPressed: _zoomIn,
          ),
          SizedBox(height: MapVisualConstants.controlButtonGap),
          _ControlButton(
            icon: Icons.remove_rounded,
            label: S.of(context)?.familyMapControlZoomOut ?? 'Zoom out',
            onPressed: _zoomOut,
          ),
          SizedBox(height: MapVisualConstants.controlButtonGap),
          _ControlButton(
            icon: Icons.layers_rounded,
            label: S.of(context)?.familyMapControlLayers ?? 'Layers',
            onPressed: () => _showLayersPopover(context),
          ),
          SizedBox(height: MapVisualConstants.controlButtonGap),
          _ControlButton(
            icon: isLightMap
                ? Icons.dark_mode_rounded
                : Icons.light_mode_rounded,
            label: isLightMap
                ? (S.of(context)?.familyMapControlDarkMode ?? 'Dark map')
                : (S.of(context)?.familyMapControlLightMode ?? 'Light map'),
            onPressed: onToggleMapMode,
            toggled: isLightMap,
            // Part 2 — use KinrelColors token (was hardcoded #F5B841).
            // KinrelColors.brightGold happens to be #F5B841 — same value,
            // now sourced from the shared theme token so it stays in sync
            // with the rest of the app's gold accents.
            toggledColor: KinrelColors.brightGold,
          ),
          // Part 1 — "3D Buildings" toggle. Only rendered when the device
          // supports 3D (mid/high tier). Low-tier devices force 2D mode
          // with no opt-in, so the button is hidden entirely.
          if (canToggle3D && onToggleBuildings3D != null) ...[
            SizedBox(height: MapVisualConstants.controlButtonGap),
            _ControlButton(
              icon: Icons.view_in_ar_rounded,
              label: buildings3DEnabled
                  ? (S.of(context)?.familyMapControl3DBuildingsOff ??
                      'Turn off 3D buildings')
                  : (S.of(context)?.familyMapControl3DBuildingsOn ??
                      'Turn on 3D buildings'),
              onPressed: onToggleBuildings3D!,
              toggled: buildings3DEnabled,
              // Part 2 — use KinrelColors.orange (the app's primary CTA
              // color, = #E8612A) so the 3D toggle's "on" state matches
              // every other active-state highlight in the app.
              toggledColor: KinrelColors.orange,
            ),
          ],
        ],
      )
          .animate(onPlay: (c) => c.forward())
          .fadeIn(
            duration: reducedMotion ? 1.ms : 420.ms,
            delay: reducedMotion ? 0.ms : 240.ms,
          )
          .slideX(
            begin: 0.35,
            end: 0,
            duration: reducedMotion ? 1.ms : 380.ms,
            curve: Curves.easeOutCubic,
          ),
    );
  }

  // ── Camera actions ─────────────────────────────────────────────────

  void _zoomIn() {
    final controller = mapController;
    if (controller == null) return;
    final cam = controller.camera;
    final zoom = (cam?.zoom ?? 4.0) + 1.0;
    controller.animateCamera(
      zoom: zoom.clamp(2.0, 18.0),
      nativeDuration: const Duration(milliseconds: 260),
    );
  }

  void _zoomOut() {
    final controller = mapController;
    if (controller == null) return;
    final cam = controller.camera;
    final zoom = (cam?.zoom ?? 4.0) - 1.0;
    controller.animateCamera(
      zoom: zoom.clamp(2.0, 18.0),
      nativeDuration: const Duration(milliseconds: 260),
    );
  }

  /// Fly the camera to the user's current GPS position (best-effort).
  /// On permission denial or service disabled, shows a snackbar.
  Future<void> _locate(BuildContext context) async {
    final controller = mapController;
    if (controller == null) return;
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) {
        _showSnack(
          context,
          S.of(context)?.familyMapLocateServiceOff ??
              'Location services are off.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack(
          context,
          S.of(context)?.familyMapLocatePermissionDenied ??
              'Location permission denied.',
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      controller.animateCamera(
        center: Geographic(lon: pos.longitude, lat: pos.latitude),
        zoom: 15.0,
        pitch: MapVisualConstants.focusPitch,
        nativeDuration: const Duration(milliseconds: 720),
      );
    } catch (_) {
      _showSnack(
        context,
        S.of(context)?.familyMapLocateFailed ??
            'Could not get your current location.',
      );
    }
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KinrelColors.darkCard,
      ),
    );
  }

  // ── Layers popover ─────────────────────────────────────────────────

  void _showLayersPopover(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(
              right: MapVisualConstants.controlStackRightInset + 56,
              top: MediaQuery.of(dialogContext).size.height * 0.18,
              bottom: MediaQuery.of(dialogContext).size.height * 0.18,
            ),
            child: Material(
              color: Colors.transparent,
              child: _LayersPopover(
                layerStates: layerStates,
                onToggle: onToggleLayer,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Popover panel shown when the Layers button is tapped.
class _LayersPopover extends StatelessWidget {
  const _LayersPopover({
    required this.layerStates,
    required this.onToggle,
  });

  final Map<MapControlLayer, bool> layerStates;
  final void Function(MapControlLayer layer, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.darkElevated, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.layers_rounded,
                size: 18,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.familyMapLayersTitle ?? 'Map layers',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final layer in MapControlStack._allLayers)
            _LayerRow(
              layer: layer,
              value: layerStates[layer] ?? true,
              onChanged: (v) => onToggle(layer, v),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  l10n?.familyMapLayersDone ?? 'Done',
                  style: TextStyle(
                    color: KinrelColors.orange,
                    fontFamily: KinrelTypography.bodyFont,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideX(begin: 0.15, end: 0, duration: 220.ms);
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.layer,
    required this.value,
    required this.onChanged,
  });

  final MapControlLayer layer;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final meta = _layerMeta(layer);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(color: meta.color, width: 1.4),
            ),
            child: Icon(meta.icon, size: 12, color: meta.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              meta.label(context),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: KinrelColors.orange,
            inactiveThumbColor: KinrelColors.textDim,
            inactiveTrackColor: KinrelColors.darkElevated,
          ),
        ],
      ),
    );
  }
}

/// All toggleable layer categories. Order is the display order in the
/// Layers popover.
enum MapControlLayer {
  /// Family homes (current + childhood + ancestral + grandparents).
  homes,

  /// Wedding venues (pulse-animated).
  weddings,

  /// Memorial locations (candle-flicker).
  memorials,

  /// Schools / colleges.
  schools,

  /// Other important places (businesses, temples, vacation, etc.).
  places,

  /// Relationship path overlay (animated curves between pins).
  relationships,

  /// Place callouts (floating chips above buildings).
  callouts,

  /// Live location pulses (teal rings on live tier pins).
  livePulses,
}

/// Maps a [MapControlLayer] to the set of [PlaceType]s it controls.
/// Returns null for non-place layers (relationships, callouts, livePulses)
/// — those are handled separately by the screen.
///
/// Used by [filterPlacesByLayers] to filter the family-places GeoJSON
/// source based on the user's layer toggles. When a layer is OFF, all
/// places of its associated types are excluded from the GeoJSON source
/// (so the 3D building extrusion, glow halo, and fallback circle all
/// disappear together).
Set<PlaceType> placeTypesForLayer(MapControlLayer layer) {
  switch (layer) {
    case MapControlLayer.homes:
      return const {
        PlaceType.currentHome,
        PlaceType.childhoodHome,
        PlaceType.ancestralHome,
        PlaceType.grandparentsHome,
        PlaceType.birthplace,
      };
    case MapControlLayer.weddings:
      return const {PlaceType.wedding};
    case MapControlLayer.memorials:
      return const {PlaceType.memorial};
    case MapControlLayer.schools:
      return const {PlaceType.school};
    case MapControlLayer.places:
      return const {
        PlaceType.familyBusiness,
        PlaceType.familyTemple,
        PlaceType.vacationHome,
        PlaceType.importantPlace,
      };
    case MapControlLayer.relationships:
    case MapControlLayer.callouts:
    case MapControlLayer.livePulses:
      return const {}; // non-place layers
  }
}

/// Filters a list of [FamilyPlace]s by the given layer toggle state.
///
/// A place is INCLUDED when at least one of these is true:
///   • Its PlaceType is not associated with any [MapControlLayer]
///     (forward-compat: future PlaceTypes not yet mapped always show).
///   • The [MapControlLayer] associated with its PlaceType is ON
///     (true in [layerStates], or absent — defaults to true).
///
/// A place is EXCLUDED when the layer associated with its PlaceType
/// is explicitly OFF (false) in [layerStates].
///
/// This is used by the screen to filter the places list before calling
/// [FamilyBuildingLayer.update] so the GeoJSON source reflects the
/// user's layer toggles. The same filtered list is also passed to
/// [PlaceCalloutOverlay] so callouts stay in sync with buildings.
List<FamilyPlace> filterPlacesByLayers(
  List<FamilyPlace> places,
  Map<MapControlLayer, bool> layerStates,
) {
  // Pre-compute the OFF layers (the only ones that exclude places).
  final offTypes = <PlaceType>{};
  for (final layer in MapControlLayer.values) {
    final isOn = layerStates[layer] ?? true;
    if (!isOn) {
      offTypes.addAll(placeTypesForLayer(layer));
    }
  }
  if (offTypes.isEmpty) return List.unmodifiable(places);
  return places.where((p) => !offTypes.contains(p.placeType)).toList();
}

/// Serializes the layer toggle state to a JSON-friendly Map<String, bool>.
/// Used by [MapSessionState.layerToggles] for persistence.
Map<String, bool> serializeLayerToggles(
  Map<MapControlLayer, bool> layerStates,
) {
  return {
    for (final entry in layerStates.entries)
      entry.key.name: entry.value,
  };
}

/// Deserializes the layer toggle state from a Map<String, bool>.
/// Missing keys default to true (forward-compat: new layers added in
/// future versions default to ON until the user explicitly toggles).
/// Unknown keys are dropped (forward-compat: removed layers are forgotten).
Map<MapControlLayer, bool> deserializeLayerToggles(
  Map<String, bool>? stored,
) {
  if (stored == null || stored.isEmpty) {
    return {for (final l in MapControlLayer.values) l: true};
  }
  final out = <MapControlLayer, bool>{
    for (final l in MapControlLayer.values) l: stored[l.name] ?? true,
  };
  return out;
}

class _LayerMeta {
  const _LayerMeta({
    required this.icon,
    required this.color,
    required this.labelResolver,
  });

  final IconData icon;
  final Color color;
  final String Function(BuildContext) labelResolver;

  String label(BuildContext c) => labelResolver(c);
}

_LayerMeta _layerMeta(MapControlLayer l) {
  switch (l) {
    case MapControlLayer.homes:
      return _LayerMeta(
        icon: Icons.home_rounded,
        color: const Color(0xFFE8612A),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerHomes ?? 'Family homes',
      );
    case MapControlLayer.weddings:
      return _LayerMeta(
        icon: Icons.favorite_rounded,
        color: const Color(0xFFE8612A),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerWeddings ?? 'Wedding venues',
      );
    case MapControlLayer.memorials:
      return _LayerMeta(
        icon: Icons.local_florist_rounded,
        color: const Color(0xFFF59240),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerMemorials ?? 'Memorials',
      );
    case MapControlLayer.schools:
      return _LayerMeta(
        icon: Icons.school_rounded,
        color: const Color(0xFF4E6984),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerSchools ?? 'Schools',
      );
    case MapControlLayer.places:
      return _LayerMeta(
        icon: Icons.place_rounded,
        color: const Color(0xFFD85720),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerPlaces ?? 'Important places',
      );
    case MapControlLayer.relationships:
      return _LayerMeta(
        icon: Icons.timeline_rounded,
        color: const Color(0xFFE8B941),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerRelationships ?? 'Relationship paths',
      );
    case MapControlLayer.callouts:
      return _LayerMeta(
        icon: Icons.label_rounded,
        color: const Color(0xFF4ED9C7),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerCallouts ?? 'Place labels',
      );
    case MapControlLayer.livePulses:
      return _LayerMeta(
        icon: Icons.sensors_rounded,
        color: const Color(0xFF4ED9C7),
        labelResolver: (c) =>
            S.of(c)?.familyMapLayerLivePulses ?? 'Live pulses',
      );
  }
}
