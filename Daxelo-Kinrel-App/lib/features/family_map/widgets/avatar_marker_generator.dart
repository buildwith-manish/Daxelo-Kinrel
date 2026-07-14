// lib/features/family_map/widgets/avatar_marker_generator.dart
//
// P10.3 — Premium Avatar Marker Generator.
//
// Replaces the generic CircleStyleLayer pins with premium avatar markers
// that show each family member's profile photo, an orange ring, a soft
// glow, and a drop shadow. Selected markers get a gold ring, larger size,
// stronger glow, and a smooth spring scale animation.
//
// Render pipeline (PictureRecorder → PNG bytes):
//   ┌─ drop shadow (offset down-right, blur)
//   ├─ soft glow (radial gradient, orange, tunable alpha)
//   ├─ orange ring (KinrelColors.orange / gold when selected)
//   ├─ dark circle background (for contrast)
//   └─ profile photo (clipped to circle) OR initials (white text)
//
// Rule 11 (MapLibre API): maplibre 0.3.5 exposes StyleController.addImage
// via the `images` parameter on SymbolLayer, plus the high-level
// `style.addImage(name, bytes)` API. We use the higher-level API and
// fall back to a Flutter overlay (Positioned widgets) when addImage
// is unavailable (Rule 12). The fallback path is documented in the
// completion report.
//
// Rule 13 (Performance): Generating 50 marker images is < 500ms on a
// mid-tier device (Rule 16 — tune after benchmarking). If it exceeds
// that, generation switches to lazy mode (visible markers first) and
// aggressively caches. Low-tier devices use a smaller marker size.
//
// Rule 15 (Offline): Photos are loaded via CachedAvatar which has its
// own disk cache. When offline + photo not cached, the marker falls
// back to initials.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/utils/device_tier.dart';
import '../config/map_visual_constants.dart';
import '../providers/family_map_provider.dart';
import '../providers/live_location_provider.dart';

/// Renders premium avatar marker images offscreen and returns PNG bytes
/// that can be added to a MapLibre style via `style.addImage(name, bytes)`.
///
/// Instances are stateless — the class exists mainly to namespace the
/// render helpers and to keep the generator out of the screen widget
/// (Rule 4 — decompose).
class AvatarMarkerGenerator {
  AvatarMarkerGenerator({this.deviceTier});

  final DeviceTier? deviceTier;

  DeviceTier get _effectiveTier =>
      deviceTier ?? DeviceTierCache.instance.tier;

  /// Tunable scale factor applied to marker sizes on low-tier devices
  /// (Rule 13). 1.0 on mid/high, 0.8 on low.
  double get _tierScale => _effectiveTier == DeviceTier.low ? 0.8 : 1.0;

  /// Generates a single avatar marker image as PNG bytes.
  ///
  /// [photo] — already-decoded ImageProvider. If null, [initials] is used.
  /// [initials] — 1-2 character fallback string (e.g. "RS").
  /// [selected] — when true, larger size + gold ring + stronger glow.
  /// [liveTier] — drives the pulsing ring color/opacity for live location.
  Future<Uint8List> generate({
    required ImageProvider? photo,
    required String initials,
    bool selected = false,
    LocationTier? liveTier,
  }) async {
    final baseSize = selected
        ? MapVisualConstants.markerSelectedSize
        : MapVisualConstants.markerNormalSize;
    final size = (baseSize * _tierScale).ceilToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // We render at 2x for crispness on high-DPR screens.
    const scale = 2.0;
    final logicalSize = size;
    final physicalSize = size * scale;
    canvas.scale(scale);

    _drawShadow(canvas, logicalSize);
    _drawGlow(canvas, logicalSize, selected: selected);
    _drawRing(canvas, logicalSize, selected: selected, liveTier: liveTier);
    await _drawAvatar(
      canvas,
      logicalSize,
      photo: photo,
      initials: initials,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      physicalSize.ceil(),
      physicalSize.ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('AvatarMarkerGenerator: toByteData returned null');
    }
    return byteData.buffer.asUint8List();
  }

  /// Generates a marker image and returns it as a [ui.Image] for use
  /// by the Flutter overlay fallback (Rule 12).
  Future<ui.Image> generateAsImage({
    required ImageProvider? photo,
    required String initials,
    bool selected = false,
    LocationTier? liveTier,
  }) async {
    final bytes = await generate(
      photo: photo,
      initials: initials,
      selected: selected,
      liveTier: liveTier,
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Drawing primitives
  // ─────────────────────────────────────────────────────────────────────

  void _drawShadow(ui.Canvas canvas, double size) {
    final offset = MapVisualConstants.markerShadowOffset;
    final paint = ui.Paint()
      ..color = Colors.black.withOpacity(MapVisualConstants.markerShadowOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final center = ui.Offset(size / 2 + offset, size / 2 + offset);
    canvas.drawCircle(center, size / 2, paint);
  }

  void _drawGlow(ui.Canvas canvas, double size, {required bool selected}) {
    final blur = selected
        ? MapVisualConstants.markerGlowBlurSelected
        : MapVisualConstants.markerGlowBlurNormal;
    // Bug 7 fix: reference the centralized glow-alpha constants instead
    // of magic 0.55 / 0.30 literals. Same values, single source of truth.
    final baseAlpha = selected
        ? MapVisualConstants.markerGlowAlphaSelected
        : MapVisualConstants.markerGlowAlphaNormal;
    final paint = ui.Paint()
      ..color = KinrelColors.orange.withOpacity(baseAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    final center = ui.Offset(size / 2, size / 2);
    canvas.drawCircle(center, size / 2 + 4, paint);
  }

  void _drawRing(
    ui.Canvas canvas,
    double size, {
    required bool selected,
    LocationTier? liveTier,
  }) {
    // P11.x — Gradient ring (IgniteGradient: orange → amber) per master prompt.
    // Selected: gold → amber gradient; unselected: orange → amber gradient.
    // NOTE: SweepGradient + Alignment are Flutter framework classes
    // (painting.dart / material.dart), NOT dart:ui — do not prefix with ui.
    final ringGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: 2 * 3.141592653589793,
      colors: selected
          ? [const ui.Color(0xFFE8B941), const ui.Color(0xFFF59240), const ui.Color(0xFFE8B941)]
          : [const ui.Color(0xFFE8612A), const ui.Color(0xFFF59240), const ui.Color(0xFFE8612A)],
      stops: const [0.0, 0.5, 1.0],
    );

    final strokeWidth = selected
        ? MapVisualConstants.markerRingWidthSelected
        : MapVisualConstants.markerRingWidthNormal;

    // Background fill — dark for contrast.
    canvas.drawCircle(
      ui.Offset(size / 2, size / 2),
      size / 2,
      ui.Paint()..color = const ui.Color(0xFF1A1A22),
    );

    // Outer ring stroke (gradient).
    canvas.drawCircle(
      ui.Offset(size / 2, size / 2),
      size / 2 - strokeWidth / 2,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = ringGradient.createShader(
          ui.Rect.fromCircle(
            center: ui.Offset(size / 2, size / 2),
            radius: size / 2,
          ),
        ),
    );

    // P11.x — Selection halo (radial gradient orange→transparent, 4px stroke).
    // Drawn outside the marker ring when selected (master prompt spec).
    if (selected) {
      final haloRadius = size / 2 + MapVisualConstants.selectionHaloRadiusPadding;
      final haloGradient = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          const ui.Color(0xFFE8612A).withOpacity(0.55),
          const ui.Color(0xFFE8612A).withOpacity(0.20),
          const ui.Color(0x00E8612A),
        ],
        stops: const [0.55, 0.85, 1.0],
      );
      canvas.drawCircle(
        ui.Offset(size / 2, size / 2),
        haloRadius,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = MapVisualConstants.selectionHaloStrokeWidth
          ..shader = haloGradient.createShader(
            ui.Rect.fromCircle(
              center: ui.Offset(size / 2, size / 2),
              radius: haloRadius,
            ),
          ),
      );
    }

    // Live-location pulse indicator — a thin outer arc.
    if (liveTier != null) {
      final pulsePaint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5;
      switch (liveTier) {
        case LocationTier.live:
          pulsePaint.color = MapVisualConstants.livePulseRingColor.withOpacity(MapVisualConstants.livePulseRingOpacity);
          canvas.drawCircle(
            ui.Offset(size / 2, size / 2),
            size / 2 + 2,
            pulsePaint,
          );
          break;
        case LocationTier.recent:
          pulsePaint.color = MapVisualConstants.markerSelectedRingColor.withOpacity(MapVisualConstants.recentRingOpacity);
          canvas.drawCircle(
            ui.Offset(size / 2, size / 2),
            size / 2 + 1.5,
            pulsePaint,
          );
          break;
        case LocationTier.stale:
          pulsePaint.color = MapVisualConstants.staleRingColor.withOpacity(MapVisualConstants.staleRingOpacity);
          canvas.drawCircle(
            ui.Offset(size / 2, size / 2),
            size / 2 + 1,
            pulsePaint,
          );
          break;
        case LocationTier.cityFallback:
          // No pulse — city-level precision only.
          break;
      }
    }
  }

  Future<void> _drawAvatar(
    ui.Canvas canvas,
    double size, {
    required ImageProvider? photo,
    required String initials,
  }) async {
    final center = ui.Offset(size / 2, size / 2);
    final radius = (size / 2) - 4; // padding for ring

    if (photo != null) {
      try {
        final stream = photo.resolve(const ImageConfiguration());
        final completer = _ImageStreamCompleter();
        completer.attachTo(stream);
        final imageInfo = await completer.future.timeout(
          MapVisualConstants.photoDecodeTimeout,
          onTimeout: () => throw TimeoutException('photo decode'),
        );
        final src = imageInfo.image;
        final dst = ui.Rect.fromCircle(center: center, radius: radius);
        // Clip to circle then draw the image fitted.
        canvas.save();
        canvas.clipRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromCircle(center: center, radius: radius),
            ui.Radius.circular(radius),
          ),
        );
        paintImage(
          canvas: canvas,
          rect: dst,
          image: src,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        );
        canvas.restore();
        return;
      } catch (e) {
        debugPrint('AvatarMarkerGenerator: photo decode failed: $e — '
            'falling back to initials.');
      }
    }
    _drawInitials(canvas, center, radius, initials);
  }

  void _drawInitials(
    ui.Canvas canvas,
    ui.Offset center,
    double radius,
    String initials,
  ) {
    // Background tint.
    canvas.drawCircle(
      center,
      radius,
      ui.Paint()..color = KinrelColors.orange.withOpacity(MapVisualConstants.markerInitialsBgOpacity),
    );

    // Initials text. Use a sane font size relative to the radius.
    final fontSize = radius * 0.85;
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ))
      ..addText(initials);
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: radius * 2));
    canvas.drawParagraph(
      paragraph,
      ui.Offset(
        center.dx - paragraph.width / 2,
        center.dy - paragraph.height / 2,
      ),
    );
  }
}

/// Tiny wrapper around Flutter's [ImageStreamListener] that turns the
/// listener callback into a Future. Used by [_drawAvatar] to await the
/// decoded image bytes.
class _ImageStreamCompleter {
  _ImageStreamCompleter();

  final Completer<ImageInfo> _completer = Completer<ImageInfo>();
  late ImageStream _stream;
  late ImageStreamListener _listener;

  void attachTo(ImageStream stream) {
    _stream = stream;
    _listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!_completer.isCompleted) _completer.complete(image);
        _stream.removeListener(_listener);
      },
      onError: (exception, stackTrace) {
        if (!_completer.isCompleted) {
          _completer.completeError(exception, stackTrace);
        }
        _stream.removeListener(_listener);
      },
    );
    stream.addListener(_listener);
  }

  Future<ImageInfo> get future => _completer.future.timeout(
        MapVisualConstants.imageStreamTimeout,
        onTimeout: () => throw TimeoutException('ImageStream'),
      );
}

/// Helper that builds a list of (pin, marker bytes) pairs ready to be
/// added to a MapLibre style. Designed to be called from a compute
/// isolate for large families (Rule 13 lazy generation).
///
/// This top-level function is what the screen calls; it manages the
/// generator instance + caching internally.
class AvatarMarkerCache {
  AvatarMarkerCache._() : _generator = AvatarMarkerGenerator();

  static final AvatarMarkerCache instance = AvatarMarkerCache._();

  final AvatarMarkerGenerator _generator;
  final Map<String, Uint8List> _bytesById = <String, Uint8List>{};
  final Map<String, Uint8List> _selectedBytesById = <String, Uint8List>{};

  /// Generates marker bytes for [pin] (and a selected variant).
  /// Results are cached by personId + selected flag.
  Future<Uint8List> bytesFor(
    MapPin pin, {
    bool selected = false,
    LocationTier? liveTier,
    ImageProvider? photoProvider,
  }) async {
    final cache = selected ? _selectedBytesById : _bytesById;
    final key = '${pin.personId}|${liveTier?.name ?? ""}';
    final cached = cache[key];
    if (cached != null) return cached;
    final bytes = await _generator.generate(
      photo: photoProvider,
      initials: _initials(pin.name),
      selected: selected,
      liveTier: liveTier,
    );
    cache[key] = bytes;
    return bytes;
  }

  /// Evicts every cached entry for [personId]. Called when the user
  /// changes their photo or when the live-location tier changes.
  void invalidate(String personId) {
    _bytesById.removeWhere((k, _) => k.startsWith(personId));
    _selectedBytesById.removeWhere((k, _) => k.startsWith(personId));
  }

  /// Clears the entire cache. Called on family switch.
  void clear() {
    _bytesById.clear();
    _selectedBytesById.clear();
  }

  /// Extracts 1-2 character initials from a name. Falls back to '?'
  /// for empty/null names.
  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Re-exported so the screen can pass a [NetworkImage] / [FileImage] /
/// [MemoryImage] without knowing about [ImageProvider] internals.
typedef PhotoProvider = ImageProvider;
