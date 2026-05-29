# Complete Fix Prompt for Kinrel App Crash on Sign In

## Root Cause Analysis
The app crashes (or ANRs) immediately after successful sign-in because:
1. After login, `ProfileNotifier.loadProfile()` makes a GET `/api/users/me` which returns 404 (user not found on backend or endpoint mismatch).
2. Dio is configured to throw on non-2xx responses, and the error is not caught properly, leading to unhandled `DioException` / `FlutterError` which crashes the app via Crashlytics reporting.
3. Similar unhandled 404 on FCM token sync in `PushNotificationService`.
4. The login screen shows "Connecting..." but the subsequent profile load fails hard.

The provided stacktraces confirm:
- `profile_provider.dart:393` → NetworkError on /api/users/me (404)
- `push_notification_service.dart:283` → Failed to sync FCM token (404)

## Complete Step-by-Step Fix (Apply in Order)

### 1. Update Dio Configuration for Graceful Error Handling (lib/core/network/api_client.dart or wherever Dio is initialized)
```dart
// In your Dio interceptor or base client
dio.options.validateStatus = (status) => status != null && status < 500; // Allow 4xx to be handled manually
// Or better: wrap all calls with try-catch
```

### 2. Fix Profile Loading (lib/features/profile/data/profile_provider.dart)
Replace the `loadProfile` method around line 393 with robust error handling:

```dart
Future<void> loadProfile() async {
  state = const AsyncLoading();
  try {
    final response = await dio.get('/api/users/me');
    if (response.statusCode == 200) {
      // parse and set state
      state = AsyncData(Profile.fromJson(response.data));
    } else if (response.statusCode == 404) {
      // Handle new user or missing profile gracefully
      state = const AsyncData(null); // or navigate to profile setup
      // Optionally show "Complete your profile" UI
    } else {
      state = AsyncError('Unexpected error: ${response.statusCode}', StackTrace.current);
    }
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      state = const AsyncData(null);
    } else {
      state = AsyncError(e, e.stackTrace);
    }
  } catch (e, st) {
    state = AsyncError(e, st);
  }
}
```

Also add similar try-catch around the call site in the login success flow.

### 3. Fix Push Notification Token Sync (lib/features/notifications/push_notification_service.dart)
Around lines 264-283, wrap the sync:

```dart
Future<void> _syncTokenToBackend(String token) async {
  try {
    final response = await dio.post('/api/notifications/fcm', data: {'token': token});
    if (response.statusCode == 404) {
      // Log and continue - don't crash
      debugPrint('FCM sync endpoint not found or user not registered yet');
      return;
    }
    // normal handling
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      debugPrint('FCM token sync 404 - ignoring');
      return;
    }
    rethrow; // only rethrow non-404
  }
}
```

Call this inside a try-catch in `initialize()` and `_acquireAndSyncToken()`.

### 4. Update Login Flow (lib/features/auth/presentation/login_screen.dart or auth notifier)
After successful credential login (the "Connecting..." button):
- Wrap the navigation / profile load in try-catch.
- On 404 profile, redirect to a "Complete Profile" screen instead of crashing.
- Ensure the sign-in button disables during async operation and shows proper loading state.

### 5. Global Error Handler Improvements (lib/main.dart)
Add to `FlutterError.onError` and `PlatformDispatcher.instance.onError`:

```dart
FlutterError.onError = (details) {
  if (details.exception is DioException) {
    final dioErr = details.exception as DioException;
    if (dioErr.response?.statusCode == 404) {
      // swallow 404s or log only
      return;
    }
  }
  FirebaseCrashlytics.instance.recordFlutterError(details);
};
```

### 6. Backend / Endpoint Check (Recommended)
Verify the server has:
- `GET /api/users/me` returning 200 for logged-in users (or 201 for new users)
- Proper user creation on first login via Google/email

If the backend returns 404 for valid logged-in users, fix the backend route or ensure user is created during signup/login.

### 7. Testing Checklist
1. Clean build: `flutter clean && flutter pub get`
2. Test sign-in with the shown credentials.
3. Verify no crash on 404 responses.
4. Test with airplane mode / bad network.
5. Run `flutter analyze` and fix any new warnings.
6. Test on physical device (the crash is reported on Android).

### 8. Additional Hardening
- Add `Interceptor` that converts all 404s to a custom `UserNotFoundException` that UI can handle.
- Use Riverpod's `AsyncValue.guard` everywhere possible for Dio calls.
- Consider adding a retry mechanism only for 5xx errors.

Apply these changes, then rebuild and test the sign-in flow. This should provide a 200% crash-free experience. After fixing, revoke the PAT.

If you need the exact diff for any file, provide the file content and I can generate precise patches.