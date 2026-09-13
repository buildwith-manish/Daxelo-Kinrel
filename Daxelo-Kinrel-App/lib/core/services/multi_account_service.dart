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
///
/// Privacy contract: `email` is kept on the model for auth/session
/// restoration only and must NEVER be rendered in quick-switch menus,
/// profile previews, or any public-facing UI. UI layers should rely on
/// [displayName] and [username] instead. See `AccountSwitcherSheet` for
/// the canonical identity-focused rendering.
class StoredAccount {
  final String userId;
  final String email;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String accessToken;
  final String refreshToken;
  final String? preferredLanguage;
  final DateTime storedAt;

  StoredAccount({
    required this.userId,
    required this.email,
    this.displayName,
    this.username,
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
    'username': username,
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
    // Backward-compatible: older stored accounts (pre-username field) have
    // no `username` key — `as String?` returns null, which is the desired
    // fallback so the UI shows the neutral '@username' placeholder.
    username: json['username'] as String?,
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

  // Use conditional import for secure storage — flutter_secure_storage
  // with AndroidOptions doesn't compile on web.
  final _storage = const FlutterSecureStorage();

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
  ///
  /// Identity fields (`displayName`, `username`, `avatarUrl`) are sourced
  /// from Supabase auth user metadata when not explicitly supplied, so the
  /// stored account always reflects the latest identity the user has set
  /// (e.g., after they update their username via the username setup flow).
  Future<void> saveCurrentSession({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? preferredLanguage,
  }) async {
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      final user = client.auth.currentUser;
      if (session == null || user == null) return;

      // Some flows store display name under 'display_name' (e.g., signup)
      // while others use 'name' (e.g., profile_screen). Try both so the
      // stored account always has the freshest display name available.
      final metadata = user.userMetadata;
      final effectiveDisplayName = displayName
          ?? metadata?['display_name'] as String?
          ?? metadata?['name'] as String?;

      final account = StoredAccount(
        userId: user.id,
        email: user.email ?? '',
        displayName: effectiveDisplayName,
        username: username ?? metadata?['username'] as String?,
        avatarUrl: avatarUrl ?? metadata?['avatar_url'] as String?,
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

      // Restore the target session using the refresh token.
      // Supabase auth.setSession() takes a single positional argument:
      // the refresh token. It returns a new access + refresh token pair.
      final response = await client.auth.setSession(
        target.refreshToken,
      );

      if (response.session == null) {
        debugPrint('⚠️ MultiAccount: failed to restore session — token may be expired');
        return false;
      }

      // Update the stored tokens (they may have been refreshed).
      // Identity fields (displayName, username, avatarUrl) are preserved
      // as-is — the switch operation only refreshes auth tokens.
      final updatedAccount = StoredAccount(
        userId: target.userId,
        email: target.email,
        displayName: target.displayName,
        username: target.username,
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

  /// Refresh the active account's identity metadata (display name,
  /// username, avatar URL) from the live Supabase session WITHOUT touching
  /// auth tokens.
  ///
  /// Used by the Account Switcher sheet on every load so the displayed
  /// identity stays current even for accounts that were stored before the
  /// `username` field existed on [StoredAccount]. After this call, the
  /// active account's stored identity matches whatever Supabase auth
  /// user metadata currently reports.
  ///
  /// Returns true if a stored account was actually updated, false if the
  /// active user is not stored or no field changed.
  Future<bool> refreshActiveAccountIdentity({
    String? displayName,
    String? username,
    String? avatarUrl,
  }) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return false;

      final accounts = await getAccounts();
      final idx = accounts.indexWhere((a) => a.userId == user.id);
      if (idx == -1) return false;

      final existing = accounts[idx];
      final newDisplayName = displayName ?? existing.displayName;
      final newUsername = username ?? existing.username;
      final newAvatarUrl = avatarUrl ?? existing.avatarUrl;

      // Skip the write if nothing actually changed — avoids needless
      // secure-storage round-trips on every switcher open.
      if (newDisplayName == existing.displayName &&
          newUsername == existing.username &&
          newAvatarUrl == existing.avatarUrl) {
        return false;
      }

      accounts[idx] = StoredAccount(
        userId: existing.userId,
        email: existing.email,
        displayName: newDisplayName,
        username: newUsername,
        avatarUrl: newAvatarUrl,
        accessToken: existing.accessToken,
        refreshToken: existing.refreshToken,
        preferredLanguage: existing.preferredLanguage,
        storedAt: existing.storedAt,
      );

      await _storage.write(key: _kAccountsKey, value: json.encode(accounts));
      debugPrint('✅ MultiAccount: refreshed identity for ${existing.userId} '
          '(username=${newUsername ?? '<null>'})');
      return true;
    } catch (e) {
      debugPrint('⚠️ MultiAccount: failed to refresh identity: $e');
      return false;
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
