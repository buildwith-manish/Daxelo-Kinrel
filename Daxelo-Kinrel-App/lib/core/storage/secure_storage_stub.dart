/// Web/Stub backend for SecureStorageService
/// Uses SharedPreferences (which maps to localStorage on web)
/// This file is used when dart.library.io is NOT available (i.e., web)
library;

import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageBackend {
  Future<void> write({required String key, required String value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<String?> read({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> delete({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> deleteAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

SecureStorageBackend createBackend() => SecureStorageBackend();
