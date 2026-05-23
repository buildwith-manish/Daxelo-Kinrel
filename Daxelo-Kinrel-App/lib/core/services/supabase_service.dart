import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../config/app_config.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// Supabase client provider
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Whether Supabase is initialized and ready
final isSupabaseReadyProvider = Provider<bool>((ref) {
  try {
    Supabase.instance.client;
    return AppConfig.isSupabaseConfigured;
  } catch (_) {
    return false;
  }
});

/// Supabase initialization
Future<bool> initSupabase() async {
  if (!AppConfig.isSupabaseConfigured) {
    _log.w('⚠️ Supabase anon key is missing! Auth features will not work.');
    _log.w('   Add your SUPABASE_ANON_KEY to flutter_app/.env file');
    _log.w('   Get it from: https://app.supabase.com/project/vxnyjhvcipgqeowdgfah/settings/api');
    return false;
  }

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      debug: false,
    );
    _log.i('✅ Supabase initialized successfully');
    return true;
  } catch (e) {
    _log.e('❌ Supabase initialization failed: $e');
    return false;
  }
}

/// Auth state provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  try {
    return Supabase.instance.client.auth.onAuthStateChange;
  } catch (e) {
    _log.w('Auth state stream unavailable: $e');
    return const Stream.empty();
  }
});

/// Current user provider
final currentUserProvider = Provider<User?>((ref) {
  try {
    final authState = ref.watch(authStateProvider);
    return authState.value?.session?.user;
  } catch (e) {
    return null;
  }
});

/// Is authenticated provider
final isAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});

/// Auth service
class AuthService {
  final SupabaseClient _client;

  AuthService(this._client);

  /// Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    if (!AppConfig.isSupabaseConfigured) {
      throw AuthException(
        'Supabase is not configured. Please add your SUPABASE_ANON_KEY to the .env file. '
        'Get it from your Supabase project settings.',
      );
    }
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
    return response;
  }

  /// Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    if (!AppConfig.isSupabaseConfigured) {
      throw AuthException(
        'Supabase is not configured. Please add your SUPABASE_ANON_KEY to the .env file. '
        'Get it from your Supabase project settings.',
      );
    }
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    if (!AppConfig.isSupabaseConfigured) return;
    await _client.auth.signOut();
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    if (!AppConfig.isSupabaseConfigured) {
      throw AuthException('Supabase is not configured.');
    }
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Update password
  Future<void> updatePassword(String newPassword) async {
    if (!AppConfig.isSupabaseConfigured) {
      throw AuthException('Supabase is not configured.');
    }
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Get current session
  Session? get session => _client.auth.currentSession;

  /// Get current user
  User? get user => _client.auth.currentUser;

  /// Refresh session
  Future<Session?> refreshSession() async {
    if (!AppConfig.isSupabaseConfigured) return null;
    final response = await _client.auth.refreshSession();
    return response.session;
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  try {
    final client = ref.watch(supabaseProvider);
    return AuthService(client);
  } catch (e) {
    _log.w('AuthService creation failed: $e');
    // Return a dummy service that will throw on auth operations
    rethrow;
  }
});
