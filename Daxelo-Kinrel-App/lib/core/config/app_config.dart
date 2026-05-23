import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-level configuration constants
class AppConfig {
  AppConfig._();

  static const String appName = 'KINREL';
  static const String appTagline = 'Indian Family Relationship Intelligence';
  static const String appNameByDaxelo = 'KINREL by Daxelo';
  static const String version = '1.0.0';
  
  // Supabase — reads from .env file (loaded via flutter_dotenv)
  // Falls back to --dart-define, then hardcoded defaults
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ??
      const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://vxnyjhvcipgqeowdgfah.supabase.co');

  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ??
      const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  
  // Backend API
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ??
      const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://daxelo-kinrel.vercel.app');

  /// Check if Supabase is properly configured
  static bool get isSupabaseConfigured => supabaseAnonKey.isNotEmpty;

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
  static const Duration splashDuration = Duration(seconds: 3);
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
}
