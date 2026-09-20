import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-level configuration constants
class AppConfig {
  AppConfig._();

  static const String appName = 'KINREL';
  static const String appTagline = 'Indian Family Relationship Intelligence';
  static const String appNameByDaxelo = 'Daxelo KINREL';
  static const String version = '1.0.0';

  // ── Supabase: ENV-ONLY, fails loudly (QA hardening 2026-09-20) ────
  //
  // The hardcoded Supabase URL + publishable-key fallbacks were REMOVED.
  // Resolution order: .env (flutter_dotenv) → --dart-define at compile
  // time → THROW. Rationale from the QA pass:
  //
  //   • The 2026-09-19 key rotation (legacy anon JWT → publishable key)
  //     proved a baked-in key cannot be rotated without a code release.
  //   • The fallback silently masked missing CI config: the "Create .env"
  //     steps in the build workflows wrote a file that was never bundled
  //     (.env is NOT a pubspec asset), so every CI build was actually
  //     running on these constants.
  //   • Build pipelines now inject the values via --dart-define from
  //     GitHub secrets / Vercel environment variables and FAIL loudly
  //     when they are absent.
  //
  // Non-secret public identifiers (Google OAuth client IDs, the backend
  // API base URL) keep their defaults below — they are not credentials,
  // they cannot be rotated server-side, and the native client IDs must
  // stay in lockstep with google-services.json / GoogleService-Info.plist
  // which are committed to the repo anyway.
  static String get supabaseUrl => _requiredEnv(
      'SUPABASE_URL', const String.fromEnvironment('SUPABASE_URL'));

  static String get supabaseAnonKey => _requiredEnv(
      'SUPABASE_ANON_KEY', const String.fromEnvironment('SUPABASE_ANON_KEY'));

  /// [dartDefineValue] must be passed as a `const String.fromEnvironment`
  /// literal from the getter above — the environment key is baked in at
  /// compile time, so it cannot flow through a runtime [key] parameter.
  static String _requiredEnv(String key, String dartDefineValue) {
    final env = _safeDotenv(key);
    if (env != null && env.isNotEmpty) return env;
    if (dartDefineValue.isNotEmpty) return dartDefineValue;
    throw StateError(missingConfigMessage(key));
  }

  /// The error surfaced when a required key is absent. Separate static
  /// so tests can pin the remediation instructions.
  @visibleForTesting
  static String missingConfigMessage(String key) =>
      '$key is not configured. Provide it via .env (flutter_dotenv) or at '
      'build time with --dart-define=$key=<value>. Hardcoded fallbacks were '
      'removed (QA hardening 2026-09-20) so a rotated key can never be '
      'silently masked by a stale baked-in value. CI: check the $key '
      'GitHub secret / Vercel environment variable.';

  /// Non-throwing diagnostic peek at [supabaseUrl].
  ///
  /// FOR LOGGING ONLY — real resolution must use the throwing getter so
  /// missing config fails loudly. Returns null when the key is unset.
  static String? get peekSupabaseUrl => _peekEnv(
      'SUPABASE_URL', const String.fromEnvironment('SUPABASE_URL'));

  /// Non-throwing diagnostic peek at [supabaseAnonKey].
  ///
  /// FOR LOGGING ONLY — never use this to build a Supabase client.
  /// Returns null when the key is unset (never the key material).
  static String? get peekSupabaseAnonKey => _peekEnv(
      'SUPABASE_ANON_KEY', const String.fromEnvironment('SUPABASE_ANON_KEY'));

  static String? _peekEnv(String key, String dartDefineValue) {
    final env = _safeDotenv(key);
    if (env != null && env.isNotEmpty) return env;
    if (dartDefineValue.isNotEmpty) return dartDefineValue;
    return null;
  }

  /// Check if Supabase is properly configured.
  ///
  /// Built on the non-throwing peek so the check itself can never crash
  /// startup diagnostics (main.dart logs this before any Supabase use).
  static bool get isSupabaseConfigured =>
      peekSupabaseUrl != null && peekSupabaseAnonKey != null;

  /// Safely read a value from dotenv, returning null if dotenv is not
  /// initialized or the key is absent (instead of throwing NotInitializedError).
  static String? _safeDotenv(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      // dotenv not initialized — return null so dart-define is used
      return null;
    }
  }

  // Backend API — non-secret endpoint, keeps its default (see note above).
  static String get apiBaseUrl {
    final env = _safeDotenv('API_BASE_URL');
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://daxelo-kinrel-server.onrender.com',
    );
  }

  // Google OAuth Client IDs
  //
  // The serverClientId (Web Client ID) MUST match the Google OAuth client
  // configured in the Supabase Dashboard → Authentication → Providers → Google.
  // That provider uses project 726935858050's credentials, so the Web Client ID
  // here must be from that project — NOT from the Firebase project 643588134212.
  //
  // The Android & iOS client IDs come from Firebase project 643588134212
  // (google-services.json / GoogleService-Info.plist) — they validate the
  // app's package name + SHA-1 at the native Google Sign-In level.
  //
  // Supabase OAuth callback URL (for Google Cloud Console authorized redirect URIs):
  // https://promxswvsnvilplmrtsj.supabase.co/auth/v1/callback
  static const String _fallbackGoogleWebClientId =
      '726935858050-b0q96taocaa7rto463u466c49jdqkp41.apps.googleusercontent.com';
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
  // Note: Web client ID is from project 726935858050 (Supabase provider),
  // Android/iOS client IDs are from project 643588134212 (Firebase).
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
