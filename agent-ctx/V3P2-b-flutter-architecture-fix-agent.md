# V3P2-b — Flutter Architecture Fix Agent

## Task: V3 Phase 2 — Flutter Architecture fixes (5 items)

### Fix 1 (CQ-01): Split main.dart
- Split 718-line main.dart into 5 files:
  - `lib/main.dart` — 16-line entry point
  - `lib/app.dart` — KinrelApp widget with all lifecycle handling
  - `lib/core/bootstrap/app_initializer.dart` — Quick pre-runApp setup
  - `lib/core/bootstrap/error_handler.dart` — Global error handlers
  - `lib/core/bootstrap/service_orchestrator.dart` — Deferred services, auth listeners, connectivity listener

### Fix 2 (CQ-02): Replace global mutable state
- Created `lib/core/bootstrap/app_init_provider.dart` with `AppInitNotifier extends AsyncNotifier<void>`
- Removed `_globalContainer`, `_appInitComplete`, `_initCompleter` global variables
- `appInitProvider` AsyncNotifierProvider replaces `appInitCompleteProvider` FutureProvider
- Supabase readiness notified via `ref` inside the notifier instead of `_globalContainer`

### Fix 3 (CARRY-07): Wire offline mutation queue to connectivity
- Added `_setupConnectivityListener()` in `service_orchestrator.dart`
- Listens to `isOnlineProvider` (from `connectivity_service.dart`)
- On offline→online transition, calls `backgroundSyncManagerProvider.onConnectivityRestored()`
- `connectivity_plus` already in pubspec.yaml

### Fix 4 (NEW-07): Wrap Future.delayed with unawaited() + error handling
- Fixed 15 fire-and-forget `Future.delayed` calls across the codebase:
  - main.dart (already in new bootstrap files)
  - deep_link_service.dart
  - invite_screen.dart
  - join_family_screen.dart
  - relationship_graph_screen.dart
  - share_provider.dart
  - profile_edit_screen.dart
  - path_finder_screen.dart
  - two_factor_login_screen.dart
  - sign_up_screen.dart
  - chat_provider.dart
  - chat_screen.dart
  - documents_screen.dart
  - splash_screen.dart (2 calls)
  - smart_calendar_screen.dart

### Fix 5 (NEW-10): Replace S.delegate with AppLocalizations.delegate
- Renamed `abstract class S` → `abstract class AppLocalizations` in `app_localizations.dart`
- Renamed `_SDelegate` → `_AppLocalizationsDelegate`
- Renamed `lookupS` → `lookupAppLocalizations`
- Updated all 15 locale files (`extends S` → `extends AppLocalizations`)
- Updated `app.dart` to use `AppLocalizations.delegate` and `AppLocalizations.supportedLocales`
- Updated splash_screen.dart import from `main.dart show appInitCompleteProvider` → `app_init_provider.dart show appInitProvider`

### Files Modified/Created
- **Created**: main.dart (rewritten), app.dart, app_initializer.dart, error_handler.dart, service_orchestrator.dart, app_init_provider.dart
- **Modified**: app_localizations.dart + 15 locale files, splash_screen.dart, deep_link_service.dart, invite_screen.dart, join_family_screen.dart, relationship_graph_screen.dart, share_provider.dart, profile_edit_screen.dart, path_finder_screen.dart, two_factor_login_screen.dart, sign_up_screen.dart, chat_provider.dart, chat_screen.dart, documents_screen.dart, smart_calendar_screen.dart
