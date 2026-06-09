// lib/core/widgets/cached_avatar.dart
//
// DAXELO KINREL — Cached Avatar Widget
//
// Reusable cached avatar widgets that use CachedNetworkImage
// with optimized cache settings:
//   - 7-day stale time via KinrelImageCacheManager
//   - 100MB max memory cache size
//   - Shimmer placeholder while loading
//   - Graceful fallback to icons / initials when no image
//   - Circular clipping via ClipOval
//
// Use these widgets everywhere the app shows person `photoUrl`
// or family `avatarUrl` to eliminate redundant network requests
// and image flicker on widget rebuilds.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../constants/brand_colors.dart';
import '../utils/image_cache_config.dart';

// ════════════════════════════════════════════════════════════════════
// CACHED AVATAR
// ════════════════════════════════════════════════════════════════════

/// A reusable cached avatar widget that uses [CachedNetworkImage]
/// with optimized cache settings.
///
/// Features:
/// - Uses [KinrelImageCacheManager] with 7-day stale time
/// - Shimmer placeholder while loading
/// - Falls back to a person icon when [imageUrl] is null / empty
/// - Circular clipping via [ClipOval]
/// - Memory-optimized with [memCacheWidth] / [memCacheHeight]
/// - Works with both person `photoUrl` and family `avatarUrl`
///
/// ```dart
/// CachedAvatar(
///   imageUrl: person.photoUrl,
///   radius: 32,
/// )
/// ```
class CachedAvatar extends StatelessWidget {
  const CachedAvatar({
    super.key,
    this.imageUrl,
    this.radius = 24,
    this.placeholder,
    this.errorWidget,
    this.backgroundColor,
    this.border,
    this.fit,
  });

  /// The URL of the image to display.
  ///
  /// If null or empty, shows a default person icon placeholder.
  final String? imageUrl;

  /// The radius of the circular avatar. Defaults to 24.
  final double radius;

  /// Optional custom placeholder widget shown while the image loads.
  ///
  /// When not provided, a shimmer effect is used.
  final Widget? placeholder;

  /// Optional custom error widget shown when the image fails to load.
  ///
  /// When not provided, a default person icon is shown.
  final Widget? errorWidget;

  /// Background color for the placeholder / fallback icon.
  ///
  /// Defaults to [KinrelColors.elevation2] (#202338) in dark mode
  /// or [KinrelColors.lightElevated] (#F5F0EE) in light mode.
  final Color? backgroundColor;

  /// Optional border around the avatar.
  final BoxBorder? border;

  /// How the image should fit within the circle.
  ///
  /// Defaults to [BoxFit.cover].
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final effectiveBg = backgroundColor ?? _defaultBackgroundColor(context);
    final effectiveFit = fit ?? BoxFit.cover;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    // No URL — show icon fallback
    if (imageUrl == null || imageUrl!.isEmpty) {
      if (border != null) {
        return Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: effectiveBg,
            border: border,
          ),
          child: Center(
            child: Icon(
              Icons.person,
              size: radius,
              color: KinrelColors.textSilver,
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: radius,
        backgroundColor: effectiveBg,
        child: Icon(
          Icons.person,
          size: radius,
          color: KinrelColors.textSilver,
        ),
      );
    }

    // URL present — show cached network image inside a circular container
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: effectiveBg,
        border: border,
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          cacheManager: KinrelImageCacheManager.instance,
          fadeInDuration: const Duration(milliseconds: 200),
          fit: effectiveFit,
          width: diameter,
          height: diameter,
          memCacheWidth: (diameter * pixelRatio).toInt(),
          memCacheHeight: (diameter * pixelRatio).toInt(),
          placeholder: (context, url) =>
              placeholder ?? _buildShimmerPlaceholder(diameter, effectiveBg),
          errorWidget: (context, url, error) =>
              errorWidget ??
              Center(
                child: Icon(
                  Icons.person,
                  size: radius,
                  color: KinrelColors.textSilver,
                ),
              ),
        ),
      ),
    );
  }

  /// Builds a shimmer placeholder that matches the avatar shape.
  Widget _buildShimmerPlaceholder(double diameter, Color bgColor) {
    return Shimmer.fromColors(
      baseColor: KinrelColors.darkElevated,
      highlightColor: KinrelColors.darkCard,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// Returns the default background color based on theme brightness.
  Color _defaultBackgroundColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? KinrelColors.elevation2
        : KinrelColors.lightElevated;
  }
}

// ════════════════════════════════════════════════════════════════════
// INITIALS AVATAR
// ════════════════════════════════════════════════════════════════════

/// A variant of [CachedAvatar] that shows initials when no image
/// is available.
///
/// When [imageUrl] is present and non-empty, renders a [CachedAvatar].
/// When [imageUrl] is null or empty, shows [initials] inside a
/// [CircleAvatar] with a themed background.
///
/// ```dart
/// InitialsAvatar(
///   imageUrl: person.photoUrl,
///   initials: person.initials,  // e.g. "RK"
///   radius: 28,
/// )
/// ```
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.radius = 24,
    this.backgroundColor,
    this.foregroundColor,
    this.fontSize,
    this.border,
  });

  /// The URL of the image to display.
  /// If null or empty, shows [initials] instead.
  final String? imageUrl;

  /// The initials to display when no image is available (e.g. "RK").
  final String initials;

  /// The radius of the circular avatar. Defaults to 24.
  final double radius;

  /// Background color for the initials circle.
  ///
  /// Defaults to [KinrelColors.orange] with 20% opacity (orangeGlow).
  final Color? backgroundColor;

  /// Foreground (text) color for the initials.
  ///
  /// Defaults to [KinrelColors.orange].
  final Color? foregroundColor;

  /// Font size for the initials text.
  ///
  /// Defaults to `radius * 0.8`.
  final double? fontSize;

  /// Optional border around the avatar.
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    // If an image URL exists, use CachedAvatar
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedAvatar(
        imageUrl: imageUrl,
        radius: radius,
        backgroundColor: backgroundColor,
        border: border,
      );
    }

    // No image — show initials
    final effectiveBg =
        backgroundColor ?? KinrelColors.orangeGlow;
    final effectiveFg =
        foregroundColor ?? KinrelColors.orange;
    final effectiveFontSize = fontSize ?? (radius * 0.8);

    if (border != null) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveBg,
          border: border,
        ),
        child: Center(
          child: Text(
            initials.toUpperCase(),
            style: TextStyle(
              color: effectiveFg,
              fontSize: effectiveFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: effectiveBg,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: effectiveFg,
          fontSize: effectiveFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// HELPER: Generate initials from a full name
// ════════════════════════════════════════════════════════════════════

/// Generates initials from a full name string.
///
/// Rules:
/// - Single name: first character (e.g. "Madhuri" → "M")
/// - Two names: first char of each (e.g. "Rahul Kumar" → "RK")
/// - Three+ names: first char of first + first char of last
///   (e.g. "Arun Kumar Sharma" → "AS")
/// - Empty / null: returns "?"
///
/// ```dart
/// final initials = generateInitials('Rahul Kumar'); // "RK"
/// ```
String generateInitials(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return '?';

  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts[0].characters.first.toUpperCase();
  }
  if (parts.length == 2) {
    return '${parts[0].characters.first}${parts[1].characters.first}'
        .toUpperCase();
  }
  // 3+ parts: first + last
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}
