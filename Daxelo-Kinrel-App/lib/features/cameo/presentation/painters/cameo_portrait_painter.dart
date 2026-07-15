// lib/features/cameo/presentation/painters/cameo_portrait_painter.dart
//
// KINREL CAMEO — Portrait Painter (the deterministic Kinrel fallback)
//
// This is the DESIGNED, DETERMINISTIC, CINEMATIC Kinrel portrait that
// ships TODAY as the "no 3D Cameo yet" fallback (V2 §3.6, §39.3).
//
// It is NOT a placeholder. It is NOT an emoji. It is NOT a stock
// avatar. It is a hand-tuned CustomPainter that renders the same
// Kinrel visual language the eventual 3D character will render:
//   • Warm ivory key light + ember rim (the signature pair)
//   • Soft rounded silhouette (CameoShapeLanguage)
//   • Skin tone, hair, clothing colors from CameoColorPalette
//   • Vignette backdrop (CameoColorPalette.vignetteGradient)
//   • Breathing / blink / saccade animation (when enabled)
//   • Reduced-motion static state
//
// When the B1 prototype gate passes and real 3D characters replace
// this, this painter remains as the OFFLINE / LOAD-FAILURE / NO-CAMEO
// fallback. It is the durable Kinrel visual identity for the absence
// state — never a "broken image" placeholder.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../style/cameo_color_palette.dart';
import '../../style/cameo_shape_language.dart';
import '../../style/cameo_style_system.dart';

/// Renders a single deterministic Kinrel Cameo portrait.
///
/// The painter is pure: it derives everything from the
/// [ResolvedCameoStyle] + an optional [animationPhase] in [0, 1].
/// Callers (CameoAvatar) drive [animationPhase] from a timer; the
/// painter itself owns no state.
class CameoPortraitPainter extends CustomPainter {
  CameoPortraitPainter({
    required this.style,
    this.animationPhase = 0.0,
    this.blinkCloseFactor = 0.0, // 0 = open, 1 = closed
    this.saccadeOffset = Offset.zero,
  }) {
    // Debug-only quality check. Cheap; runs only in debug builds.
    assert(() {
      if (!style.passesQualityGates) {
        debugPrint('CameoPortraitPainter: resolved style failed quality '
            'gates for surface "${style.surfaceId}".');
      }
      return true;
    }());
  }

  final ResolvedCameoStyle style;

  /// Breathing phase in [0, 1]. 0 = exhale bottom, 0.5 = inhale peak.
  final double animationPhase;

  /// Blink factor in [0, 1]. 0 = eyes open, 1 = eyes closed.
  final double blinkCloseFactor;

  /// Iris offset for saccades, in fractions of iris radius.
  final Offset saccadeOffset;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Backdrop vignette.
    _paintBackdrop(canvas, size);

    // 2. Floor hint (if enabled for this surface).
    if (style.sceneDensity.floorHintVisible) {
      _paintFloorHint(canvas, size);
    }

    // 3. Breathing offset (subtle chest rise).
    final breathe =
        style.animation.allowBreathing ? math.sin(animationPhase * 2 * math.pi) : 0.0;
    final breathDy = breathe * style.animation.breathingAmplitudePx;

    // 4. Body silhouette (shoulders + neck).
    _paintBody(canvas, size, breathDy);

    // 5. Hair back silhouette (behind head).
    _paintHairBack(canvas, size, breathDy);

    // 6. Neck.
    _paintNeck(canvas, size, breathDy);

    // 7. Head (skin tone gradient with ivory key + ember rim).
    _paintHead(canvas, size, breathDy);

    // 8. Hair front (bangs / sides).
    _paintHairFront(canvas, size, breathDy);

    // 9. Ears.
    _paintEars(canvas, size, breathDy);

    // 10. Eyes (sclera + iris + catchlight + upper lid).
    _paintEyes(canvas, size, breathDy);

    // 11. Brows.
    _paintBrows(canvas, size, breathDy);

    // 12. Nose.
    _paintNose(canvas, size, breathDy);

    // 13. Mouth (expression-aware).
    _paintMouth(canvas, size, breathDy);

    // 14. Ember rim hair-line (the signature — always last over figure).
    _paintEmberRim(canvas, size, breathDy);
    // State overlays (birthday garland, festival rangoli, etc.) are UI
    // layers on top of the CameoAvatar widget — never in the painter
    // and never baked into the character (V2 §1, §44).
  }

  // ── Painters ───────────────────────────────────────────────────────

  void _paintBackdrop(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.08), // slightly above center, where the head sits
        radius: 0.85,
        colors: CameoColorPalette.vignetteGradient,
        stops: <double>[0.0, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _paintFloorHint(Canvas canvas, Size size) {
    final cy = size.height * 0.88;
    final paint = Paint()
      ..color = CameoColorPalette.vignetteCenter.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, cy),
        width: size.width * 0.5,
        height: size.height * 0.04,
      ),
      paint,
    );
  }

  void _paintBody(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final shoulderW = size.width *
        (CameoShapeLanguage.shoulderToHeadWidth *
            (style.ageBand == CameoAgeBand.baby ||
                    style.ageBand == CameoAgeBand.child
                ? 0.7
                : 1.0));
    final top = size.height * 0.66 + breathDy;
    final bottom = size.height + 8;

    final path = Path();
    final leftShoulder = Offset(cx - shoulderW / 2, top);
    final rightShoulder = Offset(cx + shoulderW / 2, top);
    final cornerR = shoulderW * CameoShapeLanguage.shoulderRadiusFraction;
    path.moveTo(leftShoulder.dx + cornerR, top);
    path.lineTo(rightShoulder.dx - cornerR, top);
    path.quadraticBezierTo(
        rightShoulder.dx, top, rightShoulder.dx, top + cornerR);
    path.lineTo(rightShoulder.dx + 4, bottom);
    path.lineTo(leftShoulder.dx - 4, bottom);
    path.lineTo(leftShoulder.dx, top + cornerR);
    path.quadraticBezierTo(
        leftShoulder.dx, top, leftShoulder.dx + cornerR, top);
    path.close();

    // Clothing color: pick a neutral that complements the skin tone.
    final clothColor = _clothingColorFor(style.skinTone);

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          clothColor.withValues(alpha: 0.95),
          Color.lerp(clothColor, CameoColorPalette.vignetteEdge, 0.4)!,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  void _paintHairBack(Canvas canvas, Size size, double breathDy) {
    if (!_hasHair()) return;
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final volume = headR * CameoShapeLanguage.hairVolumeFraction;
    final hairColor = _hairColorFor(style);

    final paint = Paint()
      ..color = hairColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(cx, headCy - volume * 0.4),
      headR + volume,
      paint,
    );
  }

  void _paintNeck(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final neckW = headR * 0.55;
    final neckTop = headCy + headR * 0.7;
    final neckBottom = size.height * 0.70 + breathDy;

    final paint = Paint()
      ..color = Color.lerp(
        style.skinTone,
        CameoColorPalette.vignetteEdge,
        0.15,
      )!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, (neckTop + neckBottom) / 2),
          width: neckW,
          height: neckBottom - neckTop,
        ),
        Radius.circular(neckW * 0.4),
      ),
      paint,
    );
  }

  void _paintHead(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;

    // Skin tone gradient: ivory key side (top-left) → base → shadow side.
    final key = style.lighting.key.color;
    final skin = style.skinTone;
    final shadowSide = Color.lerp(skin, CameoColorPalette.vignetteEdge, 0.45)!;
    final litSide = Color.lerp(skin, key, 0.18)!;

    final rect = Rect.fromCircle(center: Offset(cx, headCy), radius: headR);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[litSide, skin, shadowSide],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(rect);

    // Slightly oval head (CameoShapeLanguage.headWidthToHeight).
    canvas.save();
    canvas.translate(cx, headCy);
    canvas.scale(CameoShapeLanguage.headWidthToHeight, 1.0);
    final headPath = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: headR));
    canvas.drawPath(headPath, paint);
    canvas.restore();
  }

  void _paintHairFront(Canvas canvas, Size size, double breathDy) {
    if (!_hasHair()) return;
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final hairColor = _hairColorFor(style);

    final paint = Paint()
      ..color = hairColor
      ..style = PaintingStyle.fill;

    // Bangs: a soft arc across the top of the forehead.
    final bangPath = Path()
      ..moveTo(cx - headR * 0.75, headCy - headR * 0.2)
      ..quadraticBezierTo(
        cx,
        headCy - headR * 1.15,
        cx + headR * 0.75,
        headCy - headR * 0.2,
      )
      ..quadraticBezierTo(
        cx + headR * 0.4,
        headCy - headR * 0.55,
        cx,
        headCy - headR * 0.5,
      )
      ..quadraticBezierTo(
        cx - headR * 0.4,
        headCy - headR * 0.55,
        cx - headR * 0.75,
        headCy - headR * 0.2,
      )
      ..close();
    canvas.drawPath(bangPath, paint);

    // Side hair down to jaw.
    final sidePaint = Paint()
      ..color = hairColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - headR * 1.02,
          headCy - headR * 0.3,
          headR * 0.28,
          headR * 1.5,
        ),
        Radius.circular(headR * 0.14),
      ),
      sidePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx + headR * 0.74,
          headCy - headR * 0.3,
          headR * 0.28,
          headR * 1.5,
        ),
        Radius.circular(headR * 0.14),
      ),
      sidePaint,
    );
  }

  void _paintEars(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final earY = headCy + headR * 0.05;
    final earW = headR * 0.18;
    final earH = headR * 0.32;

    final paint = Paint()
      ..color = Color.lerp(style.skinTone, CameoColorPalette.vignetteEdge, 0.2)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx - headR * 0.95, earY),
          width: earW,
          height: earH,
        ),
        Radius.circular(earW * 0.5),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx + headR * 0.95, earY),
          width: earW,
          height: earH,
        ),
        Radius.circular(earW * 0.5),
      ),
      paint,
    );
  }

  void _paintEyes(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final eyeW = headR * 2 * CameoShapeLanguage.eyeWidthFraction;
    final eyeH = eyeW * CameoShapeLanguage.eyeHeightToWidth *
        (1.0 - blinkCloseFactor * 0.92);
    final eyeY = headCy - headR * 0.05;
    final eyeSeparation = eyeW * 1.05;

    final scleraPaint = Paint()..color = const Color(0xFFF2EADC);
    final irisColor = _irisColorFor(style);
    final irisPaint = Paint()..color = irisColor;
    final pupilPaint = Paint()..color = const Color(0xFF1A0E08);
    final catchPaint = Paint()..color = Colors.white;

    final irisR = eyeW * CameoShapeLanguage.irisDiameterFraction / 2;
    final catchR = irisR * CameoShapeLanguage.catchlightRadiusFraction;

    for (final sign in <int>[-1, 1]) {
      final ex = cx + sign * eyeSeparation / 2;
      // Sclera.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(ex, eyeY), width: eyeW, height: eyeH),
        scleraPaint,
      );
      // Iris (offset by saccade).
      final irisCx = ex + saccadeOffset.dx * irisR * 0.6;
      final irisCy = eyeY + saccadeOffset.dy * irisR * 0.6;
      canvas.drawCircle(Offset(irisCx, irisCy), irisR, irisPaint);
      // Pupil.
      canvas.drawCircle(Offset(irisCx, irisCy), irisR * 0.5, pupilPaint);
      // Catchlight (top-left — matches GraphLighting.lightSource).
      canvas.drawCircle(
        Offset(irisCx - irisR * 0.3, irisCy - irisR * 0.3),
        catchR,
        catchPaint,
      );
    }
  }

  void _paintBrows(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final browY = headCy - headR * 0.22;
    final browW = headR * 0.42;
    final browH = headR * 0.05;
    final browOffset = headR * 0.55;

    final paint = Paint()
      ..color = _hairColorFor(style).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    for (final sign in <int>[-1, 1]) {
      canvas.save();
      canvas.translate(cx + sign * browOffset, browY);
      canvas.rotate(sign * -0.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(width: browW, height: browH),
          Radius.circular(browH * 0.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintNose(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final noseTop = headCy - headR * 0.12;
    final noseBottom = headCy + headR * 0.32;
    final noseW = headR * CameoShapeLanguage.noseBridgeWidthFraction * 2;

    // Soft nose shadow on the camera-right side.
    final shadowPaint = Paint()
      ..color = Color.lerp(
        style.skinTone,
        CameoColorPalette.vignetteEdge,
        0.32,
      )!.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = noseW * 0.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(cx + noseW * 0.3, noseTop)
        ..quadraticBezierTo(
          cx + noseW * 0.7,
          (noseTop + noseBottom) / 2,
          cx + noseW * 0.2,
          noseBottom,
        ),
      shadowPaint,
    );
  }

  void _paintMouth(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final mouthY = headCy + headR * 0.48;
    final mouthW = headR * 0.42;

    // Expression: mouth_corner_up weight drives smile.
    final smile = style.expression.morphWeights['mouth_corner_up'] ?? 0.0;
    final frown = style.expression.morphWeights['mouth_corner_down'] ?? 0.0;
    final lift = smile - frown; // [-1, 1]

    final paint = Paint()
      ..color = const Color(0xFF8A4A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = headR * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(cx - mouthW / 2, mouthY + lift * headR * 0.08)
        ..quadraticBezierTo(
          cx,
          mouthY + lift * headR * 0.16,
          cx + mouthW / 2,
          mouthY + lift * headR * 0.08,
        ),
      paint,
    );
  }

  void _paintEmberRim(Canvas canvas, Size size, double breathDy) {
    final cx = size.width / 2;
    final headR = _headRadius(size);
    final headCy = _headCenterY(size) + breathDy;
    final rimColor = style.lighting.rim.color;

    // Hair-line rim on the camera-right side of the head.
    final paint = Paint()
      ..color = rimColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = headR * 0.06
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 1.2);

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, headCy), radius: headR * 1.02),
      -math.pi / 4,
      math.pi / 2,
      false,
      paint,
    );

    // Subtle rim on the camera-right shoulder too.
    final shoulderRimPaint = Paint()
      ..color = rimColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = headR * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx + headR * 1.0, headCy + headR * 1.4),
        width: headR * 1.4,
        height: headR * 1.4,
      ),
      -math.pi / 2,
      math.pi / 3,
      false,
      shoulderRimPaint,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  double _headRadius(Size size) {
    // Face occupies the target fraction of the frame width.
    final faceW = size.width * style.sceneDensity.targetFaceWidthFraction;
    return faceW / (2 * CameoShapeLanguage.headWidthToHeight);
  }

  double _headCenterY(Size size) {
    return size.height * style.camera.eyeHeightFraction;
  }

  bool _hasHair() {
    // Babies (under 1) have wisps; everyone else has hair. Baldness
    // is a future trait; for now, hair is always present in fallback.
    return true;
  }

  Color _hairColorFor(ResolvedCameoStyle s) {
    // Default to dark brown; grey shift per age band.
    final base = CameoColorPalette.hairDarkBrown;
    final greying = CameoMaterialLibrary.greyingForAgeBand(
      _ageBandIndex(s.ageBand),
    );
    return Color.lerp(base, CameoColorPalette.hairGrey, greying)!;
  }

  Color _irisColorFor(ResolvedCameoStyle s) {
    return CameoColorPalette.eyeDarkBrown;
  }

  Color _clothingColorFor(Color skinTone) {
    // Pick a complementary neutral from the cloth palette.
    // Warm skin → slate; deep skin → ivory; for contrast & dignity.
    final tone = style.skinMaterial.toneIndex;
    if (tone <= 3) return CameoColorPalette.clothSlate;
    if (tone <= 6) return CameoColorPalette.clothClay;
    return CameoColorPalette.clothIvory;
  }

  int _ageBandIndex(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:        return 1;
      case CameoAgeBand.child:       return 2;
      case CameoAgeBand.teenager:    return 3;
      case CameoAgeBand.youngAdult:  return 4;
      case CameoAgeBand.adult:       return 5;
      case CameoAgeBand.middleAged:  return 6;
      case CameoAgeBand.senior:      return 7;
      case CameoAgeBand.elder:       return 8;
    }
  }

  @override
  bool shouldRepaint(covariant CameoPortraitPainter old) {
    return old.style != style ||
        old.animationPhase != animationPhase ||
        old.blinkCloseFactor != blinkCloseFactor ||
        old.saccadeOffset != saccadeOffset;
  }
}
