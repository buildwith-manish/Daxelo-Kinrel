// lib/features/cameo/runtime/cameo_runtime_scene.dart
//
// KINREL CAMEO — Runtime Scene
//
// Manages the lifecycle of a single Cameo rendering session. Owns:
//   - The renderer instance (injected via constructor)
//   - The animation controller
//   - The camera + lighting configuration
//   - The render loop (driven by an external ticker)
//
// The scene is renderer-agnostic. It calls CameoRenderer methods.
// The concrete renderer (ThermionCameoRenderer, future) implements
// the actual GPU calls.
//
// Lifecycle:
//   final scene = CameoRuntimeScene(renderer: myRenderer);
//   await scene.loadCharacter(definition, style);
//   scene.start(ticker);  // begins render loop
//   scene.stop();         // pauses
//   await scene.dispose(); // releases all resources

import 'dart:async';
import 'dart:typed_data';

import '../data/cameo_definition.dart';
import '../rendering/cameo_renderer.dart';
import '../style/cameo_animation_curves.dart';
import '../style/cameo_camera_rules.dart';
import '../style/cameo_lighting_presets.dart';
import '../style/cameo_expression_catalog.dart';
import '../style/cameo_style_system.dart';
import 'cameo_animation_controller.dart';

/// The runtime state of a Cameo scene.
enum CameoSceneState {
  uninitialized,
  loading,
  ready,
  rendering,
  paused,
  error,
  disposed,
}

/// Manages a single Cameo rendering session.
///
/// One scene = one character in one surface (Studio, Profile, etc.).
/// For family compositions (2+ characters), multiple scenes are created.
class CameoRuntimeScene {
  CameoRuntimeScene({required CameoRenderer renderer}) : _renderer = renderer;

  final CameoRenderer _renderer;
  CameoAnimationController? _animationController;
  Timer? _renderTimer;
  DateTime? _lastTickTime;

  CameoSceneState _state = CameoSceneState.uninitialized;
  CameoRendererCapabilities? _capabilities;
  CameoDefinition? _definition;
  ResolvedCameoStyle? _style;

  /// Current scene state.
  CameoSceneState get state => _state;

  /// The renderer's capabilities (available after initialize).
  CameoRendererCapabilities? get capabilities => _capabilities;

  /// True if the renderer passed the B1 gate.
  bool get isB1GatePassed => _capabilities?.passesB1Gate ?? false;

  /// Initializes the renderer. Must be called before loadCharacter.
  Future<bool> initialize() async {
    if (_state != CameoSceneState.uninitialized) {
      throw StateError('Scene already initialized. State: $_state');
    }

    _state = CameoSceneState.loading;
    try {
      final result = await _renderer.initialize();
      if (!result.success) {
        _state = CameoSceneState.error;
        return false;
      }
      _capabilities = result.capabilities;
      _state = CameoSceneState.ready;
      return result.capabilities.passesB1Gate;
    } catch (e) {
      _state = CameoSceneState.error;
      return false;
    }
  }

  /// Loads a character definition into the renderer.
  ///
  /// [definition] — the character's appearance (CameoDefinition).
  /// [style] — the resolved visual style (from CameoStyleSystem.resolve).
  /// [glbAssetPath] — path to the GLB file in the asset bundle.
  Future<void> loadCharacter({
    required CameoDefinition definition,
    required ResolvedCameoStyle style,
    required String glbAssetPath,
  }) async {
    if (_state != CameoSceneState.ready) {
      throw StateError(
        'Scene not ready. Call initialize() first. State: $_state',
      );
    }

    _definition = definition;
    _style = style;

    try {
      await _renderer.loadCharacter(
        assetPath: glbAssetPath,
        morphTargetNames: _collectMorphTargetNames(),
      );

      // Apply camera + lighting from the resolved style.
      await _renderer.setCamera(style.camera);
      await _renderer.setLighting(style.lighting);

      // Create the animation controller.
      _animationController = CameoAnimationController(
        definition: definition,
        animationCurves: style.animation,
      );

      _state = CameoSceneState.ready;
    } catch (e) {
      _state = CameoSceneState.error;
      rethrow;
    }
  }

  /// Starts the render loop at [targetFps] frames per second.
  /// The loop calls _renderer.render() each frame, applies animation
  /// morph weights, and triggers callbacks.
  void start({int targetFps = 60}) {
    if (_state != CameoSceneState.ready && _state != CameoSceneState.paused) {
      throw StateError('Scene not ready to start. State: $_state');
    }

    _state = CameoSceneState.rendering;
    _lastTickTime = null;

    final interval = Duration(milliseconds: 1000 ~/ targetFps);
    _renderTimer = Timer.periodic(interval, (_) => _onTick());
  }

  /// Pauses the render loop. The renderer keeps its resources but
  /// stops rendering frames.
  void pause() {
    _renderTimer?.cancel();
    _renderTimer = null;
    if (_state == CameoSceneState.rendering) {
      _state = CameoSceneState.paused;
    }
  }

  /// Resumes from paused state.
  void resume() {
    if (_state == CameoSceneState.paused) {
      start();
    }
  }

  /// Renders a single frame (manual — used when the loop is paused).
  Future<void> renderOnce() async {
    await _onTickAsync();
  }

  /// Renders a portrait (offscreen PNG) at the given resolution.
  /// Used by the portrait pipeline for derived images (Map/Graph/Chat).
  Future<Uint8List> renderPortrait({int width = 256, int height = 256}) async {
    if (_state != CameoSceneState.ready &&
        _state != CameoSceneState.rendering &&
        _state != CameoSceneState.paused) {
      throw StateError('Scene not ready for portrait render. State: $_state');
    }
    return _renderer.renderPortrait(width: width, height: height);
  }

  /// Changes the expression (smooth blend).
  void setExpression(String expressionId) {
    _animationController?.setExpression(expressionId);
  }

  /// Updates the animation curves (e.g., for reduced motion).
  void updateAnimationCurves(CameoAnimationCurves curves) {
    _animationController?.updateCurves(curves);
  }

  /// Updates the character definition (e.g., user changed appearance).
  Future<void> updateDefinition(CameoDefinition definition) async {
    if (_definition == null) return;
    _definition = definition;
    _animationController?.updateDefinition(definition);
  }

  /// Releases all GPU resources. The scene cannot be used after this.
  Future<void> dispose() async {
    _renderTimer?.cancel();
    _renderTimer = null;
    _animationController = null;
    await _renderer.dispose();
    _state = CameoSceneState.disposed;
  }

  // ── Internal ────────────────────────────────────────────────────

  void _onTick() {
    _onTickAsync();
  }

  Future<void> _onTickAsync() async {
    if (_state != CameoSceneState.rendering &&
        _state != CameoSceneState.ready) {
      return;
    }

    final now = DateTime.now();
    double dt = 0.0;
    if (_lastTickTime != null) {
      dt = now.difference(_lastTickTime!).inMicroseconds / 1000000.0;
    }
    _lastTickTime = now;

    // Update animation
    if (_animationController != null && dt > 0) {
      final frame = _animationController!.tick(dt);
      // Apply morph weights to the renderer
      try {
        await _renderer.setMorphWeights(frame.morphWeights);
      } catch (_) {
        // Renderer may not support morph targets — graceful degradation.
      }
    }

    // Render the frame
    try {
      await _renderer.render();
    } catch (_) {
      // Rendering error — don't crash the timer loop.
    }
  }

  List<String> _collectMorphTargetNames() {
    // Collect all morph target names from the expression catalog.
    // The renderer needs to know which morph targets to enable.
    final names = <String>{};

    // 1. Collect keys from every expression in the catalog.
    for (final expression in CameoExpressionCatalog.all) {
      names.addAll(expression.morphWeights.keys);
    }

    // 2. Add the full production morph target list.
    // Face morphs (24)
    names.addAll([
      'brow_inner_up',
      'brow_outer_up',
      'brow_furrow',
      'eye_close',
      'eye_widen',
      'eye_crinkle',
      'upper_lid_lower',
      'lower_lid_raise',
      'nose_wrinkle',
      'mouth_relax',
      'mouth_corner_up',
      'mouth_corner_down',
      'mouth_open',
      'mouth_pout',
      'mouth_smile_full',
      'jaw_open',
      'jaw_forward',
      'cheek_raise',
      'cheek_puff',
      'chin_raise',
      'tongue_out',
      'lip_bite',
      'lip_funnel',
      'lip_press',
    ]);

    // Age morphs (8)
    names.addAll([
      'age_brow_sag',
      'age_eyelid_drop',
      'age_crow_feet',
      'age_nasolabial',
      'age_jowl',
      'age_neck_sag',
      'age_ear_lengthen',
      'age_hair_recede',
    ]);

    // Expression morphs (4) — for B1 test GLB compatibility
    names.addAll([
      'blink_left',
      'blink_right',
      'smile',
      'jaw_open', // already in face morphs; set handles dedup
    ]);

    return names.toList()..sort();
  }
}
