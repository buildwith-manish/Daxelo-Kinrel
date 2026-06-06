/// App-level configuration constants
class AppConfig {
  AppConfig._();

  static const String appName = 'KINREL';
  static const String appTagline = 'Indian Family Relationship Intelligence';
  static const String appNameByDaxelo = 'Daxelo KINREL';
  static const String version = '1.0.0';

  // ── Environment variables ─────────────────────────────────────────
  // All credentials MUST be supplied via --dart-define at build time.
  // There are NO hardcoded fallbacks — this prevents credential leakage
  // if source code is exposed. Build will assert at startup if any
  // required variable is missing.
  //
  // Usage:
  //   flutter run \
  //     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  //     --dart-define=SUPABASE_ANON_KEY=eyJ... \
  //     --dart-define=API_BASE_URL=https://api.example.com \
  //     --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com \
  //     --dart-define=GOOGLE_ANDROID_CLIENT_ID=xxx.apps.googleusercontent.com \
  //     --dart-define=GOOGLE_IOS_CLIENT_ID=xxx.apps.googleusercontent.com

  static String get supabaseUrl {
    const val = String.fromEnvironment('SUPABASE_URL');
    assert(val.isNotEmpty, 'SUPABASE_URL must be set via --dart-define');
    return val;
  }

  static String get supabaseAnonKey {
    const val = String.fromEnvironment('SUPABASE_ANON_KEY');
    assert(val.isNotEmpty, 'SUPABASE_ANON_KEY must be set via --dart-define');
    return val;
  }

  static String get apiBaseUrl {
    const val = String.fromEnvironment('API_BASE_URL');
    assert(val.isNotEmpty, 'API_BASE_URL must be set via --dart-define');
    return val;
  }

  /// Check if Supabase is properly configured
  static bool get isSupabaseConfigured => supabaseAnonKey.isNotEmpty;

  // Google OAuth Client IDs
  //
  // The serverClientId (Web Client ID) MUST match the Google OAuth client
  // configured in the Supabase Dashboard → Authentication → Providers → Google.
  // The Android & iOS client IDs come from the Firebase project
  // (google-services.json / GoogleService-Info.plist) — they validate the
  // app's package name + SHA-1 at the native Google Sign-In level.
  static String get googleWebClientId {
    const val = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    assert(val.isNotEmpty, 'GOOGLE_WEB_CLIENT_ID must be set via --dart-define');
    return val;
  }

  static String get googleAndroidClientId {
    const val = String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');
    assert(val.isNotEmpty, 'GOOGLE_ANDROID_CLIENT_ID must be set via --dart-define');
    return val;
  }

  static String get googleIosClientId {
    const val = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    assert(val.isNotEmpty, 'GOOGLE_IOS_CLIENT_ID must be set via --dart-define');
    return val;
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
