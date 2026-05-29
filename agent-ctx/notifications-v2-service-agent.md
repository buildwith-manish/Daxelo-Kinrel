# Task: Enhanced Notification Service V2 (Feature 8)

## Agent: notifications-v2-agent
## Date: 2025-05-29

## Summary

Created an enhanced notification service (`NotificationsV2Service`) and controller (`NotificationsV2Controller`) for the Daxelo-Kinrel application that handles all Feature 8 notification types.

## Files Created

### 1. `/home/z/my-project/server/src/modules/notifications/notifications-v2.service.ts`

**Complete implementation with:**

- **Specific notification triggers:**
  - `notifyNewInvitation()` — Finds recipient by email/phone, sends critical notification
  - `notifyInvitationAccepted()` — Notifies original inviter when invitation accepted
  - `notifyNewRelative()` — Broadcasts to all family members about new relative
  - `notifyProfileUpdate()` — Notifies family members about profile changes
  - `sendBirthdayReminders()` — Cron job: queries persons with matching DOB month+day, respects preferences & quiet hours
  - `sendAnniversaryReminders()` — Cron job: queries persons with matching anniversary date month+day

- **Core notification methods:**
  - `createAndSend()` — Full pipeline: rate limiting → preference checking → quiet hours → multi-channel delivery → delivery tracking
  - `sendPushNotification()` — FCM integration with data payload for deep linking
  - `sendInAppNotification()` — Creates notification record + delivery tracking
  - `getUserNotifications()` — Paginated results with total, unread count, and page metadata
  - `markAsRead()` — Marks specific notification IDs as read, updates delivery tracking
  - `markAllAsRead()` — Marks all unread as read for a user
  - `getUnreadCount()` — Returns unread notification count

- **Preference management:**
  - `getUserPreferences()` — Returns all preferences or seeds defaults for 8 event types
  - `updatePreference()` — Upserts preference with validation (time format, digestMode, maxPerDay)

- **Key features:**
  - Quiet hours with IANA timezone support (default IST/Asia/Kolkata)
  - In-memory rate limiting: 10/day non-critical, 50/day critical
  - Event type defaults for 8 notification types
  - Notification delivery tracking via NotificationUpdate records
  - Multi-channel delivery (push, inApp, email, whatsapp)

### 2. `/home/z/my-project/server/src/modules/notifications/notifications-v2.controller.ts`

**REST endpoints:**
- `GET /notifications/v2` — Paginated notifications (page, limit query params)
- `GET /notifications/v2/unread` — Unread count
- `PATCH /notifications/v2/read` — Mark specific IDs as read
- `PATCH /notifications/v2/read-all` — Mark all as read
- `GET /notifications/v2/preferences` — Get user preferences
- `PATCH /notifications/v2/preferences` — Update preferences per event type

### 3. Updated `/home/z/my-project/server/src/modules/notifications/notifications.module.ts`

Added `NotificationsV2Controller` and `NotificationsV2Service` to the module's controllers and providers, and exported `NotificationsV2Service` for use by other modules.

## Integration Points

- Uses existing `PrismaService` for all database operations
- Uses existing `FcmService` for push notification delivery
- Uses existing `JwtAuthGuard` and `CurrentUser` decorator for authentication
- Works with existing Prisma models: `Notification`, `NotificationPreference`, `NotificationUpdate`, `Person`, `FamilyMember`, `Family`, `User`
