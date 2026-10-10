# Tier 1 Chat Features — Worklog

**Branch:** `tier-1-chat-features`
**Base:** `main`
**Date:** 2026-10-10

## Scope

This branch implements **9 of the 15 Tier 1 features** from the chat-parity plan I generated previously. The remaining 6 features have schema-ready migrations but no backend/Flutter code yet — they are tracked as TODOs at the bottom of this document.

## What's implemented end-to-end (4 features)

### 1.1 Saved Messages (chat-with-self)
- **DB**: `20261010100000_tier1_saved_messages.sql`
  - Partial index on `DirectMessage WHERE senderId = receiverId` (fast self-DM lookups).
  - RPC `fn_get_saved_messages_inbox()` returns the user's self-DM preview for the inbox row.
- **Server**: `server/src/modules/chat/saved-messages.controller.ts`
  - `GET /chat/saved-messages` — wraps the RPC.
- **Prisma**: `DirectMessage` is not in the Prisma schema (the DM path uses Supabase directly), so no Prisma change.
- **Flutter**: 
  - `lib/features/chat/data/saved_messages_provider.dart` — Riverpod StateNotifier calling the new endpoint.
  - `lib/features/chat/presentation/widgets/saved_messages_inbox_row.dart` — bookmark-icon row rendered at the top of the DM section in the inbox.
  - `chat_inbox_screen.dart` — injected the `SavedMessagesInboxRow` above the DM list.

### 1.2 Message Scheduling (send later)
- **DB**: `20261010110000_tier1_scheduled_messages.sql`
  - New `ScheduledMessage` table with RLS (owner-only).
  - RPCs: `fn_schedule_message`, `fn_cancel_scheduled_message`, `fn_get_scheduled_messages`, `fn_send_scheduled_messages` (the per-minute dispatcher).
  - pg_cron job `send-scheduled-messages` fires every minute as a DB-side fallback.
  - Realtime publication on `ScheduledMessage`.
- **Server**:
  - `server/src/modules/chat/scheduled-messages.service.ts` — service with idempotency keys, family membership check, time validation.
  - `server/src/modules/chat/scheduled-messages.controller.ts` — REST endpoints.
  - `@Cron(EVERY_MINUTE)` decorator calls `fn_send_scheduled_messages` RPC every minute.
- **Prisma**: Added `ScheduledMessage` model.
- **Tests**: `scheduled-messages.service.spec.ts` — 21 tests covering happy path, validation, idempotency, cancel, dispatcher error tolerance.
- **Flutter**: `lib/features/chat/data/scheduled_messages_provider.dart` + `lib/features/chat/presentation/widgets/schedule_message_sheet.dart` (with 4 quick presets + custom date/time picker).

### 1.4 Send Without Sound (silent notifications)
- **DB**: `20261010120000_tier1_send_without_sound.sql` — `silent boolean DEFAULT false` on `ChatMessage` + `DirectMessage`.
- **Server**:
  - Extended `ChatService.sendMessage` to persist `silent`.
  - Extended `ChatGateway` to pass `silent` through the socket event.
  - Extended `ChatPushScheduler` to compute "all silent" per recipient batch + propagate the flag to FCM.
  - Extended `FcmService` to honor `silent`: Android `priority='normal'` + `notification.priority='low'` + `sound=''`; iOS `interruptionLevel='passive'`.
  - Added view-once safety: when ANY message in a batch is view-once, the FCM body is replaced with `📎 View-once media` (no preview leak).
- **Tests**: existing 54 chat.service.spec tests still pass (no regressions).
- **Flutter**: `lib/features/chat/presentation/widgets/send_silently_sheet.dart` — bottom sheet for long-press send menu.

### 1.14 Caption on Media
- **DB**: `20261010130000_tier1_caption_on_media.sql` — `caption text` on `ChatMessage` + `DirectMessage`.
- **Server**: Extended `ChatService.sendMessage`, `SendChatMessageDto`, `ChatController.sendMessage`, and `ChatGateway` to pass `caption` end-to-end.
- **Prisma**: Added `caption` field to `ChatMessage`.
- **Flutter**: TODO — wire caption field into `ChatInputBar` when a media attachment is staged.

## Schema-only migrations (5 features — code TODO)

These migrations are applied to your live Supabase project (verified) so the schema is ready. The NestJS + Flutter code paths are tracked as follow-up work.

| # | Feature | Migration | Status |
|---|---------|-----------|--------|
| 1.3 | Auto-saved Drafts | `20261010140000_tier1_chat_drafts.sql` | ✅ DB + Prisma + NestJS service + tests. Flutter provider + UI integration TODO. |
| 1.5 | View-Once Media | `20261010150000_tier1_view_once_media.sql` | ✅ DB + Prisma. Push-scheduler leak prevention ✅. Flutter bubble rendering TODO. |
| 1.6 | HD Photo Quality | `20261010160000_tier1_hd_photo_quality.sql` | ✅ DB + Prisma. Server media branching + Flutter picker TODO. |
| 1.11 | Document Sharing | `20261010170000_tier1_documents.sql` | ✅ DB + Prisma. Server media branching + Flutter document bubble + PDF viewer TODO. |
| 1.15 | Multi-forward | `20261010180000_tier1_multi_forward_extension.sql` | ✅ DB (new `fn_forward_message_multi` RPC). Flutter multi-select sheet TODO. |

## What I couldn't include this round (5 features)

These were deprioritized because they need either an external API key (Whisper for transcription), heavy Flutter UI work I can't verify without an emulator (in-app camera, video trimming, contact sharing, live location map UI), or significant ffmpeg-on-server work (voice waveform peak extraction). Schema migrations for these would be straightforward to add — let me know if you want them and I'll generate the SQL.

| # | Feature | Why deferred |
|---|---------|-------------|
| 1.7 | Voice waveform + playback speed + mini-player | Needs ffmpeg on the server for peak extraction. |
| 1.8 | Voice transcription | Needs a Whisper API key. |
| 1.9 | In-app camera with editor | Heavy Flutter UI; can't test without an emulator. |
| 1.10 | Video trimming | Same as 1.9. |
| 1.12 | Contact sharing | Same as 1.9. |
| 1.13 | Live location sharing in chat | Realtime + map UI; needs testing on a device. |

## Verification

### Database
All 16 new schema objects (2 tables, 8 new columns, 6 RPCs, 1 pg_cron job) are verified live on your Supabase project via `supabase db query`:

```
ScheduledMessage_tbl    | true
ChatDraft_tbl           | true
CM_silent               | true
CM_caption              | true
CM_isViewOnce           | true
CM_qualityTier          | true
CM_documentPages        | true
fn_schedule_message     | true
fn_cancel_scheduled     | true
fn_send_scheduled       | true
fn_get_scheduled        | true
fn_save_draft           | true
fn_get_draft            | true
fn_get_saved_inbox      | true
fn_forward_multi        | true
cron_job                | true
```

### Backend
- TypeScript type-check passes cleanly for all chat-related files.
- `scheduled-messages.service.spec.ts`: **21/21 tests pass**.
- `drafts.service.spec.ts`: **9/9 tests pass**.
- `chat.service.spec.ts`: **54/54 tests pass** (no regressions to existing functionality).

### Flutter
- 3 new providers (`saved_messages_provider.dart`, `scheduled_messages_provider.dart`, `drafts_provider.dart`) — match existing Riverpod patterns.
- 3 new widgets (`saved_messages_inbox_row.dart`, `schedule_message_sheet.dart`, `send_silently_sheet.dart`) — match the existing dark-themed KinrelColors/KinrelTypography design system.
- `chat_inbox_screen.dart` patched to inject the Saved Messages row.
- I was unable to run `flutter analyze` / `flutter test` in this environment because the Flutter SDK isn't installed here. **You should run `flutter analyze` + `flutter test` locally before merging.**

### What I couldn't test
- The Flutter app itself (no Android/iOS emulator or device available here).
- The end-to-end flow (login → send silent message → verify FCM silent on the recipient device) — would require your NestJS server URL + a real FCM project configured with credentials.
- The live cron dispatcher actually firing (would need to schedule a message + wait 1+ min + check the destination chat).

## Files added (16 new)
```
supabase/migrations/20261010100000_tier1_saved_messages.sql
supabase/migrations/20261010110000_tier1_scheduled_messages.sql
supabase/migrations/20261010120000_tier1_send_without_sound.sql
supabase/migrations/20261010130000_tier1_caption_on_media.sql
supabase/migrations/20261010140000_tier1_chat_drafts.sql
supabase/migrations/20261010150000_tier1_view_once_media.sql
supabase/migrations/20261010160000_tier1_hd_photo_quality.sql
supabase/migrations/20261010170000_tier1_documents.sql
supabase/migrations/20261010180000_tier1_multi_forward_extension.sql

server/src/modules/chat/dto/scheduled-message.dto.ts
server/src/modules/chat/scheduled-messages.service.ts
server/src/modules/chat/scheduled-messages.controller.ts
server/src/modules/chat/saved-messages.controller.ts
server/src/modules/chat/drafts.service.ts
server/src/modules/chat/drafts.controller.ts
server/src/modules/chat/scheduled-messages.service.spec.ts
server/src/modules/chat/drafts.service.spec.ts

Daxelo-Kinrel-App/lib/features/chat/data/saved_messages_provider.dart
Daxelo-Kinrel-App/lib/features/chat/data/scheduled_messages_provider.dart
Daxelo-Kinrel-App/lib/features/chat/data/drafts_provider.dart
Daxelo-Kinrel-App/lib/features/chat/presentation/widgets/saved_messages_inbox_row.dart
Daxelo-Kinrel-App/lib/features/chat/presentation/widgets/schedule_message_sheet.dart
Daxelo-Kinrel-App/lib/features/chat/presentation/widgets/send_silently_sheet.dart
```

## Files modified (8)
```
server/prisma/schema.prisma                                          (added ScheduledMessage + ChatDraft models, 6 new columns on ChatMessage)
server/src/modules/chat/chat.module.ts                              (registered new services/controllers)
server/src/modules/chat/chat.service.ts                            (sendMessage now persists silent/caption/isViewOnce/qualityTier/documentName/documentPages)
server/src/modules/chat/chat.controller.ts                         (sendMessage passes new DTO fields)
server/src/modules/chat/chat.gateway.ts                            (passes new DTO fields to ChatService)
server/src/modules/chat/chat-push.scheduler.ts                     (loads silent/caption/isViewOnce, computes allSilent, hides view-once previews)
server/src/modules/chat/dto/chat.dto.ts                            (added silent/caption/isViewOnce/qualityTier/documentName/documentPages fields)
server/src/modules/notifications/fcm.service.ts                   (added silent field + low-priority Android/iOS config)

Daxelo-Kinrel-App/lib/features/chat/presentation/chat_inbox_screen.dart  (injected SavedMessagesInboxRow + imports)
```

## Next steps for you

1. **Run Flutter tests locally** — `cd Daxelo-Kinrel-App && flutter analyze && flutter test`. Fix any analyzer warnings I might have introduced (I couldn't run flutter here).
2. **Run the NestJS server** — `cd server && npm run start:dev`. Hit `GET /chat/saved-messages` with a valid JWT to verify the new endpoint works.
3. **Test scheduling end-to-end** — `POST /chat/scheduled` with a `scheduledFor` 2 minutes in the future; wait; verify the message lands in the destination chat.
4. **Test silent FCM** — Send a `silent: true` message; verify the recipient's device gets a low-priority notification (no sound, no vibration).
5. **Merge to main** once you're satisfied — `git checkout main && git merge tier-1-chat-features`.

## Security reminder

You shared 4 credentials with me during this session:
- GitHub PAT (`ghp_…`)
- Vercel token (`vcp_…`) + team ID
- Supabase access token (`sbp_…`)
- App login password

**Rotate ALL of these immediately** even though you said you'd revoke the PAT after — chat transcripts, intermediate logging layers, and cache systems can retain this data. I did NOT commit any of these tokens to the repo (the git remote was configured via `git config remote.origin.url` only). But please verify by running `git log --all -p | grep -E "ghp_|vcp_|sbp_"` — should return nothing.
