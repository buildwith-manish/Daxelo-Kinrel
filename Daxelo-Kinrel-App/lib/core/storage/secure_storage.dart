import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Secure storage for sensitive data (auth tokens, keys)
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

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
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<void> clearAuthTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  // ── User ────────────────────────────────────────────────────
  Future<void> saveUserId(String id) =>
      _storage.write(key: _keyUserId, value: id);
  Future<String?> getUserId() => _storage.read(key: _keyUserId);

  Future<void> saveUserEmail(String email) =>
      _storage.write(key: _keyUserEmail, value: email);
  Future<String?> getUserEmail() => _storage.read(key: _keyUserEmail);

  Future<void> savePreferredLanguage(String lang) =>
      _storage.write(key: _keyPreferredLanguage, value: lang);
  Future<String?> getPreferredLanguage() =>
      _storage.read(key: _keyPreferredLanguage);

  // ── Onboarding ──────────────────────────────────────────────
  Future<void> setOnboardingComplete(bool complete) =>
      _storage.write(key: _keyOnboardingComplete, value: complete.toString());
  Future<bool> isOnboardingComplete() async {
    final value = await _storage.read(key: _keyOnboardingComplete);
    return value == 'true';
  }

  // ── Clear All ───────────────────────────────────────────────
  Future<void> clearAll() => _storage.deleteAll();
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
