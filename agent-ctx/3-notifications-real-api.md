# Task 3 — Rewrite notifications_provider.dart for real API + polling

## Summary
Replaced demo data loading with real backend API calls, added 30-second polling for real-time updates, and added pull-to-refresh support.

## Files Modified
1. **`Daxelo-Kinrel-App/lib/features/notifications/providers/notifications_provider.dart`** — Complete rewrite of `NotificationsNotifier`
2. **`Daxelo-Kinrel-App/lib/features/notifications/presentation/notifications_screen.dart`** — Real-time polling + pull-to-refresh

## Key Changes

### notifications_provider.dart
- Removed `_loadDemoData()` (180 lines of hardcoded demo data)
- Added `loadNotifications()` — calls `GET /api/notifications/v2?page=1&limit=50`
- Added `_startPolling()` — `Timer.periodic` every 30 seconds
- Added `dispose()` — cancels poll timer
- Added `_mapNotification()` — maps backend JSON → `NotificationModel`
- Added `_mapEventType()` — maps `eventType` strings → `NotificationType` enum (8 mappings)
- Added `_formatTime()` — ISO 8601 → relative time ("Just now", "5 min ago", etc.)
- Added `_colorForType()` — consistent avatar color per `NotificationType`
- Changed `markAsRead()` → `Future<void>` with optimistic update + `PATCH /api/notifications/v2/read` + rollback
- Changed `markAllRead()` → `Future<void>` with optimistic update + `PATCH /api/notifications/v2/read-all` + rollback
- Changed `deleteNotification()` → `Future<void>` with optimistic update (no v2 delete endpoint)
- Added `refresh()` — alias for `loadNotifications()`
- Updated `getNotificationPreferences()` → `GET /api/notifications/v2/preferences`
- Updated `updateNotificationPreference()` → `PATCH /api/notifications/v2/preferences` with `_notificationTypeToEventType()` mapping
- Added `_notificationTypeToEventType()` — reverse maps `NotificationType` → backend `eventType` strings (10 mappings)

### notifications_screen.dart
- Added `import 'dart:async';`
- Added `Timer? _refreshTimer` field
- Updated `initState()` — calls `loadNotifications()` via `addPostFrameCallback` + starts 30s periodic timer
- Updated `dispose()` — cancels `_refreshTimer`
- Wrapped notification list in `RefreshIndicator` (orange accent, dark background, `AlwaysScrollableScrollPhysics`)
- Wrapped empty state in `RefreshIndicator` too (so pull-to-refresh works even when empty)

## Notes
- Flutter/Dart CLI not available in environment — manual code review performed
- All existing models, types, enums, and provider signatures preserved — no downstream breakage
