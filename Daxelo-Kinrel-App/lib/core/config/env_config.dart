import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment configuration with secure handling
class EnvConfig {
  EnvConfig._();

  // Hardcoded fallbacks (same as AppConfig)
  static const String _fallbackSupabaseUrl = 'https://promxswvsnvilplmrtsj.supabase.co';
  static const String _fallbackSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1OTcxODAsImV4cCI6MjA5NTE3MzE4MH0.70VPcCiCItKPx56cH-Y0DmcvWnrBiegmDkjv-V21taY';
  static const String _fallbackApiBaseUrl = 'https://daxelo-kinrel-server.onrender.com';

  static bool get isProduction => const bool.fromEnvironment('dart.vm.product');
  static bool get isDebug => !isProduction;
  static bool get isProfile => const bool.fromEnvironment('dart.vm.profile');

  // IMPORTANT: Handles both null AND empty string from dotenv
  static String get supabaseUrl {
    final env = dotenv.env['SUPABASE_URL'];
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment('SUPABASE_URL', defaultValue: _fallbackSupabaseUrl);
  }

  static String get supabaseAnonKey {
    final env = dotenv.env['SUPABASE_ANON_KEY'];
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: _fallbackSupabaseAnonKey);
  }

  static String get apiBaseUrl {
    final env = dotenv.env['API_BASE_URL'];
    if (env != null && env.isNotEmpty) return env;
    return const String.fromEnvironment('API_BASE_URL', defaultValue: _fallbackApiBaseUrl);
  }
}
