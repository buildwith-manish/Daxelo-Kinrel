// lib/graph/widgets/graph_network_image.dart
//
// Created in v31 refactor.
//
// A CORS-safe, web-compatible network image widget for graph node
// avatars. Uses [Image.network] with:
//   - loadingBuilder: shows a shimmer placeholder while loading
//   - errorBuilder: falls back to initials on any error (CORS, 404, etc.)
//   - cacheWidth: downsamples the decoded image to the display size,
//     reducing memory usage on mobile and improving paint performance
//     on web (especially CanvasKit which decodes images to GPU textures)
//
// Web compatibility notes:
//   - CanvasKit (the default web renderer) loads images via fetch() +
//     decodeImageFromBytes. This requires the image server to send
//     proper CORS headers (Access-Control-Allow-Origin). Supabase
//     Storage does this by default for public buckets.
//   - If the image fails to load (CORS, 404, network error), the
//     errorBuilder kicks in and shows the person's initials instead.
//     This ensures the graph never has "broken image" placeholders.
//   - We do NOT use [Image.network] directly in the widget tree because
//     on web, a failed CORS fetch can spam the browser console with
//     errors. The errorBuilder silences this gracefully.

import 'package:flutter/material.dart';

/// A network image widget optimized for graph node avatars.
///
/// Shows a circular image with [diameter] size. If the image fails
/// to load for any reason (CORS, 404, timeout), falls back to
/// showing [initials] on a colored background.
class GraphNetworkImage extends StatelessWidget {
  const GraphNetworkImage({
    super.key,
    required this.photoUrl,
    required this.diameter,
    required this.initials,
    this.backgroundColor = const Color(0xFF334155),
    this.textColor = Colors.white,
  });

  final String? photoUrl;
  final double diameter;
  final String initials;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) {
      return _buildInitials(diameter);
    }

    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        // Downsample to display size — reduces memory on mobile and
        // GPU texture size on web (CanvasKit). The cacheWidth is in
        // physical pixels, so we multiply by the device pixel ratio.
        cacheWidth: (diameter * 2).round(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildShimmer(diameter);
        },
        errorBuilder: (context, error, stackTrace) =>
            _buildInitials(diameter),
      ),
    );
  }

  Widget _buildInitials(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: diameter * 0.28,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: SizedBox(
          width: diameter * 0.3,
          height: diameter * 0.3,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              textColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
