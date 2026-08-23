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
import 'multi_account_service.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

// ── Credentials loaded from AppConfig (which reads .env) ───────────
// No hardcoded credentials in source code. The .env file is gitignored
// and must be present in the build environment. If .env is missing,
// the app shows a config error instead of falling back to hardcoded keys.
bool _supabaseInitialized = false;
bool get isSupabaseInitialized => _supabaseInitialized;

/// Riverpod state provider for Supabase readiness.
/// Updated when Supabase initializes, so dependent providers auto-refresh.
final supabaseReadyStateProvider = StateProvider<bool>((ref) => false);

String _resolveSupabaseUrl() {
  return AppConfig.supabaseUrl;
}

String _resolveSupabaseAnonKey() {
  return AppConfig.supabaseAnonKey;
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
    return false; // Assume offline if the check itself throws
  }
}

// ── Supabase Providers ───────────────────────────────────────────────

final supabaseProvider = Provider<SupabaseClient?>((ref) {
  // Watch the state provider so this auto-refreshes when Supabase initializes.
  // Previously this was a plain Provider that cached null if read before init.
  final isReady = ref.watch(supabaseReadyStateProvider);
  if (!isReady) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});

final isSupabaseReadyProvider = Provider<bool>((ref) {
  return ref.watch(supabaseReadyStateProvider);
});

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
      // Note: supabaseReadyStateProvider will be updated by the caller
      // (we don't have a Ref here to update it directly)
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

/// Call after initSupabase() to update the Riverpod state provider.
/// This must be called from a context that has access to a ProviderContainer.
void notifySupabaseReady(ProviderContainer container) {
  container.read(supabaseReadyStateProvider.notifier).state = _supabaseInitialized;
}

/// Auto sign-in helper retained as a no-op for backward compatibility.
///
/// v2.2: All authentication is real. This function previously attempted
/// to silently sign in with debug credentials; it now always returns
/// `false`. Callers should rely on [AuthService.signIn] /
/// [AuthService.signInWithGoogle] for real authentication.
Future<bool> autoSignInForDebug(WidgetRef ref) async {
  return false;
}

// ── Auth State Providers ─────────────────────────────────────────────

/// v5.78 (AUTH FIX): authStateProvider now watches supabaseReadyStateProvider
/// so it is re-created when Supabase becomes ready. Previously, if this
/// provider was first read BEFORE Supabase finished initializing, it
/// returned Stream.empty() and Riverpod cached that empty stream forever
/// — causing currentUserProvider to always return null, which made the
/// graph screen show "Auth User ID: NULL" even for logged-in users.
final authStateProvider = StreamProvider<AuthState>((ref) {
  // Watch the ready state — this causes the provider to be re-created
  // when Supabase finishes initializing.
  final isReady = ref.watch(supabaseReadyStateProvider);
  if (!isReady) return const Stream.empty();
  try {
    return Supabase.instance.client.auth.onAuthStateChange;
  } catch (e) {
    _log.w('Auth state stream unavailable: $e');
    return const Stream.empty();
  }
});

/// v5.78 (AUTH FIX): currentUserProvider now also watches
/// supabaseReadyStateProvider so it re-evaluates when Supabase becomes
/// ready. Previously, it was computed once with auth.currentUser == null
/// (during the init race) and never recomputed because its only watched
/// dependency (authStateProvider) was stuck on Stream.empty().
final currentUserProvider = Provider<User?>((ref) {
  // Watch the ready state so this provider re-evaluates when Supabase
  // finishes initializing.
  ref.watch(supabaseReadyStateProvider);

  // Real session only — no mock user.
  try {
    final authState = ref.watch(authStateProvider);
    final user = authState.value?.session?.user;
    if (user != null) return user;
    // Also check Supabase directly (avoids Riverpod stream lag)
    if (_supabaseInitialized) {
      try {
        return Supabase.instance.client.auth.currentUser;
      } catch (_) {}
    }
  } catch (e) {
    // Fallback: check Supabase directly
    if (_supabaseInitialized) {
      try {
        return Supabase.instance.client.auth.currentUser;
      } catch (_) {}
    }
  }
  return null;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});

/// v2.2: Returns null in production (no mock user).
/// Retained as a no-op for backward compatibility with any screen that
/// still references it — those screens must be migrated to use
/// [currentUserProvider] instead.
final mockUserProvider = Provider<Map<String, dynamic>?>((ref) {
  return null;
});

// ── Retry Helper ─────────────────────────────────────────────────────

/// Retry helper with exponential backoff for cold starts.
/// Only retries on network errors — non-network errors are rethrown immediately.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 1,
  Duration initialDelay = const Duration(seconds: 1),
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
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw const AuthException(
          'Sign in timed out. The server may be waking up — please try again.',
        );
      }),
      maxAttempts: 1,
      initialDelay: const Duration(seconds: 1),
      operationName: 'Sign in',
    );
  }

  // ── Sign In (Identifier = email OR username + Password) ───────────
  //
  // This is the primary sign-in entry point for the Sign In screen.
  // It accepts either:
  //   - An email address (contains '@') → used directly with Supabase
  //     signInWithPassword().
  //   - A username (no '@') → resolved to the user's email via the
  //     `fn_get_email_by_identifier` Postgres RPC (SECURITY DEFINER,
  //     callable by anon). The resolved email is then used with
  //     signInWithPassword().
  //
  // PRIVACY: If the username doesn't exist OR the password is wrong,
  // Supabase returns the same generic "Invalid login credentials"
  // message, so username enumeration is no easier than password
  // brute-force.
  //
  // FALLBACK: If the RPC fails (e.g., the migration hasn't been applied
  // to this Supabase project, or a network blip), we attempt to sign
  // in with the raw identifier as the email — this succeeds for email
  // logins even when the RPC is unavailable, and fails cleanly for
  // username logins with the same "Invalid login credentials" message.
  Future<AuthResponse> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app.',
      );
    }

    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      throw const AuthException('Please enter your email or username.');
    }

    // ── Case 1: Identifier is an email → sign in directly ──────────
    if (trimmed.contains('@')) {
      return signIn(email: trimmed.toLowerCase(), password: password);
    }

    // ── Case 2: Identifier is a username → resolve to email ────────
    final username = trimmed.toLowerCase();

    String? resolvedEmail;
    try {
      // Call the SECURITY DEFINER RPC. This is callable by anon
      // (pre-auth) and returns just the email column for the matched
      // user row, or NULL if no match.
      final result = await client
          .rpc('fn_get_email_by_identifier', params: {'p_identifier': username})
          .timeout(const Duration(seconds: 8), onTimeout: () {
            throw const AuthException(
              'Sign in is taking too long. The server may be waking up — please try again.',
            );
          });

      if (result is String && result.isNotEmpty) {
        resolvedEmail = result;
      } else if (result is List && result.isNotEmpty) {
        // Some Supabase client versions return rows as a list of
        // maps even for scalar-returning functions. Handle both.
        final first = result.first;
        if (first is Map && first['email'] is String) {
          resolvedEmail = first['email'] as String;
        } else if (first is String) {
          resolvedEmail = first;
        }
      } else if (result is Map && result['email'] is String) {
        resolvedEmail = result['email'] as String;
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      _log.w('signInWithIdentifier: RPC lookup failed for "$username": $e — '
          'falling back to direct email sign-in');
      // Fallback: try the identifier as an email. This will succeed
      // for email logins (in case the user typed an email that
      // contains '@' but the validator let it through as a username
      // — shouldn't happen, but be safe), and fail cleanly with the
      // standard Supabase error for username logins.
      try {
        return signIn(email: username, password: password);
      } on AuthException {
        rethrow;
      } catch (_) {
        throw const AuthException(
          'Invalid login credentials. Please check your username and password.',
        );
      }
    }

    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      // Username not found — return the same generic error Supabase
      // returns for a wrong password, so we don't reveal that the
      // username doesn't exist.
      throw const AuthException('Invalid login credentials');
    }

    // ── Sign in with the resolved email ────────────────────────────
    return signIn(email: resolvedEmail, password: password);
  }

  // ── Sign In with Google ───────────────────────────────────────────
  //
  // CRITICAL: This must NEVER crash the app. Every step is wrapped
  // in try-catch with timeouts. Native Google Play Services errors
  // (DEVELOPER_ERROR, sign_in_failed) are caught and converted to
  // user-friendly AuthException messages.
  //
  // Returns null if the user cancelled the sign-in flow.
  // Throws AuthException on configuration or network errors.
  //
  // The most common crash cause is a SHA-1 mismatch between the
  // APK signing key and what's registered in Google Cloud Console.
  // Debug APKs have a different SHA-1 than release APKs, so Google
  // Sign-In may fail on debug builds. This is handled gracefully.

  Future<AuthResponse?> signInWithGoogle() async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app.',
      );
    }

    _log.i('Google Sign-In: Starting...');

    try {
      // ── Step 0: Clear stale Google Sign-In state ──────────────────
      // If a previous sign-in attempt left stale state in Google Play
      // Services, it can cause DEVELOPER_ERROR or sign_in_failed on
      // the next attempt. Calling signOut() first clears this state.
      try {
        final staleSignIn = _buildGoogleSignIn();
        await staleSignIn.signOut().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
      } catch (_) {
        // signOut() failure must not block the sign-in attempt
      }

      // ── Step 1: Build GoogleSignIn with scopes ───────────────────
      final googleSignIn = _buildGoogleSignIn();

      // ── Step 2: Trigger Google Sign-In UI (20s timeout) ──────────
      final googleUser = await googleSignIn.signIn().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          _log.w('Google Sign-In: Timed out after 20 seconds');
          return null;
        },
      );

      if (googleUser == null) {
        _log.w('Google Sign-In: Cancelled by user or timed out');
        return null; // user cancelled or timeout — do NOT throw
      }

      _log.i('Google Sign-In: User obtained: ${googleUser.email}');

      // ── Step 3: Get authentication tokens ────────────────────────
      final googleAuth = await googleUser.authentication.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw const AuthException(
            'Failed to get Google authentication tokens. Please try again.',
          );
        },
      );

      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || idToken.isEmpty) {
        _log.e('Google Sign-In: ID token is null or empty');
        throw const AuthException(
          'No ID token received. This may be a configuration issue. '
          'Please try email sign-in instead.',
        );
      }

      _log.i('Google Sign-In: ID token obtained, verifying with Supabase...');

      // ── Step 4: Verify with Supabase ─────────────────────────────
      return await withRetry(
        () => client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        ).timeout(const Duration(seconds: 10), onTimeout: () {
          throw const AuthException(
            'Supabase verification timed out. The server may be waking up — please try again.',
          );
        }),
        maxAttempts: 1,
        initialDelay: const Duration(seconds: 1),
        operationName: 'Google Sign-In verification',
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
      _log.e('Google Sign-In: error: $e');
      if (_isDeveloperError(e)) {
        throw const AuthException(
          'Google sign-in failed due to a configuration issue. '
          'This is common on debug builds. Please try email sign-in instead.',
        );
      }
      throw AuthException('Google sign-in failed: ${_sanitizeError(e)}');
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.auth.signOut();
      // Clear all stored multi-account sessions on full sign-out
      await MultiAccountService.instance.clearAll();
    } catch (e) {
      _log.w('Sign out error: $e');
    }
  }

  // ── Link Google Account ───────────────────────────────────────────
  //
  // Links the Google identity to the current Supabase user account
  // using signInWithIdToken(). After linking, the Google provider
  // appears in user.appMetadata['providers'] and the user can sign
  // in with Google on subsequent logins.
  //
  // This is the correct Supabase flow — calling updateUser() with
  // metadata alone does NOT create an identity link; it only sets
  // a flag in user_metadata which is not the same as a true provider link.
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

      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          'Failed to get Google ID token. This may be a configuration issue. '
          'Please try again or contact support.',
        );
      }

      // Link the Google identity to the current Supabase account.
      // This adds 'google' to user.appMetadata['providers'] and creates
      // an identity entry that allows future Google sign-in.
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      _log.i('🔐 Google account linked successfully — provider added to identities');
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on AuthException {
      rethrow;
    } catch (e) {
      _log.e('🔐 Link Google account error: $e');
      throw AuthException('Failed to link Google account: ${_sanitizeError(e)}');
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
        scopes: ['email', 'profile'],
      );
    } else if (Platform.isIOS) {
      return GoogleSignIn(
        clientId: AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId,
        scopes: ['email', 'profile'],
      );
    }
    // Android: serverClientId triggers requestIdToken() in the native
    // GoogleSignInOptions builder, which produces the ID token needed
    // for Supabase's signInWithIdToken().
    // scopes: ['email', 'profile'] ensures the ID token contains
    // the email and profile claims that Supabase requires.
    return GoogleSignIn(
      serverClientId: AppConfig.googleWebClientId,
      scopes: ['email', 'profile'],
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
    if (str.length > 200) {
      return '${str.substring(0, 200)}...';
    }
    return str.replaceAll('Exception: ', '').replaceAll('AuthException: ', '');
  }
}

// ── Auth Service Provider ────────────────────────────────────────────

/// Uses ref.watch so provider rebuilds when Supabase initializes.
/// Previously used ref.read which caused authServiceProvider to get
/// a null client if Supabase hadn't initialized yet at build time.
final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(supabaseProvider);
  return AuthService(client);
});

// ── 2FA Verification State ────────────────────────────────────────────
//
// Tracks whether the currently authenticated user needs to complete
// 2FA verification. This is critical for the GoRouter redirect logic:
//
// - Set to `true` after Supabase auth succeeds + backend confirms 2FA enabled
// - Set to `false` after successful 2FA TOTP verification
// - Reset to `false` on sign-out
//
// Without this, GoRouter would redirect authenticated users away from
// /2fa-verify to /home, completely bypassing the 2FA check.

final pending2FAProvider = StateProvider<bool>((ref) => false);

// Whether the user has completed 2FA verification in this session.
// Used by the router to decide whether to allow access to protected routes.
final twoFactorVerifiedProvider = StateProvider<bool>((ref) => false);

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
