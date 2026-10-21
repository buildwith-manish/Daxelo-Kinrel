# Phase A — @mentions across chat: deploy order

This doc explains the deploy order for the Phase A @mentions feature.
Read it before running any of the migrations or pushing any of the code.

## TL;DR deploy order

1. **Migration first** (Supabase SQL)
2. **Server second** (NestJS)
3. **App third** (Flutter)

Each step is independently backward-compatible. You can stop after any
step and the previous code keeps working.

---

## Step 1: Supabase migration (apply on staging first)

Migration file: `supabase/migrations/20261021051801_chat_mention_notify_and_group.sql`

### What it adds

| Table                     | Column                | Type        | Default | Notes                                           |
| ------------------------- | --------------------- | ----------- | ------- | ----------------------------------------------- |
| `ChatMention`             | `groupId`             | text        | NULL    | Scopes a mention to a group/DM chat (NULL = family-wide). |
| `ChatMention`             | `notify`              | boolean     | `true`  | Server-derived from conversation type (group→true, DM→false). |
| `ChatMention`             | `notifiedAt`          | timestamptz | NULL    | NULL = pending push; non-NULL = pushed.        |
| `ChatMention`             | `isRead`              | boolean     | `false` | Flipped when the recipient opens the chat.     |
| `NotificationPreference`  | `mentionsBreakMute`   | boolean     | `true`  | When `true`, mentions push even in muted chats. |

### Indexes added (all partial — small + fast)

- `idx_chatmention_recipient_unread` on `("mentionedUserId") WHERE "isRead" = false`
- `idx_chatmention_group` on `("groupId", "mentionedUserId") WHERE "groupId" IS NOT NULL`
- `idx_chatmention_message` on `("messageId")` (safety re-add)

### Why it's safe

- All columns are nullable or have `NOT NULL DEFAULT` — existing rows
  survive. Old code paths that don't write the new columns keep
  working (Postgres fills in the default).
- The Prisma schema (`server/prisma/schema.prisma`) already declares
  these columns. Apply the migration BEFORE deploying the server so
  the Prisma queries that reference the new columns don't fail at
  runtime.

### How to apply

Use the Supabase Management API (the user's PAT-driven flow), not the
service key. Apply on staging, smoke-test, then apply on production.

```bash
curl -sS -X POST "https://api.supabase.com/v1/projects/<ref>/database/query" \
  -H "Authorization: Bearer <supabase-access-token>" \
  -H "Content-Type: application/json" \
  --data @<(jq -Rs '{query: .}' < supabase/migrations/20261021051801_chat_mention_notify_and_group.sql)
```

### Smoke test post-apply

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'ChatMention'
ORDER BY ordinal_position;

SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'NotificationPreference'
  AND column_name = 'mentionsBreakMute';

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'ChatMention'
ORDER BY indexname;
```

---

## Step 2: Server deploy (NestJS)

Modified files:
- `server/src/modules/chat/chat.service.ts` — `sendMessageWithMentions` rewritten with: dedupe, cap-reject (5), notify derivation from conversation type, batched membership validation, skip DM references from ChatMention row creation.
- `server/src/modules/chat/chat.gateway.ts` — fixed the `chat:mentionReceived` leak: now uses `kinrelGateway.emitToUser(mentionedUserId, ...)` (was broadcasting to the family room with message content). Passes `groupId` through to the service so the persisted ChatMessage row is scoped.
- `server/src/modules/chat/chat-mention.push.scheduler.ts` — NEW. Per-event 7s batch window per recipient, skip-if-online, mute-aware (with `mentionsBreakMute` override), quiet-hours-aware, cron retry every 30s.
- `server/src/modules/chat/chat.module.ts` — imports `GatewayModule` (for `KinrelGateway.emitToUser`) + registers the new `ChatMentionPushScheduler`.
- `server/src/modules/gateway/kinrel.gateway.ts` — added `isUserConnected(userId)` helper used by the new push scheduler.

### Verification

```bash
cd server
./node_modules/.bin/tsc --noEmit
# Expect: 0 errors in chat/* files (5 pre-existing errors in
# predictions.scheduler.ts are unrelated — see conversation worklog).
```

### Server-side tests

`chat.service.spec.ts` should be extended with:
- `sendMessageWithMentions` rejects >5 mentions (BadRequest)
- `sendMessageWithMentions` rejects non-family-member mentions (Forbidden)
- `sendMessageWithMentions` rejects non-group-member mentions when groupId set (Forbidden)
- `sendMessageWithMentions` dedupes by userId (4 mentions of the same user → 1 ChatMention row)
- `sendMessageWithMentions` derives notify=false for direct chats (no ChatMention rows written)
- `sendMessageWithMentions` derives notify=true for family-wide chat

**Deferred**: these tests are Phase A.5 scope. The core path is wired
and typechecks; the test extension is the next commit.

---

## Step 3: App deploy (Flutter)

Modified files:
- `Daxelo-Kinrel-App/lib/features/chat/data/mention_candidates_provider.dart` — NEW. `MentionCandidate` data type + `mentionCandidatesProvider` (autoDispose family). Filters: linkedUserId-required, self-excluded, blocked-excluded, group-scoped. Warmed on chat open.
- `Daxelo-Kinrel-App/lib/features/chat/presentation/widgets/mention_picker.dart` — rewritten. `MentionPickerOverlay` is now a `StatefulWidget` watching `ValueNotifier<String>` query + `ValueNotifier<AsyncValue<List<MentionCandidate>>>` candidates — list narrows per keystroke (post-150ms-debounce, post-IME-composition). Rows: avatar + kinship term bold + name muted + relation line. Loading/error/empty states all visible (no silent `SizedBox.shrink`). Keyboard: Arrow/Enter/Tab/Esc. Accessibility: 44dp tap targets, 12sp min text, 4.5:1 contrast, 1.5x text scale, RTL-aware, reduced-motion. `MentionTracker` rewritten to be grapheme-cluster-aware (`characters` package) — backspace deletes whole mention cluster, edits before a mention shift offsets correctly. `MentionableMember` kept as a compatibility adapter so existing call sites still compile.
- `Daxelo-Kinrel-App/lib/features/chat/presentation/chat_screen.dart` — surgical edits: warm `mentionCandidatesProvider` in initState, publish query+candidates to ValueNotifiers, dispose cleanup. The overlay is built ONCE per picker session; updates flow through the ValueNotifiers (no more `markNeedsBuild`).
- `Daxelo-Kinrel-App/lib/features/chat/presentation/widgets/chat_input_bar.dart` — dropped the "(group only)" doc comment on `inputLayerLink`.

### Verification

```bash
cd Daxelo-Kinrel-App
flutter analyze lib/features/chat/data/mention_candidates_provider.dart \
                 lib/features/chat/presentation/widgets/mention_picker.dart \
                 lib/features/chat/presentation/chat_screen.dart \
                 lib/features/chat/presentation/widgets/chat_input_bar.dart
# Expect: 0 errors, 0 new warnings. (Pre-existing info-level lints
# in chat_screen.dart far from the Phase A edits are unchanged.)
```

### Flutter widget tests

**Deferred**: Phase A.5 scope. Tests to write:
- `mention_picker_live_filter_test.dart` — typing narrows the list.
- `mention_picker_empty_state_test.dart` — loading / error / no-match rows render visibly.
- `mention_tracker_offset_test.dart` — Hindi text + emoji + backspace + paste.
- `mention_candidates_provider_test.dart` — group members only; self + blocked excluded; linkedUserId-required.

---

## Deferred items (Phase A.5 follow-up)

The following were scoped for Phase A but are deferred to a follow-up
"A.5" commit so this checkpoint stays reviewable:

1. **Chat-list `@` badge** (`unified_inbox_provider` + `unified_chat_row`) — count unread `ChatMention` per (familyId, groupId); render `@` chip next to the unread-count badge.
2. **"Mentions break mute" settings UI** (`settings_registry` row + `settings_category_screen` toggle) — reads/writes `NotificationPreference.mentionsBreakMute`. Migration column is in place; settings UI is the follow-up.
3. **Analytics events** — `mention_picker_opened`, `mention_selected`, `mention_notification_opened`. (`mention_sent` is already tracked in `chat.service.ts`.)
4. **Server-side tests** — extend `chat.service.spec.ts` with the 6 cases listed above.
5. **Flutter widget tests** — 4 files listed above.
6. **Full family-room leak fix** — the gateway still broadcasts `chat:messageReceived` to the family room for group/DM messages. The current Flutter app's mention path goes through Supabase RPC (not the gateway), so the leak is currently dormant. Fixing it requires joining clients to `chat:group:<groupId>` rooms in `chat:joinFamily` — a follow-up because it touches the join flow.
7. **SQL `fn_add_mentions_to_message` rewrite** — the Flutter app calls this RPC after inserting the message; if it exists, it should be updated to do the same validation as the new `chat.service.ts` path. If it doesn't exist, the call fails silently (the catch block logs + continues) and the server-side `ChatMention` rows are never written from that path. The NestJS gateway path writes them directly via Prisma. Decide whether to (a) ship a migration that creates/updates `fn_add_mentions_to_message`, or (b) have the Flutter app stop calling the RPC and rely on the gateway path. Either way is a follow-up.

---

## Rollback

If any step breaks production:

1. **App rollback** (Flutter): revert to the previous `sparq` commit. The server's new columns are unused by the old app — no breaking change.
2. **Server rollback** (NestJS): revert to the previous `sparq` commit. The Supabase migration is additive — old server code keeps working with the new columns present.
3. **Migration rollback**: write a `down` migration that drops the 4 new columns + the 3 new indexes. **Not provided here** because Phase A's deploy plan doesn't anticipate needing it — the columns are nullable/defaulted and the app tolerates their absence just as well.

---

## Acceptance checks for Phase A (the spec's acceptance list)

| Check                                                                                                 | Status       | Notes |
| ----------------------------------------------------------------------------------------------------- | ------------ | ----- |
| In a group chat, typing `@` shows the members of that group only, and the list narrows per keystroke. | ✅ wired      | `mentionCandidatesProvider` filters by `groupId` via GroupMember; `MentionPickerOverlay` is reactive (ValueNotifier-driven). |
| Typing `@mama` or `@mausi` finds the right relative in Hindi and English.                            | ✅ wired      | Search index uses `KinshipTerm.primary` (the native term in the viewer's language) + the name. Ranking: exact term match > term starts-with > name starts-with > term contains > name contains. |
| No silent states: loading, error, no-match each show a visible row.                                   | ✅ wired      | `_buildLoading` / `_buildError` / `_buildEmpty` all return a visible `_StatusRow` (was `SizedBox.shrink`). |
| In a DM, `@` shows other relatives with the "won't be notified" line; selecting one sends a reference chip and notifies nobody. | ⏳ Phase B  | Phase A still early-returns DMs at the picker trigger (preserved from the prior code). Phase B removes the early return + wires the `excludeUserIds` and the header line. |
| A mentioned group member gets one batched notification and an `@` badge.                              | ⚠️ partial   | Batched notification: wired (`ChatMentionPushScheduler`, 7s window per recipient). `@` badge: deferred to Phase A.5 (`unified_inbox_provider` + `unified_chat_row`). |
| Mention positions stay correct with Hindi text, emoji, deletions and pasted text. Old messages render exactly as before. | ✅ wired      | `MentionTracker` rewritten with `characters` package for grapheme-cluster awareness. `MentionText` is UNCHANGED — backward compat preserved. |
| Direct API calls cannot mention a non-member in a group or reference a non-family person in a DM.    | ✅ wired      | `ChatService.sendMessageWithMentions` validates family + group membership in one batched query per scope. |
| `flutter analyze` and server tests report no new issues; widget tests for live filtering, empty states, DM reference behavior and offset handling. | ⚠️ partial   | `flutter analyze`: 0 new issues (verified). Server tests: deferred to Phase A.5. Widget tests: deferred to Phase A.5. |
