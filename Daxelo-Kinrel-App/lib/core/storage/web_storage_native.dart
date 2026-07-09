// lib/core/storage/web_storage_native.dart
//
// Native (non-web) stub for the conditional import.
// The actual native implementation is in web_storage.dart via SharedPreferences.
// This file exists only so the conditional import resolves on native platforms.

bool getBool(String key, {bool fallback = false}) {
  // This should never be called on native — the WebStorage class handles
  // native via SharedPreferences directly. But we provide a fallback
  // just in case.
  return fallback;
}

Future<bool> setBool(String key, bool value) async {
  // This should never be called on native.
  return false;
}
