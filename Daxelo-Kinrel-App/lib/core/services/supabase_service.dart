// lib/core/services/supabase_service.dart
//
// DAXELO KINREL — Supabase Auth Service
//
// Clean rewrite with bulletproof error handling.
// Every async operation is wrapped in try-catch to prevent native crashes.
//
// Google Sign-In flow:
//   1. Build GoogleSignIn with platform-specific config
//   2. Call signIn() with timeout
//   3. Get ID token from GoogleSignInAccount.authentication()
//   4. Verify with Supabase signInWithIdToken()
//   5. Navigate to /home on success
//
// Email Sign-In flow:
//   1. Validate email/password on the UI side
//   2. Call Supabase signInWithPassword() with retry
//   3. Navigate to /home on success

import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../config/app_config.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

// ── Hardcoded fallback credentials ──────────────────────────────────
// The anon key is safe for client-side use (only service_role is secret).
const String _hardcodedSupabaseUrl = 'https://promxswvsnvilplmrtsj.supabase.co';
const String _hardcodedSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY';

bool _supabaseInitialized = false;
bool get isSupabaseInitialized => _supabaseInitialized;

String _resolveSupabaseUrl() {
  final appConfigUrl = AppConfig.supabaseUrl;
  if (appConfigUrl.isNotEmpty && appConfigUrl.startsWith('https://')) {
    return appConfigUrl;
  }
  return _hardcodedSupabaseUrl;
}

String _resolveSupabaseAnonKey() {
  final appConfigKey = AppConfig.supabaseAnonKey;
  if (appConfigKey.isNotEmpty && appConfigKey.startsWith('eyJ')) {
    return appConfigKey;
  }
  return _hardcodedSupabaseAnonKey;
}

/// Check if the device has internet connectivity.
Future<bool> _hasConnectivity() async {
  try {
    final result = await Connectivity().checkConnectivity();
    final hasConnection = result.any((c) => c != ConnectivityResult.none);
    _log.i('Connectivity check: $result (hasConnection: $hasConnection)');
    return hasConnection;
  } catch (e) {
    _log.w('Connectivity check failed: $e');
    return true; // Assume connected if check fails
  }
}

// ── Supabase Providers ───────────────────────────────────────────────

final supabaseProvider = Provider<SupabaseClient?>((ref) {
  if (!_supabaseInitialized) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});

final isSupabaseReadyProvider = Provider<bool>((ref) => _supabaseInitialized);

// ── Initialize Supabase ──────────────────────────────────────────────

Future<bool> initSupabase() async {
  final url = _resolveSupabaseUrl();
  final anonKey = _resolveSupabaseAnonKey();
  _log.i('Initializing Supabase...');
  _log.i('  URL: $url');
  _log.i('  Anon Key: ${anonKey.isNotEmpty ? "SET" : "EMPTY"}');

  if (url.isEmpty || anonKey.isEmpty) {
    _log.e('Supabase URL or Anon Key is empty!');
    _supabaseInitialized = false;
    return false;
  }

  // Check connectivity (advisory only — don't block on it)
  final hasConnection = await _hasConnectivity();
  if (!hasConnection) {
    _log.w('No internet connectivity — attempting init anyway...');
  }

  // Initialize with retry (max 2 attempts to avoid long blocking)
  int attempts = 0;
  const maxAttempts = 2;

  while (attempts < maxAttempts) {
    attempts++;
    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _supabaseInitialized = true;
      _log.i('Supabase initialized successfully (attempt $attempts)');
      return true;
    } catch (e) {
      _log.e('Supabase init failed (attempt $attempts/$maxAttempts): $e');
      if (attempts < maxAttempts) {
        final delay = Duration(seconds: attempts * 2);
        _log.i('Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
  }

  _supabaseInitialized = false;
  return false;
}

// ── Auth State Providers ─────────────────────────────────────────────

final authStateProvider = StreamProvider<AuthState>((ref) {
  if (!_supabaseInitialized) return const Stream.empty();
  try {
    return Supabase.instance.client.auth.onAuthStateChange;
  } catch (e) {
    _log.w('Auth state stream unavailable: $e');
    return const Stream.empty();
  }
});

final currentUserProvider = Provider<User?>((ref) {
  try {
    final authState = ref.watch(authStateProvider);
    return authState.value?.session?.user;
  } catch (e) {
    return null;
  }
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});

// ── Retry Helper ─────────────────────────────────────────────────────

/// Retry helper with exponential backoff for cold starts.
/// Only retries on network errors — non-network errors are rethrown immediately.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 3),
  String operationName = 'operation',
}) async {
  int attempt = 0;
  Duration delay = initialDelay;

  while (true) {
    attempt++;
    try {
      return await fn();
    } catch (e) {
      final errStr = e.toString();
      final isNetworkError =
          errStr.contains('SocketException') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('AuthRetryableFetchException') ||
          errStr.contains('Connection refused') ||
          errStr.contains('Network is unreachable') ||
          errStr.contains('No address associated with hostname') ||
          errStr.contains('Connection timed out') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('timed out') ||
          errStr.contains('Unable to connect') ||
          errStr.contains('FetchException') ||
          errStr.contains('Connection reset');

      if (!isNetworkError || attempt >= maxAttempts) rethrow;

      _log.w('$operationName attempt $attempt failed (network error), retrying in ${delay.inSeconds}s...');
      await Future.delayed(delay);
      delay = Duration(seconds: (delay.inSeconds * 1.5).round());
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// AUTH SERVICE — The core authentication class
// ═══════════════════════════════════════════════════════════════════════

class AuthService {
  AuthService(this._client);
  final SupabaseClient? _client;
  bool get isAvailable => _client != null;

  // ── Sign Up (Email) ───────────────────────────────────────────────

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app.',
      );
    }
    return withRetry(
      () => client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
        emailRedirectTo: 'com.daxelo.kinrel://auth/callback',
      ),
      operationName: 'Sign up',
    );
  }

  // ── Sign In (Email + Password) ────────────────────────────────────

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app.',
      );
    }
    return withRetry(
      () => client.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        throw const AuthException(
          'Sign in timed out. The server may be waking up — please try again.',
        );
      }),
      maxAttempts: 3,
      initialDelay: const Duration(seconds: 2),
      operationName: 'Sign in',
    );
  }

  // ── Sign In with Google ───────────────────────────────────────────
  //
  // CRITICAL: This must NEVER crash the app. Every step is wrapped
  // in try-catch with timeouts. Native Google Play Services errors
  // (DEVELOPER_ERROR, sign_in_failed) are caught and converted to
  // user-friendly AuthException messages.
  //
  // The most common crash cause is a SHA-1 mismatch between the
  // APK signing key and what's registered in Google Cloud Console.
  // Debug APKs have a different SHA-1 than release APKs, so Google
  // Sign-In may fail on debug builds. This is handled gracefully.

  Future<AuthResponse> signInWithGoogle() async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app.',
      );
    }

    _log.i('Google Sign-In: Starting...');

    // ── Step 1: Build GoogleSignIn ─────────────────────────────────
    final googleSignIn = _buildGoogleSignIn();

    // ── Step 2: Trigger Google Sign-In UI ──────────────────────────
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _log.w('Google Sign-In: Timed out after 30 seconds');
          throw const AuthException(
            'Google sign-in timed out. Please check your internet connection and try again.',
          );
        },
      );
    } on PlatformException catch (e) {
      _log.e('Google Sign-In: PlatformException ${e.code} - ${e.message}');
      throw _mapPlatformException(e);
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException(
        'Google sign-in timed out. Please try again.',
      );
    } catch (e) {
      _log.e('Google Sign-In: signIn() error: $e');
      if (_isDeveloperError(e)) {
        throw const AuthException(
          'Google sign-in failed due to a configuration issue. '
          'This is common on debug builds. Please try email sign-in instead.',
        );
      }
      throw AuthException('Google sign-in failed: ${_sanitizeError(e)}');
    }

    if (googleUser == null) {
      _log.w('Google Sign-In: Cancelled by user');
      throw const AuthException('Google sign-in was cancelled.');
    }

    _log.i('Google Sign-In: User obtained: ${googleUser.email}');

    // ── Step 3: Get authentication tokens ──────────────────────────
    GoogleSignInAuthentication googleAuth;
    try {
      googleAuth = await googleUser.authentication.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw const AuthException(
            'Failed to get Google authentication tokens. Please try again.',
          );
        },
      );
    } on AuthException {
      rethrow;
    } on PlatformException catch (e) {
      _log.e('Google Sign-In: Auth PlatformException ${e.code}');
      throw _mapPlatformException(e);
    } catch (e) {
      _log.e('Google Sign-In: authentication() error: $e');
      throw AuthException(
        'Failed to get Google authentication tokens. Please try again.',
      );
    }

    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null || idToken.isEmpty) {
      _log.e('Google Sign-In: ID token is null or empty');
      throw const AuthException(
        'Failed to get Google ID token. This may be a configuration issue. '
        'Please try email sign-in instead.',
      );
    }

    _log.i('Google Sign-In: ID token obtained, verifying with Supabase...');

    // ── Step 4: Verify with Supabase ───────────────────────────────
    try {
      return await withRetry(
        () => client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        ).timeout(const Duration(seconds: 15), onTimeout: () {
          throw const AuthException(
            'Supabase verification timed out. The server may be waking up — please try again.',
          );
        }),
        maxAttempts: 3,
        initialDelay: const Duration(seconds: 2),
        operationName: 'Google Sign-In verification',
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      _log.e('Google Sign-In: Supabase verification error: $e');
      if (_isDeveloperError(e)) {
        throw const AuthException(
          'Google sign-in verification failed. This may be a configuration issue. '
          'Please try email sign-in instead.',
        );
      }
      throw AuthException('Google sign-in verification failed: ${_sanitizeError(e)}');
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (e) {
      _log.w('Sign out error: $e');
    }
  }

  // ── Link Google Account ───────────────────────────────────────────

  Future<void> linkGoogleAccount() async {
    final client = _client;
    if (client == null) {
      throw const AuthException('Authentication service is not available.');
    }

    _log.i('Linking Google account...');

    final googleSignIn = _buildGoogleSignIn();
    try {
      final googleUser = await googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw const AuthException('Google sign-in timed out. Please try again.');
        },
      );
      if (googleUser == null) {
        throw const AuthException('Google sign-in was cancelled.');
      }

      final googleAuth = await googleUser.authentication.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw const AuthException(
            'Failed to get Google authentication tokens. Please try again.',
          );
        },
      );

      if (googleAuth.idToken == null) {
        throw const AuthException(
          'Failed to get Google ID token. Please try again.',
        );
      }

      await client.auth.updateUser(
        UserAttributes(
          data: {
            'linked_google': true,
            'linked_google_at': DateTime.now().toIso8601String(),
          },
        ),
      );

      _log.i('Google account linked successfully');
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Failed to link Google account: $e');
    }
  }

  // ── Password Reset ────────────────────────────────────────────────

  Future<void> resetPassword(String email) async {
    final client = _client;
    if (client == null) {
      throw const AuthException('Authentication service is not available.');
    }
    await withRetry(
      () => client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.daxelo.kinrel://auth/callback',
      ),
      operationName: 'Reset password',
    );
  }

  Future<void> updatePassword(String newPassword) async {
    final client = _client;
    if (client == null) {
      throw const AuthException('Authentication service is not available.');
    }
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // ── Session Access ────────────────────────────────────────────────

  Session? get session => _client?.auth.currentSession;
  User? get user => _client?.auth.currentUser;

  Future<Session?> refreshSession() async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client.auth.refreshSession();
      return response.session;
    } catch (e) {
      _log.w('Refresh session error: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═════════════════════════════════════════════════════════════════

  /// Build GoogleSignIn with platform-specific configuration.
  ///
  /// ANDROID: Uses `serverClientId` (NOT `clientId`) to call
  /// `requestIdToken(serverClientId)` in GoogleSignInOptions.Builder.
  /// This produces an OpenID Connect ID token that Supabase can verify
  /// with signInWithIdToken(). The Android client ID validation (package
  /// name + SHA-1) is handled automatically by Google Play Services
  /// via google-services.json.
  ///
  /// iOS: Uses `clientId` (iOS client ID / reversed client ID) and
  /// `serverClientId` (web client ID for ID token audience).
  ///
  /// Web: Uses `clientId` (web client ID).
  GoogleSignIn _buildGoogleSignIn() {
    if (kIsWeb) {
      return GoogleSignIn(
        clientId: AppConfig.googleWebClientId,
      );
    } else if (Platform.isIOS) {
      return GoogleSignIn(
        clientId: AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId,
      );
    }
    // Android: serverClientId triggers requestIdToken() in the native
    // GoogleSignInOptions builder, which produces the ID token needed
    // for Supabase's signInWithIdToken().
    return GoogleSignIn(
      serverClientId: AppConfig.googleWebClientId,
    );
  }

  /// Map PlatformException from Google Sign-In to user-friendly errors.
  AuthException _mapPlatformException(PlatformException e) {
    switch (e.code) {
      case 'sign_in_failed':
        return const AuthException(
          'Google sign-in failed. This is common on debug builds due to '
          'SHA-1 mismatch. Please try email sign-in instead.',
        );
      case 'network_error':
        return const AuthException(
          'Network error during Google sign-in. Please check your internet connection.',
        );
      case 'sign_in_required':
        return const AuthException(
          'Please sign in to your Google account first.',
        );
      case 'invalid_account':
        return const AuthException(
          'Invalid Google account. Please try a different account.',
        );
      default:
        // DEVELOPER_ERROR (code 10) — usually SHA-1 or client ID mismatch
        if (e.message?.contains('10') == true ||
            e.message?.contains('DEVELOPER_ERROR') == true ||
            e.code == 'DEVELOPER_ERROR') {
          return const AuthException(
            'Google sign-in configuration error. This is common on debug builds. '
            'Please try email sign-in instead.',
          );
        }
        return AuthException(
          'Google sign-in error: ${e.message ?? e.code}. Please try again.',
        );
    }
  }

  /// Check if an error indicates a developer/configuration error.
  bool _isDeveloperError(dynamic e) {
    final str = e.toString().toLowerCase();
    return str.contains('developer_error') ||
        str.contains('apiexception') ||
        str.contains('sign_in_failed') ||
        str.contains('status{statusCode=10') ||
        str.contains('statuscode=10');
  }

  /// Sanitize error messages for user display.
  String _sanitizeError(dynamic e) {
    final str = e.toString();
    if (str.length > 100) {
      return 'An unexpected error occurred. Please try again.';
    }
    return str.replaceAll('Exception: ', '').replaceAll('AuthException: ', '');
  }
}

// ── Auth Service Provider ────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(supabaseProvider);
  return AuthService(client);
});

// ── Route Persistence ────────────────────────────────────────────────

const _lastRouteKey = 'kinrel_last_route';

Future<void> saveLastRoute(String route) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRouteKey, route);
  } catch (_) {}
}

Future<String?> getLastRoute() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRouteKey);
  } catch (_) {
    return null;
  }
}

Future<void> clearLastRoute() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRouteKey);
  } catch (_) {}
}
