// lib/core/config/auth_config.dart
//
// DAXELO KINREL — Auth Configuration
//
// All authentication flows are REAL. There is no bypass flag, no mock
// user, and no debug auto sign-in. Every authenticated operation
// requires a real Supabase session obtained through one of:
//   - Email + password sign-in
//   - Google Sign-In
//   - Apple Sign-In (iOS)
//
// If you need to test without auth, sign up a real account in the
// Supabase project and use those credentials.

/// Authentication is always enabled.
///
/// This constant exists only for backward compatibility with any
/// third-party code that still references it. The value is always
/// `false` — there is no bypass path.
const bool kAuthDisabled = false;
