// lib/core/config/auth_config.dart
//
// DAXELO KINREL — Auth Configuration (Development Mode)
//
// Set kAuthDisabled = true to bypass ALL authentication.
// Set kAuthDisabled = false to restore normal auth flow.
// This is a TEMPORARY development flag — do NOT ship with kAuthDisabled = true.

/// Global flag to disable authentication for development.
/// When true:
/// - Skip all auth initialization (Supabase, Firebase Auth)
/// - Skip all login checks
/// - Skip session validation
/// - Use mock user for all auth-dependent code
/// - Bypass all auth guards
const bool kAuthDisabled = false;

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
