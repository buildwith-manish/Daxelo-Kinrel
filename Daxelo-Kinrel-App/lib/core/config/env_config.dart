import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_config.dart';
import 'app_environment.dart';

/// Environment configuration with secure handling.
///
/// QA hardening 2026-09-20: this class previously DUPLICATED AppConfig's
/// entire resolution chain — including its own copies of the hardcoded
/// Supabase URL + publishable-key fallbacks. It now DELEGATES to
/// AppConfig wherever the two overlapped, so:
///
///   • there is exactly ONE place that resolves SUPABASE_URL /
///     SUPABASE_ANON_KEY (env-only, fails loudly, no fallback), and
///   • the two config classes can never drift apart again the way they
///     did during the 2026-09-19 key rotation.
///
/// Only the members unique to this class keep their own logic: the
/// environment-mode helpers and the AppEnvironmentConfig-aware
/// [apiBaseUrl] chain.
class EnvConfig {
  EnvConfig._();

  static bool get isProduction => const bool.fromEnvironment('dart.vm.product');
  static bool get isDebug => !isProduction;
  static bool get isProfile => const bool.fromEnvironment('dart.vm.profile');

  // ── Supabase — single source of truth in AppConfig ────────────────
  // Env-only resolution (dotenv → --dart-define → StateError). See
  // AppConfig for the rationale and the non-throwing peek API.
  static String get supabaseUrl => AppConfig.supabaseUrl;
  static String get supabaseAnonKey => AppConfig.supabaseAnonKey;

  /// Non-throwing diagnostic peeks (logging only — see AppConfig).
  static String? get peekSupabaseUrl => AppConfig.peekSupabaseUrl;
  static String? get peekSupabaseAnonKey => AppConfig.peekSupabaseAnonKey;

  static bool get isSupabaseConfigured => AppConfig.isSupabaseConfigured;

  /// Safely read a value from dotenv, returning null if dotenv is not
  /// initialized or the key is absent (instead of throwing NotInitializedError).
  static String? _safeDotenv(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  static String get apiBaseUrl {
    final env = _safeDotenv('API_BASE_URL');
    if (env != null && env.isNotEmpty) return env;
    // Check AppEnvironment for environment-specific URL
    try {
      return AppEnvironmentConfig.current.apiBaseUrl;
    } catch (_) {}
    return AppConfig.apiBaseUrl;
  }

  // Google OAuth Client IDs — delegated to AppConfig (single source).
  static String get googleWebClientId => AppConfig.googleWebClientId;
  static String get googleAndroidClientId => AppConfig.googleAndroidClientId;
  static String get googleIosClientId => AppConfig.googleIosClientId;

  /// Deep link scheme for the app (e.g. 'kinrel' → 'kinrel://')
  static const String appDeepLinkScheme = 'kinrel';
}
