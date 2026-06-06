import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app_config.dart';
import 'app_environment.dart';

/// Environment configuration with secure handling
///
/// Fallback/default values are defined ONCE in [AppConfig] and referenced
/// here — never duplicated. This ensures a single source of truth for
/// all credentials across the app.
class EnvConfig {
  EnvConfig._();

  static bool get isProduction => const bool.fromEnvironment('dart.vm.product');
  static bool get isDebug => !isProduction;
  static bool get isProfile => const bool.fromEnvironment('dart.vm.profile');

  /// Safely read a value from dotenv, returning null if dotenv is not
  /// initialized or the key is absent (instead of throwing NotInitializedError).
  static String? _safeDotenv(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  // IMPORTANT: Handles both null AND empty string from dotenv
  // Fallback values delegated to AppConfig (single source of truth)
  static String get supabaseUrl {
    final env = _safeDotenv('SUPABASE_URL');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: AppConfig.fallbackSupabaseUrl,
    );
  }

  static String get supabaseAnonKey {
    final env = _safeDotenv('SUPABASE_ANON_KEY');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: AppConfig.fallbackSupabaseAnonKey,
    );
  }

  static String get apiBaseUrl {
    final env = _safeDotenv('API_BASE_URL');
    if (env != null && env.isNotEmpty) return env;
    // Check AppEnvironment for environment-specific URL
    try {
      return AppEnvironmentConfig.current.apiBaseUrl;
    } catch (_) {}
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: AppConfig.fallbackApiBaseUrl,
    );
  }

  // Google OAuth Client IDs — fallback values delegated to AppConfig
  // Web client ID is from project 726935858050 (must match Supabase Google provider config)
  // Android/iOS client IDs are from project 643588134212 (must match google-services.json)
  static String get googleWebClientId {
    final env = _safeDotenv('GOOGLE_WEB_CLIENT_ID');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: AppConfig.fallbackGoogleWebClientId,
    );
  }

  static String get googleAndroidClientId {
    final env = _safeDotenv('GOOGLE_ANDROID_CLIENT_ID');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'GOOGLE_ANDROID_CLIENT_ID',
      defaultValue: AppConfig.fallbackGoogleAndroidClientId,
    );
  }

  static String get googleIosClientId {
    final env = _safeDotenv('GOOGLE_IOS_CLIENT_ID');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'GOOGLE_IOS_CLIENT_ID',
      defaultValue: AppConfig.fallbackGoogleIosClientId,
    );
  }
}
