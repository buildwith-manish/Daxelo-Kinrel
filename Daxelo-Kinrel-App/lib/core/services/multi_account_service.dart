// lib/core/services/multi_account_service.dart
//
// DAXELO KINREL — Multi-Account Manager
//
// Allows users to add multiple accounts and switch between them instantly,
// similar to Instagram, X, or Gmail. Each account's session, data,
// notifications, and preferences are kept separate.
//
// Architecture:
//   - Stores up to 5 account sessions in flutter_secure_storage
//   - Each session includes: userId, email, displayName, avatarUrl,
//     accessToken, refreshToken, and preferredLanguage
//   - The "active" account is the one currently logged in via Supabase
//   - Switching accounts: save current session, restore the target
//     session's tokens in Supabase, refresh providers
//   - Adding an account: sign in with the new credentials, save the
//     session, keep the old session intact
//   - Removing an account: delete the stored session (does NOT sign out
//     the user from Supabase unless it's the active account)
//
// Security:
//   - All tokens stored in flutter_secure_storage (Keychain on iOS,
//     EncryptedSharedPreferences on Android, WebCrypto on web)
//   - No tokens in plaintext anywhere
//   - Switching does NOT require re-entering credentials (the refresh
//     token is used to restore the session)
//   - If a refresh token expires, the user is prompted to re-login

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Maximum number of accounts that can be stored.
const int kMaxAccounts = 5;

/// Storage key for the list of accounts.
const String _kAccountsKey = 'kinrel_multi_accounts';

/// Storage key for the active account's userId.
const String _kActiveAccountKey = 'kinrel_active_account';

/// Represents a stored account session.
class StoredAccount {
  final String userId;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String accessToken;
  final String refreshToken;
  final String? preferredLanguage;
  final DateTime storedAt;

  StoredAccount({
    required this.userId,
    required this.email,
    this.displayName,
    this.avatarUrl,
    required this.accessToken,
    required this.refreshToken,
    this.preferredLanguage,
    required this.storedAt,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'preferredLanguage': preferredLanguage,
    'storedAt': storedAt.toIso8601String(),
  };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
    userId: json['userId'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    preferredLanguage: json['preferredLanguage'] as String?,
    storedAt: DateTime.parse(json['storedAt'] as String),
  );
}

/// Multi-account manager service.
class MultiAccountService {
  static final MultiAccountService _instance = MultiAccountService._();
  static MultiAccountService get instance => _instance;
  MultiAccountService._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Get all stored accounts.
  Future<List<StoredAccount>> getAccounts() async {
    try {
      final raw = await _storage.read(key: _kAccountsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = json.decode(raw) as List;
      return list
          .map((e) => StoredAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ MultiAccount: failed to read accounts: $e');
      return [];
    }
  }

  /// Get the active account's userId.
  Future<String?> getActiveUserId() async {
    try {
      return await _storage.read(key: _kActiveAccountKey);
    } catch (_) {
      return null;
    }
  }

  /// Save the current Supabase session as a stored account.
  /// Called after sign-in or when the user explicitly adds an account.
  Future<void> saveCurrentSession({
    String? displayName,
    String? avatarUrl,
    String? preferredLanguage,
  }) async {
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      final user = client.auth.currentUser;
      if (session == null || user == null) return;

      final account = StoredAccount(
        userId: user.id,
        email: user.email ?? '',
        displayName: displayName ?? user.userMetadata?['display_name'] as String?,
        avatarUrl: avatarUrl ?? user.userMetadata?['avatar_url'] as String?,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        preferredLanguage: preferredLanguage,
        storedAt: DateTime.now(),
      );

      final accounts = await getAccounts();
      // Remove any existing entry for this userId
      accounts.removeWhere((a) => a.userId == account.userId);
      accounts.add(account);

      // Enforce max accounts (remove oldest)
      while (accounts.length > kMaxAccounts) {
        accounts.removeAt(0);
      }

      await _storage.write(key: _kAccountsKey, value: json.encode(accounts));
      await _storage.write(key: _kActiveAccountKey, value: account.userId);
      debugPrint('✅ MultiAccount: saved session for ${account.email}');
    } catch (e) {
      debugPrint('⚠️ MultiAccount: failed to save session: $e');
    }
  }

  /// Switch to a different stored account.
  /// Restores the target account's session in Supabase.
  /// Returns true on success, false on failure (e.g., expired refresh token).
  /// The caller is responsible for invalidating Riverpod providers after
  /// a successful switch (to avoid circular imports).
  Future<bool> switchToAccount(String userId) async {
    try {
      final accounts = await getAccounts();
      final target = accounts.where((a) => a.userId == userId).firstOrNull;
      if (target == null) {
        debugPrint('⚠️ MultiAccount: account not found: $userId');
        return false;
      }

      // Save current session before switching (if there is one)
      final client = Supabase.instance.client;
      final currentSession = client.auth.currentSession;
      if (currentSession != null) {
        await saveCurrentSession();
      }

      // Restore the target session using the refresh token
      final response = await client.auth.setSession(
        accessToken: target.accessToken,
        refreshToken: target.refreshToken,
      );

      if (response.session == null) {
        debugPrint('⚠️ MultiAccount: failed to restore session — token may be expired');
        return false;
      }

      // Update the stored tokens (they may have been refreshed)
      final updatedAccount = StoredAccount(
        userId: target.userId,
        email: target.email,
        displayName: target.displayName,
        avatarUrl: target.avatarUrl,
        accessToken: response.session!.accessToken,
        refreshToken: response.session!.refreshToken ?? target.refreshToken,
        preferredLanguage: target.preferredLanguage,
        storedAt: DateTime.now(),
      );

      accounts.removeWhere((a) => a.userId == userId);
      accounts.add(updatedAccount);
      await _storage.write(key: _kAccountsKey, value: json.encode(accounts));
      await _storage.write(key: _kActiveAccountKey, value: userId);

      // Provider invalidation is handled by the caller (AccountSwitcherSheet)
      // to avoid circular import with supabase_service.dart.

      debugPrint('✅ MultiAccount: switched to ${target.email}');
      return true;
    } catch (e) {
      debugPrint('⚠️ MultiAccount: switch failed: $e');
      return false;
    }
  }

  /// Remove a stored account (does NOT sign out if it's the active account).
  /// If the removed account is the active one, the user will need to sign in
  /// again or switch to another account.
  Future<void> removeAccount(String userId) async {
    try {
      final accounts = await getAccounts();
      accounts.removeWhere((a) => a.userId == userId);
      await _storage.write(key: _kAccountsKey, value: json.encode(accounts));

      // If the removed account was the active one, clear the active marker
      final activeId = await getActiveUserId();
      if (activeId == userId) {
        await _storage.delete(key: _kActiveAccountKey);
      }

      debugPrint('✅ MultiAccount: removed account $userId');
    } catch (e) {
      debugPrint('⚠️ MultiAccount: failed to remove account: $e');
    }
  }

  /// Check if the user has multiple accounts stored.
  Future<bool> hasMultipleAccounts() async {
    final accounts = await getAccounts();
    return accounts.length > 1;
  }

  /// Clear all stored accounts (used on full sign-out).
  Future<void> clearAll() async {
    await _storage.delete(key: _kAccountsKey);
    await _storage.delete(key: _kActiveAccountKey);
  }
}
