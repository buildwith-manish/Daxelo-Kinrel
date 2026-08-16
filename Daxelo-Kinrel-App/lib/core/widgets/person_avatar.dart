// lib/core/widgets/person_avatar.dart
//
// DAXELO KINREL — Shared PersonAvatar Widget (v5.15)
//
// A single reusable avatar widget that shows a person's photo (if present)
// or a colored circle with their initial. Replaces ~21 independent inline
// implementations across the codebase.
//
// This is a lightweight extraction — it does NOT handle graph-node-specific
// concerns (category rings, dashed-unlinked styling, badges). Those remain
// in graph_node.dart which layers its own decorations on top.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';

/// A circular avatar showing a person's photo or initial.
///
/// Parameters:
/// - [name] — the person's name (first letter used as the initial fallback)
/// - [photoUrl] — optional network image URL
/// - [size] — diameter in pixels (default 40)
/// - [backgroundColor] — circle background when no photo (defaults to
///   KinrelColors.orange at 15% opacity)
/// - [textColor] — initial text color (defaults to KinrelColors.orange)
/// - [borderColor] — optional border ring color
/// - [borderWidth] — border width (default 0 = no border)
/// - [onTap] — optional tap callback
/// - [cacheManager] — optional cache manager for CachedNetworkImage
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.borderWidth = 0,
    this.onTap,
    this.fontWeight = FontWeight.w700,
  });

  /// The person's display name. First character (uppercased) is used as
  /// the initial when no photo is available. Falls back to '?' if empty.
  final String name;

  /// Optional network image URL. When null or empty, the initial is shown.
  final String? photoUrl;

  /// Diameter in pixels.
  final double size;

  /// Background color when no photo. Defaults to orange at 15% opacity.
  final Color? backgroundColor;

  /// Text color for the initial. Defaults to orange.
  final Color? textColor;

  /// Optional border color.
  final Color? borderColor;

  /// Border width. 0 = no border.
  final double borderWidth;

  /// Optional tap callback.
  final VoidCallback? onTap;

  /// Font weight for the initial text. Defaults to FontWeight.w700.
  final FontWeight fontWeight;

  /// Static helper: computes the initial for a name.
  /// Returns the first character uppercased, or '?' if empty.
  /// Use this when you need just the initials string (e.g. for DKAvatar).
  static String initialsFor(String name) {
    if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }

  String get _initial => initialsFor(name);

  double get _fontSize => size * 0.4;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? KinrelColors.orange.withValues(alpha: 0.15);
    final fg = textColor ?? KinrelColors.orange;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    Widget avatar;

    if (hasPhoto) {
      avatar = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            fit: BoxFit.cover,
            placeholder: (context, url) => _buildInitialCircle(bg, fg),
            errorWidget: (context, url, error) => _buildInitialCircle(bg, fg),
          ),
        ),
      );
    } else {
      avatar = _buildInitialCircle(bg, fg);
    }

    if (borderWidth > 0 && borderColor != null) {
      avatar = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor!, width: borderWidth),
        ),
        child: avatar,
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }

  Widget _buildInitialCircle(Color bg, Color fg) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initial,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: _fontSize,
            fontWeight: fontWeight,
            color: fg,
            height: 1,
          ),
        ),
      ),
    );
  }
}
