// lib/graph/interaction/camera_controller.dart
//
// DAXELO KINREL — Camera Controller (V2.1 Interaction Layer)
//
// Manages pan, zoom, focus, and fit-to-view for the graph canvas.
// Camera NEVER moves without explicit user action. No idle drift.
// No auto-center. No auto-zoom without user action.
//
// Gesture Navigation:
//   Pan (single-finger drag): Translate 1:1, instant with momentum
//     decay (300 ms)
//   Pinch Zoom: Scale centered on pinch point, range 0.2x–5.0x,
//     smooth 150 ms
//   Scroll Zoom (mouse): Scale centered on cursor, range 0.2x–5.0x,
//     smooth 100 ms
//   Double-Tap Focus: Center on node, zoom to 1.5x, 400 ms curved
//     ease-in-out
//   Keyboard Arrows: Pan 50 px per keypress, linear 50 ms
//   Keyboard +/-: Zoom 20% centered on viewport, smooth 100 ms

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/services/analytics_service.dart';
import '../data/position_memory.dart';

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
  /// [minZoom] and [maxZoom] define the zoom range (default: 0.2x–5.0x).
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
  /// Used for:
  /// - Single-finger drag (pan gesture)
  /// - Keyboard arrow keys (50 px per press)
  ///
  /// For momentum after a pan gesture, call [applyMomentum] after
  /// the gesture ends.
  void panBy(double dx, double dy) {
    _panX += dx;
    _panY += dy;
    _focusedNodeId = null;
    _scheduleSave();
    notifyListeners();
  }

  /// Applies momentum decay after a pan gesture ends.
  ///
  /// [velocityX] and [velocityY] are the gesture velocities in
  /// pixels per second. The camera decelerates to zero over
  /// [_momentumDecayDuration].
  void applyMomentum(double velocityX, double velocityY) {
    _velocityX = velocityX;
    _velocityY = velocityY;
    _startMomentumDecay();
  }

  // ── Zoom ─────────────────────────────────────────────────────────

  /// Sets the zoom level instantly, clamped to [minZoom]–[maxZoom].
  ///
  /// [focalPoint] is the screen-space point that should remain
  /// stationary during the zoom. If null, the viewport center is used.
  ///
  /// Used for:
  /// - Pinch zoom (scaled around pinch center)
  /// - Scroll zoom (scaled around cursor)
  /// - Keyboard +/- (20% step centered on viewport)
  void zoomTo(double level, {Offset? focalPoint}) {
    final newZoom = level.clamp(_minZoom, _maxZoom);
    if (newZoom == _zoomLevel) return;

    // Adjust pan so the focal point stays fixed.
    if (focalPoint != null) {
      final scale = newZoom / _zoomLevel;
      _panX = focalPoint.dx - scale * (focalPoint.dx - _panX);
      _panY = focalPoint.dy - scale * (focalPoint.dy - _panY);
    }

    _zoomLevel = newZoom;
    _scheduleSave();

    AnalyticsService.instance.logGraphZoomed(_zoomLevel);

    notifyListeners();
  }

  /// Zooms in by 20% centered on the viewport.
  ///
  /// Typically triggered by keyboard "+" key.
  void zoomIn({Size? viewportSize}) {
    final center = viewportSize != null
        ? Offset(viewportSize.width / 2, viewportSize.height / 2)
        : null;
    zoomTo(_zoomLevel * 1.2, focalPoint: center);
  }

  /// Zooms out by 20% centered on the viewport.
  ///
  /// Typically triggered by keyboard "-" key.
  void zoomOut({Size? viewportSize}) {
    final center = viewportSize != null
        ? Offset(viewportSize.width / 2, viewportSize.height / 2)
        : null;
    zoomTo(_zoomLevel / 1.2, focalPoint: center);
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
  /// Animation: 400 ms bezier ease-in-out.
  void focusOnNode(
    String nodeId,
    Offset nodePosition, {
    int connectedNodeCount = 0,
    Size viewportSize = Size.zero,
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

    animateTo(
      targetPanX,
      targetPanY,
      optimalZoom,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
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

    // Compute bounding box of all nodes.
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    // v62.5: For single-node graphs (min == max), add a minimum
    // bounding box size so the zoom calculation doesn't produce
    // extreme values. This prevents the node from being off-screen
    // until the user zooms in.
    final rawWidth = maxX - minX;
    final rawHeight = maxY - minY;
    const minBoxSize = 200.0; // Minimum 200x200 bounding box
    final width = (rawWidth < minBoxSize ? minBoxSize : rawWidth) * 1.1;
    final height = (rawHeight < minBoxSize ? minBoxSize : rawHeight) * 1.1;
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
      fitZoom = fitZoom.clamp(0.3, 2.0);
    }

    // Compute pan to center.
    final targetPanX = (viewportSize.width / 2) - (centerX * fitZoom);
    final targetPanY = (viewportSize.height / 2) - (centerY * fitZoom);

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
      final elapsed =
          DateTime.now().difference(startTime).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      final curvedT = curve.transform(t);

      _panX = startPanX + (targetPanX - startPanX) * curvedT;
      _panY = startPanY + (targetPanY - startPanY) * curvedT;
      _zoomLevel =
          startZoom + (targetZoomClamped - startZoom) * curvedT;

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
  void _startMomentumDecay() {
    _cancelAnimation();

    final startPanX = _panX;
    final startPanY = _panY;
    final startVelocityX = _velocityX;
    final startVelocityY = _velocityY;
    final startTime = DateTime.now();
    final durationMs = _momentumDecayDuration.inMilliseconds;

    _isAnimating = true;

    void tick() {
      final elapsed =
          DateTime.now().difference(startTime).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);

      // Deceleration curve: starts fast, slows to zero.
      final deceleration = 1.0 - (t * t); // Quadratic ease-out.

      _panX = startPanX +
          startVelocityX * (elapsed / 1000.0) * deceleration;
      _panY = startPanY +
          startVelocityY * (elapsed / 1000.0) * deceleration;

      notifyListeners();

      if (t < 1.0) {
        Future<void>.delayed(const Duration(milliseconds: 16), tick);
      } else {
        _isAnimating = false;
        _velocityX = 0.0;
        _velocityY = 0.0;
        _scheduleSave();
        notifyListeners();
      }
    }

    tick();
  }

  /// Cancels any active animation.
  void _cancelAnimation() {
    _isAnimating = false;
    _velocityX = 0.0;
    _velocityY = 0.0;
  }

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
