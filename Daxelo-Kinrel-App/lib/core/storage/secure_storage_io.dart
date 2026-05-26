/// Native (mobile/desktop) backend for SecureStorageService
/// Uses flutter_secure_storage (encrypted keystore on Android, Keychain on iOS)
/// This file is used when dart.library.io IS available (i.e., native platforms)

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageBackend {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  Future<String?> read({required String key}) => _storage.read(key: key);

  Future<void> delete({required String key}) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();
}

SecureStorageBackend createBackend() => SecureStorageBackend();
