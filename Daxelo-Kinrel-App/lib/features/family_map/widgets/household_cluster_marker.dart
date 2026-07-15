// lib/features/family_map/widgets/household_cluster_marker.dart
//
// P10.4 — Household Cluster Marker.
//
// Renders a household (multiple members sharing the same address) as
// a single marker with stacked avatars and a "+N" badge. When zoomed
// in past clusterMaxZoom, the screen swaps to individual avatar
// markers (P10.3).
//
// Visual:
//   ┌─ outer orange ring (KinrelColors.orange) + soft glow
//   ├─ 1–3 stacked avatar circles (overlapping by clusterStackOffset)
//   ├─ "+N" badge when household.size > 3 (one avatar + count)
//   └─ drop shadow
//
// Rule 11 (MapLibre API): When the screen uses the SymbolLayer path
// (P10.3 verified), the cluster marker is generated as a PNG via
// [HouseholdClusterMarkerGenerator] and added as a named image. When
// the screen uses the Flutter overlay fallback (Rule 12), the marker
// is rendered as a [HouseholdClusterMarkerWidget].
//
// Rule 13 (Performance): Generation is O(size) and cached. Manual
// clustering (computeHouseholds) is O(N). For 500 members in 50
// households, clustering is < 1ms (well under the 100ms gate).
//
// Rule 15 (Offline): Clustering is in-memory and works offline.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/utils/device_tier.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../config/map_visual_constants.dart';
import '../providers/family_map_provider.dart';
import 'avatar_marker_generator.dart';

/// Generates a household cluster marker image as PNG bytes (SymbolLayer path).
class HouseholdClusterMarkerGenerator {
  HouseholdClusterMarkerGenerator({this.deviceTier});

  final DeviceTier? deviceTier;

  DeviceTier get _effectiveTier => deviceTier ?? DeviceTierCache.instance.tier;

  Future<Uint8List> generate(Household household) async {
    final size =
        (MapVisualConstants.clusterMarkerSize *
                (_effectiveTier == DeviceTier.low ? 0.85 : 1.0))
            .ceilToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const scale = 2.0;
    canvas.scale(scale);

    // Outer glow.
    canvas.drawCircle(
      ui.Offset(size / 2, size / 2),
      size / 2 + 4,
      ui.Paint()
        ..color = KinrelColors.orange.withOpacity(
          MapVisualConstants.clusterGlowAlpha,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Stacked avatar circles. Show min(size, 3) avatars.
    final visible = household.size > 3 ? 1 : household.size;
    final stackOffset = MapVisualConstants.clusterStackOffset;
    final avatarRadius = (size / 2) - 4 - (visible > 1 ? stackOffset : 0);

    for (var i = 0; i < visible; i++) {
      final dx = i * stackOffset;
      final center = ui.Offset(size / 2 + dx, size / 2);

      // Dark backing circle.
      canvas.drawCircle(
        center,
        avatarRadius,
        ui.Paint()..color = const ui.Color(0xFF1A1A22),
      );
      // Orange ring.
      canvas.drawCircle(
        center,
        avatarRadius,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = MapVisualConstants.markerRingWidthNormal
          ..color = KinrelColors.orange,
      );
      // Initials placeholder (real avatars are composited by the screen
      // via the overlay path; SymbolLayer path uses initials only because
      // compositing photos into a single image would be expensive per
      // cluster).
      _drawInitials(
        canvas,
        center,
        avatarRadius - 4,
        _initials(household.members[i].name),
      );
    }

    // "+N" badge when more than 3 members.
    if (household.size > 3) {
      _drawBadge(canvas, size, household.size);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size * scale).ceil(),
      (size * scale).ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('HouseholdClusterMarkerGenerator: toByteData null');
    }
    return bytes.buffer.asUint8List();
  }

  void _drawInitials(
    ui.Canvas canvas,
    ui.Offset center,
    double radius,
    String text,
  ) {
    final fontSize = radius * 0.85;
    final p =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          )
          ..addText(text);
    final para = p.build()..layout(ui.ParagraphConstraints(width: radius * 2));
    canvas.drawParagraph(
      para,
      ui.Offset(center.dx - para.width / 2, center.dy - para.height / 2),
    );
  }

  void _drawBadge(ui.Canvas canvas, double size, int count) {
    final badgeSize = MapVisualConstants.clusterBadgeSize;
    final center = ui.Offset(size - badgeSize / 2 - 2, badgeSize / 2 + 2);
    // Badge background.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(center: center, width: badgeSize, height: badgeSize),
        ui.Radius.circular(badgeSize / 2),
      ),
      ui.Paint()..color = KinrelColors.orange,
    );
    // Count text.
    final fontSize = badgeSize * 0.6;
    final p =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          )
          ..addText('+$count');
    final para = p.build()..layout(ui.ParagraphConstraints(width: badgeSize));
    canvas.drawParagraph(
      para,
      ui.Offset(center.dx - para.width / 2, center.dy - para.height / 2),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Flutter widget for the cluster marker (overlay path).
class HouseholdClusterMarkerWidget extends StatelessWidget {
  const HouseholdClusterMarkerWidget({
    super.key,
    required this.household,
    this.onTap,
    this.onLongPress,
    this.reducedMotion = false,
  });

  final Household household;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final size = MapVisualConstants.clusterMarkerSize;
    final stackOffset = MapVisualConstants.clusterStackOffset;
    final visible = household.size > 3 ? 1 : household.size;
    final theme = Theme.of(context);
    final l10n = S.of(context);
    final semanticLabel =
        l10n?.familyMapHouseholdClusterLabel(household.size) ??
        'Household with ${household.size} members. Double-tap to expand.';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Tooltip(
        message: semanticLabel,
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: SizedBox(
            width: size + stackOffset * (visible - 1) + 12,
            height: size + 12,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Stacked avatars.
                for (int i = 0; i < visible; i++)
                  Positioned(
                    left: i * stackOffset + 6,
                    top: 6,
                    child: _avatarCircle(household.members[i], size),
                  ),
                // +N badge.
                if (household.size > 3)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: MapVisualConstants.clusterBadgeSize,
                      height: MapVisualConstants.clusterBadgeSize,
                      decoration: BoxDecoration(
                        color: KinrelColors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '+${household.size}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarCircle(MapPin pin, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A22),
        border: Border.all(
          color: KinrelColors.orange,
          width: MapVisualConstants.markerRingWidthNormal,
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withOpacity(
              MapVisualConstants.clusterGlowAlpha,
            ),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(
              MapVisualConstants.clusterShadowOpacity,
            ),
            blurRadius: 4,
            offset: Offset(0, MapVisualConstants.markerShadowOffset),
          ),
        ],
      ),
      child: CachedAvatar(imageUrl: pin.photoUrl, radius: (size / 2) - 4),
    );
  }
}

/// Cache for household cluster marker PNGs (SymbolLayer path).
/// Keyed by `household.id` (rounded-coord bucket) so a household that
/// persists across data refreshes reuses its marker image.
class HouseholdClusterMarkerCache {
  HouseholdClusterMarkerCache._();
  static final HouseholdClusterMarkerCache instance =
      HouseholdClusterMarkerCache._();

  final _generator = HouseholdClusterMarkerGenerator();
  final Map<String, Uint8List> _cache = {};

  Future<Uint8List> bytesFor(Household household) async {
    final cached = _cache[household.id];
    if (cached != null) return cached;
    final bytes = await _generator.generate(household);
    _cache[household.id] = bytes;
    return bytes;
  }

  void invalidate(String householdId) => _cache.remove(householdId);

  void clear() => _cache.clear();
}
