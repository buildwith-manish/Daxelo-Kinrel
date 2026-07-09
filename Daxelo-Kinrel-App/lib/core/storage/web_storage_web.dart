// lib/core/storage/web_storage_web.dart
//
// Web implementation of WebStorage using dart:html's window.localStorage.
// This bypasses SharedPreferences which can fail silently in certain
// browser contexts (sandboxed iframes, partitioned storage, etc.).

import 'dart:html' as html;

bool getBool(String key, {bool fallback = false}) {
  try {
    final value = html.window.localStorage[key];
    if (value == null) return fallback;
    return value == 'true';
  } catch (_) {
    return fallback;
  }
}

Future<bool> setBool(String key, bool value) async {
  try {
    html.window.localStorage[key] = value.toString();
    return true;
  } catch (_) {
    return false;
  }
}
