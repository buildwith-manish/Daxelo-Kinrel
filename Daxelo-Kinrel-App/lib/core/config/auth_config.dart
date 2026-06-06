// lib/core/config/auth_config.dart
//
// DAXELO KINREL — Auth Configuration (Development Mode)
//
// Set --dart-define=AUTH_DISABLED=true to bypass ALL authentication.
// Defaults to false (auth enabled) for production safety.

/// Global flag to disable authentication for development.
/// Controlled via --dart-define=AUTH_DISABLED=true during development.
/// Defaults to false (auth enabled) for production safety.
/// When true:
/// - Skip all auth initialization (Supabase, Firebase Auth)
/// - Skip all login checks
/// - Skip session validation
/// - Use mock user for all auth-dependent code
/// - Bypass all auth guards
const bool kAuthDisabled =
    bool.fromEnvironment('AUTH_DISABLED', defaultValue: false);

/// Mock authenticated user used when kAuthDisabled = true.
class MockUser {
  MockUser._();
  static const String id = 'debug_user';
  static const String name = 'Manish';
  static const String email = 'debug@kinrel.app';
  
  /// User metadata map matching Supabase User.userMetadata format
  static const Map<String, dynamic> userMetadata = {
    'name': name,
    'full_name': name,
    'username': 'manish',
    'preferred_language': 'en',
    'avatar_url': null,
  };
}
