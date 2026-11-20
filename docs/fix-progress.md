# Fix progress

Source of truth for the `fix/<ID>` task plan (see `daxelo-kinrel-fix-prompts-split.md`).
Status values: `not started` | `in progress (<resume note>)` | `done (merged <commit sha>)`.

## Repo findings from the 1a orientation pass (read before starting any task)

1. **There is no `main` branch on the remote.** Remote branches at the time of 1a:
   `feature-registry` (the default / `origin/HEAD`), `graph-layout`, `stability-fixes`.
   The Starter's "create `fix/<ID>` from `main`" and "merge to `main`" steps have no target
   until it is decided which branch plays the role of `main`. `fix/1a` was branched from
   `feature-registry` (commit `4e7d42bb`).
2. **CI does not run on `fix/*` branches.** `.github/workflows/ci.yml` triggers on push to
   `main`, `graph-layout`, `sparq`, `phase-**`, `wip/**`, `feat/**` and on PRs to
   `main`/`graph-layout`/`sparq`. `deploy-web.yml` triggers on push to `main` only.
   So polling Actions for a pushed `fix/<ID>` commit (Starter rule 8, Flutter tasks) will find
   nothing unless the branch is opened as a PR into one of those branches or the trigger list changes.
3. **The workflow is named `CI`, not `Flutter CI`.** Its jobs are `Flutter Analyze` and
   `Flutter Test` (plus backend/APK jobs). The Starter's "check the `Flutter CI` workflow's run"
   should read "the `CI` workflow's `Flutter Analyze` job".
4. **Server tooling in the sandbox:** `server/package-lock.json` is out of sync with
   `package.json` (`npm ci` fails: missing `date-fns@4.4.0`, `date-fns-tz@3.2.0`), and
   `prisma generate` (Prisma 5.9.3) fails in the sandbox because `binaries.prisma.sh` is blocked
   by the proxy. Without a generated client, `tsc --noEmit` reports 16 pre-existing errors
   (chat-push.scheduler.ts, chat.service.ts ~572/573/1171, graph.service.ts,
   predictions.scheduler.ts, support.service.ts). Compare against that baseline, or verify in CI.
5. **Schema scale:** `server/prisma/schema.prisma` has 151 models; `supabase/migrations/` has 339 files.

## Checklist

| ID | Status | Files it will touch / path check (verified against repo at 1a time) |
|---|---|---|
| 1a | in progress (file written and pushed on `fix/1a`; NOT merged because no `main` branch exists — merge once the target branch is decided, then flip this row to `done (merged <sha>)`) | `docs/fix-progress.md` (new) |
| 1b | in progress (code done on `stability-fixes` @ `15c39f90`, not merged; clean `tsc` unconfirmed in sandbox — see "Task 1b notes" below) | `server/src/modules/chat/chat.service.ts` (exists; `pinMessage`). Role model: `FamilyMember.role` string (`owner`/`admin`/`member`/`viewer`) in `schema.prisma`. |
| 1c | in progress (5 gaps fixed on `fix/1c`, NOT merged: no `main` branch exists and a clean `tsc` is unconfirmed in the sandbox; remaining read-path / follow-up items listed in "Task 1c notes") | `server/src/modules/chat/chat.service.ts`, `chat.gateway.ts`, `server/src/modules/circle/circle.service.ts` |
| 1d | in progress (done on `fix/1d`, based on `fix/1c`; NOT merged: no `main` branch, clean `tsc` unconfirmed in sandbox) | `server/src/modules/chat/chat.service.ts` (`getMentionsForUser`). Not in the original 1a-7c table; added at the user's request. |
| 1e | in progress (done on `fix/1e`, based on `fix/1d`; NOT merged: no `main` branch, clean `tsc` unconfirmed in sandbox) | `server/src/modules/chat/chat.service.ts` (`listMessages`, `getPinnedMessages`, `searchMessages`, new private `resolveChatScope`). Not in the original 1a-7c table; added at the user's request. |
| 1f | in progress (done on `fix/1f`, based on `fix/1e`; NOT merged: no `main` branch, local `tsc` impossible without Prisma client — see "Task 1f notes" for CI status) | `server/src/modules/chat/chat.controller.ts`, `chat.service.ts` (`getStreak`, new `getReactionCountsForMember`), `chat.service.spec.ts`. Not in the original 1a-7c table; added at the user's request. |
| 2a | not started | `server/prisma/schema.prisma` (Story: no `audience`/`thumbnailUrl` yet) + new `supabase/migrations/*.sql`. Existing visibility patterns to check: `SparqAudience` enum, `FamilyMember.role`. TODOs in `stories.service.ts` still at lines 165 and 394. |
| 2b | not started | `server/src/modules/stories/stories.service.ts` (exists, 449 lines; TODOs at 165, 394) |
| 3a | not started | `server/prisma/schema.prisma` (ShareableLink: no `userId`; has optional `familyId`, `personId`) + new `supabase/migrations/*.sql` |
| 3b | not started | `server/src/modules/share/share.service.ts` (exists, 296 lines; TODOs still at 35, 236, 248, 266, 270) |
| 4a | not started | `server/prisma/schema.prisma` + new `supabase/migrations/*.sql`. **Name collision:** a `Comment` model already exists but belongs to `CommunityPost` (`postId` -> `CommunityPost`). The new family-post comment table needs a different model name (e.g. `FamilyPostComment`) or an explicit decision. `FamilyPost` model exists (id, familyId, authorId -> Person, postType, content, reactions, timestamps). |
| 4b | not started | `server/src/modules/timeline/timeline.service.ts` (exists, 453 lines; TODO still at line 270) |
| 5a | not started | `server/src/modules/notifications/timezone-utils.ts` (exists), `server/src/modules/chat/chat-mention.push.scheduler.ts` (exists; TODO at 287). **Timezone IS stored:** `NotificationPreference.quietHoursTimezone` (default `Asia/Kolkata`). But `timezone-utils.ts` only exports IST helpers (`isInIstQuietHours` hard-codes `Asia/Kolkata`); 5a needs a per-recipient-timezone variant, not just a call to the existing helper. |
| 5b | not started | `server/src/modules/chat/chat.gateway.ts` (TODO at 312), `chat-mention.push.scheduler.ts` (TODOs at 98, 248, 261) — all still present. |
| 6a | not started | `.github/workflows/ci.yml` (only CI file; named `CI`). It already runs `flutter analyze --no-fatal-infos` in the `Flutter Analyze` job (~line 112-113), so 6a is about whether that job is actually blocking and about its triggers (see finding 2), not about adding the step. Also reads `CHANGELOG.md`. |
| 6b | not started | `scripts/check-before-deploy.sh` (does not exist yet — new file), `CONTRIBUTING.md` (exists) |
| 7a | not started | `KINREL-PULSE-PITRU-IMPLEMENTATION-PROMPT.md` (currently at repo root, moves into `docs/`), `docs/PRODUCTION_VERIFICATION_v5.0.md`, `v6.0.md`, `v7.0.md` (all exist), `docs/archive/` (does not exist yet — new) |
| 7b | not started | `docs/cameo/FILAMENT_DIRECTIVE_DELIVERABLES.md`, `THERMION_DIRECTIVE_DELIVERABLES.md`, `PREFLIGHT_SUMMARY.md` (all three exist); `docs/archive/` may be created by 7a or 7b |
| 7c | not started | `supabase/migrations/` (339 files — matches the plan's "about 339"), `CHANGELOG.md`; output is new `docs/migrations-cleanup-proposal.md` |

## Task 1b notes

- File: `server/src/modules/chat/chat.service.ts` (`pinMessage`), commit `15c39f90` on `stability-fixes`
  (which is based on `feature-registry`).
- `assertMember()` already returns the `FamilyMember` row, so `pinMessage` keeps it and throws
  `ForbiddenException('Only admins can pin messages')` unless `membership.role` is `'admin'` or `'owner'`.
  Same check as `KinrelController.assertAdmin` (`server/src/kinrel-intelligence/kinrel.controller.ts`)
  and `emotional_attachment.controller.ts`. `unpinMessage` unchanged (anyone can unpin).
- Expected behaviour to test manually: `member`/`viewer` -> 403 "Only admins can pin messages";
  `admin`/`owner` -> 200; non-member -> 403 "Not a member of this family".
- Not verified: clean `tsc` (see finding 4). The 16 baseline errors are identical with and without the change.
- The branch was named `stability-fixes`, not `fix/1b`, so the Starter's leftover-branch check
  (`fix/*`) will not see it. Merge-conflict note: `stability-fixes` also contains a
  `docs/fix-progress.md` (1b notes only); when merging, keep this file's version and fold the 1b row in.

## Task 1c notes

Branch: `fix/1c`, based on `stability-fixes` (so it includes the 1b pin fix) with `fix/1a` merged in.
There were no leftover `fix/*` branches other than `fix/1a` (marked in progress, not merged).
The sweep found no other "for now, any member can..." comments; the gaps below were found by reading
every mutating method in the three files.

### Fixed (5)

| # | Where | Gap | Fix (existing pattern reused) |
|---|---|---|---|
| 1 | `chat.gateway.ts` `chat:joinFamily` | any authenticated socket could join any family's chat room and receive its messages | `ChatService.assertFamilyMember()` (new public wrapper over the existing private `assertMember`) before `client.join`; on failure emits the module's usual `'error'` event and returns |
| 2 | `chat.gateway.ts` `chat:messageDelivered` | no membership/family check; server broadcast into the client-supplied family room | same `assertFamilyMember`, plus `getMessageSender(...).familyId === data.familyId`; returns with an `'error'` event otherwise |
| 3 | `chat.service.ts` `sendMessage` | client-supplied `groupId` not validated: any family member could post into a group/DM they are not in (`sendMessageWithMentions` falls through to this when there are no mentions) | group must exist and belong to the family (same messages as `sendMessageWithMentions`), and sender must be a `GroupMember` -> `ForbiddenException('Not a member of this group')` |
| 4 | `circle.service.ts` `addMember` | when `anyoneCanAdd` is true a NON-member could add people (`callerMember` null was only compared against admin) | non-member -> `ForbiddenException('You are not a member of this circle.')` (same text as `_assertMember`) |
| 5 | `circle.service.ts` `pinMessage` / `unpinMessage` | admin of circle A could pin/unpin any message in circle B (message id never checked against `circleId`) | new `_assertMessageInCircle()` = the same check `addReaction` already does (404 if missing, 400 'Message belongs to a different circle.') |

### Expected behaviour to test manually

- Join room: family member -> `chat:joinedFamily`; non-member -> `'error'` event "Not a member of this family", no room join.
- `chat:messageDelivered`: member + message in that family -> status flips, broadcast as before; non-member or message from another family -> `'error'` event, no broadcast.
- Send a message with `groupId` of a group you belong to -> 200/persisted; group in another family -> 403 "Cannot send a message to a group outside its family"; group in your family you are not in -> 403 "Not a member of this group"; unknown group -> 404.
- Circle `addMember`: non-member caller (even with `anyoneCanAdd` on) -> 403; member + `anyoneCanAdd` -> allowed; admin -> allowed; member without `anyoneCanAdd` -> 403 (unchanged).
- Circle pin/unpin: admin + message in this circle -> 200; admin + message from another circle -> 400; unknown message -> 404; non-admin -> 403 (unchanged).

### Not fixed — follow-up (file:line as of this branch)

- (Group scoping RESOLVED in task 1d; the 'any member can query another member's mentions' part below is still open.) `chat.service.ts:625` `getMentionsForUser`: any family member can read another member's mentions (the `mentionedUserId` param is not restricted to the caller), and messages are scoped by `familyId` only, so mentions in groups/DMs the caller is not in are visible. Needs a product decision (should a user only see their own mentions?).
- (RESOLVED for `listMessages`, `getPinnedMessages`, `searchMessages` in task 1e; reactions/pins/read-count on group messages still open — see 1e notes.) Read paths scope by `familyId` only, not `groupId`, so group/DM messages are readable by every family member: `chat.service.ts:97` `listMessages`, `:815` `getPinnedMessages`, `:1031` `searchMessages`; reactions/pins on group messages have the same shape (`:1267` `addReaction`). This is the same root cause as the `TODO(phase-a-5)` at `chat.gateway.ts:323` (broadcast to the family room instead of per-group rooms) — belongs with task 5b.
- `chat.service.ts:678` `getStreak`, `:687` `recordStreak`, `:1330` `getReactionCounts`, `:699` `markDelivered`, `:716` `getMessageSender` take no user id and do no membership check. The gateway only calls them after a membership check, but callers in `chat.controller.ts` (not in this task's scope) must be checked.
- `circle.service.ts:518` `sendMessage` trusts client-supplied `senderFamilyId` / `senderPersonId` (lines ~565-566) — a member can attribute a message to any family/person id. Needs a decision on how to validate.
- `circle.service.ts:377` `removeMember`: any admin can remove any other admin including the circle owner (`ownerId`); only the last-admin case is blocked. Decide whether the owner should be protected.
- `unpinMessage` (chat) is intentionally open to any member ("WhatsApp-style", per the comment) — left as is.

### Verification gap

- `cd server && ./node_modules/.bin/tsc --noEmit`: 16 errors with and without these changes (identical after stripping line numbers), all in files/lines caused by the missing generated Prisma client (see finding 4). Therefore not a clean pass — confirm in CI or on a machine where `prisma generate` works. Because the Prisma client is not generated, Prisma-typed expressions (e.g. `groupId_userId` compound key, `groupMember.findUnique`) were NOT strictly type-checked; the key name comes from `@@unique([groupId, userId])` on `GroupMember`.
- No unit/e2e tests were run (no generated client, no DB). `chat.service.spec.ts` mocks may need updating for the new `group`/`groupMember` calls in `sendMessage` when a `groupId` is passed.

## Task 1d notes

Branch: `fix/1d`, based on `fix/1c` (so it includes the 1a/1b/1c work). Leftover `fix/*` branches found:
`fix/1a` and `fix/1c`, both unmerged and marked in progress — left untouched.

### Change — `chat.service.ts` `getMentionsForUser`

- Models: `GroupMember(groupId, userId, @@unique([groupId,userId]))` links a user to their groups;
  `ChatMention.groupId` (nullable) and `ChatMessage.groupId` (nullable) say which group a mention/message belongs to.
  Neither `GroupMember` nor `ChatMention` has a Prisma relation, so the method first loads the requester's
  group ids: `groupMember.findMany({ where: { userId: requestingUserId }, select: { groupId: true } })`.
- Scoping condition added (same condition on both queries):
  `OR: [{ groupId: null }, { groupId: { in: <requester's group ids> } }]`
  - on `chatMention.findMany` (so `take` is not eaten by rows the caller may not see), and
  - on the `chatMessage.findMany` hydration (authoritative; also covers older `ChatMention` rows whose `groupId` is null).
- Assumption: family-wide mentions (`groupId IS NULL`) stay visible to every family member, because the family chat is.
  If you want mentions limited to ones the caller is *personally* mentioned in, that is the separate
  `mentionedUserId === requestingUserId` question left open in the 1c notes.
- Side effect: for legacy mention rows with null `groupId` whose message sits in a group the caller is not in,
  the row passes the first filter but is dropped at hydration, so a page can return fewer than `limit` items.

### Manual verification

1. User U is in family F and in group A, not in group B (both groups belong to F).
2. Someone mentions U in group A, and someone mentions U in group B, and someone mentions U in the family-wide chat.
3. U (or any other F member) calls `getMentionsForUser(F, caller, U)`:
   - as U or as another member of group A: the group-A mention and the family-wide mention appear; the group-B mention does NOT appear.
   - as a member of both A and B: all three appear.
   - as an F member in neither group: only the family-wide mention appears.
   - as a non-member of F: 403 "Not a member of this family" (unchanged).

### Verification gap

- `tsc --noEmit`: 16 errors with and without the change (identical after stripping line numbers), caused by the
  missing generated Prisma client (see finding 4) — not a clean pass. Prisma-typed expressions (`OR` with
  `groupId: null` / `{ in: [...] }`) were not strictly type-checked.
- No tests run (no generated client, no DB).

## Task 1e notes

Branch: `fix/1e`, based on `fix/1d`. Leftover `fix/*` branches found: `fix/1a`, `fix/1c`, `fix/1d` (all unmerged,
in progress) — left untouched.

### Change — `chat.service.ts`

One new private helper, `resolveChatScope(familyId, userId, groupId?)`, returns the `where` fragment all three
methods spread into their query (family membership is still asserted first, as before):

- `groupId` given -> that specific chat: group must exist (404), belong to the family (403 "Cannot read a group outside
  its family"), and the caller must be a `GroupMember` (403 "Not a member of this group"). Fragment: `{ groupId }`.
- `groupId` omitted -> everything the caller may see: `OR: [{ groupId: null }, { groupId: { in: <caller's group ids> } }]`
  (family-wide chat + groups they belong to; never other members' groups/DMs).

| Method | New signature | What changed |
|---|---|---|
| `listMessages` | `(familyId, userId, limit, before, groupId?)` | `...scope` added to the `where` (still family + not-deleted + `before` cursor) |
| `getPinnedMessages` | `(familyId, userId, groupId?)` | `...scope` added to the `where`; still capped at 10 |
| `searchMessages` | `(familyId, userId, query, limit, groupId?)` | `...scope` added to BOTH the results query and the `total` count query, so the count matches what can be returned |

`groupId` is a new optional LAST parameter in each, so existing callers compile and keep working. Default behaviour
(no `groupId`) changed only in that other members' groups/DMs no longer appear.

### Manual verification

User U is in family F and group A but not group B (both in F); family-wide chat also has messages.
1. `listMessages(F, U)` -> family-wide messages + group A messages, NO group B messages.
2. `listMessages(F, U, 50, undefined, A)` -> only group A messages. With group B -> 403 "Not a member of this group".
   With a group from another family -> 403 "Cannot read a group outside its family". Unknown group -> 404.
3. Pin a message in group B (as someone in B). `getPinnedMessages(F, U)` must not include it; `getPinnedMessages(F, <member of B>)` does.
4. Search a word that appears in a group-B message and a group-A message: as U, `searchMessages` returns only the A hit and
   `total` counts only visible hits.
5. Non-member of F -> 403 "Not a member of this family" (unchanged).

### Overlap with task 5b (so it is not redone)

5b's phase-a-5 TODOs are about the Socket.IO side (join clients to `chat:group:<groupId>` rooms —
`chat.gateway.ts` ~323 —, per-socket "current chat", per-chat mute split). Task 1e does NOT touch the gateway or the
push scheduler, so all of 5b is still open. What 1e does cover is the read-path half of the same root cause (group
membership not enforced on reads). Still open from that root cause, none touched by 1e:
- the realtime broadcast of group/DM messages to the whole `chat:family:<id>` room (5b);
- `chat.controller.ts` (not in scope here) does not yet pass a `groupId`, so the explicit-chat form is only reachable
  from code that calls the service directly until the controller accepts a `groupId` query param;
- `addReaction`, `getReadCount`, `pinMessage` (family admin can pin a message in a group they are not in) and
  `unpinMessage` still check family membership only, not group membership;
- `getMentionsForUser` (task 1d) has its own inline copy of the visible-groups condition; it could call `resolveChatScope`.

### Verification gap

- `tsc --noEmit`: 16 errors with and without the change (identical after stripping line numbers), caused by the missing
  generated Prisma client (see finding 4) — not a clean pass. The new `where` fragments (`OR` with `groupId: null` /
  `{ in: [...] }`, `groupId_userId` compound key) were not strictly type-checked.
- No tests run (no generated client, no DB). `chat.service.spec.ts` mocks may need `group` / `groupMember` entries.

## Task 1f notes

Branch: `fix/1f`, based on `fix/1e` (stack 1a -> 1c -> 1d -> 1e -> 1f; no `main` exists).

Sweep of `chat.service.ts` methods with no user/requester id parameter, and their controller callers
(the controller is behind `JwtAuthGuard` and every handler already has `@CurrentUser('id') userId`).

### Fixed (id was available in the controller, not threaded through)

| # | Method | Gap | Fix |
|---|---|---|---|
| 1 | `getStreak(familyId)` | `GET families/:familyId/chat/streak` "validated" membership with `listMessages(...).catch(() => {})` — the `.catch` swallowed the 403, so any authenticated user could read any family's streak | signature is now `getStreak(familyId, userId)` and calls `assertMember`; controller passes `userId`, swallowed call removed |
| 2 | `getReactionCounts(messageId)` | `GET .../messages/:messageId/reactions` had the same swallowed check, and never verified the message belongs to `familyId` -> any user could read emoji + reactor `userIds` for ANY message id | new `getReactionCountsForMember(familyId, userId, messageId)`: `assertMember`, message must exist in that family (404), and if the message has a `groupId` the caller must be a `GroupMember` (403). Controller uses it. `getReactionCounts` is kept unchanged as the internal aggregator (the gateway and its existing spec still call it) |
| 3 | controller `uploadMedia` (not a service method, same defect) | `POST .../media` used the same swallowed `listMessages().catch(() => {})`, so a non-member could upload into a family's storage path | now `await chatService.assertFamilyMember(familyId, userId)` (existing public wrapper from 1c) |

Spec: `chat.service.spec.ts` gained tests for `getStreak` (non-member -> 403, member -> streak) and
`getReactionCountsForMember` (non-member 403, other-family message 404, group message w/o membership 403, happy path).
Existing `getReactionCounts` spec untouched and still valid.

### Listed for later (not fixed — would need edits outside the two named files or a bigger refactor)

| # | Where | Issue |
|---|---|---|
| A | `chat.gateway.ts:763` (`chat:removeReaction`) | `removeReaction` only checks family membership, then `getReactionCounts(data.messageId)` is returned/broadcast for an arbitrary `messageId` (no check the message is in `data.familyId` or visible to the caller's groups). `addReaction` (gateway:724) is fine — the service verifies message-in-family first. Fix: have the gateway call `getReactionCountsForMember`, or make `removeReaction` verify the message. Gateway is outside 1f's file list. |
| B | `chat.service.ts:~774` `markDelivered(messageId, _recipientUserId)` | takes a user id but ignores it; updates any message id. Only caller is `chat.gateway.ts:429`, which (since 1c) asserts membership + family match first, so not exploitable today, but the method itself has no check. |
| C | `chat.service.ts:~791` `getMessageSender(messageId)` and `~762` `recordStreak(familyId)` | internal lookup/mutation helpers, called only from the gateway (after membership checks), never from the controller. No requester concept; left as is. |

### Verification
- Local `tsc --noEmit`: NOT usable. `npx prisma generate` fails here (`binaries.prisma.sh` ENOTFOUND), so the client is un-generated and every `prisma.<model>` access errors (1054 errors before, 1056 after = exactly the two new `chatMessage`/`groupMember` lookups in `getReactionCountsForMember`). No other new error.
- Expected behaviour to test manually: see the reply for the per-role status table.
- CI: see below / reply for the Actions result.

