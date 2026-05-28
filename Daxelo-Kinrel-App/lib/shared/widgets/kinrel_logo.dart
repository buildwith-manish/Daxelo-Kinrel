// lib/shared/widgets/kinrel_logo.dart
//
// DAXELO KINREL — Logo Lockup Widget
//
// Composes [KinrelIcon] + [KinrelWordmark] into a locked-up
// logo with horizontal and vertical layouts, 5 size presets,
// and an optional "by Daxelo" subtitle.
//
// Usage:
// ```dart
// KinrelLogo()
// KinrelLogo(size: LogoSize.lg, layout: LogoLayout.vertical, showByDaxelo: true)
// KinrelLogo(size: LogoSize.sm, layout: LogoLayout.horizontal)
// ```

import 'package:flutter/material.dart';
import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_spacing.dart';
import '../../core/constants/brand_typography.dart';
import 'kinrel_icon.dart';

/// Logo layout direction.
enum LogoLayout {
  /// Icon left, wordmark right
  horizontal,

  /// Icon above, wordmark below
  vertical,
}

/// Logo size presets (matching brand spec).
enum LogoSize {
  /// Compact / small screens — icon 28px
  xs,

  /// App bar — icon 36px
  sm,

  /// Standard — onboarding, cards — icon 48px
  md,

  /// Auth screens — icon 64px
  lg,

  /// Splash, about — icon 96px
  xl,
}

/// KINREL logo lockup (icon + wordmark).
///
/// Composes the brand icon and wordmark into a unified logo
/// with correct proportions per the brand specification.
class KinrelLogo extends StatelessWidget {
  const KinrelLogo({
    super.key,
    this.size = LogoSize.md,
    this.layout = LogoLayout.horizontal,
    this.showByDaxelo = false,
    this.palette =
        KinrelIconPalette.purple, // orange palette (backward-compat name)
    this.animated = false,
  });

  /// Size preset. Default md.
  final LogoSize size;

  /// Layout direction. Default horizontal.
  final LogoLayout layout;

  /// Show "by Daxelo" subtitle below the wordmark. Default false.
  final bool showByDaxelo;

  /// Icon palette variant. Default [KinrelIconPalette.purple] (orange values).
  final KinrelIconPalette palette;

  /// Whether to animate the icon. Default false.
  final bool animated;

  // ── Size Mappings ─────────────────────────────────────────────────

  double get iconSize => switch (size) {
    LogoSize.xs => KinrelSpacing.logoXs,
    LogoSize.sm => KinrelSpacing.logoSm,
    LogoSize.md => KinrelSpacing.logoMd,
    LogoSize.lg => KinrelSpacing.logoLg,
    LogoSize.xl => KinrelSpacing.logoXl,
  };

  double get _scale => switch (size) {
    LogoSize.xs => KinrelSpacing.logoScaleXs,
    LogoSize.sm => KinrelSpacing.logoScaleSm,
    LogoSize.md => KinrelSpacing.logoScaleMd,
    LogoSize.lg => KinrelSpacing.logoScaleLg,
    LogoSize.xl => KinrelSpacing.logoScaleXl,
  };

  double get wordmarkFontSize => 28 * _scale;

  // ── Text Colors per Palette ───────────────────────────────────────

  Color get _textColor => switch (palette) {
    KinrelIconPalette.purple => KinrelColors.textPrimary,
    KinrelIconPalette.light => Color(0xFF1A0A00),
    KinrelIconPalette.mono => Color(0xFF1F2937),
    KinrelIconPalette.outline => KinrelColors.textPrimary,
  };

  Color get _subtitleColor => switch (palette) {
    KinrelIconPalette.purple => KinrelColors.textSecondary,
    KinrelIconPalette.light => Color(0xFF7A5040),
    KinrelIconPalette.mono => Color(0xFF6B7280),
    KinrelIconPalette.outline => KinrelColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final icon = KinrelIcon(
      size: iconSize,
      palette: palette,
      animated: animated,
    );

    final gap = layout == LogoLayout.horizontal
        ? iconSize * 0.25
        : iconSize * 0.18;

    final letterSpacing = (size == LogoSize.xs || size == LogoSize.sm)
        ? 0.08
        : 0.14;

    final wordmark = _buildWordmark(letterSpacing);

    Widget logo;
    if (layout == LogoLayout.horizontal) {
      logo = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          SizedBox(width: gap),
          wordmark,
        ],
      );
    } else {
      logo = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          SizedBox(height: gap),
          wordmark,
        ],
      );
    }

    if (showByDaxelo) {
      logo = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: layout == LogoLayout.horizontal
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          logo,
          SizedBox(height: 4 * _scale),
          Text(
            'by Daxelo',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 9 * _scale,
              fontWeight: FontWeight.w400,
              letterSpacing: KinrelTypography.bylineDaxelo * (9 * _scale),
              color: _subtitleColor,
              height: 1.0,
            ),
          ),
        ],
      );
    }

    return Semantics(
      label: 'KINREL logo${showByDaxelo ? ' by Daxelo' : ''}',
      child: logo,
    );
  }

  Widget _buildWordmark(double letterSpacing) {
    return Align(
      alignment: layout == LogoLayout.horizontal
          ? Alignment.centerLeft
          : Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: layout == LogoLayout.horizontal
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            'KINREL',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: wordmarkFontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing * wordmarkFontSize,
              color: _textColor,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
