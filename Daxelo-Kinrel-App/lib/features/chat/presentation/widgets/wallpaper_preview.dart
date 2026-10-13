// lib/features/chat/presentation/widgets/wallpaper_preview.dart
//
// DAXELO KINREL — Wallpaper Preview (TASK 3)
//
// Small live preview of a wallpaper pattern + base color with two
// mini message bubbles. Used in the theme picker grid.

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';
import 'constellation_pattern.dart';
import 'wallpaper_palette.dart';
import 'wallpaper_patterns.dart';

/// A 96×120 dp live preview showing the wallpaper pattern on the
/// theme's base color, with two mini bubbles (a received bubble
/// with a 3 dp blue band and a sent bubble in the sent color).
class WallpaperPreview extends StatelessWidget {
  const WallpaperPreview({
    super.key,
    required this.baseColor,
    required this.patternId,
    this.tintColor,
    this.intensity = WallpaperIntensity.standard,
  });

  final Color baseColor;
  final String patternId;
  final Color? tintColor;
  final WallpaperIntensity intensity;

  @override
  Widget build(BuildContext context) {
    final palette = WallpaperPalette.resolve(
      intensity: intensity,
      tint: tintColor,
      pattern: _patternForId(patternId),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 96,
        height: 120,
        child: Stack(
          children: [
            // Base color.
            Positioned.fill(
              child: ColoredBox(color: baseColor, child: const SizedBox.expand()),
            ),
            // Pattern.
            Positioned.fill(child: _pattern(patternId, palette)),
            // Mini received bubble (left, with blue band).
            Positioned(
              left: 8,
              top: 12,
              child: _MiniBubble(
                text: 'Hi',
                isSent: false,
                baseColor: baseColor,
              ),
            ),
            // Mini sent bubble (right).
            Positioned(
              right: 8,
              top: 40,
              child: _MiniBubble(
                text: 'Hello',
                isSent: true,
                baseColor: baseColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  WallpaperPattern _patternForId(String id) {
    switch (id) {
      case 'branches': return WallpaperPattern.branches;
      case 'kolam': return WallpaperPattern.kolam;
      case 'contours': return WallpaperPattern.contours;
      default: return WallpaperPattern.constellation;
    }
  }

  Widget _pattern(String id, WallpaperPalette palette) {
    switch (id) {
      case 'branches': return BranchesPattern(palette: palette);
      case 'kolam': return KolamPattern(palette: palette);
      case 'contours': return ContoursPattern(palette: palette);
      default: return ConstellationPattern(palette: palette);
    }
  }
}

/// A mini message bubble for the wallpaper preview.
class _MiniBubble extends StatelessWidget {
  const _MiniBubble({
    required this.text,
    required this.isSent,
    required this.baseColor,
  });

  final String text;
  final bool isSent;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSent ? ChatUi.chatSent : ChatUi.chatReceived,
        borderRadius: BorderRadius.circular(8),
        border: isSent
            ? Border.all(color: ChatUi.chatSentBorder, width: 0.5)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 10,
          color: ChatUi.textPrimary,
        ),
      ),
    );
  }
}
