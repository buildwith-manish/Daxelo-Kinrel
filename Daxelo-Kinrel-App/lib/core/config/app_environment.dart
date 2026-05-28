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
        AppEnvironment.dev => 'http://10.0.2.2:3000/api', // Android emulator → host
        AppEnvironment.staging =>
          'https://daxelo-kinrel-staging.onrender.com/api',
        AppEnvironment.prod => 'https://daxelo-kinrel-server.onrender.com/api',
      };

  /// Supabase URL for this environment
  /// (In production, these would be different per environment)
  String get supabaseUrl => switch (this) {
        AppEnvironment.dev =>
          'https://promxswvsnvilplmrtsj.supabase.co',
        AppEnvironment.staging =>
          'https://promxswvsnvilplmrtsj.supabase.co',
        AppEnvironment.prod =>
          'https://promxswvsnvilplmrtsj.supabase.co',
      };

  /// Supabase anon key for this environment
  String get supabaseAnonKey => switch (this) {
        AppEnvironment.dev =>
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY',
        AppEnvironment.staging =>
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY',
        AppEnvironment.prod =>
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY',
      };
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
