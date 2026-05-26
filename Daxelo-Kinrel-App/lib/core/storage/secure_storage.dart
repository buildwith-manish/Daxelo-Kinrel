import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Conditional import — flutter_secure_storage doesn't support web
import 'secure_storage_stub.dart'
    if (dart.library.io) 'secure_storage_io.dart' as impl;

/// Secure storage for sensitive data (auth tokens, keys)
/// On web: uses SharedPreferences (localStorage)
/// On mobile: uses flutter_secure_storage (encrypted keystore/keychain)
class SecureStorageService {
  final impl.SecureStorageBackend _backend = impl.createBackend();

  // Keys
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';
  static const _keyUserEmail = 'user_email';
  static const _keyPreferredLanguage = 'preferred_language';
  static const _keyOnboardingComplete = 'onboarding_complete';

  // ── Auth ────────────────────────────────────────────────────
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _backend.write(key: _keyAccessToken, value: accessToken);
    await _backend.write(key: _keyRefreshToken, value: refreshToken);
  }

  Future<String?> getAccessToken() => _backend.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _backend.read(key: _keyRefreshToken);

  Future<void> clearAuthTokens() async {
    await _backend.delete(key: _keyAccessToken);
    await _backend.delete(key: _keyRefreshToken);
  }

  // ── User ────────────────────────────────────────────────────
  Future<void> saveUserId(String id) =>
      _backend.write(key: _keyUserId, value: id);
  Future<String?> getUserId() => _backend.read(key: _keyUserId);

  Future<void> saveUserEmail(String email) =>
      _backend.write(key: _keyUserEmail, value: email);
  Future<String?> getUserEmail() => _backend.read(key: _keyUserEmail);

  Future<void> savePreferredLanguage(String lang) =>
      _backend.write(key: _keyPreferredLanguage, value: lang);
  Future<String?> getPreferredLanguage() =>
      _backend.read(key: _keyPreferredLanguage);

  // ── Onboarding ──────────────────────────────────────────────
  Future<void> setOnboardingComplete(bool complete) =>
      _backend.write(key: _keyOnboardingComplete, value: complete.toString());
  Future<bool> isOnboardingComplete() async {
    final value = await _backend.read(key: _keyOnboardingComplete);
    return value == 'true';
  }

  // ── Clear All ───────────────────────────────────────────────
  Future<void> clearAll() => _backend.deleteAll();
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
