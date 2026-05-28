---
Task ID: 2
Agent: Main Agent
Task: Fix crash, fix login flow, create NestJS backend

Work Log:
- Read crash log: type 'String' is not a subtype of type 'int' of 'index' at ProfileNotifier.loadProfile
- Root cause: (1) loadProfile() called without await causing uncaught async errors; (2) API response parsing not defensive
- Fixed profile_provider.dart: Added defensive parsing for response.data
- Fixed main.dart: Added .catchError() to all fire-and-forget async calls
- Fixed app_router.dart: Added .catchError() to _PrefetchProfile initState calls
- Fixed onboarding_screen.dart: Removed Quick Setup flow, now goes directly to sign-in
- Created NestJS backend at /home/z/my-project/server/ on port 3001
- Updated Flutter config files to point to local NestJS
- Generated Isar code to fix cachedProfiles undefined getter error

Stage Summary:
- Crash fix: Defensive parsing + proper async error handling
- Login flow: Onboarding skips Quick Setup, goes directly to /sign-in
- NestJS backend: Running on port 3001 with 37 API endpoints
- Flutter analyze: 0 errors
