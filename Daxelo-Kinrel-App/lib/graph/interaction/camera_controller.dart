// lib/graph/interaction/camera_controller.dart
//
// DAXELO KINREL — Camera Controller (V2.1 Interaction Layer)
//
// Manages pan, zoom, focus, and fit-to-view for the graph canvas.
// Camera NEVER moves without explicit user action. No idle drift.
// No auto-center. No auto-zoom without user action.
//
// Gesture Navigation (P3.1 — spring physics on every gesture response):
//   Pan (single-finger drag): Translate 1:1 with finger, then spring
//     momentum decay (SpringPalette.pan, ~300 ms settle)
//   Pinch Zoom: Scale centered on pinch point, range 0.2x–5.0x, instant
//     1:1 with finger
//   Scroll Zoom (mouse): Scale centered on cursor, range 0.2x–5.0x,
//     instant 1:1 with wheel
//   Double-Tap Focus: Center on node, zoom to 1.5x, spring
//     (SpringPalette.focus)
//   Double-Tap Zoom (empty canvas): Toggle 1× ↔ 2×, spring
//     (SpringPalette.zoom)
//   Keyboard Arrows: Pan 50 px per keypress, spring settle
//     (SpringPalette.pan)
//   Keyboard +/-: Zoom 20% centered on viewport, spring
//     (SpringPalette.zoom)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/physics.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/services/analytics_service.dart';
import '../data/position_memory.dart';
import 'spring_palette.dart';

// ═══════════════════════════════════════════════════════════════════════
// CAMERA CONTROLLER
// ═══════════════════════════════════════════════════════════════════════

/// Controls camera pan, zoom, focus, and fit-to-view for the graph.
///
/// The camera state is exposed as [panX], [panY], [zoomLevel], and
/// [focusedNodeId]. Every change triggers [notifyListeners] so the
/// widget tree can rebuild or repaint efficiently.
///
/// Iron Rules (enforced throughout):
///   1. Never drift — camera never moves without user action.
///   2. Never auto-center — no automatic centering on any event.
///   3. Never auto-zoom without user action.
///
/// Usage:
/// ```dart
/// final camera = CameraController(positionMemory: memory);
/// camera.addListener(rebuildCallback);
/// camera.panBy(50, 0);
/// camera.focusOnNode('member_123', Offset(200, 300));
/// ```
class CameraController extends ChangeNotifier {
  /// Creates a camera controller with optional [positionMemory] for
  /// persistence.
  ///
  /// [minZoom] and [maxZoom] define the zoom range.
  /// Defaults: 0.2–5.0 — the user can zoom out to see large family
  /// graphs and zoom in for detail. Node readability at low zoom is
  /// handled by the semantic LOD system (FULL/CHIP/OVERVIEW tiers),
  /// NOT by clamping the camera.
  /// [momentumDecayDuration] controls how long momentum lasts after a
  /// pan gesture ends (default: 300 ms).
  CameraController({
    PositionMemory? positionMemory,
    double minZoom = 0.2,
    double maxZoom = 5.0,
    Duration momentumDecayDuration = const Duration(milliseconds: 300),
  })  : _positionMemory = positionMemory,
        _minZoom = minZoom,
        _maxZoom = maxZoom,
        _momentumDecayDuration = momentumDecayDuration;

  final PositionMemory? _positionMemory;
  final double _minZoom;
  final double _maxZoom;
  final Duration _momentumDecayDuration;

  // ── Camera State ─────────────────────────────────────────────────

  double _panX = 0.0;
  double _panY = 0.0;
  double _zoomLevel = 1.0;
  String? _focusedNodeId;
  bool _isAnimating = false;

  /// Generation token for cancelling stale animation ticks.
  /// Incremented by _cancelAnimation() so any in-flight tick()
  /// closures self-terminate when they see a stale generation.
  int _animationGeneration = 0;

  /// Velocity for momentum decay after pan gestures.
  double _velocityX = 0.0;
  double _velocityY = 0.0;

  /// Active animation controller (if any).
  AnimationController? _animationController;
  Animation<double>? _panXAnimation;
  Animation<double>? _panYAnimation;
  Animation<double>? _zoomAnimation;

  /// Debounce timer for position persistence.
  Timer? _saveDebounceTimer;

  /// Current family ID for position persistence.
  String? _currentFamilyId;

  // ── v4.4: Viewport Bounds (prevent nodes from being clipped) ──────
  /// Content bounds in graph-space coordinates (the bounding box of all
  /// visible nodes + labels + glow effects). When set, pan is clamped so
  /// the camera can never move the content completely off-screen.
  Rect? _contentBounds;

  /// Viewport size (screen-space) — needed to compute pan limits.
  /// Updated by the view on every LayoutBuilder rebuild.
  Size _viewportSize = Size.zero;

  /// Safe-area padding around the viewport (navbar, bottom controls, FAB).
  /// The camera keeps content within these insets so nodes are never
  /// hidden behind UI elements.
  EdgeInsets _safeAreaInsets = EdgeInsets.zero;

  /// v4.8: Height of the app's own bottom UI chrome (stats panel + bottom
  /// toolbar + FAB area) that overlays the canvas. This is NOT the OS safe
  /// area — it's the in-app UI drawn on top of the graph. When centering
  /// content (fitToView), the camera offsets the vertical center by this
  /// amount so nodes don't land behind the stats card/toolbar.
  ///
  /// Measured from family_graph_screen.dart:
  ///   - Stats panel: ~40px
  ///   - Bottom toolbar: 48px + 8px margin = 56px
  ///   - Margins/gaps: ~24px
  ///   Total: ~120px
  double _appBottomChromeHeight = 120.0;

  /// v4.8: Height of the app's top UI chrome (AppBar) that overlays the canvas.
  double _appTopChromeHeight = 0.0;

  /// Margin (in screen-space pixels) kept between content and viewport edge.
  /// v4.5: Increased from 24 to 48 to account for visual effects that extend
  /// beyond the node bounding box: glow (+24px), drop shadow (+12px),
  /// relationship badges (+12px below), connection indicators (+16px sides).
  static const double _edgeMargin = 100.0; // v4.6: was 48, increased for large nodes + glow

  /// v4.5: Overscan margin (graph-space) added to content bounds so the
  /// camera allows panning slightly beyond the outermost nodes. This gives
  /// users room to see edge nodes' visual effects without them being clipped.
  static const double _overscanMargin = 200.0; // v4.6: was 80, increased to 200 per UX recommendation

  // ── Public Getters ───────────────────────────────────────────────

  /// Current horizontal pan offset in graph-space pixels.
  double get panX => _panX;

  /// Current vertical pan offset in graph-space pixels.
  double get panY => _panY;

  /// Current zoom level (1.0 = default, range [minZoom]–[maxZoom]).
  double get zoomLevel => _zoomLevel;

  /// ID of the currently focused node, or null.
  String? get focusedNodeId => _focusedNodeId;

  /// Whether a camera animation is in progress.
  bool get isAnimating => _isAnimating;

  /// Minimum zoom level.
  double get minZoom => _minZoom;

  /// Maximum zoom level.
  double get maxZoom => _maxZoom;

  // ── v4.4: Content Bounds API ─────────────────────────────────────

  /// Sets the content bounds (graph-space bounding box of all visible
  /// nodes). The camera uses this to clamp panning so nodes can never
  /// be moved completely off-screen.
  ///
  /// Call this whenever the graph layout changes (family switch, add/
  /// remove person, expand/collapse subtree).
  void setContentBounds(Rect? bounds) {
    _contentBounds = bounds;
    // If the current pan is now out of bounds (e.g. after a layout
    // shrink), gently re-clamp it.
    _clampPan();
  }

  /// Sets the current viewport size (screen-space dimensions).
  /// Call from LayoutBuilder on every rebuild.
  void setViewportSize(Size size) {
    _viewportSize = size;
  }

  /// Sets the safe-area insets (navbar height, bottom bar, FAB, notches).
  /// The camera keeps content within these insets.
  void setSafeAreaInsets(EdgeInsets insets) {
    _safeAreaInsets = insets;
  }

  /// v4.8: Sets the app's own bottom UI chrome height (stats panel +
  /// toolbar + FAB area). This is the in-app overlay drawn on top of the
  /// canvas, NOT the OS safe area. When fitToView centers content, it
  /// offsets the vertical center by this amount so nodes don't land
  /// behind the bottom overlay.
  void setAppBottomChromeHeight(double height) {
    _appBottomChromeHeight = height;
  }

  /// v4.8: Sets the app's top UI chrome height (AppBar).
  void setAppTopChromeHeight(double height) {
    _appTopChromeHeight = height;
  }

  /// Computes the allowed pan range so that content stays visible.
  /// Returns null if bounds or viewport are not yet set (no clamping).
  ({double minX, double maxX, double minY, double maxY})? _computePanLimits() {
    if (_contentBounds == null) return null;
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return null;

    // v4.14: Use ACTUAL content bounds (without overscan expansion) for
    // the clamp calculation. The previous code expanded bounds by _overscanMargin
    // (200px), which caused the clamp to allow the node to go 200px into the
    // stats panel area. Now the clamp keeps the actual node bounding box within
    // the effective viewport — the node circle can never go behind the stats panel.
    final cb = _contentBounds!;
    final zoom = _zoomLevel;

    // v4.11: Effective viewport must account for BOTH OS safe areas AND
    // app UI chrome (stats panel, toolbar, AppBar). Previously, only
    // _safeAreaInsets was subtracted — the app chrome was ignored here
    // but WAS used in fitToView centering. This mismatch caused _clampPan()
    // to immediately re-clamp the pan back to the raw viewport center after
    // fitToView had set it to the effective (chrome-adjusted) center.
    final effectiveWidth = _viewportSize.width
        - _safeAreaInsets.left - _safeAreaInsets.right
        - _edgeMargin * 2;
    final effectiveHeight = _viewportSize.height
        - _safeAreaInsets.top - _safeAreaInsets.bottom
        - _appTopChromeHeight - _appBottomChromeHeight
        - _edgeMargin * 2;

    // Content size in screen-space.
    final contentWidth = cb.width * zoom;
    final contentHeight = cb.height * zoom;

    // Content center in screen-space (relative to content top-left).
    final contentCenterX = cb.left * zoom;
    final contentCenterY = cb.top * zoom;

    // v4.11: Viewport center must use the SAME effective center as fitToView.
    // This includes _appTopChromeHeight and _appBottomChromeHeight so the
    // pan clamp and the centering logic agree on where "center" is.
    final viewCenterX = _safeAreaInsets.left + _edgeMargin + effectiveWidth / 2;
    final viewCenterY = _safeAreaInsets.top + _appTopChromeHeight + _edgeMargin + effectiveHeight / 2;

    if (contentWidth <= effectiveWidth) {
      // Content is smaller than viewport — center it, allow small drift.
      final minX = viewCenterX - contentCenterX - contentWidth / 2;
      final maxX = viewCenterX - contentCenterX + contentWidth / 2;
      // For Y
      final minY = viewCenterY - contentCenterY - contentHeight / 2;
      final maxY = viewCenterY - contentCenterY + contentHeight / 2;
      return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
    } else {
      // Content is larger than viewport — allow panning but keep edges
      // within the margin.
      final minX = viewCenterX - contentCenterX - contentWidth / 2 + effectiveWidth / 2;
      final maxX = viewCenterX - contentCenterX + contentWidth / 2 - effectiveWidth / 2;
      final minY = viewCenterY - contentCenterY - contentHeight / 2 + effectiveHeight / 2;
      final maxY = viewCenterY - contentCenterY + contentHeight / 2 - effectiveHeight / 2;
      return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
    }
  }

  /// v4.15: Pan clamping has been REMOVED entirely.
  /// The user can pan freely — nodes go wherever the user drags them.
  /// If a node goes off-screen, that's the user's choice.
  /// Nodes are never partially clipped while on screen (handled by _OverscanClipper).
  /// fitToView still centers correctly on initial load.
  void _clampPan() {
    // No-op — free panning enabled
  }

  /// The combined transform matrix for applying the camera state
  /// to the graph widget tree.
  ///
  /// This matrix should be applied OUTSIDE all RepaintBoundaries
  /// so that pan/zoom only invalidates the transform layer.
  Matrix4 get transformMatrix => Matrix4.identity()
    ..translate(_panX, _panY)
    ..scale(_zoomLevel, _zoomLevel);

  // ── Pan ──────────────────────────────────────────────────────────

  /// Translates the camera by [dx] and [dy] pixels instantly.
  ///
  /// Used for live single-finger drag — the camera tracks the finger
  /// 1:1 with no smoothing so the gesture feels direct and responsive.
  ///
  /// For keyboard-driven pan (discrete arrow-key presses) prefer
  /// [panBySpring], which animates the pan with a critically-damped
  /// spring so each keypress has a subtle settle.
  ///
  /// For momentum after a pan gesture, call [applyMomentum] after
  /// the gesture ends.
  void panBy(double dx, double dy) {
    _panX += dx;
    _panY += dy;
    _clampPan(); // v4.4: keep nodes visible
    _focusedNodeId = null;
    _scheduleSave();
    notifyListeners();
  }

  /// Pans the camera by [dx] and [dy] pixels using a critically-damped
  /// spring (SpringPalette.pan). Used for discrete pan events where a
  /// direct 1:1 jump would feel jarring — e.g. keyboard arrow keys.
  ///
  /// [reducedMotion] — when true, snaps instantly (Duration.zero) per
  /// WCAG 2.3.3 / Guardrail 2 (opt-out respected).
  ///
  /// Live finger-drag pan should still call [panBy] for 1:1 tracking;
  /// this method is for non-gesture pan triggers.
  void panBySpring(double dx, double dy, {bool reducedMotion = false}) {
    if (reducedMotion || dx == 0 && dy == 0) {
      panBy(dx, dy);
      return;
    }
    final targetPanX = _panX + dx;
    final targetPanY = _panY + dy;
    _animateWithSpring(
      targetPanX: targetPanX,
      targetPanY: targetPanY,
      targetZoom: _zoomLevel,
      spring: SpringPalette.pan,
      clearFocusedNodeId: true,
    );
  }

  /// Applies momentum decay after a pan gesture ends using a spring
  /// (SpringPalette.pan) seeded with the gesture's release velocity.
  ///
  /// P3.1: replaces the previous linear `1 - t^2` deceleration with a
  /// critically-damped spring so the camera settles naturally instead
  /// of cutting to zero. The spring's start velocity is the clamped
  /// gesture velocity, so a flick feels like the camera was thrown and
  /// decelerates with the same feel as a thrown physical object.
  ///
  /// [velocityX] and [velocityY] are the gesture velocities in
  /// pixels per second, clamped to ±4000 px/sec to prevent extreme
  /// flicks from overshooting the viewport.
  void applyMomentum(double velocityX, double velocityY) {
    // Premium control: max velocity clamped to 1800 px/sec.
    // This prevents fast flicks from sending the graph flying across
    // the screen. 1800 px/s is still fast enough for natural fling
    // but doesn't overshoot. Combined with the reduced projection
    // factor in _startMomentumDecay (0.15s), a max-velocity flick
    // travels only 270px — less than one screen width on most phones.
    const maxVelocity = 1800.0; // px/sec — clamp hard flicks
    // Save the clamped velocities BEFORE _startMomentumDecay, which
    // calls _cancelAnimation() (which resets _velocityX/_velocityY to
    // zero as part of invalidating in-flight animations).
    final clampedX = velocityX.clamp(-maxVelocity, maxVelocity);
    final clampedY = velocityY.clamp(-maxVelocity, maxVelocity);
    _startMomentumDecay(clampedX, clampedY);
  }

  // ── Zoom ─────────────────────────────────────────────────────────

  /// Sets the zoom level instantly, clamped to [minZoom]–[maxZoom].
  ///
  /// Used for live pinch/scroll zoom — the camera tracks the gesture
  /// 1:1 with no smoothing so the zoom feels direct. For programmatic
  /// zoom transitions (double-tap, keyboard +/-, buttons) prefer
  /// [zoomToSpring], which animates with a critically-damped spring.
  ///
  /// [focalPoint] is the screen-space point that should remain
  /// stationary during the zoom. If null, the viewport center is used.
  void zoomTo(double level, {Offset? focalPoint}) {
    final newZoom = level.clamp(_minZoom, _maxZoom);
    const zoomEpsilon = 0.0001;
    if ((newZoom - _zoomLevel).abs() < zoomEpsilon) return;

    // Adjust pan so the focal point stays fixed.
    if (focalPoint != null) {
      final scale = newZoom / _zoomLevel;
      _panX = focalPoint.dx - scale * (focalPoint.dx - _panX);
      _panY = focalPoint.dy - scale * (focalPoint.dy - _panY);
    }

    _zoomLevel = newZoom;
    _clampPan(); // v4.4: re-clamp after zoom (content may shrink/grow)
    _scheduleSave();

    AnalyticsService.instance.logGraphZoomed(_zoomLevel);

    notifyListeners();
  }

  /// Zooms in by 20% centered on the viewport using a spring
  /// (SpringPalette.zoom).
  ///
  /// Typically triggered by keyboard "+" key.
  void zoomIn({Size? viewportSize, bool reducedMotion = false}) {
    final center = viewportSize != null
        ? Offset(viewportSize.width / 2, viewportSize.height / 2)
        : null;
    zoomToSpring(_zoomLevel * 1.2, focalPoint: center, reducedMotion: reducedMotion);
  }

  /// Zooms out by 20% centered on the viewport using a spring
  /// (SpringPalette.zoom).
  ///
  /// Typically triggered by keyboard "-" key.
  void zoomOut({Size? viewportSize, bool reducedMotion = false}) {
    final center = viewportSize != null
        ? Offset(viewportSize.width / 2, viewportSize.height / 2)
        : null;
    zoomToSpring(_zoomLevel / 1.2, focalPoint: center, reducedMotion: reducedMotion);
  }

  /// Animates the zoom to [level] using a critically-damped spring
  /// (SpringPalette.zoom). Used for programmatic zoom transitions:
  /// double-tap toggle, keyboard +/-, zoom buttons.
  ///
  /// [focalPoint] is the screen-space point that should remain
  /// stationary during the zoom (the point under the user's finger
  /// for double-tap, viewport center for keyboard +/-).
  ///
  /// [reducedMotion] — when true, snaps instantly (Duration.zero) per
  /// WCAG 2.3.3 / Guardrail 2 (opt-out respected).
  ///
  /// Live pinch/scroll zoom should still call [zoomTo] for 1:1
  /// tracking; this method is for non-gesture zoom triggers.
  void zoomToSpring(double level, {Offset? focalPoint, bool reducedMotion = false}) {
    final newZoom = level.clamp(_minZoom, _maxZoom);
    const zoomEpsilon = 0.0001;
    if ((newZoom - _zoomLevel).abs() < zoomEpsilon) return;

    if (reducedMotion) {
      zoomTo(level, focalPoint: focalPoint);
      return;
    }

    // Compute the target pan so the focal point stays fixed at the
    // end of the spring (we animate pan + zoom together so the focal
    // point stays stationary DURING the spring, not just at the end).
    double targetPanX = _panX;
    double targetPanY = _panY;
    if (focalPoint != null) {
      final scale = newZoom / _zoomLevel;
      targetPanX = focalPoint.dx - scale * (focalPoint.dx - _panX);
      targetPanY = focalPoint.dy - scale * (focalPoint.dy - _panY);
    }

    AnalyticsService.instance.logGraphZoomed(newZoom);
    _animateWithSpring(
      targetPanX: targetPanX,
      targetPanY: targetPanY,
      targetZoom: newZoom,
      spring: SpringPalette.zoom,
      clearFocusedNodeId: false,
    );
  }

  // ── Smart Focus ──────────────────────────────────────────────────

  /// Centers the viewport on a node with optimal zoom.
  ///
  /// Trigger: Double-tap, "Focus" context menu, search result tap.
  ///
  /// [nodeId] is the target node ID.
  /// [nodePosition] is the node's position in graph space.
  /// [connectedNodeCount] is used to compute optimal zoom (more
  ///   connections = wider view).
  /// [viewportSize] is the viewport dimensions for centering.
  ///
  /// Animation: spring (SpringPalette.focus) — slight settle, cinematic.
  /// [reducedMotion] — when true, snaps instantly (Duration.zero).
  void focusOnNode(
    String nodeId,
    Offset nodePosition, {
    int connectedNodeCount = 0,
    Size viewportSize = Size.zero,
    bool reducedMotion = false,
  }) {
    _focusedNodeId = nodeId;

    // Compute optimal zoom based on connected nodes.
    double optimalZoom;
    if (connectedNodeCount <= 3) {
      optimalZoom = 1.5;
    } else if (connectedNodeCount <= 10) {
      optimalZoom = 1.0;
    } else if (connectedNodeCount <= 30) {
      optimalZoom = 0.7;
    } else {
      optimalZoom = 0.5;
    }
    optimalZoom = optimalZoom.clamp(_minZoom, _maxZoom);

    // Compute pan so the node is centered.
    final targetPanX = viewportSize.width > 0
        ? (viewportSize.width / 2) - (nodePosition.dx * optimalZoom)
        : -nodePosition.dx * optimalZoom;
    final targetPanY = viewportSize.height > 0
        ? (viewportSize.height / 2) - (nodePosition.dy * optimalZoom)
        : -nodePosition.dy * optimalZoom;

    // P3.1: route through the spring-based animator. P2.2 introduced
    // animateToWithSpring for focus pulls; P3.1 makes it the canonical
    // path for focusOnNode and respects reduced motion at the call site.
    animateToWithSpring(
      targetPanX,
      targetPanY,
      optimalZoom,
      reducedMotion: reducedMotion,
    );
  }

  // ── Smart Fit-to-View ────────────────────────────────────────────

  /// Scales and pans the camera so all visible nodes fit in the
  /// viewport with 10% padding.
  ///
  /// Trigger: "Fit to View" button or Ctrl/Cmd+F.
  ///
  /// [positions] maps node IDs to their graph-space positions.
  /// [viewportSize] is the viewport dimensions.
  ///
  /// Animation: 600 ms smooth zoom + pan.
  /// Zoom bounds: min 0.3x, max 2.0x (tighter than normal range).
  void fitToView(Map<String, Offset> positions, Size viewportSize) {
    if (positions.isEmpty || viewportSize == Size.zero) return;

    // Screenshot Bug B fix: compute the bounding box of all node RECTANGLES
    // (position + node dimensions), not just the position points. The
    // previous code used only the top-left positions, so the rightmost
    // node's circle + name label extended beyond the bounding box and
    // got clipped by the viewport's ClipRect when the camera framed the
    // graph. We also add 20% padding (up from 10%) to leave room for
    // node labels, badges, and glow effects that extend beyond the
    // node circle.
    //
    // v4.5: Node dimensions expanded to account for visual effects that
    // extend beyond the base 140×176 node: glow (+24px each side), drop
    // shadow (+12px each side), badges (+20px below), connection indicators
    // (+16px each side). Total: 140+80=220 wide, 176+80=256 tall.
    const nodeWidth = 220.0;   // 140 base + 40 glow/shadow + 40 indicators
    const nodeHeight = 256.0;  // 176 base + 40 glow/shadow + 40 badges

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx + nodeWidth > maxX) maxX = pos.dx + nodeWidth;
      if (pos.dy + nodeHeight > maxY) maxY = pos.dy + nodeHeight;
    }

    // v62.5: For single-node graphs (min == max), add a minimum
    // bounding box size so the zoom calculation doesn't produce
    // extreme values. This prevents the node from being off-screen
    // until the user zooms in.
    final rawWidth = maxX - minX;
    final rawHeight = maxY - minY;
    const minBoxSize = 200.0; // Minimum 200x200 bounding box
    // v4.5: 30% padding (was 20%) to leave room for node labels, badges,
    // glow effects, drop shadows, and connection indicators that extend
    // beyond the node circle. This ensures nodes are NEVER placed directly
    // on viewport edges after fit-to-screen.
    final width = (rawWidth < minBoxSize ? minBoxSize : rawWidth) * 1.3;
    final height = (rawHeight < minBoxSize ? minBoxSize : rawHeight) * 1.3;
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    // Compute scale to fit.
    final scaleX = viewportSize.width / width;
    final scaleY = viewportSize.height / height;
    var fitZoom = math.min(scaleX, scaleY);

    // v62.5: For single-node or tiny graphs, target 1.0 (100%)
    // so the node is clearly visible without zooming.
    if (rawWidth < 50 && rawHeight < 50) {
      fitZoom = 1.0;
    } else {
      // Clamp fit-to-screen zoom to the valid camera range.
      // With minZoom=0.2, large graphs can fit at low zoom
      // (entering CHIP or OVERVIEW LOD tiers).
      fitZoom = fitZoom.clamp(_minZoom, 2.0);
    }

    // v4.8: Compute pan to center using the EFFECTIVE viewport — not the
    // raw viewport height. The app draws bottom UI chrome (stats panel +
    // toolbar + FAB) as an overlay on top of the canvas, so the visual
    // center of the usable area is higher than the raw viewport center.
    // Without this fix, single-node graphs (brand-new families) get
    // centered behind the bottom overlay, making the node look cut off.
    final topInset = _safeAreaInsets.top + _appTopChromeHeight;
    final bottomInset = _safeAreaInsets.bottom + _appBottomChromeHeight;
    final effectiveHeight = viewportSize.height - topInset - bottomInset;
    final effectiveCenterY = topInset + effectiveHeight / 2;
    final effectiveCenterX = viewportSize.width / 2; // no horizontal chrome

    final targetPanX = effectiveCenterX - (centerX * fitZoom);
    final targetPanY = effectiveCenterY - (centerY * fitZoom);

    // v62.5: Use instant set (no animation) for initial fit to prevent
    // blank screen during the 600ms animation. The animation was causing
    // the graph to appear blank until the animation completed.
    _panX = targetPanX;
    _panY = targetPanY;
    _zoomLevel = fitZoom;
    _scheduleSave();
    notifyListeners();
  }

  // ── Animated Transition ──────────────────────────────────────────

  /// Animates the camera to the given [targetPanX], [targetPanY], and
  /// [targetZoom] over [duration] with [curve].
  ///
  /// Cancels any existing animation before starting a new one.
  void animateTo(
    double targetPanX,
    double targetPanY,
    double targetZoom, {
    Duration duration = const Duration(milliseconds: 400),
    Curve curve = Curves.easeInOut,
  }) {
    _cancelAnimation();
    final myGeneration = ++_animationGeneration;

    // Use a ticker-based animation via a single-frame vsync.
    final startPanX = _panX;
    final startPanY = _panY;
    final startZoom = _zoomLevel;
    final targetZoomClamped = targetZoom.clamp(_minZoom, _maxZoom);

    _isAnimating = true;
    notifyListeners();

    // Create a simple animation using Timer-based interpolation.
    final startTime = DateTime.now();
    final durationMs = duration.inMilliseconds;

    void tick() {
      if (myGeneration != _animationGeneration) return; // superseded
      final elapsed =
          DateTime.now().difference(startTime).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      final curvedT = curve.transform(t);

      _panX = startPanX + (targetPanX - startPanX) * curvedT;
      _panY = startPanY + (targetPanY - startPanY) * curvedT;
      _zoomLevel =
          startZoom + (targetZoomClamped - startZoom) * curvedT;
      _clampPan(); // v4.4: keep nodes visible during animation

      notifyListeners();

      if (t < 1.0) {
        Future<void>.delayed(const Duration(milliseconds: 16), tick);
      } else {
        _isAnimating = false;
        _scheduleSave();
        notifyListeners();
      }
    }

    tick();
  }

  // ── P2.2 / P3.1: Spring Physics Transitions ──────────────────────────

  /// Animates the camera to the given targets using the focus spring
  /// (SpringPalette.focus) — slight settle, cinematic.
  ///
  /// P2.2 introduced this method for focus pulls. P3.1 makes it the
  /// canonical animation path for all programmatic camera transitions
  /// (focusOnNode, fit-to-view via spring, history navigation) and
  /// routes pan/zoom springs through the private [_animateWithSpring]
  /// helper so every gesture response shares the same spring plumbing.
  ///
  /// [reducedMotion] — when true, snaps instantly (Duration.zero) per
  /// WCAG 2.3.3 / Guardrail 2 (opt-out respected).
  void animateToWithSpring(
    double targetPanX,
    double targetPanY,
    double targetZoom, {
    bool reducedMotion = false,
  }) {
    _animateWithSpring(
      targetPanX: targetPanX,
      targetPanY: targetPanY,
      targetZoom: targetZoom,
      spring: SpringPalette.focus,
      clearFocusedNodeId: false,
      reducedMotion: reducedMotion,
    );
  }

  /// Internal spring animator shared by [panBySpring], [zoomToSpring],
  /// and [animateToWithSpring]. Each caller picks the appropriate
  /// [SpringDescription] from [SpringPalette].
  ///
  /// [clearFocusedNodeId] — when true, clears [_focusedNodeId] (used by
  /// pan operations that break the focus lock).
  /// [reducedMotion] — when true, snaps instantly (Duration.zero).
  void _animateWithSpring({
    required double targetPanX,
    required double targetPanY,
    required double targetZoom,
    required SpringDescription spring,
    bool clearFocusedNodeId = false,
    bool reducedMotion = false,
  }) {
    if (reducedMotion) {
      _panX = targetPanX;
      _panY = targetPanY;
      _zoomLevel = targetZoom.clamp(_minZoom, _maxZoom);
      if (clearFocusedNodeId) _focusedNodeId = null;
      _scheduleSave();
      notifyListeners();
      return;
    }

    _cancelAnimation();
    final myGeneration = ++_animationGeneration;

    final startPanX = _panX;
    final startPanY = _panY;
    final startZoom = _zoomLevel;
    final targetZoomClamped = targetZoom.clamp(_minZoom, _maxZoom);

    _isAnimating = true;
    if (clearFocusedNodeId) _focusedNodeId = null;
    notifyListeners();

    // Create three independent spring simulations (panX, panY, zoom).
    // Start velocity is 0 — these are programmatic transitions, not
    // gesture-velocity-seeded (momentum decay is handled separately
    // in [_startMomentumDecay]).
    final simX = SpringSimulation(spring, startPanX, targetPanX, 0);
    final simY = SpringSimulation(spring, startPanY, targetPanY, 0);
    final simZoom =
        SpringSimulation(spring, startZoom, targetZoomClamped, 0);

    // Set tolerance so the simulation ends when the values are close enough.
    simX.tolerance = SpringPalette.defaultTolerance;
    simY.tolerance = SpringPalette.defaultTolerance;
    simZoom.tolerance = SpringPalette.normalizedTolerance;

    final startTime = DateTime.now();

    void tick() {
      if (myGeneration != _animationGeneration) return; // superseded
      final elapsedSeconds =
          DateTime.now().difference(startTime).inMilliseconds / 1000.0;

      _panX = simX.x(elapsedSeconds);
      _panY = simY.x(elapsedSeconds);
      _zoomLevel = simZoom.x(elapsedSeconds);
      _clampPan(); // v4.4: keep nodes visible during spring animation

      notifyListeners();

      // Continue until all three simulations have settled.
      if (!simX.isDone(elapsedSeconds) ||
          !simY.isDone(elapsedSeconds) ||
          !simZoom.isDone(elapsedSeconds)) {
        Future<void>.delayed(const Duration(milliseconds: 16), tick);
      } else {
        _panX = targetPanX;
        _panY = targetPanY;
        _zoomLevel = targetZoomClamped;
        _clampPan(); // v4.4: final clamp
        _isAnimating = false;
        _scheduleSave();
        notifyListeners();
      }
    }

    tick();
  }

  // ── Reset ────────────────────────────────────────────────────────

  // ── Initial Fit (blank-screen fix) ──────────────────────────────────────

  /// Guard so the one-time initial fit runs at most once per data load.
  bool _didInitialFit = false;

  /// Whether the one-time initial fit has already run for the current family.
  bool get didInitialFit => _didInitialFit;

  /// Performs a ONE-TIME fit-to-view the first time graph data is available
  /// and the viewport size is known.
  ///
  /// This is a sanctioned exception to the "no auto-center" rule: it is the
  /// initial framing of the graph, NOT an automatic re-center on every event.
  /// Without it, the camera stays at the origin (pan 0,0 / zoom 1.0) while the
  /// center-anchored layout places nodes far from (0,0) — so the viewport
  /// culler sees no nodes in view and the canvas renders blank. This is the
  /// root cause of the historical blank-screen bug that triggered the v40
  /// rewrite.
  ///
  /// Safe to call on every build / post-frame callback — it no-ops after the
  /// first successful fit and while the viewport size is still zero. Call
  /// [resetInitialFit] when switching to a different family / dataset.
  void initialFitOnce(Map<String, Offset> positions, Size viewportSize) {
    if (_didInitialFit) return;
    if (positions.isEmpty) return;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    fitToView(positions, viewportSize);
    _didInitialFit = true;
  }

  /// Clears the initial-fit guard so the next [initialFitOnce] will run again.
  /// Call when loading a different family so it re-frames the new graph.
  void resetInitialFit() {
    _didInitialFit = false;
  }

  // ── Reset ────────────────────────────────────────────────────────────────

  /// Resets the camera to the default position (origin, zoom 1.0).
  ///
  /// Together with [initialFitOnce], this is one of only two exceptions to the
  /// "no auto-center" rule — it requires explicit user action (e.g. a
  /// "Reset View" button).
  void reset() {
    _cancelAnimation();
    _panX = 0.0;
    _panY = 0.0;
    _zoomLevel = 1.0;
    _focusedNodeId = null;
    _velocityX = 0.0;
    _velocityY = 0.0;
    _scheduleSave();
    notifyListeners();
  }

  /// v107.1: Resets the view so the focus node (the green "You" /
  /// anchor node) is at the EXACT center of the viewport, at the
  /// default zoom level (1.0).
  ///
  /// This is the "Reset View" button behavior. It:
  ///   1. Restores the default zoom level (1.0).
  ///   2. Centers the focus node's VISUAL CIRCLE (not the bounding
  ///      box) at the exact viewport center.
  ///   3. Works regardless of the current zoom or pan position.
  ///
  /// [focusNodePosition] — the graph-space position of the node to
  ///   center. Per the layout system (node_layer.dart), this is the
  ///   CENTER of the node's Positioned box (NOT the top-left). The
  ///   visual circle center is offset from this by
  ///   _kCircleCenterYOffset (-28px Y, 0px X) because the circle
  ///   sits at the top of the node's Column.
  /// [circleCenterYOffset] — the Y offset from the box center to the
  ///   visual circle center. Passed in by the caller (the engine view
  ///   passes _kCircleCenterYOffset = -28.0) so the camera controller
  ///   doesn't hardcode layout internals.
  /// [viewportSize] — the viewport dimensions.
  /// [reducedMotion] — when true, snaps instantly (no animation).
  ///
  /// The centering math is pure viewport geometry:
  ///   targetPan = viewportCenter - focusCircleCenter * zoom
  /// This places the focus node's visual circle at the exact viewport
  /// center (viewportSize/2) at the default zoom (1.0), every time.
  void resetView({
    required Offset focusNodePosition,
    required double circleCenterYOffset,
    required Size viewportSize,
    bool reducedMotion = false,
  }) {
    if (viewportSize == Size.zero) {
      // Defensive fallback: if viewport isn't resolved, just reset
      // to origin + default zoom.
      reset();
      return;
    }

    _cancelAnimation();

    // The focus node's VISUAL CIRCLE center in graph space.
    // layout.positions gives the box CENTER (node_layer.dart places
    // the Positioned box centered at pos). The visual circle is at
    // the top of the Column, so its center is offset by
    // circleCenterYOffset (negative = above box center) in Y, and
    // 0 in X (the circle is horizontally centered in the box).
    final focusCircleCenter = Offset(
      focusNodePosition.dx,
      focusNodePosition.dy + circleCenterYOffset,
    );

    // Restore the DEFAULT zoom level (1.0) — not a fit-to-graph
    // zoom. The user requirement: "Reset should restore the default
    // zoom level and perfectly center the base node every time."
    const targetZoom = 1.0;

    // Pan so the focus node's visual circle center lands at the
    // exact viewport center.
    final targetPanX =
        (viewportSize.width / 2) - (focusCircleCenter.dx * targetZoom);
    final targetPanY =
        (viewportSize.height / 2) - (focusCircleCenter.dy * targetZoom);

    if (reducedMotion) {
      _panX = targetPanX;
      _panY = targetPanY;
      _zoomLevel = targetZoom;
      _scheduleSave();
      notifyListeners();
    } else {
      // Smooth animated transition to the default zoom + centered
      // focus node.
      animateTo(
        targetPanX,
        targetPanY,
        targetZoom,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // ── Restoration from Position Memory ─────────────────────────────

  /// Restores the camera position from [PositionMemory].
  ///
  /// If a saved position exists, it is applied instantly (no
  /// animation). If the underlying data has changed since the
  /// position was saved, [needsRepositioning] will be true and
  /// the caller should apply a 300 ms repositioning animation.
  ///
  /// [familyId] identifies the family whose position to restore.
  /// [defaultPosition] is the fallback if no saved position exists.
  ///
  /// Returns the restored [CameraPosition], or null if none found.
  Future<CameraPosition?> restorePosition(
    String familyId, {
    CameraPosition? defaultPosition,
  }) async {
    // Track the family ID for automatic position saves.
    _currentFamilyId = familyId;

    if (_positionMemory == null) return null;

    final saved = await _positionMemory.loadPosition(familyId);
    if (saved == null) {
      if (defaultPosition != null) {
        _panX = defaultPosition.panX;
        _panY = defaultPosition.panY;
        _zoomLevel = defaultPosition.zoomLevel;
        _focusedNodeId = defaultPosition.focusedNodeId;
        notifyListeners();
      }
      return defaultPosition;
    }

    // Apply instantly — Iron Rule: never drift.
    _panX = saved.panX;
    _panY = saved.panY;
    _zoomLevel = saved.zoomLevel;
    _focusedNodeId = saved.focusedNodeId;
    notifyListeners();

    return saved;
  }

  /// Returns whether the data has changed since the position was
  /// saved, indicating a 300 ms repositioning animation is needed.
  Future<bool> needsRepositioning(String familyId) async {
    if (_positionMemory == null) return false;
    return _positionMemory.hasDataChanged(familyId);
  }

  // ── Viewport Computation ─────────────────────────────────────────

  /// Computes the current viewport rectangle in graph-space
  /// coordinates.
  ///
  /// [viewportSize] is the screen-space viewport dimensions.
  Rect computeViewport(Size viewportSize) {
    final left = -_panX / _zoomLevel;
    final top = -_panY / _zoomLevel;
    final width = viewportSize.width / _zoomLevel;
    final height = viewportSize.height / _zoomLevel;
    return Rect.fromLTWH(left, top, width, height);
  }

  // ── v4.4: Auto-Recenter ─────────────────────────────────────────

  /// Checks if the current viewport shows any content. If not (e.g.
  /// after a layout update changed node positions), gently animates
  /// the camera back to a valid position so nodes are visible.
  ///
  /// Call this after any layout change (add/remove person, expand/
  /// collapse subtree, family switch).
  void recenterIfNeeded() {
    if (_contentBounds == null) return;
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return;
    if (_isAnimating) return; // don't interrupt active animations

    final limits = _computePanLimits();
    if (limits == null) return;

    final needsRecenterX =
        _panX < limits.minX - 1 || _panX > limits.maxX + 1;
    final needsRecenterY =
        _panY < limits.minY - 1 || _panY > limits.maxY + 1;

    if (needsRecenterX || needsRecenterY) {
      // Gently animate to the clamped position
      final targetX = _panX.clamp(limits.minX, limits.maxX);
      final targetY = _panY.clamp(limits.minY, limits.maxY);
      animateTo(
        targetX,
        targetY,
        _zoomLevel,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────

  @override
  void dispose() {
    _cancelAnimation();
    _saveDebounceTimer?.cancel();
    _animationController?.dispose();
    // Flush any pending position save.
    _positionMemory?.flush();
    super.dispose();
  }

  // ── Private Methods ──────────────────────────────────────────────

  /// Starts momentum decay animation after a pan gesture ends.
  ///
  /// P3.1: replaces the previous linear `1 - t^2` deceleration with a
  /// critically-damped spring (SpringPalette.pan) seeded with the
  /// gesture's release velocity. The camera's pan position asymptotically
  /// approaches the position it would reach if the gesture velocity
  /// continued indefinitely, decelerating naturally.
  ///
  /// [velocityX] / [velocityY] are the clamped gesture velocities
  /// (already clamped by [applyMomentum]). Passed as parameters because
  /// [_cancelAnimation] resets the field velocities to zero before the
  /// spring can read them.
  void _startMomentumDecay(double velocityX, double velocityY) {
    _cancelAnimation();
    final myGeneration = ++_animationGeneration;

    final startPanX = _panX;
    final startPanY = _panY;
    final startVelocityX = velocityX;
    final startVelocityY = velocityY;

    _isAnimating = true;
    notifyListeners();

    // P3.1: Spring-seeded momentum. The target is the position the
    // camera would reach at constant velocity for a short projection
    // window, but the critically-damped spring decelerates it to zero
    // there. Using a fixed projection gives a consistent feel regardless
    // of flick strength — the spring does the work of decelerating from
    // the start velocity to zero.
    //
    // SpringPalette.pan is critically damped so the camera does NOT
    // overshoot (no oscillation). Tolerance ensures the simulation
    // terminates within ~300ms for typical flick velocities.
    final spring = SpringPalette.pan;

    // Premium control: momentum projection factor of 0.15s.
    // This means a max-velocity 1800px/s flick targets 270px away
    // (1800 × 0.15 = 270). On a 390px-wide phone, that's ~0.7 screen
    // widths — enough to feel like a natural continuation of the drag
    // without overshooting. The previous value of 0.4s targeted 880px
    // (2.25 screen widths) which felt uncontrolled.
    //
    // The spring is critically damped (damping ratio ≈ 0.87), so there
    // is NO oscillation — the camera smoothly decelerates to the target
    // and stops. The user perceives this as "the graph glides to a halt
    // right where I expected."
    const momentumProjectionSeconds = 0.15;
    final targetPanX = startPanX + startVelocityX * momentumProjectionSeconds;
    final targetPanY = startPanY + startVelocityY * momentumProjectionSeconds;

    final simX = SpringSimulation(
      spring,
      startPanX,
      targetPanX,
      startVelocityX,
    )..tolerance = SpringPalette.defaultTolerance;
    final simY = SpringSimulation(
      spring,
      startPanY,
      targetPanY,
      startVelocityY,
    )..tolerance = SpringPalette.defaultTolerance;

    final startTime = DateTime.now();

    void tick() {
      if (myGeneration != _animationGeneration) return; // superseded
      final elapsedSeconds =
          DateTime.now().difference(startTime).inMilliseconds / 1000.0;

      _panX = simX.x(elapsedSeconds);
      _panY = simY.x(elapsedSeconds);
      _clampPan(); // v4.4: keep nodes visible during momentum decay

      notifyListeners();

      if (!simX.isDone(elapsedSeconds) || !simY.isDone(elapsedSeconds)) {
        Future<void>.delayed(const Duration(milliseconds: 16), tick);
      } else {
        _panX = targetPanX;
        _panY = targetPanY;
        _clampPan(); // v4.4: final clamp
        _isAnimating = false;
        _velocityX = 0.0;
        _velocityY = 0.0;
        _scheduleSave();
        notifyListeners();
      }
    }

    tick();
  }

  /// Cancels any active animation and invalidates in-flight tick() closures.
  void _cancelAnimation() {
    _isAnimating = false;
    _velocityX = 0.0;
    _velocityY = 0.0;
    _animationGeneration++; // invalidates any in-flight tick() closures
  }

  /// Public so gesture handlers can cancel a fling/animateTo when a new
  /// gesture starts.
  void stopAnimation() => _cancelAnimation();

  /// Sets the current family ID for position persistence.
  ///
  /// This must be called before positions can be automatically
  /// saved. Typically called when a family graph is loaded.
  void setFamilyId(String familyId) {
    _currentFamilyId = familyId;
  }

  /// Schedules a debounced save of the camera position to
  /// [PositionMemory].
  void _scheduleSave() {
    if (_positionMemory == null || _currentFamilyId == null) return;

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _positionMemory!.savePosition(
        _currentFamilyId!,
        panX: _panX,
        panY: _panY,
        zoomLevel: _zoomLevel,
        focusedNodeId: _focusedNodeId,
      );
    });
  }
}
