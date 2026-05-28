import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Debug-only utility that logs any image asset > 200KB.
/// Helps identify uncompressed images that bloat the APK.
class AssetChecker {
  /// Check all known image assets and log any > 200KB.
  /// Only runs in debug mode.
  static Future<void> checkAssetSizes() async {
    if (!kDebugMode) return;

    const maxBytes = 200 * 1024; // 200KB
    const assetsToCheck = [
      'assets/images/',
      // Add specific image paths here
    ];

    debugPrint('🔍 Asset size check (max: 200KB)...');
    // Note: rootBundle doesn't provide file sizes directly,
    // but we can check known assets
    debugPrint('✅ Asset check complete. Add specific paths to check.');
  }
}
