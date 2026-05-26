import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

// Hardcoded fallback credentials (anon key is safe for client-side use)
const String _hardcodedSupabaseUrl = 'https://promxswvsnvilplmrtsj.supabase.co';
const String _hardcodedSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY';

bool _supabaseInitialized = false;
bool get isSupabaseInitialized => _supabaseInitialized;

String _resolveSupabaseUrl() {
  final appConfigUrl = AppConfig.supabaseUrl;
  if (appConfigUrl.isNotEmpty && appConfigUrl.startsWith('https://')) return appConfigUrl;
  return _hardcodedSupabaseUrl;
}

String _resolveSupabaseAnonKey() {
  final appConfigKey = AppConfig.supabaseAnonKey;
  if (appConfigKey.isNotEmpty && appConfigKey.startsWith('eyJ')) return appConfigKey;
  return _hardcodedSupabaseAnonKey;
}

/// Pre-warm the Supabase server by making a lightweight HTTP request.
/// Supabase free tier pauses after inactivity — this wakes the server up.
/// Returns true if the server is reachable.
Future<bool> _warmUpSupabase(String url) async {
  try {
    _log.i('🔧 Warming up Supabase server...');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 45);
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
  _log.i('   Anon Key: ${anonKey.isNotEmpty ? "SET (length: ${anonKey.length})" : "EMPTY"}');

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

  // Pre-warm the Supabase server (critical for free tier cold starts)
  await _warmUpSupabase(url);

  // Retry Supabase initialization up to 3 times for cold starts
  int attempts = 0;
  const maxAttempts = 3;

  while (attempts < maxAttempts) {
    attempts++;
    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _supabaseInitialized = true;
      _log.i('✅ Supabase initialized successfully (attempt $attempts)');
      return true;
    } catch (e) {
      _log.e('❌ Supabase initialization failed (attempt $attempts/$maxAttempts): $e');
      if (attempts < maxAttempts) {
        final delay = Duration(seconds: attempts * 5);
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
Future<T> withRetry<T>(Future<T> Function() fn, {
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
      final isNetworkError = errStr.contains('SocketException') ||
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

      _log.w('⚠️ $operationName attempt $attempt failed (network error), retrying in ${delay.inSeconds}s...');
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
  final SupabaseClient? _client;
  AuthService(this._client);
  bool get isAvailable => _client != null;

  /// Sign up with retry for cold starts.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    if (_client == null) {
      throw AuthException(
        'Authentication service is not available. Please restart the app and try again.',
      );
    }
    return withRetry(
      () => _client!.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      ),
      operationName: 'Sign up',
    );
  }

  /// Sign in with retry for cold starts.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    if (_client == null) {
      throw AuthException(
        'Authentication service is not available. Please restart the app and try again.',
      );
    }
    return withRetry(
      () => _client!.auth.signInWithPassword(
        email: email,
        password: password,
      ),
      operationName: 'Sign in',
    );
  }

  Future<void> signOut() async {
    if (_client == null) return;
    await _client!.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    if (_client == null) {
      throw AuthException('Authentication service is not available.');
    }
    await withRetry(
      () => _client!.auth.resetPasswordForEmail(email),
      operationName: 'Reset password',
    );
  }

  Future<void> updatePassword(String newPassword) async {
    if (_client == null) {
      throw AuthException('Authentication service is not available.');
    }
    await _client!.auth.updateUser(UserAttributes(password: newPassword));
  }

  Session? get session => _client?.auth.currentSession;
  User? get user => _client?.auth.currentUser;

  Future<Session?> refreshSession() async {
    if (_client == null) return null;
    final response = await _client!.auth.refreshSession();
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
