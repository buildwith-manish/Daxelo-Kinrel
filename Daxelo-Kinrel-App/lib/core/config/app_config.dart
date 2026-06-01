import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-level configuration constants
class AppConfig {
  AppConfig._();

  static const String appName = 'KINREL';
  static const String appTagline = 'Indian Family Relationship Intelligence';
  static const String appNameByDaxelo = 'Daxelo KINREL';
  static const String version = '1.0.0';

  // Hardcoded fallbacks — Supabase anon key is safe for client-side use
  // (only service_role key is secret). These ensure the app ALWAYS has
  // valid credentials even when .env is missing or env vars are empty.
  static const String _fallbackSupabaseUrl =
      'https://promxswvsnvilplmrtsj.supabase.co';
  static const String _fallbackSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY';
  static const String _fallbackApiBaseUrl =
      'https://daxelo-kinrel-server.onrender.com';

  /// Safely read a value from dotenv, returning null if dotenv is not
  /// initialized or the key is absent (instead of throwing NotInitializedError).
  static String? _safeDotenv(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      // dotenv not initialized — return null so fallback is used
      return null;
    }
  }

  // Supabase — reads from .env file (loaded via flutter_dotenv)
  // Falls back to --dart-define, then hardcoded defaults
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

  // Backend API
  static String get apiBaseUrl {
    final env = _safeDotenv('API_BASE_URL');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _fallbackApiBaseUrl,
    );
  }

  /// Check if Supabase is properly configured
  static bool get isSupabaseConfigured => supabaseAnonKey.isNotEmpty;

  // Google OAuth Client IDs — aligned to Firebase project 643588134212
  // (daxelo-kinrel-d8ccf). These match the updated google-services.json
  // and GoogleService-Info.plist. The old project 726935858050 client IDs
  // have been removed to fix the cross-project mismatch that caused
  // Google Sign-In ApiException:10 (DEVELOPER_ERROR).
  //
  // Web client ID — used as serverClientId for Supabase signInWithIdToken
  // This is the audience (aud) claim in the Google ID token that Supabase verifies.
  //
  // Supabase OAuth callback URL (for Google Cloud Console authorized redirect URIs):
  // https://promxswvsnvilplmrtsj.supabase.co/auth/v1/callback
  static const String _fallbackGoogleWebClientId =
      '643588134212-rj7354vgqk7efjd075kvkaodfdenen3m.apps.googleusercontent.com';
  // Android client ID — registered in google-services.json with SHA-1 fingerprint
  // Updated: new OAuth2 credential with SHA-1 aee41e0947cce859c1028511d343826d704f3ef5
  static const String _fallbackGoogleAndroidClientId =
      '643588134212-e74dp3uuh526ticm3c413b3gioefsenp.apps.googleusercontent.com';
  // iOS client ID — from GoogleService-Info.plist (reversed client ID)
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

  /// All Google client IDs comma-separated for Supabase dashboard config
  static String get googleClientIdsCommaSeparated =>
      '$googleWebClientId,$googleAndroidClientId,$googleIosClientId';

  // Feature flags
  static const bool enableWhatsApp = true;
  static const bool enableCommunity = true;
  static const bool enableModeration = true;

  // Limits
  static const int maxFamilyMembers = 500;
  static const int maxTreeDepth = 7;
  static const int searchDebounceMs = 300;
  static const int kinshipCacheDurationMinutes = 60;

  // Animation
  static const Duration splashDuration = Duration(milliseconds: 1500);
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
}
