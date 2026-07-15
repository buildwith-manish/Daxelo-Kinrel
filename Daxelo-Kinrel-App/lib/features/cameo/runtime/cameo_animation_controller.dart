// lib/features/cameo/runtime/cameo_animation_controller.dart
//
// KINREL CAMEO — Animation Controller
//
// Drives breathing, blinking, saccades, and expression blending.
// V2 §32 — deterministic, personality-driven, reduced-motion-safe.
//
// This controller is renderer-independent. It computes morph target
// weights and animation timing. The renderer applies them via
// CameoRenderer.setMorphWeights().
//
// The controller does NOT own a Ticker or Timer — it is driven by
// the CameoRuntimeScene's render loop. The scene calls tick(dt) each
// frame; the controller returns the current morph weights + blink state.
// This prevents orphaned timers and keeps the animation lifecycle
// tied to the renderer lifecycle.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../data/cameo_definition.dart';
import '../style/cameo_animation_curves.dart';
import '../style/cameo_expression_catalog.dart';

/// The output of a single animation tick.
class CameoAnimationFrame {
  const CameoAnimationFrame({
    required this.morphWeights,
    required this.blinkAmount,
    required this.saccadeOffset,
    required this.breathingPhase,
  });

  /// Morph target weights to apply (name → 0.0..1.0).
  final Map<String, double> morphWeights;

  /// Blink amount: 0.0 = eyes open, 1.0 = eyes closed.
  final double blinkAmount;

  /// Saccade offset in normalized eye-space [-1, 1].
  final Offset saccadeOffset;

  /// Breathing phase [0, 1) — used for chest rise.
  final double breathingPhase;
}

/// Drives all Cameo animation.
///
/// Lifecycle:
///   final controller = CameoAnimationController(
///     definition: myDefinition,
///     animationCurves: CameoAnimationPresets.studio,
///   );
///   // Each frame:
///   final frame = controller.tick(dt);
///   renderer.setMorphWeights(frame.morphWeights);
///
/// Reduced motion: When [CameoAnimationCurves.allowBreathing] etc. are
/// false (resolved from MediaQuery.disableAnimationsOf), ALL motion
/// stops. The controller returns a static frame.
class CameoAnimationController {
  CameoAnimationController({
    required CameoDefinition definition,
    required CameoAnimationCurves animationCurves,
  }) : _definition = definition,
       _curves = animationCurves {
    _currentExpression = _resolveExpression(definition.expressionId);
    _targetExpression = _currentExpression;
  }

  CameoDefinition _definition;
  CameoAnimationCurves _curves;

  // Animation state
  double _breathingPhase = 0.0;
  double _blinkAmount = 0.0;
  bool _blinkClosing = false;
  double _blinkTimer = 0.0;
  double _nextBlinkDelay = 0.0;
  Offset _saccadeOffset = Offset.zero;
  double _saccadeTimer = 0.0;
  double _nextSaccadeDelay = 0.0;

  // Expression blending
  late CameoExpression _currentExpression;
  late CameoExpression _targetExpression;
  double _expressionBlend = 1.0; // 1.0 = fully at target
  double _expressionBlendSpeed = 1.0; // 1/transitionDuration

  // Personality-driven micro-expression timer
  double _microExpressionTimer = 0.0;
  double _nextMicroExpressionDelay = 45.0;

  final math.Random _rng = math.Random();

  /// Updates the definition (e.g., when user changes appearance in Studio).
  void updateDefinition(CameoDefinition definition) {
    _definition = definition;
    final newExpression = _resolveExpression(definition.expressionId);
    if (newExpression.id != _targetExpression.id) {
      setExpression(newExpression.id);
    }
  }

  /// Updates the animation curves (e.g., when surface changes or
  /// reduced motion is toggled).
  void updateCurves(CameoAnimationCurves curves) {
    _curves = curves;
  }

  /// Smoothly transitions to a new expression.
  void setExpression(
    String expressionId, {
    Duration transition = const Duration(milliseconds: 260),
  }) {
    _targetExpression = _resolveExpression(expressionId);
    _expressionBlend = 0.0;
    _expressionBlendSpeed = 1.0 / (transition.inMilliseconds / 1000.0);
  }

  /// Advances the animation by [dt] seconds and returns the current frame.
  CameoAnimationFrame tick(double dt) {
    if (dt <= 0 || dt > 0.1) {
      // Skip first frame or huge gap (e.g., app was backgrounded).
      return _buildStaticFrame();
    }

    // ── Breathing ──────────────────────────────────────────────────
    if (_curves.allowBreathing) {
      final periodSec = _curves.breathingPeriod.inSeconds;
      if (periodSec > 0) {
        _breathingPhase += dt / periodSec;
        _breathingPhase = _breathingPhase % 1.0;
      }
    }

    // ── Blinking ───────────────────────────────────────────────────
    if (_curves.allowBlink) {
      _updateBlink(dt);
    }

    // ── Saccades ───────────────────────────────────────────────────
    if (_curves.allowSaccades) {
      _updateSaccade(dt);
    }

    // ── Expression blending ────────────────────────────────────────
    if (_expressionBlend < 1.0) {
      _expressionBlend += _expressionBlendSpeed * dt;
      if (_expressionBlend > 1.0) _expressionBlend = 1.0;
    }

    // ── Personality-driven micro-expressions ───────────────────────
    _updateMicroExpression(dt);

    return _buildFrame();
  }

  /// Returns a static frame (no animation) — used for reduced motion
  /// or when the controller is paused.
  CameoAnimationFrame _buildStaticFrame() {
    return CameoAnimationFrame(
      morphWeights: Map<String, double>.from(_currentExpression.morphWeights),
      blinkAmount: 0.0,
      saccadeOffset: Offset.zero,
      breathingPhase: 0.0,
    );
  }

  void _updateBlink(double dt) {
    if (_blinkAmount > 0) {
      // Blink in progress
      final closeDur = _curves.blinkCloseMs / 1000.0;
      final openDur = _curves.blinkOpenMs / 1000.0;
      if (_blinkClosing) {
        _blinkAmount += dt / closeDur;
        if (_blinkAmount >= 1.0) {
          _blinkAmount = 1.0;
          _blinkClosing = false;
        }
      } else {
        _blinkAmount -= dt / openDur;
        if (_blinkAmount <= 0.0) {
          _blinkAmount = 0.0;
          // Schedule next blink
          _nextBlinkDelay =
              _curves.blinkIntervalMinS +
              _rng.nextDouble() *
                  (_curves.blinkIntervalMaxS - _curves.blinkIntervalMinS);
          _blinkTimer = 0.0;
        }
      }
    } else {
      // Waiting for next blink
      _blinkTimer += dt;
      if (_blinkTimer >= _nextBlinkDelay) {
        _blinkClosing = true;
        _blinkAmount = 0.001;
      }
    }
  }

  void _updateSaccade(double dt) {
    _saccadeTimer += dt;
    if (_saccadeTimer >= _nextSaccadeDelay) {
      // New saccade — random eye offset
      final mag = _curves.saccadeMagnitudeMm;
      _saccadeOffset = Offset(
        (_rng.nextDouble() * 2 - 1) * mag,
        (_rng.nextDouble() * 2 - 1) * mag * 0.5,
      );
      _saccadeTimer = 0.0;
      _nextSaccadeDelay =
          _curves.saccadeIntervalMinS +
          _rng.nextDouble() *
              (_curves.saccadeIntervalMaxS - _curves.saccadeIntervalMinS);
    }
  }

  void _updateMicroExpression(double dt) {
    // Personality: playfulness → soft_surprise every ~45s
    if (_definition.personality.playfulness > 0.6) {
      _microExpressionTimer += dt;
      if (_microExpressionTimer >= _nextMicroExpressionDelay) {
        // Briefly blend toward soft_surprise
        final surprise = CameoExpressionCatalog.softSurprise;
        _currentExpression = _currentExpression.lerpTo(surprise, 0.3);
        _microExpressionTimer = 0.0;
        _nextMicroExpressionDelay = 30.0 + _rng.nextDouble() * 30.0;
      }
    }

    // Personality: warmth → slight smile baseline
    // Already handled in _buildFrame via personality adjustment
  }

  CameoAnimationFrame _buildFrame() {
    // Blend current → target expression
    final blended = _expressionBlend < 1.0
        ? _currentExpression.lerpTo(_targetExpression, _expressionBlend)
        : _targetExpression;

    // Apply personality adjustments to morph weights
    final weights = Map<String, double>.from(blended.morphWeights);

    // Warmth → slight smile baseline
    if (_definition.personality.warmth > 0.5) {
      final smileBoost = (_definition.personality.warmth - 0.5) * 0.1;
      weights['mouth_corner_up'] =
          (weights['mouth_corner_up'] ?? 0.0) + smileBoost;
    }

    // Apply blink to eye_close morph
    if (_blinkAmount > 0) {
      weights['eye_close'] = _blinkAmount;
    }

    return CameoAnimationFrame(
      morphWeights: weights,
      blinkAmount: _blinkAmount,
      saccadeOffset: _saccadeOffset,
      breathingPhase: _breathingPhase,
    );
  }

  CameoExpression _resolveExpression(String? expressionId) {
    if (expressionId == null) return CameoExpressionCatalog.neutral;
    return CameoExpressionCatalog.byId(expressionId);
  }

  /// Resets all animation state (used when switching characters).
  void reset() {
    _breathingPhase = 0.0;
    _blinkAmount = 0.0;
    _blinkClosing = false;
    _blinkTimer = 0.0;
    _saccadeOffset = Offset.zero;
    _saccadeTimer = 0.0;
    _expressionBlend = 1.0;
    _microExpressionTimer = 0.0;
  }
}
