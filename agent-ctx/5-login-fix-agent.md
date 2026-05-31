# Task ID: 5 — Login Error / Crash / ANR Fix Agent

## Summary
Applied 8 fixes to resolve login errors, crashes, and ANRs in the Daxelo-Kinrel Flutter app.

## Fixes Applied

### FIX 1: _waitForSession() race condition (sign_in_screen.dart + sign_up_screen.dart)
- Changed loop from 10 iterations (2s) to 25 iterations (5s)
- Instead of silently returning when session never arrives (causing redirect loops), now throws `AuthException` so the caller's catch block handles the error properly
- Added `on AuthException { rethrow; }` to preserve the meaningful error message
- Added `import 'dart:async'` and `import 'package:supabase_flutter/supabase_flutter.dart'` to both files

### FIX 2: _hasCachedProfile race condition (splash_screen.dart)
- Changed `_checkIsarCache()` from `void` to `Future<void>` and made it `async`
- Changed `db.profileCount().then()` fire-and-forget to `await db.profileCount()` 
- Added `await` to `_checkIsarCache()` call in `_initialize()` to prevent reading `_hasCachedProfile` before the check completes

### FIX 3: Token refresh in _AuthInterceptor (dio_client.dart)
- When session is expired, now attempts `client.auth.refreshSession()` before proceeding
- If refresh succeeds, uses the new session for the Authorization header
- If refresh fails, proceeds without token (will get 401) with debug logging
- Added `import 'package:flutter/foundation.dart'` for `debugPrint`

### FIX 4: Sign-out doesn't clear route persistence (settings_screen.dart)
- Added `await clearLastRoute()` to the sign-out handler
- `clearLastRoute()` is already available via the `supabase_service.dart` import

### FIX 5: Delete account doesn't clear SecureStorage tokens (delete_account_screen.dart)
- Added `await SecureStorageService().clearAuthTokens()` to `_clearAllLocalStorage()`
- Added `await clearLastRoute()` to `_clearAllLocalStorage()`
- Added `import '../../../core/storage/secure_storage.dart'`

### FIX 6: Analytics logLogin/logSignUp truly fire-and-forget (sign_in_screen.dart + sign_up_screen.dart)
- Changed from `await AnalyticsService.instance.logLogin('google')` (blocking) to `unawaited(AnalyticsService.instance.logLogin('google').catchError((_) {}))`
- Same change for `logLogin('email')`, `logSignUp('google')`, `logSignUp('email')`
- This prevents analytics slowness from blocking the sign-in/sign-up flow

### FIX 7: Double auth state listener guard (main.dart)
- Added guard check: only calls `_handlePostSignIn()` if `pushService.isInitialized` is false
- Prevents double initialization of push notifications (once by auth listener, once by deferred init)
- Falls back to calling `_handlePostSignIn()` if push service can't be read

### FIX 8: Manual dispose on Riverpod-managed provider (main.dart)
- Removed `pushService.dispose()` call from `_handleSignOut()`
- Riverpod manages the provider lifecycle; manual dispose causes use-after-dispose errors

## Files Modified
1. `lib/features/auth/presentation/sign_in_screen.dart`
2. `lib/features/auth/presentation/sign_up_screen.dart`
3. `lib/features/splash/presentation/splash_screen.dart`
4. `lib/core/networking/dio_client.dart`
5. `lib/features/settings/presentation/settings_screen.dart`
6. `lib/features/profile/presentation/delete_account_screen.dart`
7. `lib/main.dart`
