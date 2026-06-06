import 'app_config.dart';
import 'app_environment.dart';

/// Environment configuration with secure handling
///
/// All credentials are supplied via --dart-define at build time.
/// [AppConfig] is the single source of truth — this class provides
/// environment-level helpers and delegates to AppConfig for values.
class EnvConfig {
  EnvConfig._();

  static bool get isProduction => const bool.fromEnvironment('dart.vm.product');
  static bool get isDebug => !isProduction;
  static bool get isProfile => const bool.fromEnvironment('dart.vm.profile');

  // Supabase — delegates to AppConfig (compile-time --dart-define)
  static String get supabaseUrl => AppConfig.supabaseUrl;
  static String get supabaseAnonKey => AppConfig.supabaseAnonKey;

  // Backend API — check AppEnvironment for environment-specific URL first
  static String get apiBaseUrl {
    try {
      return AppEnvironmentConfig.current.apiBaseUrl;
    } catch (_) {}
    return AppConfig.apiBaseUrl;
  }

  // Google OAuth Client IDs — delegates to AppConfig (compile-time --dart-define)
  static String get googleWebClientId => AppConfig.googleWebClientId;
  static String get googleAndroidClientId => AppConfig.googleAndroidClientId;
  static String get googleIosClientId => AppConfig.googleIosClientId;
}
