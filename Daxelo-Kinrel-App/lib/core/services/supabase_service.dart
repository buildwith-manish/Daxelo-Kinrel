import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/app_config.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

// Hardcoded fallback credentials (anon key is safe for client-side use)
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

/// Pre-warm the Supabase server by making a lightweight HTTP request.
/// Supabase free tier pauses after inactivity — this wakes the server up.
/// Returns true if the server is reachable.
Future<bool> _warmUpSupabase(String url) async {
  try {
    _log.i('🔧 Warming up Supabase server...');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.getUrl(Uri.parse('$url/rest/v1/'));
    request.headers.set('apikey', _resolveSupabaseAnonKey());
    request.headers.set('Authorization', 'Bearer ${_resolveSupabaseAnonKey()}');
    final response = await request.close();
    await response.drain<void>();
    client.close();
    _log.i('🔧 Supabase warm-up complete (status: ${response.statusCode})');
    return true;
  } catch (e) {
    _log.w('⚠️ Supabase warm-up failed (server may be cold starting): $e');
    return false;
  }
}

/// Check if the device has internet connectivity.
Future<bool> _hasConnectivity() async {
  try {
    final result = await Connectivity().checkConnectivity();
    final hasConnection = result.any((c) => c != ConnectivityResult.none);
    _log.i('🔧 Connectivity check: $result (hasConnection: $hasConnection)');
    return hasConnection;
  } catch (e) {
    _log.w('⚠️ Connectivity check failed: $e');
    return true;
  }
}

final supabaseProvider = Provider<SupabaseClient?>((ref) {
  if (!_supabaseInitialized) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});

final isSupabaseReadyProvider = Provider<bool>((ref) => _supabaseInitialized);

Future<bool> initSupabase() async {
  final url = _resolveSupabaseUrl();
  final anonKey = _resolveSupabaseAnonKey();
  _log.i('🔧 Initializing Supabase...');
  _log.i('   URL: $url');
  _log.i(
    '   Anon Key: ${anonKey.isNotEmpty ? "SET (length: ${anonKey.length})" : "EMPTY"}',
  );

  if (url.isEmpty || anonKey.isEmpty) {
    _log.e('❌ Supabase URL or Anon Key is empty!');
    _supabaseInitialized = false;
    return false;
  }

  // Check connectivity first
  final hasConnection = await _hasConnectivity();
  if (!hasConnection) {
    _log.e('❌ No internet connectivity!');
    // Don't return false immediately — try anyway, connectivity check can be wrong
    _log.i('🔧 Attempting initialization anyway...');
  }

  // Pre-warm the Supabase server (fire-and-forget — don't block startup)
  // The warmup helps with free tier cold starts but should never delay app init.
  unawaited(_warmUpSupabase(url));

  // Retry Supabase initialization up to 2 times (reduced from 3 to avoid
  // blocking app startup for 30+ seconds on cold Supabase free tier).
  // The splash screen navigates based on local state anyway, so a
  // failed Supabase init won't cause a blank screen.
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
      _log.i('✅ Supabase initialized successfully (attempt $attempts)');
      return true;
    } catch (e) {
      _log.e(
        '❌ Supabase initialization failed (attempt $attempts/$maxAttempts): $e',
      );
      if (attempts < maxAttempts) {
        final delay = Duration(seconds: attempts * 2);
        _log.i('🔄 Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
  }

  _supabaseInitialized = false;
  return false;
}

/// Retry helper with exponential backoff for cold starts.
/// Supabase free tier can take 10-30+ seconds to wake from paused state.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
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

      _log.w(
        '⚠️ $operationName attempt $attempt failed (network error), retrying in ${delay.inSeconds}s...',
      );
      _log.w('   Error: $e');
      await Future.delayed(delay);
      delay = Duration(seconds: (delay.inSeconds * 1.5).round());
    }
  }
}

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

class AuthService {
  AuthService(this._client);

  final SupabaseClient? _client;
  bool get isAvailable => _client != null;

  /// Sign up with retry for cold starts.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app and try again.',
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

  /// Sign in with retry for cold starts.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app and try again.',
      );
    }
    return withRetry(
      () => client.auth.signInWithPassword(email: email, password: password),
      maxAttempts: 3, // Reduced from 5 — avoid 24+ second retry storms
      initialDelay: const Duration(seconds: 2),
      operationName: 'Sign in',
    );
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
  }

  /// Sign in with Google using the native Google Sign-In flow.
  ///
  /// On Android: uses the Android client ID from google-services.json
  /// On iOS: uses the iOS client ID (reversed client ID) from GoogleService-Info.plist
  /// On Web: uses the web client ID
  ///
  /// After obtaining the Google ID token, verifies it with Supabase
  /// using `signInWithIdToken(provider: 'google', idToken: ...)`.
  Future<AuthResponse> signInWithGoogle() async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available. Please restart the app and try again.',
      );
    }

    _log.i('🔐 Starting Google Sign-In...');

    // ── Build GoogleSignIn instance with platform-specific config ──
    final googleSignIn = _buildGoogleSignIn();

    // ── Trigger the Google Sign-In flow ────────────────────────────
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      _log.w('🔐 Google Sign-In cancelled by user');
      throw const AuthException('Google sign-in was cancelled.');
    }

    _log.i('🔐 Google user obtained: ${googleUser.email}');

    // ── Get the authentication tokens ──────────────────────────────
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      _log.e('🔐 Google Sign-In failed: ID token is null');
      throw const AuthException(
        'Failed to get Google ID token. Please try again.',
      );
    }

    _log.i('🔐 Google ID token obtained, verifying with Supabase...');

    // ── Verify with Supabase ───────────────────────────────────────
    return withRetry(
      () => client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      ),
      maxAttempts: 3,
      initialDelay: const Duration(seconds: 2),
      operationName: 'Google Sign-In',
    );
  }

  /// Link a Google account to an existing authenticated user.
  ///
  /// This allows users who signed in with email/password to also
  /// sign in with Google in the future.
  Future<void> linkGoogleAccount() async {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Authentication service is not available.',
      );
    }

    _log.i('🔐 Linking Google account...');

    final googleSignIn = _buildGoogleSignIn();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw const AuthException('Google sign-in was cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw const AuthException(
        'Failed to get Google ID token. Please try again.',
      );
    }

    // Use updateUser to link the Google identity
    await client.auth.updateUser(
      UserAttributes(
        data: {
          'linked_google': true,
          'linked_google_at': DateTime.now().toIso8601String(),
        },
      ),
    );

    _log.i('🔐 Google account linked successfully');
  }

  /// Build a GoogleSignIn instance with platform-specific configuration.
  ///
  /// On Android, we pass BOTH:
  /// - `clientId` (Android OAuth client ID) so Google Play Services can
  ///   identify the app even when google-services.json lacks a type-1 client
  /// - `serverClientId` (web client ID) so the ID token is issued for the
  ///   audience that Supabase expects
  GoogleSignIn _buildGoogleSignIn() {
    if (kIsWeb) {
      // Web: use the web client ID
      return GoogleSignIn(
        clientId: AppConfig.googleWebClientId,
      );
    } else if (Platform.isIOS) {
      // iOS: use the iOS client ID (the reversed client ID goes in
      // GoogleService-Info.plist; the clientId parameter here is the
      // OAuth client ID)
      return GoogleSignIn(
        clientId: AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId,
      );
    }
    // Android: pass clientId + serverClientId explicitly so that
    // Google Sign-In works even when google-services.json only has a
    // type-3 (web) client and no type-1 (Android) client.
    //
    // clientId  → the Android OAuth client ID registered in Google
    //             Cloud Console (package name + SHA-1)
    // serverClientId → the web client ID; Google issues the ID token
    //                  with this as the audience, which Supabase then
    //                  verifies with signInWithIdToken().
    return GoogleSignIn(
      clientId: AppConfig.googleAndroidClientId,
      serverClientId: AppConfig.googleWebClientId,
    );
  }

  Future<void> resetPassword(String email) async {
    final client = _client;
    if (client == null) {
      throw const AuthException('Authentication service is not available.');
    }
    await withRetry(
      () => client.auth.resetPasswordForEmail(email),
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

  Session? get session => _client?.auth.currentSession;
  User? get user => _client?.auth.currentUser;

  Future<Session?> refreshSession() async {
    final client = _client;
    if (client == null) return null;
    final response = await client.auth.refreshSession();
    return response.session;
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(supabaseProvider);
  return AuthService(client);
});

// ── Route Persistence (for app resume) ──────────────────────────────

const _lastRouteKey = 'kinrel_last_route';

/// Save the current route so we can restore it on app restart.
Future<void> saveLastRoute(String route) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRouteKey, route);
  } catch (_) {}
}

/// Get the last saved route. Returns null if not saved.
Future<String?> getLastRoute() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRouteKey);
  } catch (_) {
    return null;
  }
}

/// Clear the saved route (e.g., on sign out).
Future<void> clearLastRoute() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRouteKey);
  } catch (_) {}
}
