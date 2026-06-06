// lib/core/config/app_environment.dart
//
// DAXELO KINREL — App Environment / Flavor System
//
// Provides environment separation (dev/staging/prod) so crash reports,
// analytics, and backend URLs are correctly isolated per environment.
//
// Usage:
//   flutter run --dart-define=APP_ENV=dev
//   flutter run --dart-define=APP_ENV=staging
//   flutter run --dart-define=APP_ENV=prod
//
// If not specified, defaults to:
//   - debug mode → dev
//   - profile mode → staging
//   - release mode → prod

import 'package:flutter/foundation.dart';
import 'app_config.dart';

/// App environment enum — determines which backend, Crashlytics project,
/// and feature flags are active.
enum AppEnvironment {
  dev,
  staging,
  prod;

  /// Parse from string (case-insensitive)
  static AppEnvironment? fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      default:
        return null;
    }
  }

  /// Short label for crash reports and logs
  String get label => switch (this) {
        AppEnvironment.dev => 'dev',
        AppEnvironment.staging => 'staging',
        AppEnvironment.prod => 'prod',
      };

  /// Full display name
  String get displayName => switch (this) {
        AppEnvironment.dev => 'Development',
        AppEnvironment.staging => 'Staging',
        AppEnvironment.prod => 'Production',
      };

  /// Whether this is a production environment
  bool get isProduction => this == AppEnvironment.prod;

  /// Whether this is a development environment
  bool get isDev => this == AppEnvironment.dev;

  /// Whether Crashlytics should be enabled (only prod & staging)
  bool get shouldReportCrashes => this != AppEnvironment.dev;

  /// Whether verbose logging should be enabled
  bool get enableVerboseLogging => this == AppEnvironment.dev;

  /// API base URL for this environment
  String get apiBaseUrl => switch (this) {
        AppEnvironment.dev => 'http://10.0.2.2:3001', // Android emulator → NestJS on host
        AppEnvironment.staging =>
          'https://daxelo-kinrel-staging.onrender.com',
        AppEnvironment.prod => AppConfig.fallbackApiBaseUrl,
      };

  /// Supabase URL for this environment
  /// All environments share the same Supabase project — value from AppConfig
  String get supabaseUrl => AppConfig.fallbackSupabaseUrl;

  /// Supabase anon key for this environment
  /// All environments share the same Supabase project — value from AppConfig
  String get supabaseAnonKey => AppConfig.fallbackSupabaseAnonKey;
}

/// Global current environment — resolved once at startup.
class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  static late final AppEnvironment current;

  /// Initialize the environment from --dart-define or build mode.
  /// Must be called before `runApp()`.
  static void initialize() {
    // 1. Try dart-define APP_ENV
    const envString = String.fromEnvironment('APP_ENV');
    final env = AppEnvironment.fromString(envString);

    if (env != null) {
      current = env;
    } else if (kReleaseMode) {
      current = AppEnvironment.prod;
    } else if (kProfileMode) {
      current = AppEnvironment.staging;
    } else {
      current = AppEnvironment.dev;
    }

    debugPrint('🔧 App Environment: ${current.displayName} (${current.label})');
  }
}
