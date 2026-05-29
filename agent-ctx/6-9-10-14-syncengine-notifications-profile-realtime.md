# Task 6-9-10-14: Activate SyncEngine, Enhance Offline System, Notifications, Profile, and Realtime

## Summary

All 8 sub-tasks completed successfully. No existing features removed, frameworks replaced, or libraries swapped.

## Files Created (3 new files)

1. `lib/core/database/sync/sync_engine_provider.dart` — Riverpod providers for SyncEngine, SyncStatus, SyncEvent
2. `lib/core/sync/background_sync_manager.dart` — Background sync lifecycle manager (app resume, connectivity, periodic)
3. `lib/core/network/realtime_dedup.dart` — Event deduplication for Supabase Realtime (last 100 events cache)

## Files Modified (5 files)

1. `lib/main.dart` — Switched from SyncService to SyncEngine + BackgroundSyncManager
2. `lib/features/notifications/providers/notifications_provider.dart` — NotificationType enum, preferences, grouping
3. `lib/core/services/local_notification_scheduler.dart` — Birthday/anniversary reminders
4. `lib/features/profile/data/profile_provider.dart` — Completion score, extended fields, validation
5. `lib/core/network/supabase_realtime_service.dart` — Dedup, connection status, duplicate sub fix

## Key Changes

### SyncEngine Activation
- SyncEngine (previously unused) is now wired in via `syncEngineProvider`
- BackgroundSyncManager coordinates sync on app resume, connectivity restore, and periodically
- App lifecycle integration: stops periodic sync when paused, resumes delta sync when resumed

### Notifications
- 10 notification types with labels and category mappings
- Per-type preferences (push/inApp/email) with optimistic API updates
- Grouping by familyId + notificationType

### Profile
- ProfileCompletionScore (0-100%) with weighted fields and suggestions
- Extended fields: occupation, education, privacySettings
- Field validation before save (username, name, bio, phone, etc.)

### Realtime
- RealtimeDedup prevents duplicate event processing (100-event cache)
- Connection status stream (Stream<bool>) for online/offline detection
- Duplicate subscription prevention in subscribeToNotifications()
- New `realtimeOnlineStatusProvider` Riverpod provider
