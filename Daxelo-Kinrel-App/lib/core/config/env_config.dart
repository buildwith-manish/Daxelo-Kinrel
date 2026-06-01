import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app_environment.dart';

/// Environment configuration with secure handling
class EnvConfig {
  EnvConfig._();

  // Hardcoded fallbacks (same as AppConfig)
  static const String _fallbackSupabaseUrl =
      'https://promxswvsnvilplmrtsj.supabase.co';
  static const String _fallbackSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY';
  static const String _fallbackApiBaseUrl =
      'https://daxelo-kinrel-server.onrender.com';

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
  static String get supabaseUrl {
    final env = _safeDotenv('SUPABASE_URL');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: _fallbackSupabaseUrl,
    );
  }

  static String get supabaseAnonKey {
    final env = _safeDotenv('SUPABASE_ANON_KEY');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: _fallbackSupabaseAnonKey,
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
      defaultValue: _fallbackApiBaseUrl,
    );
  }

  // Google OAuth Client IDs — aligned to Firebase project 643588134212
  // (daxelo-kinrel-d8ccf). Must match AppConfig and google-services.json.
  static const String _fallbackGoogleWebClientId =
      '643588134212-rj7354vgqk7efjd075kvkaodfdenen3m.apps.googleusercontent.com';
  static const String _fallbackGoogleAndroidClientId =
      '643588134212-e74dp3uuh526ticm3c413b3gioefsenp.apps.googleusercontent.com';
  static const String _fallbackGoogleIosClientId =
      '643588134212-ep2guf1q8fk5idsa224fu9e3t4bdu2e3.apps.googleusercontent.com';

  static String get googleWebClientId {
    final env = _safeDotenv('GOOGLE_WEB_CLIENT_ID');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: _fallbackGoogleWebClientId,
    );
  }

  static String get googleAndroidClientId {
    final env = _safeDotenv('GOOGLE_ANDROID_CLIENT_ID');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'GOOGLE_ANDROID_CLIENT_ID',
      defaultValue: _fallbackGoogleAndroidClientId,
    );
  }

  static String get googleIosClientId {
    final env = _safeDotenv('GOOGLE_IOS_CLIENT_ID');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'GOOGLE_IOS_CLIENT_ID',
      defaultValue: _fallbackGoogleIosClientId,
    );
  }
}
