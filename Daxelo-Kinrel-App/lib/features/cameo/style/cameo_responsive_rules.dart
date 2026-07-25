// lib/features/cameo/style/cameo_responsive_rules.dart
//
// KINREL CAMEO — Responsive Scaling Rules
//
// Deterministic rules so every Cameo is visually stable across desktop,
// tablet, and mobile with NO clipping, stretching, accidental zooming,
// overflow, layout shift, broken aspect ratios, or forced viewport
// behavior (per the request).
//
// PRINCIPLE: A Cameo is letterboxed inside its container — it NEVER
// crops the face, NEVER stretches to fill, NEVER forces a viewport.
// The aspect ratio is locked to the camera frame's target ratio.
// The Cameo scales to fit the SMALLEST container dimension, then
// letterboxes the rest with the warm vignette.

import 'package:flutter/material.dart';

/// The target aspect ratio (width / height) for each camera frame.
/// Portrait = 1:1.2 (slightly tall). Bust = 1:1. Full = 1:1.6.
@immutable
class CameoAspectRatio {
  const CameoAspectRatio._();

  static const double portrait = 1.0 / 1.2;
  static const double bust = 1.0;
  static const double full = 1.0 / 1.6;
}

/// Deterministic responsive scaling rules for a Cameo surface.
@immutable
class CameoResponsiveRules {
  const CameoResponsiveRules({
    required this.surfaceId,
    required this.aspectRatio,
    required this.minRenderSize,
    required this.maxRenderSize,
    required this.desktopMaxSize,
    required this.tabletMaxSize,
    required this.mobileMaxSize,
    required this.allowStretch,
    required this.allowCrop,
    required this.allowViewportForce,
  });

  final String surfaceId;
  final double aspectRatio;

  /// Minimum render size (width, height) in logical px. Below this,
  /// the Cameo shows the fallback silhouette only (no detail).
  final (double, double) minRenderSize;

  /// Maximum render size (width, height) in logical px. Above this,
  /// the Cameo stops scaling (no infinite zoom on desktop).
  final (double, double) maxRenderSize;

  /// Per-breakpoint max sizes. The effective max is the smaller of
  /// maxRenderSize and the breakpoint max.
  final (double, double) desktopMaxSize;
  final (double, double) tabletMaxSize;
  final (double, double) mobileMaxSize;

  // SAFETY INVARIANTS — all must be false for a Kinrel Cameo.
  /// ALWAYS false. The Cameo never stretches.
  final bool allowStretch;

  /// ALWAYS false. The Cameo never crops the face.
  final bool allowCrop;

  /// ALWAYS false. The Cameo never forces a viewport.
  final bool allowViewportForce;

  /// Compute the effective render size for a given container + breakpoint.
  /// The Cameo fits the container while preserving aspect ratio,
  /// clamped to [minRenderSize, maxRenderSize] and the breakpoint max.
  Size effectiveSizeFor({
    required Size containerSize,
    required CameoBreakpoint breakpoint,
  }) {
    final bpMax = switch (breakpoint) {
      CameoBreakpoint.desktop => desktopMaxSize,
      CameoBreakpoint.tablet => tabletMaxSize,
      CameoBreakpoint.mobile => mobileMaxSize,
    };

    final maxWidth = [
      maxRenderSize.$1,
      bpMax.$1,
    ].reduce((a, b) => a < b ? a : b);
    final maxHeight = [
      maxRenderSize.$2,
      bpMax.$2,
    ].reduce((a, b) => a < b ? a : b);

    // Fit aspect ratio inside container, then clamp.
    double w = containerSize.width;
    double h = w / aspectRatio;
    if (h > containerSize.height) {
      h = containerSize.height;
      w = h * aspectRatio;
    }

    // Clamp to max.
    if (w > maxWidth) {
      w = maxWidth;
      h = w / aspectRatio;
    }
    if (h > maxHeight) {
      h = maxHeight;
      w = h * aspectRatio;
    }

    // Clamp to min (no smaller than min render size).
    if (w < minRenderSize.$1) {
      w = minRenderSize.$1;
      h = w / aspectRatio;
    }
    if (h < minRenderSize.$2) {
      h = minRenderSize.$2;
      w = h * aspectRatio;
    }

    return Size(w, h);
  }
}

/// Responsive breakpoints (aligns with the app's responsive_framework).
enum CameoBreakpoint { desktop, tablet, mobile }

/// Returns the breakpoint for a given width (logical px).
CameoBreakpoint cameoBreakpointForWidth(double width) {
  if (width >= 1024) return CameoBreakpoint.desktop;
  if (width >= 600) return CameoBreakpoint.tablet;
  return CameoBreakpoint.mobile;
}

/// The deterministic library of approved responsive rules.
@immutable
class CameoResponsiveLibrary {
  const CameoResponsiveLibrary._();

  /// Studio — bust aspect, scales freely up to desktop max.
  static const CameoResponsiveRules studio = CameoResponsiveRules(
    surfaceId: 'studio',
    aspectRatio: CameoAspectRatio.bust,
    minRenderSize: (180, 180),
    maxRenderSize: (720, 720),
    desktopMaxSize: (640, 640),
    tabletMaxSize: (520, 520),
    mobileMaxSize: (380, 380),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// Profile hero — bust aspect, mid-size on desktop.
  static const CameoResponsiveRules profileHero = CameoResponsiveRules(
    surfaceId: 'profile_hero',
    aspectRatio: CameoAspectRatio.bust,
    minRenderSize: (120, 120),
    maxRenderSize: (480, 480),
    desktopMaxSize: (320, 320),
    tabletMaxSize: (280, 280),
    mobileMaxSize: (220, 220),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// Family Map marker — portrait, small.
  static const CameoResponsiveRules mapMarker = CameoResponsiveRules(
    surfaceId: 'map_marker',
    aspectRatio: CameoAspectRatio.portrait,
    minRenderSize: (48, 58),
    maxRenderSize: (96, 115),
    desktopMaxSize: (80, 96),
    tabletMaxSize: (72, 86),
    mobileMaxSize: (64, 77),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// Family Graph node — portrait, small.
  static const CameoResponsiveRules graphNode = CameoResponsiveRules(
    surfaceId: 'graph_node',
    aspectRatio: CameoAspectRatio.portrait,
    minRenderSize: (44, 53),
    maxRenderSize: (88, 106),
    desktopMaxSize: (72, 86),
    tabletMaxSize: (64, 77),
    mobileMaxSize: (56, 67),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// Chat avatar — portrait, very small.
  static const CameoResponsiveRules chatAvatar = CameoResponsiveRules(
    surfaceId: 'chat_avatar',
    aspectRatio: CameoAspectRatio.portrait,
    minRenderSize: (32, 38),
    maxRenderSize: (64, 77),
    desktopMaxSize: (48, 58),
    tabletMaxSize: (44, 53),
    mobileMaxSize: (40, 48),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// Journey cinematic — full aspect, large.
  static const CameoResponsiveRules journey = CameoResponsiveRules(
    surfaceId: 'journey',
    aspectRatio: CameoAspectRatio.full,
    minRenderSize: (240, 384),
    maxRenderSize: (1280, 2048),
    desktopMaxSize: (960, 1536),
    tabletMaxSize: (720, 1152),
    mobileMaxSize: (420, 672),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// Timeline card — portrait, mid.
  static const CameoResponsiveRules timelineCard = CameoResponsiveRules(
    surfaceId: 'timeline_card',
    aspectRatio: CameoAspectRatio.portrait,
    minRenderSize: (80, 96),
    maxRenderSize: (200, 240),
    desktopMaxSize: (160, 192),
    tabletMaxSize: (140, 168),
    mobileMaxSize: (120, 144),
    allowStretch: false,
    allowCrop: false,
    allowViewportForce: false,
  );

  /// All approved responsive presets.
  static const List<CameoResponsiveRules> all = <CameoResponsiveRules>[
    studio,
    profileHero,
    mapMarker,
    graphNode,
    chatAvatar,
    journey,
    timelineCard,
  ];

  /// Look up by surface id. Returns [studio] as the safe default.
  static CameoResponsiveRules byId(String surfaceId) {
    for (final r in all) {
      if (r.surfaceId == surfaceId) return r;
    }
    return studio;
  }

  /// Safety invariant: every approved preset must have all three safety
  /// flags false. Quality gates (CameoQualityGates) call this.
  static bool get allPresetsSafe {
    for (final r in all) {
      if (r.allowStretch || r.allowCrop || r.allowViewportForce) {
        return false;
      }
    }
    return true;
  }
}
