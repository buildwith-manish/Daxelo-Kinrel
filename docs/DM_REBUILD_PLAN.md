# DM Rebuild Plan — Direct Chat → Private 2-Person Group

**Branch:** `feat/kin-thread`
**Date:** 2026-10-10 (updated after the C1 migration rewrite)
**Flags:** `RUN_DM_REBUILD = YES` | `BACKFILL_OLD_DMS = NO`

> Correction vs the first draft: the groups tables are **`"Group"` and
> `"GroupMember"`** (created in `20260813000000_create_family_groups.sql`).
> `Group.name`, `GroupMember.displayName`, `Group.groupType` (documented
> values `cousins|parents|siblings|family_event|travel|custom`, **no CHECK
> constraint**). The first draft wrongly put `groupType`/`directKey` on
> `"Family"` and used `"FamilyMember"` rows as the "group members"; that
> design is scrapped. The migration file
> `20261101120000_dm_rebuild_direct_groups.sql` was rewritten to the real
> Group design.

## C0 — Audit + Safety Gate (read-only)

### STOP ITEM 1: Privacy — ChatMessage RLS with groupId

**Finding:** The LIVE ChatMessage policies (replaced in
`20260813000000`) are:

```sql
CREATE POLICY chatmessage_select_policy ON "ChatMessage"
    FOR SELECT USING (
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        OR ("groupId" IS NOT NULL AND fn_user_is_group_member("groupId")) );
```

`fn_user_is_group_member(group_id)` passes for a **GroupMember row OR any
FamilyMember of the group's family** (second branch). For a direct group
that lives inside a real family, every family member would pass — i.e.
**the whole family could read the direct chat**.

**Verdict:** ⛔ **STOP — privacy fix required.**

**Fix (inside the C1 migration, smallest possible):** a new
`fn_user_can_access_group_chat(group_id)` helper that is strict
(GroupMember rows only) **only for `groupType='direct'` groups** and
delegates to `fn_user_is_group_member` for every other group. The
ChatMessage (select/insert/update), `GroupMember` (select),
`Group` (select), `ChatMessageReaction` (select/insert) and
`ChatReadReceipt` (select/insert) policies are recreated with it. Family
-wide chat (`groupId IS NULL`) and existing groups keep EXACTLY their
previous visibility.

### STOP ITEM 2: Notifications for new ChatMessage rows

**Finding (every notifier path):**
1. **No DB trigger** creates notifications on ChatMessage inserts.
2. Push + in-app notifications are produced by the **NestJS
   ChatPushScheduler** (`server/src/modules/chat/chat-push.scheduler.ts`,
   cron every 5 min): it batches `ChatMessage` rows with `notified=false`
   and resolves recipients via **`FamilyMember` on `msg.familyId`** — it
   never reads `groupId`, so it would notify the whole family about a
   direct-group message.
3. RPC-level notifications (`fn_send_thinking_of_you`,
   `fn_accept_graph_invitation`) insert into `"Notification"` directly —
   the rewritten `fn_send_thinking_of_you` targets only the receiver.
4. Edge functions: none touch chat notifications (8 functions, all
   games/push-utilities).

**Verdict:** ⛔ **STOP — notification fix required (NestJS code, not SQL).**

**Fix (described exactly; server/ is not modified in this PR since C1 is
SQL+docs and C2 is Dart only):** in `chat-push.scheduler.ts`, branch the
recipient resolution on `msg.groupId`:

```ts
const members = msg.groupId != null
  ? await this.prisma.groupMember.findMany({
      where: { groupId: msg.groupId },
      select: { userId: true },
    })
  : await this.prisma.familyMember.findMany({
      where: { familyId: msg.familyId },
      select: { userId: true },
    });
```

(Sender-skip, readBy-skip, mute and quiet-hours logic stay unchanged.)

### 3. Family-wide queries never return group-scoped rows

**Finding:** `ChatNotifier._loadMessages()` selects by `familyId` only;
the SCREEN then filters client-side — family-wide chat shows
`groupId == null` rows only, group chat shows `groupId == widget.groupId`
(`chat_screen.dart`). Realtime subscriptions filter by `familyId`
(not groupId), but the same client-side filter applies before rendering,
so no group-scoped row ever renders in the family chat.

**Verdict:** ✅ Safe — behavior preserved. (Documented nuance: the
subscription itself is family-wide; extra events are filtered client-
side — same as existing group chats today.)

### 4. Every place that reads or writes DirectMessage / direct chat

**Dart (app):**
- `lib/features/chat/data/direct_message_provider.dart` — `DirectChatNotifier`, `DmInboxItem`, `sendGameInviteDm`, `fn_sync_dm_game_invites` caller
- `lib/features/chat/data/direct_message_adapter.dart` — DirectMessage → ChatMessage adapter (`directChatMessagesProvider`)
- `lib/features/chat/presentation/direct_chat_screen.dart` — the DM screen
- `lib/features/chat/presentation/chat_inbox_screen.dart` — DM inbox rows + member suggestions
- `lib/features/chat/presentation/archived_chats_screen.dart` — archived DM rows
- `lib/features/family/presentation/family_chat_list_screen.dart` — Direct tab (partners list)
- `lib/features/thinking/data/thinking_service.dart` — `fn_send_thinking_of_you` caller (signature unchanged → no change needed)
- `lib/features/thinking/presentation/family_ring_widget.dart` — DM entry point ×2
- `lib/features/games/shared/data/game_invite_chat_sync.dart` — DM leg (`fn_sync_dm_game_invites` RPC)
- `lib/features/games/shared/widgets/invite_family_sheet.dart` — `sendGameInviteDm` callers (single + multi invite)
- `lib/features/notifications/presentation/notifications_screen.dart` — notification tap → `/dm/:id`
- `lib/core/services/notification_reply_handler.dart` — DM notification replies
- `lib/core/services/local_notification_service.dart` — DM vs family routing
- `lib/core/routing/app_router.dart` — `/dm/:otherUserId` route
- `lib/features/profile/presentation/member_profile_sheet.dart` — message button
- `lib/graph/widgets/graph_quick_actions.dart` — graph "Message" action → `/dm/$linkedUserId` (**graph code is off-limits** → handled via the `/dm/:otherUserId` route redirect instead of editing the graph)

**Tests:** `test/features/chat/dm_game_invite_adapter_test.dart` (DM adapter — deleted with the adapter).

**SQL:** `fn_send_thinking_of_you` (rewritten in C1), `fn_forward_message`
DM variant (tier-1, unmerged), `fn_sync_dm_game_invites` (stays — old rows
keep syncing, but nothing calls it after C2).

**Edge functions:** none. **NestJS server:** zero DirectMessage references
(DMs were Supabase-RPC + Flutter only).

### 5. Group-only things shown in group chat (HIDDEN in direct chat)

Group info screen (members/add/leave/invite link), admin roles + admin
actions, mentions picker, Family chip, sender names + avatars,
relationship pills + 3px rails, read-by list (normal ticks stay), group
name/photo editing.

KEEP everything else: reply, swipe-to-reply, reactions, selection mode
with Forward/Delete/Star/Pin/Edit/Copy/Share, photos, files, voice
notes, stickers, GIFs, polls, location, search, wallpapers (incl. the
new Constellation preset), game invites with the same lifecycle, the
unread divider, the floating date chip, and system notices.

Reported deviations (documented, not silently dropped):
- **Typing indicator:** `ChatTypingStatus` is family-scoped
  (`UNIQUE("familyId","userId")`, no groupId column), so a private typing
  signal would leak into the family chat. Direct chats therefore do not
  write typing status (the indicator won't trigger there). A private
  mechanism needs a follow-up (scoped typing table).
- **Disappearing messages:** `fn_set_disappearing_messages` is
  family-scoped; the menu entry stays available but affects the family
  chat's settings (noted in the PR).

### 6. Design: direct chat via directKey

- `Group.directKey text` = the two user ids sorted + joined with `_`
  (nullable; unique partial index `WHERE directKey IS NOT NULL`).
- `groupType = 'direct'` (no CHECK constraint exists, so no constraint
  change; documented values extended by comment).
- `Group.name = 'Direct'` (neutral — the app always shows the other
  person); two `GroupMember` rows with each user's display name.
- The direct group lives in **a family both users belong to** — the
  family it was started from, or the oldest shared family when unknown
  (the RPC resolves it when `p_family_id` is null). **No shared family →
  no message button** (`no_shared_family` error).
- Direct groups never appear in group lists (app-side
  `groupType <> 'direct'` filters in `group_provider` + inbox) and their
  `Group`/`GroupMember` rows are RLS-hidden from other family members.

## C1 — SQL Migration (additive + idempotent; this branch, NOT merged)

**File:** `supabase/migrations/20261101120000_dm_rebuild_direct_groups.sql`
(timestamp later than every existing migration).

Contents:
1. `Group.directKey` + unique partial index + `GroupMember.userId` index.
2. `fn_user_can_access_group_chat` + the strict policy set (STOP ITEM 1).
3. `fn_get_or_create_direct_group(other_user_id, family_id)` —
   SECURITY DEFINER house style, self-chat rejection, shared-family
   resolution, directKey lookup, Group + 2 GroupMember creation.
4. Rewritten `fn_send_thinking_of_you` — same cooldowns/templates,
   inserts a ChatMessage (familyEvent + thinking_of_you) into the direct
   group, correct `"Notification"` columns (eventType/channels/priority/
   read/actionUrl — the first draft used non-existent columns).
5. Verification SELECTs.

**Proof file:** `supabase/manual/dm_privacy_proof.sql` — run as user A,
B and a third family member C; every C query must return 0 rows (or a
policy violation).

**Safe apply order:** backup → migration → verification SELECTs →
privacy proof → deploy C2 Dart → apply the NestJS scheduler snippet.

**Rollback:** see the migration header (functions, policies, direct
groups + their cascade-deleted messages, index, column).

## C2 — Dart Rewrite (depends on C1 being applied to the database)

**New:** `direct_group_service.dart` (`openDirectChat` helper +
`getOrCreateDirectGroup` RPC wrapper + `directGroupInboxProvider`),
route `/family/:id/direct/:otherUserId` (DirectChatEntryScreen), and the
legacy `/dm/:otherUserId` route kept as a redirect.

**ChatScreen** gains `isDirectChat` + `directOtherUserId` (hides
group-only UI; header shows the other person's name/avatar with the
relationship or online status as subtitle; wallpaper keyed
`dm_<otherUserId>` so existing saved DM wallpapers keep working).

**Deleted:** `direct_chat_screen.dart`, `direct_message_provider.dart`,
`direct_message_adapter.dart`, DM-only tests, `sendGameInviteDm`, the DM
leg of `game_invite_chat_sync.dart`, and DM inbox items. **NOT deleted:**
the `DirectMessage` table or any SQL.

**Game invites:** `invite_family_sheet` single/multi invites now go
through `ChatNotifier.sendGameInvite(groupId: <direct group id>)` — the
same code path, card, and lifecycle sync as the group chat.
