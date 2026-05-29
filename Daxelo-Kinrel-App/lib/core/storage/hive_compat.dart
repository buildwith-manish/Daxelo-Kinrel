// lib/core/storage/hive_compat.dart
//
// Hive compatibility shim — provides a global `box` variable that
// mimics the Hive Box API but delegates to SharedPreferences.
// Required because lib/features/ files reference `box` directly
// and cannot be modified.

import 'package:shared_preferences/shared_preferences.dart';

/// A Hive Box-like interface backed by SharedPreferences.
/// Supports get(), put(), containsKey(), delete() — the methods
/// used by lib/features/ screens.
class HiveCompatBox {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError('HiveCompatBox not initialized. Call init() first.');
    }
    return _prefs!;
  }

  bool containsKey(String key) {
    return _p.containsKey(key);
  }

  dynamic get(String key, {dynamic defaultValue}) {
    final p = _p;
    if (!p.containsKey(key)) return defaultValue;
    // SharedPreferences stores all values; return whatever type is stored
    return p.get(key);
  }

  Future<void> put(String key, dynamic value) async {
    if (value is bool) {
      await _p.setBool(key, value);
    } else if (value is int) {
      await _p.setInt(key, value);
    } else if (value is double) {
      await _p.setDouble(key, value);
    } else if (value is String) {
      await _p.setString(key, value);
    } else if (value is List<String>) {
      await _p.setStringList(key, value);
    } else {
      await _p.setString(key, value.toString());
    }
  }

  Future<void> delete(String key) async {
    await _p.remove(key);
  }

  Future<void> clear() async {
    await _p.clear();
  }
}

/// Global box instance — replaces the removed Hive box.
/// Must be initialized via `await box.init()` before use.
late final HiveCompatBox box = HiveCompatBox();
