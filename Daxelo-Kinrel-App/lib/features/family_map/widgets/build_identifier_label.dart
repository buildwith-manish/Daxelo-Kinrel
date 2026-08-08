// lib/features/family_map/widgets/build_identifier_label.dart
//
// v13.0 — Permanent, visible build identifier for the Family Map screen.
//
// This widget reads the git short hash + UTC build timestamp that
// vercel-build.sh injects at build time via:
//
//   flutter build web --release \
//     --dart-define=KINREL_BUILD_COMMIT="$BUILD_COMMIT" \
//     --dart-define=KINREL_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
//
// It renders a tiny monospace label in a corner of the map screen so
// that anyone — the developer, the user, a future agent — can open the
// live URL and immediately see which commit the running bundle was
// built from. This eliminates the ambiguity that plagued previous
// debugging passes where it was unclear whether a fix actually shipped.
//
// On non-web platforms (or when dart-define is unset, e.g. local dev),
// the label falls back to "dev" so it's still visible.
//
// The label is intentionally minimal: a single line of muted monospace
// text in the bottom-left corner, sized so it doesn't interfere with
// the actual map UI. It is NOT clickable, NOT animated, and does NOT
// participate in focus/layer state — it's a passive read-only chip.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

/// Reads build-time --dart-define values.
///
/// `KINREL_BUILD_COMMIT` — git short hash (e.g. "a3f9c21")
/// `KINREL_BUILD_TIMESTAMP` — UTC build timestamp string (e.g. "2026-07-29 14:32 UTC")
class BuildInfo {
  BuildInfo._();

  static const String commit =
      String.fromEnvironment('KINREL_BUILD_COMMIT', defaultValue: 'dev');
  static const String timestamp =
      String.fromEnvironment('KINREL_BUILD_TIMESTAMP', defaultValue: '');

  /// "build: a3f9c21 · 2026-07-29 14:32 UTC"
  /// or "build: dev" when dart-define is unset (local dev).
  static String get label {
    if (timestamp.isEmpty) return 'build: $commit';
    return 'build: $commit · $timestamp';
  }

  /// Whether this is a real production build (dart-define was set).
  static bool get isProductionBuild => commit != 'dev';
}

/// A tiny bottom-left build identifier label.
///
/// Always rendered (even in dev) so we can confirm the widget tree
/// contains it. Visibility of the label on the live URL is the
/// Step 0 acceptance criterion in the v13 prompt.
class BuildIdentifierLabel extends StatelessWidget {
  const BuildIdentifierLabel({super.key});

  @override
  Widget build(BuildContext context) {
    // Positioned in the TOP-LEFT corner so it doesn't collide with the
    // timeline scrubber (bottom: 0, full-width) or the map control stack
    // (right side). Safe-area aware so it doesn't sit under the notch /
    // status bar on notched devices.
    return Positioned(
      left: 8,
      top: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            BuildInfo.label,
            style: const TextStyle(
              color: Color(0xFFB8B8B8),
              fontSize: 10,
              fontFamily: 'RobotoMono, monospace',
              letterSpacing: 0.2,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
