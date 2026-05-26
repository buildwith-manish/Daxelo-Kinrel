// lib/shared/widgets/kinrel_wordmark.dart
//
// DAXELO KINREL — Wordmark Widget
//
// Renders the "KINREL" text in the brand display font (Outfit)
// with support for gradient, solid, and mono variants.
//
// Usage:
// ```dart
// KinrelWordmark()                                    // gradient, 24px
// KinrelWordmark(fontSize: 32, variant: WordmarkVariant.solidPurple)
// KinrelWordmark(fontSize: 14, variant: WordmarkVariant.solidWhite)
// ```

import 'package:flutter/material.dart';
import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';

/// Wordmark variant styles.
enum WordmarkVariant {
  /// White → purple gradient (hero / splash screens)
  gradient,

  /// Flat #5D5FEF purple
  solidPurple,

  /// Flat white (#F5F0EE)
  solidWhite,

  /// Flat dark (#1A0A00) for light backgrounds
  solidDark,

  /// Greyed-out #F9FAFB for greyscale contexts
  mono,
}

/// KINREL wordmark widget.
///
/// Renders "KINREL" in the display font with brand-specific
/// letter-spacing that varies by size (tighter at small sizes,
/// wider at larger sizes per brand spec).
class KinrelWordmark extends StatelessWidget {
  /// Font size in logical pixels. Default 24.
  final double fontSize;

  /// Color variant. Default gradient.
  final WordmarkVariant variant;

  /// Override letter spacing. If null, uses brand spec rules.
  final double? letterSpacing;

  /// Optional subtitle "by Daxelo" shown below the wordmark.
  final bool showSubtitle;

  const KinrelWordmark({
    super.key,
    this.fontSize = 24,
    this.variant = WordmarkVariant.gradient,
    this.letterSpacing,
    this.showSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    // Brand spec: tighter tracking at small sizes
    final ls = letterSpacing ?? (fontSize < 20 ? 0.08 : 0.14);

    final style = TextStyle(
      fontFamily: KinrelTypography.displayFont,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: ls * fontSize,
      height: 1.0,
    );

    final wordmark = _buildWordmark(style);

    if (!showSubtitle) return wordmark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        wordmark,
        SizedBox(height: fontSize * 0.1),
        _buildByline(),
      ],
    );
  }

  Widget _buildWordmark(TextStyle style) {
    if (variant == WordmarkVariant.gradient) {
      return ShaderMask(
        shaderCallback: (bounds) =>
            KinrelGradients.wordmarkGradient.createShader(bounds),
        child: Text(
          'KINREL',
          style: style.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }

    final color = switch (variant) {
      WordmarkVariant.solidPurple => KinrelColors.purple,
      WordmarkVariant.solidWhite => KinrelColors.textPrimary,
      WordmarkVariant.solidDark => const Color(0xFF1A0A00),
      WordmarkVariant.mono => const Color(0xFFF9FAFB),
      WordmarkVariant.gradient => KinrelColors.purple, // fallback
    };

    return Text(
      'KINREL',
      style: style.copyWith(color: color),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildByline() {
    final subtitleColor = switch (variant) {
      WordmarkVariant.gradient => KinrelColors.textSecondary,
      WordmarkVariant.solidPurple => KinrelColors.textSecondary,
      WordmarkVariant.solidWhite => KinrelColors.textSecondary,
      WordmarkVariant.solidDark => const Color(0xFF7A5040),
      WordmarkVariant.mono => const Color(0xFF9CA3AF),
    };

    final bylineFontSize = fontSize * 0.32;

    return Text(
      'by Daxelo',
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: bylineFontSize,
        fontWeight: FontWeight.w400,
        letterSpacing: KinrelTypography.bylineDaxelo * bylineFontSize,
        height: 1.0,
        color: subtitleColor,
      ),
      textAlign: TextAlign.center,
    );
  }
}
