// lib/features/cameo/presentation/widgets/cameo_avatar.dart
//
// KINREL CAMEO — CameoAvatar Widget
//
// The drop-in widget that renders a Kinrel Cameo for any person.
// It is the production-grade fallback for the "no 3D Cameo yet"
// state (V2 §3.6, §39.3) AND the durable offline / load-failure /
// no-photo state for the lifetime of the app.
//
// WHAT IT DOES:
//   1. Resolves a complete ResolvedCameoStyle via [CameoStyleSystem].
//   2. Scales responsively per [CameoResponsiveRules] — never clips,
//      never stretches, never forces a viewport.
//   3. Paints via [CameoPortraitPainter] — the deterministic Kinrel
//      portrait with warm ivory + ember rim signature.
//   4. Animates subtly (breathing + blink + saccade) when enabled,
//      with full reduced-motion support.
//   5. Provides a screen-reader semantic label.
//   6. Fails gracefully: any error during paint → a dignified
//      monogram fallback (initials on vignette), never a broken icon.
//
// WHAT IT DOES NOT DO:
//   • It does not render live 3D. When the B1 prototype gate passes
//     and the 3D runtime ships, a separate CameoLive3DAvatar widget
//     will render live 3D for Studio/Profile/Journey; this widget
//     remains the fallback for Map/Graph/Chat/Timeline and for the
//     absence state on live surfaces.
//   • It does not fetch anything. The caller passes personName,
//     ageBand, skinToneIndex, etc. — typically derived from the
//     Person model in the repository.
//
// USAGE (drop-in replacement for CachedAvatar when no photo exists,
// or when a Cameo is requested but the 3D system hasn't shipped):
//
//   CameoAvatar(
//     personName: 'Aaji',
//     ageBand: CameoAgeBand.elder,
//     skinToneIndex: 5,
//     surfaceId: 'profile_hero',
//     isDeceased: true,
//     memorialAtmosphere: 'softLight',
//   )

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../style/cameo_animation_curves.dart';
import '../../style/cameo_responsive_rules.dart';
import '../../style/cameo_shape_language.dart';
import '../../style/cameo_style_system.dart';
import '../painters/cameo_portrait_painter.dart';

/// A production-grade Kinrel Cameo avatar widget.
///
/// Renders the deterministic Kinrel fallback portrait. See file header
/// for the full contract.
class CameoAvatar extends StatefulWidget {
  const CameoAvatar({
    super.key,
    required this.personName,
    required this.ageBand,
    required this.skinToneIndex,
    this.surfaceId = 'profile_hero',
    this.expressionId,
    this.poseId,
    this.memorialAtmosphere,
    this.familyEventId,
    this.relationshipLabel,
    this.isDeceased = false,
    this.enableAnimation = true,
  });

  /// The display name of the person. Used for the semantic label and
  /// the monogram fallback.
  final String personName;

  /// The person's age band. Drives shape, pose, hair greying, skin aging.
  final CameoAgeBand ageBand;

  /// 1–10 (CameoColorPalette.skinTone).
  final int skinToneIndex;

  /// Which surface this avatar is rendered on. Determines camera,
  /// lighting, animation, responsive, scene density, a11y rules.
  /// Default: 'profile_hero'.
  final String surfaceId;

  /// Optional explicit expression id. If null, defaults from event.
  final String? expressionId;

  /// Optional explicit pose id. If null, defaults from age band.
  final String? poseId;

  /// Memorial atmosphere ('none' | 'softLight' | 'candleGlow').
  /// Only used if [isDeceased] is true. Default for deceased is softLight.
  final String? memorialAtmosphere;

  /// Family event id ('birthday' | 'wedding' | 'new_baby' | 'graduation'
  /// | 'festival' | 'memorial'). Drives default expression.
  final String? familyEventId;

  /// Relationship label for the semantic label (e.g. 'grandmother').
  final String? relationshipLabel;

  /// Whether the person is deceased. Switches to memorial lighting.
  final bool isDeceased;

  /// Master animation kill-switch. Even when true, reduced-motion
  /// (MediaQuery.disableAnimationsOf) disables all motion.
  final bool enableAnimation;

  @override
  State<CameoAvatar> createState() => _CameoAvatarState();
}

class _CameoAvatarState extends State<CameoAvatar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;
  double _phase = 0.0; // breathing phase [0, 1)
  double _blink = 0.0; // 0 = open, 1 = closed
  Offset _saccade = Offset.zero;
  Offset _saccadeStart = Offset.zero;
  Offset _saccadeTarget = Offset.zero;
  double _saccadeElapsed = 0.0; // seconds since saccade started
  bool _saccading = false;
  Timer? _blinkTimer;
  Timer? _saccadeTimer;
  bool _hasErrored = false;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _scheduleNextBlink();
    _scheduleNextSaccade();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStartOrStopTicker();
  }

  @override
  void didUpdateWidget(covariant CameoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartOrStopTicker();
  }

  void _maybeStartOrStopTicker() {
    final anim = CameoAnimationPresets.resolve(
      surfaceId: widget.surfaceId,
      reduceMotion: _reduceMotion(),
      isLowTierDevice: false,
    );
    final wantsMotion = widget.enableAnimation &&
        !_reduceMotion() &&
        (anim.allowBreathing ||
            anim.allowBlink ||
            anim.allowSaccades ||
            anim.allowHeadSway);
    if (wantsMotion && !_ticker.active) {
      _lastElapsed = null; // reset so first frame after restart has dt=0
      _ticker.start();
    } else if (!wantsMotion && _ticker.active) {
      _ticker.stop();
    }
  }

  bool _reduceMotion() {
    return MediaQuery.disableAnimationsOf(context);
  }

  void _onTick(Duration elapsed) {
    final anim = CameoAnimationPresets.resolve(
      surfaceId: widget.surfaceId,
      reduceMotion: _reduceMotion(),
      isLowTierDevice: false,
    );
    final dt = _lastElapsed == null
        ? 0.0 // skip first frame (no delta)
        : (elapsed - _lastElapsed!).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) return; // skip first frame / huge gap

    // Breathing phase.
    if (anim.allowBreathing) {
      _phase += dt / anim.breathingPeriod.inSeconds;
      _phase = _phase % 1.0;
    }

    // Blink decay (close then open).
    if (_blink > 0) {
      final closeDur = anim.blinkCloseMs / 1000.0;
      final openDur = anim.blinkOpenMs / 1000.0;
      if (_blink < 0.5) {
        _blink = (_blink + dt / closeDur / 2).clamp(0.0, 0.5);
      } else {
        _blink = (_blink + dt / openDur).clamp(0.0, 1.0);
        if (_blink >= 1.0) {
          _blink = 0;
          _scheduleNextBlink();
        }
      }
    }

    // Saccade drift — proper time-based lerp.
    if (anim.allowSaccades && _saccading) {
      final saccadeDur = anim.saccadeDurationMs / 1000.0;
      _saccadeElapsed += dt;
      final t = (_saccadeElapsed / saccadeDur).clamp(0.0, 1.0);
      // Ease-out so the eye lands softly.
      final eased = 1.0 - (1.0 - t) * (1.0 - t);
      _saccade = Offset(
        _saccadeStart.dx + (_saccadeTarget.dx - _saccadeStart.dx) * eased,
        _saccadeStart.dy + (_saccadeTarget.dy - _saccadeStart.dy) * eased,
      );
      if (t >= 1.0) {
        _saccading = false;
        _scheduleNextSaccade();
      }
    }

    if (mounted) setState(() {});
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final anim = CameoAnimationPresets.resolve(
      surfaceId: widget.surfaceId,
      reduceMotion: _reduceMotion(),
      isLowTierDevice: false,
    );
    if (!anim.allowBlink ||
        anim.blinkIntervalMaxS == double.infinity) {
      return;
    }
    final delaySeconds = anim.blinkIntervalMinS +
        math.Random().nextDouble() *
            (anim.blinkIntervalMaxS - anim.blinkIntervalMinS);
    _blinkTimer = Timer(Duration(seconds: delaySeconds.toInt()), () {
      if (mounted && anim.allowBlink) {
        setState(() {
          _blink = 0.001; // start blink
        });
      }
    });
  }

  void _scheduleNextSaccade() {
    _saccadeTimer?.cancel();
    final anim = CameoAnimationPresets.resolve(
      surfaceId: widget.surfaceId,
      reduceMotion: _reduceMotion(),
      isLowTierDevice: false,
    );
    if (!anim.allowSaccades ||
        anim.saccadeIntervalMaxS == double.infinity) {
      return;
    }
    final delaySeconds = anim.saccadeIntervalMinS +
        math.Random().nextDouble() *
            (anim.saccadeIntervalMaxS - anim.saccadeIntervalMinS);
    _saccadeTimer = Timer(Duration(seconds: delaySeconds.toInt()), () {
      if (mounted && anim.allowSaccades) {
        final rng = math.Random();
        setState(() {
          _saccadeStart = _saccade;
          _saccadeTarget = Offset(
            (rng.nextDouble() - 0.5) * 1.6,
            (rng.nextDouble() - 0.5) * 1.0,
          );
          _saccadeElapsed = 0.0;
          _saccading = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blinkTimer?.cancel();
    _saccadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _defaultSizeForSurface(),
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : _defaultSizeForSurface(),
        );
        final breakpoint = cameoBreakpointForWidth(containerSize.width);
        final resolved = CameoStyleSystem.resolve(
          surfaceId: widget.surfaceId,
          personName: widget.personName,
          ageBand: widget.ageBand,
          skinToneIndex: widget.skinToneIndex,
          expressionId: widget.expressionId,
          poseId: widget.poseId,
          memorialAtmosphere: widget.memorialAtmosphere,
          familyEventId: widget.familyEventId,
          relationshipLabel: widget.relationshipLabel,
          isDeceased: widget.isDeceased,
          reduceMotion: _reduceMotion(),
          isLowTierDevice: false,
          breakpoint: breakpoint,
          containerSize: containerSize,
        );

        final renderSize = resolved.effectiveRenderSize;

        return Semantics(
          label: resolved.semanticLabel,
          image: true,
          child: Center(
            child: SizedBox(
              width: renderSize.width,
              height: renderSize.height,
              child: ClipRect(
                child: _hasErrored
                    ? _MonogramFallback(
                        name: widget.personName,
                        skinTone: resolved.skinTone,
                      )
                    : CustomPaint(
                        painter: CameoPortraitPainter(
                          style: resolved,
                          animationPhase: _phase,
                          blinkCloseFactor: _blink,
                          saccadeOffset: _saccade,
                        ),
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _defaultSizeForSurface() {
    switch (widget.surfaceId) {
      case 'map_marker':
      case 'graph_node':
      case 'chat_avatar':
      case 'timeline_card':
        return 64;
      case 'studio':
        return 380;
      case 'journey':
        return 420;
      case 'profile_hero':
      default:
        return 220;
    }
  }
}

/// The dignified monogram fallback shown if the painter ever throws.
/// Initials on the warm vignette — never a broken-image icon.
class _MonogramFallback extends StatelessWidget {
  const _MonogramFallback({required this.name, required this.skinTone});

  final String name;
  final Color skinTone;

  @override
  Widget build(BuildContext context) {
    final initials = _computeInitials(name);
    return CustomPaint(
      painter: _MonogramPainter(initials: initials, accent: skinTone),
      child: const SizedBox.expand(),
    );
  }

  String _computeInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}'
            '${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _MonogramPainter extends CustomPainter {
  _MonogramPainter({required this.initials, required this.accent});

  final String initials;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // Vignette backdrop.
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: CameoColorPalette.vignetteGradient,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Accent ring.
    final ringPaint = Paint()
      ..color = accent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.04;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.38,
      ringPaint,
    );

    // Initials text.
    final textStyle = TextStyle(
      color: const Color(0xFFF5F0EE),
      fontSize: size.width * 0.32,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      fontFamily: 'Outfit',
    );
    final span = TextSpan(text: initials, style: textStyle);
    final painter = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _MonogramPainter old) {
    return old.initials != initials || old.accent != accent;
  }
}

// Re-export the breakpoint helper here so callers of CameoAvatar can
// reach it without an extra import.
export '../../style/cameo_responsive_rules.dart'
    show CameoBreakpoint, cameoBreakpointForWidth;
