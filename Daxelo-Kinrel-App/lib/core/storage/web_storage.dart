// lib/core/storage/web_storage.dart
//
// Cross-platform key-value storage that works reliably on both web and
// native. On web, uses dart:html's window.localStorage directly (bypassing
// SharedPreferences which can fail silently in certain browser contexts
// like sandboxed iframes or partitioned storage). On native, delegates
// to SharedPreferences.
//
// Used by the graph tutorial overlay and any other feature that needs
// a simple "has the user seen this?" flag.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Conditional import: on web, import dart:html; on native, import a stub.
import 'web_storage_web.dart' if (dart.library.io) 'web_storage_native.dart'
    as platform;

/// Cross-platform key-value storage for simple flags.
class WebStorage {
  WebStorage._();

  /// Read a boolean flag. Returns [fallback] if not set or on error.
  static Future<bool> getBool(String key, {bool fallback = false}) async {
    if (kIsWeb) {
      return platform.getBool(key, fallback: fallback);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Write a boolean flag. Returns true on success.
  static Future<bool> setBool(String key, bool value) async {
    if (kIsWeb) {
      return platform.setBool(key, value);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(key, value);
    } catch (_) {
      return false;
    }
  }
}
