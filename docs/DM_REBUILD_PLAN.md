# DM Rebuild Plan — Direct Chat → Private 2-Person Group

**Branch:** `feat/kin-thread`
**Date:** 2026-10-10
**Flags:** `RUN_DM_REBUILD = YES` | `BACKFILL_OLD_DMS = NO`

## C0 — Audit + Safety Gate (read-only)

### STOP ITEM 1: Privacy — ChatMessage RLS with groupId

**Finding:** ChatMessage's SELECT policy is:
```sql
CREATE POLICY chatmessage_select_policy ON "ChatMessage"
    FOR SELECT USING (fn_user_is_family_member("familyId"));
```

This means **ANY family member can read ALL ChatMessage rows** in that family,
including messages with a `groupId` set (which would be direct-chat-scoped rows).

**Verdict:** ⛔ **STOP — privacy fix required.**

**Proposed fix (in the C1 migration):**
Add a new RLS policy that scopes group-scoped messages to only the two group members:
```sql
-- New policy: group-scoped messages only readable by group members
CREATE POLICY chatmessage_select_group_scoped ON "ChatMessage"
    FOR SELECT USING (
        "groupId" IS NULL  -- family-wide chat: all family members can read
        OR EXISTS (
            SELECT 1 FROM "GroupMember" gm
            WHERE gm."groupId" = "ChatMessage"."groupId"
              AND gm."userId" = auth.uid()::text
        )
    );
-- Drop the old policy (or make it apply only to groupId IS NULL).
```

This preserves family-wide chat (groupId NULL) visibility while restricting
group-scoped (direct) messages to the two participants.

### STOP ITEM 2: Notifications — triggers that notify for new ChatMessage

**Finding:** The ChatMessage table has these triggers:
1. `trg_chatmessage_set_updated_at` — sets updatedAt on UPDATE (no notification)
2. `trg_chatmessage_gen_id` — generates message ID on INSERT (no notification)
3. `trg_chatmessage_mark_read` — on ChatReadReceipt INSERT, updates readBy (no notification)

Push notifications are sent by the **NestJS server** (ChatPushScheduler), not
by DB triggers. The server queries `ChatMessage` rows where `notified=false`
and sends FCM pushes to family members.

**For direct groups:** the NestJS server currently pushes to ALL family members
(not just the two group members). This would leak the existence of a direct
message to other family members via the push notification.

**Verdict:** ⛔ **STOP — notification fix required.**

**Proposed fix (in the C1 migration + NestJS code):**
The NestJS `ChatPushScheduler` needs to check `groupId` on each message and
only push to the two `GroupMember` rows for that group (not all family members).
This is a NestJS code change, not a SQL change — but the C1 migration should
document the requirement.

### 3. Family-wide chat queries (groupId NULL) never return group-scoped rows

**Finding:** The current queries in `ChatNotifier._loadMessages()` fetch all
ChatMessage rows where `familyId = X` (no groupId filter). After the DM
rebuild, these queries must filter: `groupId IS NULL` for family-wide chat
and `groupId = Y` for direct chats.

**Verdict:** ✅ **Safe — this is a Dart code change (C2), not a SQL change.**
The C2 PR must update every query that loads ChatMessage to filter by groupId.

### 4. Every place that reads or writes DirectMessage or direct chat

**Dart files (188 references found):**
- `lib/features/chat/data/direct_message_provider.dart` — DirectChatNotifier
- `lib/features/chat/data/direct_message_adapter.dart` — converts DirectMessage → ChatMessage
- `lib/features/chat/presentation/direct_chat_screen.dart` — the DM screen
- `lib/features/chat/presentation/chat_inbox_screen.dart` — DM inbox section
- `lib/features/thinking/data/thinking_service.dart` — fn_send_thinking_of_you
- `lib/features/games/shared/data/game_invite_chat_sync.dart` — DM game invite sync
- `lib/features/games/shared/widgets/invite_family_sheet.dart` — DM invite flow
- `lib/features/chat/providers/chat_provider.dart` — sendGameInviteDm + system message inserts
- `lib/core/routing/app_router.dart` — `/dm/:otherUserId` route
- `lib/core/services/notification_reply_handler.dart` — DM notification reply
- `lib/core/services/local_notification_service.dart` — DM vs family routing

**SQL functions:**
- `fn_send_thinking_of_you(p_receiver_id, p_family_id)` — currently inserts a DirectMessage row.
  Must be rewritten to insert a ChatMessage into the direct group.

**Edge functions:** None found that directly reference DirectMessage.

### 5. Group-only things shown in group chat (to be HIDDEN in direct chat)

After C2, direct chat should use the SAME group chat screen + provider but
hide these UI elements:
- Group info screen (member list, add member, leave, invite link)
- Admin roles + admin actions
- Mentions picker (no @mentions in 1:1)
- Family chip (the "Family" relationship label in the header)
- Sender name label + avatar (both participants know who sent each message)
- Relationship pills + rails (the 3px left band)
- Read-by list (keep normal read ticks, but not the "Read by" sheet)
- Group name + photo editing

**Keep everything else:** reply, swipe-to-reply, reactions, selection mode,
Forward/Delete/Star/Pin/Edit/Copy/Share, photos, files, voice notes, stickers,
GIFs, polls, location, search, wallpapers, disappearing messages, typing
indicator, game invites.

### 6. Design: direct chat via directKey

**Table changes (C1 migration):**
- Add `directKey text` to `Group` (or `Family` if groups use that table).
  `directKey` = the two user IDs sorted + joined (e.g. `"userA_userB"`).
- Add a UNIQUE INDEX on `directKey WHERE directKey IS NOT NULL`.
- Add `groupType text DEFAULT 'family'` if not already present
  (valid values: 'family', 'group', 'direct').
- The `get_or_create_direct_group` RPC verifies both users are in the
  same family, creates the Group + 2 GroupMember rows if needed, returns
  the groupId.

**Inbox:** Direct groups appear as person rows (other user's name, avatar,
last message, unread count). Excluded from every group list.

**No shared family → no message button:** If the two users share no family,
direct chat is not available (the message button is hidden).

## C1 — SQL Migration Plan (additive, idempotent, not to be merged)

**Migration file:** `supabase/migrations/20261101120000_dm_rebuild_direct_groups.sql`

**Contents:**
1. ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "groupType" text DEFAULT 'family';
2. ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "directKey" text;
3. CREATE UNIQUE INDEX IF NOT EXISTS "Family_directKey_uniq" ON "Family"("directKey") WHERE "directKey" IS NOT NULL;
4. New RLS policy for group-scoped ChatMessage (STOP ITEM 1 fix).
5. `get_or_create_direct_group(other_user_id, family_id)` RPC.
6. Rewrite `fn_send_thinking_of_you` to insert ChatMessage into direct group.
7. Verification queries at the end.
8. SQL proof file: `supabase/manual/dm_privacy_proof.sql` — queries a user
   can run as two DM participants + a third family member to prove the third
   cannot see the direct chat.

**Safe apply order:**
1. Back up the database first.
2. Apply the migration.
3. Run the verification SELECTs.
4. Apply the C2 Dart changes (separate branch).
5. Test with two users.

**Rollback steps:**
1. `DROP FUNCTION IF EXISTS get_or_create_direct_group;`
2. `DROP FUNCTION IF EXISTS fn_send_thinking_of_you;` (re-run the old definition)
3. `DROP INDEX IF EXISTS "Family_directKey_uniq";`
4. `ALTER TABLE "Family" DROP COLUMN IF EXISTS "directKey";`
5. `ALTER TABLE "Family" DROP COLUMN IF EXISTS "groupType";`
6. Restore the old ChatMessage RLS policy.

## C2 — Dart Rewrite Plan (depends on C1 being applied)

**Branch:** `feat/dm-app` from `main` (but all work goes to `feat/kin-thread`)

**New helper:** `openDirectChat(otherUserId, familyId)` — calls
`get_or_create_direct_group`, opens the group chat screen with `isDirect`
derived from groupType.

**Files to DELETE (after C2 is verified working):**
- `lib/features/chat/presentation/direct_chat_screen.dart`
- `lib/features/chat/data/direct_message_provider.dart`
- `lib/features/chat/data/direct_message_adapter.dart`
- DM-only models, inbox items, routes, tests
- `sendGameInviteDm` method + DM-only invite card code

**Files to UPDATE:**
- `lib/core/routing/app_router.dart` — replace `/dm/:otherUserId` with the
  group chat route + a redirect for old DM routes.
- `lib/features/chat/presentation/chat_inbox_screen.dart` — show direct
  groups as person rows, exclude from group lists.
- `lib/features/thinking/data/thinking_service.dart` — call the rewritten
  `fn_send_thinking_of_you`.
- `lib/features/games/shared/data/game_invite_chat_sync.dart` — use the
  direct groupId for game invites.
- `lib/features/games/shared/widgets/invite_family_sheet.dart` — use
  `openDirectChat` instead of `sendGameInviteDm`.
- `lib/features/chat/providers/chat_provider.dart` — load messages filtered
  by groupId (null for family-wide, groupId for direct).
- `lib/core/services/notification_reply_handler.dart` — route to the
  direct group instead of DM.
- `lib/core/services/local_notification_service.dart` — DM vs family routing.

**Do NOT delete:**
- The `DirectMessage` table (keep it for historical data).
- Any SQL migration files.

## Summary

| STOP Item | Status | Fix Location |
|-----------|--------|--------------|
| 1. Privacy (ChatMessage RLS) | ⛔ STOP | C1 migration (new RLS policy) |
| 2. Notifications (push to all family members) | ⛔ STOP | C1 migration (document) + NestJS code |
| 3. Family-wide queries | ✅ Safe | C2 Dart (filter by groupId) |
| 4. DM entry points | ✅ 188 references found | C2 Dart (rewrite all) |
| 5. Group-only UI | ✅ Design ready | C2 Dart (hide in direct chat) |
| 6. DirectKey design | ✅ Design ready | C1 SQL + C2 Dart |
