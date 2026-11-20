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
| 1g | in progress (done on `fix/1g`, based on `fix/1f`; NOT merged: no `main` branch, Backend CI typecheck already red on the base — see "Task 1g notes") | `server/src/modules/circle/circle.service.ts` (`sendMessage`), `dto/circle.dto.ts` (doc comments only), `circle.service.spec.ts`. Not in the original 1a-7c table; added at the user's request. |
| 1h | in progress (done on `fix/1h`, based on `fix/1g`; NOT merged: no `main` branch, Backend CI typecheck already red on the base — see "Task 1h notes") | `server/src/modules/circle/circle.service.ts` (`removeMember`), `circle.service.spec.ts`. Not in the original 1a-7c table; added at the user's request. |
| 2a | in progress (done on `fix/2a`, based on `fix/1h`; NOT merged: no `main` branch; `prisma generate`/`validate` impossible in sandbox, migration unapplied — see "Task 2a notes") | `server/prisma/schema.prisma` (Story: `audience`, `thumbnailUrl`) + `supabase/migrations/20261120120000_story_audience_thumbnail.sql`. `stories.service.ts` untouched (task 2b). |
| 2b | in progress (done on `fix/2b`, based on `fix/2a`; NOT merged: no `main` branch, Backend CI typecheck already red on the base, and 2a's schema was never generated — see "Task 2b notes") | `server/src/modules/stories/stories.service.ts` (`findByFamily`, `create`, `formatStory`, one comment), `stories.service.spec.ts` |
| 3a | in progress (done on `fix/3a`, based on `fix/2b`; NOT merged: no `main` branch; `prisma generate` impossible in sandbox, migration unapplied — see "Task 3a notes") | `server/prisma/schema.prisma` (ShareableLink `userId`/`user`/index; User `shareableLinks`) + `supabase/migrations/20261120130000_shareablelink_userid_reconcile.sql`. `share.service.ts` untouched (task 3b). |
| 3b | in progress (done on `fix/3b`, based on `fix/3a`; NOT merged: no `main` branch, Backend CI typecheck red on the base and its log is unreadable from the sandbox — see "Task 3b notes") | `server/src/modules/share/share.service.ts` (all 5 `userId` TODOs resolved), `share.service.spec.ts` |
| 4a | in progress (done on `fix/4a`, based on `fix/3b`; NOT merged: no `main` branch, and local `tsc` still has 5 PRE-EXISTING errors in `predictions.scheduler.ts` — see "Task 4a notes") | `server/prisma/schema.prisma` (new model `FamilyPostComment`; inverse relations on `FamilyPost` and `User`) + `supabase/migrations/20261120140000_create_familypostcomment.sql`. `timeline.service.ts` untouched (task 4b). |
| 4b | in progress (done on `fix/4b`, based on `fix/4a`; NOT merged: no `main` branch, and local `tsc` still has the 5 PRE-EXISTING `predictions.scheduler.ts` errors — see "Task 4b notes") | `server/src/modules/timeline/timeline.service.ts` (`getComments`, `addComment`, `deleteComment`, + `getTimeline`/`getHomeFeed`/`toggleReaction` comment count), `timeline.service.spec.ts`, `server/src/__tests__/agent03-integration.spec.ts` (mocks only) |
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
- `circle.service.ts:377` `removeMember`: any admin can remove any other admin including the circle owner (`ownerId`); only the last-admin case is blocked. Decide whether the owner should be protected. (DEFAULT APPLIED in task 1h: owner is protected — see 1h notes; awaiting product confirmation.)
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
- CI (CI workflow, temp branch `wip/fix-1f-ci` @ `874f6430`, since `ci.yml` does not trigger on `fix/*`; branch deleted afterwards):
  `Backend CI` = **failure** at step "Typecheck (backend)" (exit code 2); Build and Test steps were SKIPPED, so the jest suite never ran.
  The same job on the unmodified `fix/1e` tip (`d28c409f`, temp branch `wip/fix-1e-baseline-ci`) fails at the identical step, so
  the typecheck failure predates 1f. The step logs are not downloadable from this sandbox (log redirect host is blocked) and the
  annotations API only returns "exit code 2", so it is NOT known whether 1f added any tsc error on top of the existing ones.
  `Flutter Analyze` also failed (no Dart touched by 1f). **Next step:** read the `Typecheck (backend)` log in the Actions UI for run on
  `fix/1f`, fix/confirm the baseline errors, then re-run so `Test` actually executes `chat.service.spec.ts`.
- SQL: none in this task.

## Task 1g notes

Branch: `fix/1g`, based on `fix/1f` (no `main`).

`CircleService.sendMessage(circleId, userId, dto)` — called by `CircleController.POST :circleId/messages` and `CircleGateway` `circle:sendMessage`
(both pass the authenticated `userId`: `@CurrentUser('id')` / `client.data.userId`).

| Field written to `CircleMessage` | Before | After |
|---|---|---|
| `senderId` | session user | session user (unchanged) |
| `senderName` | `CircleMember.displayName` (DB) | unchanged |
| `senderPersonId` | **`dto.senderPersonId`** (client) | `Person.id` where `linkedUserId = userId AND deletedAt IS NULL` (server DB; same lookup as `viewer.service.ts`), else `null` |
| `senderFamilyId` | **`dto.senderFamilyId`** (client) | that Person's `familyId`, else `null` |
| `senderInitials` | **`dto.senderInitials`** (client) | derived from `senderName` (first letters of up to 2 words) — extra, same spoof class; mirrors chat's `resolveSender` |

DTO fields `senderPersonId/senderFamilyId/senderInitials` are kept (marked `@deprecated`, ignored) so older clients that still send them don't get a 400.
Still trusted from the client (all non-identity): `content`, `messageType`, `replyToId` (validated to be in the same circle), media fields.
Caveat: a user with no linked Person now gets `null` person/family (previously whatever the client claimed). Circles are not family-scoped, so
the family is the linked Person's own family.
Follow-up (not done): `GET` side / Flutter client may display `senderPersonId`/`senderFamilyId` — not checked (outside task files).

Verification: local `tsc` un-generated Prisma client (1056 -> 1057 errors, the +1 is the new `prisma.person` access; no non-Prisma error in `modules/circle`).
Specs added in `circle.service.spec.ts` (spoofed ids ignored; no linked Person -> null). CI result below.

CI: temp branch `wip/fix-1g-ci` @ `5f48b778` (deleted afterwards; `ci.yml` doesn't trigger on `fix/*`). `Backend CI` = **failure** at "Typecheck (backend)";
Build and Test SKIPPED, so the new specs never ran. Same step fails on the unmodified `fix/1e` base (see 1f notes), and the log isn't downloadable
from this sandbox, so it is NOT known whether 1g added a tsc error. **Next step:** read that step's log in the Actions UI, clear the baseline
typecheck errors, re-run so `circle.service.spec.ts` executes. Not merged.

## Task 1h notes

Branch: `fix/1h`, based on `fix/1g` (no `main`). File: `server/src/modules/circle/circle.service.ts` `removeMember`.

> **⚠ NEEDS YOUR CONFIRMATION — DEFAULT CHOICE, not a confirmed product decision:** `removeMember` now blocks removing the circle owner (`Circle.ownerId`) outright (403), even for an admin; override later if admins should be able to remove an owner under some condition. (No earlier note from you on this task was found in this file.)

- Check order: caller must be admin (`_assertAdmin`, unchanged) -> target must not be `Circle.ownerId` (new, `ForbiddenException`) -> existing last-admin guard -> delete.
- The owner is also blocked from removing themselves through this method (self-leave is `leaveCircle`, unchanged: owner can still leave; the circle is then orphaned as before — `ownerId` stays).
- **Your stated path "transfer ownership first" does not exist in this codebase:** `transferAdmin` only sets `CircleMember.role='admin'` for the target; nothing ever updates `Circle.ownerId`. So today the owner is effectively permanent: removable only by leaving (`leaveCircle`) or via `deleteCircle` (owner-only). If you want a real ownership transfer, that is a separate task (new method; `ownerId` is also used by `deleteCircle` and block checks in `addMember`).
- Specs added (`circle.service.spec.ts`, `removeMember`): admin removing owner -> 403 and no delete; non-admin -> 403 before owner lookup; admin removing ordinary member -> ok; admin removing a non-owner admin (>1 admins) -> ok.
- Verification: local `tsc` is un-generated-Prisma (1057 -> 1058 errors, the +1 is the new `prisma.circle` lookup; no non-Prisma error in `modules/circle`). CI result below.

CI: temp branch `wip/fix-1h-ci` @ `851511b2` (deleted afterwards). `Backend CI` = **failure** at "Typecheck (backend)"; Build and Test SKIPPED, so the new
`removeMember` specs never ran. Same step already fails on the unmodified `fix/1e` base (see 1f notes); logs aren't downloadable from this sandbox, so it is NOT
known whether 1h added a tsc error. **Next step:** read that step's log in the Actions UI, clear the baseline errors, re-run. Not merged.

## Task 2a notes

Branch: `fix/2a`, based on `fix/1h` (no `main`).

Added to `model Story` in `server/prisma/schema.prisma`:
- `audience     String  @default("PUBLIC")` — `PUBLIC | FAMILY_ONLY`
- `thumbnailUrl String?`

Migration: `supabase/migrations/20261120120000_story_audience_thumbnail.sql` (newest timestamp; idempotent `ADD COLUMN IF NOT EXISTS`, `Story_audience_check` CHECK added only if missing, `RAISE NOTICE` backfill report). No function created, so SECURITY DEFINER/search_path n/a. No existing migration edited.

Design choice (flagging, easy to change): `audience` is `String` + DB CHECK, NOT the `SparqAudience` enum. Reasons: the `stories.service.ts` header and `CreateStoryDto.audience?: string` / controller Swagger enum already specify `PUBLIC | FAMILY_ONLY` as a string; many other visibility columns here are strings (`visibility`, `profileVisibility`, `gotraVisibility`); `SparqAudience` also has `CIRCLE`/`VIP_CIRCLE`, which stories have no audience-circle join for. Existing rows default to `PUBLIC` = today's behaviour. Task 2b must validate the DTO string against `PUBLIC|FAMILY_ONLY` (the CHECK will reject anything else with a DB error).

Not verified:
- `npx prisma generate` FAILED in the sandbox (`binaries.prisma.sh` ENOTFOUND), as did `prisma format`/`validate` (same engine download) — so the schema edit is un-parsed locally and NO generated types exist; "tsc passes (generated types only)" could not be checked. Local `tsc` error count unchanged at 1058 (no code changed; all Prisma-client errors).
- SQL migration cannot be applied here. **Needs review/testing against a staging Supabase project before prod.**
- `ci.yml` has no explicit `prisma generate` step, so CI is also not a guaranteed schema check. CI result below.

CI: temp branch `wip/fix-2a-ci` @ `df3299d8` (deleted afterwards). `Backend CI` = **failure** at "Typecheck (backend)"; Build/Test SKIPPED. Same step already fails on the
unmodified `fix/1e` base (see 1f notes) and logs aren't downloadable from this sandbox, so it is NOT known whether the schema edit parses or whether 2a added an error.
**Next step:** read that step's log in the Actions UI (and run `npx prisma generate && npx tsc --noEmit` somewhere with network), then apply the migration to staging. Not merged.

## Task 2b notes

Branch: `fix/2b`, based on `fix/2a` (no `main`). File: `server/src/modules/stories/stories.service.ts` (+ spec).

TODO 1 (`findByFamily`, was ~165) — RESOLVED: the app-level `.filter(() => true)` is gone; the Prisma `where` now has `...(isFamilyMember ? {} : { audience: 'PUBLIC' })`.
Family members see PUBLIC + FAMILY_ONLY; non-members and callers with no user id see PUBLIC only. (Controller already passes `@CurrentUser('id')`.)

TODO 2 (`uploadMediaToCloudinary`, was ~394) — RESOLVED: the helper already computed `thumbnailUrl`; `create()` threw it away. `create()` now keeps it and writes it to `Story.thumbnailUrl`;
`formatStory()` returns `thumbnailUrl` (and `audience`), so `create`/`findByFamily`/`findByUser` responses include them. The TODO comment is replaced by a pointer to `create()`.

Edits beyond the two TODO sites (needed for them to work; flagging because the task said "no other method"):
- `create()`: also persists `audience: dto.audience ?? 'PUBLIC'`. Without this every row stays PUBLIC and the new filter would be dead code. The DTO already has `@IsIn(['PUBLIC','FAMILY_ONLY'])`, so no extra validation was added.
- `formatStory()`: param type + output gained `audience`, `thumbnailUrl` (client-visible response shape change: two new keys on every story).
- Header comment ("SCHEMA CHANGE REQUESTS") updated. No other method touched.

Assumptions on audience semantics: (1) `FAMILY_ONLY` = visible only to members of `story.familyId`; (2) a story with no `familyId` is never returned by `findByFamily` anyway; (3) the author is not special-cased — an author who has left the family can no longer see their own FAMILY_ONLY story via `findByFamily` (still visible via `GET /mine`, `findByUser`, which is the caller's own stories only); (4) `markViewed(storyId)` still has no audience/membership check (any authed user who knows a story id can record a view) — not in scope, left as is; (5) dev fallback (no Cloudinary config) stores `thumbnailUrl = null`.

Specs added to `stories.service.spec.ts` (create persists audience/thumbnail; findByFamily where-clause for member / non-member / no user). Existing specs untouched and compatible.

Verification: local `tsc` un-generated Prisma (error count unchanged at 1058; no non-Prisma error in `modules/stories`). **"tsc passes" is NOT confirmed** — 2a's `prisma generate` never succeeded here, so `audience`/`thumbnailUrl` are unchecked against generated types. CI result below.

CI: temp branch `wip/fix-2b-ci` @ `b7730024` (deleted afterwards). `Backend CI` = **failure** at "Typecheck (backend)"; Build/Test SKIPPED, so the new stories specs never ran. Same step already fails on the
unmodified `fix/1e` base (see 1f notes); logs aren't downloadable from this sandbox, so it is NOT known whether 2a/2b added an error. **Next step:** read that step's log in the Actions UI
(and run `npx prisma generate && npx tsc --noEmit && npx jest src/modules/stories` somewhere with network), then merge 2a+2b together. Not merged.

## Task 3a notes

Branch: `fix/3a`, based on `fix/2b` (no `main`).

**The DB column already existed.** `supabase/migrations/20260617163842_fix_shareablelink_rls_scope_to_owner.sql` (applied to prod via the SQL editor, backfilled into the repo 2026-06-18) already added
`"ShareableLink"."userId" TEXT` (nullable), FK `ShareableLink_userId_fkey -> "User"(id) ON DELETE SET NULL ON UPDATE CASCADE`, index `ShareableLink_userId_idx`, and owner-scoped RLS policies. Only `schema.prisma` was behind.

Schema edit (`server/prisma/schema.prisma`): `ShareableLink` gains `userId String?`, `user User? @relation(fields:[userId], references:[id], onDelete: SetNull)`, `@@index([userId])`; `User` gains the inverse `shareableLinks ShareableLink[]`.
Kept NULLABLE on purpose (matches the DB; legacy rows have no creator). Pattern follows `Story`/`ApiKey` (`user User @relation(...)`, `@@index([userId])`), except `SetNull` instead of `Cascade` to match the existing FK.

Migration: `supabase/migrations/20261120130000_shareablelink_userid_reconcile.sql` — idempotent (`ADD COLUMN IF NOT EXISTS`, FK only if missing, `CREATE INDEX IF NOT EXISTS`), expected to be a NO-OP on any DB that has the 20260617 migration; it also `RAISE NOTICE`s how many rows have NULL `userId`. No existing migration edited.

**Backfill: NOT possible, none done.** Nothing records who created a link: `ShareableLink` only has optional `familyId`/`personId` (no relation, no creator column), and no other model references it. Inferring from the family owner/person would be a guess, so all existing rows stay NULL.
Heads-up for 3b: `createShareableLink` receives `userId` but does not write it, so links created since 2026-06-17 are almost certainly NULL as well. If 3b makes `revokeShareableLink` require `link.userId === userId` and `getMyShareableLinks` filter by `userId`, every pre-existing link becomes un-revocable and invisible in "my links" (RLS already treats NULL as "legacy"). Decide in 3b whether legacy NULL rows should stay publicly resolvable by token but unmanaged (probably yes), or be adopted manually.

Not verified: `npx prisma generate` FAILED here (`binaries.prisma.sh` ENOTFOUND), so the schema edit is un-parsed and no generated types exist; local `tsc` error count unchanged at 1058 (un-generated baseline, no code changed) — "tsc passes" NOT confirmed. SQL not applied anywhere: **review/test on a staging Supabase project before prod.** CI result below.

CI: temp branch `wip/fix-3a-ci` @ `3eea51c2` (deleted afterwards). `Backend CI` = **failure** at "Typecheck (backend)"; Build/Test SKIPPED. Same step already fails on the unmodified `fix/1e` base (see 1f notes);
logs aren't downloadable from this sandbox, so it is NOT known whether the schema edit parses or 3a added an error. **Next step:** read that step's log in the Actions UI and run `npx prisma generate && npx tsc --noEmit`
somewhere with network; apply the migration to staging (expect a NOTICE with the NULL-userId count). Not merged.

## Task 3b notes

Branch: `fix/3b`, based on `fix/3a` (no `main`; leftover `fix/1a`..`fix/3a` all unmerged and marked in progress, none "done", so nothing was merged by housekeeping).
File: `server/src/modules/share/share.service.ts` (+ `share.service.spec.ts`). Schema/`userId` column come from 3a.

### The five TODOs

| # | Was (line) | Now |
|---|---|---|
| 1 | 35, `createShareableLink` doc: "Add userId column" | `userId` (the caller) is written on create |
| 2 | 236, `revokeShareableLink` doc: "any authenticated user can revoke" | doc rewritten to the real rule below |
| 3 | 248, `revokeShareableLink` body: commented-out check | `link.userId` set and `!== userId` -> `ForbiddenException('Not your link')` |
| 4 | 266, `getMyShareableLinks` doc: "returns all links" | doc rewritten |
| 5 | 270, `getMyShareableLinks` body: "Add where: { userId }" | `where` applied to BOTH `findMany` and `count` (total matches the page) |

Public token paths (`getSharedCard`, `getShareStats`, `trackShare`) have no user context and are unchanged.

### Legacy NULL-`userId` rows — DECISION (please confirm)

Nothing can recover who created a legacy link (see 3a notes), so they are treated as follows:
- **Still publicly resolvable by token** (nothing was touched on those paths) — no existing shared link stops working.
- **Revoke:** allowed for an `owner`/`admin` of the link's `familyId` (`FamilyMember.role`, same check as other modules). A plain member/viewer/non-member -> 403. A legacy row with NO `familyId` cannot be revoked through the API at all (stays live until someone deletes it in the DB).
- **List (`GET /share/mine`):** the caller's own links, plus legacy NULL links whose `familyId` is in a family where the caller is owner/admin — i.e. exactly the set they are allowed to revoke, so "what I can see" == "what I can revoke".
- Rows that HAVE an owner are never revocable by anyone else, including a family admin.
- Not chosen: letting any authenticated user revoke NULL rows (that is the old hole), and "NULL rows unmanaged forever" (permanent public links with no way to take them down). Easy to change: the whole legacy policy is the `else if` in `revokeShareableLink` and `getAdminFamilyIds` / the `OR` in `getMyShareableLinks`.

### Expected behaviour to test manually

`DELETE /share/:id`
- creator -> 200 `{deleted:true}`; other user, link has owner -> 403 "Not your link" (even if they are a family admin); unknown id -> 404.
- legacy link with familyId: family owner/admin -> 200; family member/viewer or non-member -> 403.
- legacy link without familyId: everyone -> 403.

`GET /share/mine`: own links; plus legacy NULL links of families you own/admin; never another user's links; `total` counts the same set.

`POST /share` -> new row has `userId` = caller. `GET /share/:token` and `POST /share/track` on an old (NULL) link still work.

### Not fixed — follow-up (outside the TODOs)

- `createShareableLink` accepts `dto.familyId` / `dto.personId` without checking the caller belongs to that family/person; `getSharedCard` then exposes that family's/person's data to anyone with the token. Needs a membership check (decision on who may share what).

### Verification gap

- `npx prisma generate` is impossible here (`binaries.prisma.sh` ENOTFOUND), so no generated client. Local `tsc --noEmit`: 1058 errors before, 1060 after; the +2 are the two new `prisma.familyMember` accesses (same "Property ... does not exist on type 'PrismaService'" class as the existing `shareableLink` ones); no non-Prisma error in `modules/share`. **"tsc passes" is NOT confirmed.**
- `package.json` unchanged. (`npm install` rewrote `package-lock.json` locally because it is already out of sync; that change was reverted, not committed.)
- CI: temp branch `wip/fix-3b-ci` @ `57fd5ecf` (deleted afterwards; run 44680171900). `Backend CI` = **failure** at "Typecheck (backend)"; Build and Test SKIPPED, so the updated `share.service.spec.ts` never ran. Same step fails on the unmodified base (see 1f notes). The job log redirects to a host blocked from this sandbox and the annotations contain only Node-20 deprecation warnings, so it is NOT known whether 3b added a tsc error. **Next step:** read the `Typecheck (backend)` log in the Actions UI (run 44680171900), clear the baseline errors (generate the Prisma client in CI), re-run so the spec executes. Not merged.
- `share.service.spec.ts` was updated (new `familyMember` mock; create persists `userId`; revoke: creator/other user/legacy admin/legacy member/legacy non-member/legacy no-familyId; list: `where` on both queries, legacy-admin `OR`). Not executed anywhere yet.

## Task 4a notes

Branch: `fix/4a`, based on `fix/3b` (no `main`). Leftover `fix/1a`..`fix/3b` are all unmerged and "in progress" — none marked done, nothing merged.

### New model `FamilyPostComment` (`server/prisma/schema.prisma`)

Named `FamilyPostComment` because `Comment` already belongs to `CommunityPost`. Fields mirror `CommentData` in `timeline.service.ts` (`{id, authorId, authorName, body, parentId, createdAt}`), so 4b is a field-for-field swap:

| Field | Type | Notes |
|---|---|---|
| `id` | `String @id @default(cuid())` | workaround ids are preserved by the backfill |
| `familyPostId` | `String` | FK -> `FamilyPost.id`, ON DELETE CASCADE |
| `authorId` | `String` | FK -> `User.id`, ON DELETE CASCADE. A **User** id (service resolves the name from `User`), NOT a Person id like `FamilyPost.authorId` |
| `authorName` | `String` | snapshot of `User.name` at write time, as the JSON workaround does |
| `body` | `String` | |
| `parentId` | `String?` | self-FK, ON DELETE CASCADE (replies go with their parent = current `deleteComment` behaviour) |
| `createdAt` | `DateTime @default(now()) @db.Timestamptz` | service returns ISO strings today: 4b should `.toISOString()` it |

Relations/indexes: `post`, `author`, `parent`/`replies` (`"FamilyPostCommentReplies"`); `@@index([familyPostId, createdAt])` (matches the sort + cursor paging in `getComments`), `@@index([authorId])`, `@@index([parentId])`. Inverse fields added: `FamilyPost.comments`, `User.familyPostComments`.
No `updatedAt` (the service has no edit) and no stored `commentCount`: 4b can use `_count`/`count` instead of the JSON counter.

### Migration `supabase/migrations/20261120140000_create_familypostcomment.sql`

Idempotent table + FKs + indexes (Prisma-style names), RLS enabled with 3 policies (family members read; insert only as yourself and only in your family; delete own or family owner/admin; no UPDATE policy), and a backfill that COPIES existing comments out of `FamilyPost.reactions` JSON (does not modify the JSON) with `RAISE NOTICE` counts. No function created, so SECURITY DEFINER/search_path n/a. No existing migration edited.
Backfill rules: keep the original comment id; skip comments with no id/body or whose author is not in `User`; a malformed-JSON post is skipped (NOTICE), never aborts; a reply whose parent is missing becomes top-level.

### What WAS verified (new this task — earlier notes said this was impossible)

- **Prisma generate/validate DO work in the sandbox** if the engine download is bypassed: `PRISMA_QUERY_ENGINE_LIBRARY=/tmp/dummy-engine PRISMA_SCHEMA_ENGINE_BINARY=/tmp/dummy-engine PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING=1 DATABASE_URL=postgresql://u:p@localhost/db DIRECT_URL=postgresql://u:p@localhost/db ./node_modules/.bin/prisma generate` (and `validate`). Types are generated from the schema (the engine is a dummy, so no DB queries). `npm install` first (do NOT commit the lockfile change it causes: `package-lock.json` is out of sync, see finding 4).
- `prisma validate`: schema is valid. (`prisma format` rewrites unrelated lines of the file, so it was not applied.)
- **Real `tsc --noEmit`** (with the generated client): **5 errors, identical on the base `fix/3b` and on `fix/4a`** — all in `src/modules/predictions/predictions.scheduler.ts` (397: `isInWeeklyRecapWindowAt` misspelled for `isWeeklyRecapWindowAt`; 601/601/615/636: `question_text`/`correct_answer` typed as `number`, `null` arithmetic). None are in files touched by 1b-4a. So the earlier "1054-1058 errors" baseline was purely the missing client, and **the real blocker for `Backend CI`'s typecheck step is these 5 errors** (CI then skips Build/Test). Fixing them is a separate task: `predictions.scheduler.ts` is outside every task's file list.
- `jest src/modules/share src/modules/timeline`: 2 suites, 67 tests pass (first time 3b's updated share spec has actually run).
- **Migration run on a scratch PostgreSQL 16** (installed from the Ubuntu archive, stub `User`/`Family`/`FamilyMember`/`FamilyPost` tables, stub `auth.uid()`): applies cleanly; second run is a no-op (0 inserted); backfill on test data = 3 inserted / 2 skipped / 2 malformed posts skipped, parent link kept (`c_b -> c_a`), orphan reply became top-level, unknown author skipped, duplicate id on another post skipped; cascades verified (delete parent -> replies gone, delete post -> comments gone, delete user -> their comments gone). RLS as a non-superuser: outsider read 0 rows; member read OK; insert as self OK; insert with someone else's authorId -> RLS error; outsider insert -> RLS error; outsider delete 0 rows; member UPDATE 0 rows; family admin deletes another's comment 1 row; author deletes own 1 row.

### Still NOT verified

- The migration was run against stub tables, not the real Supabase schema (real `auth.uid()`, real `FamilyMember`/`FamilyPost` RLS interplay, realtime). **Still needs a run on a staging Supabase project before prod.**
- `Prisma` column-type drift vs a real DB (`prisma migrate diff`) was not run (needs the schema engine).
- CI was not run for this commit: local `tsc` completed, so the Actions fallback did not apply (it would hit the same 5 pre-existing errors).
- The existing `timeline.service.ts` still reads/writes the JSON until 4b; until then the new table stays empty for new comments (backfill only copies old ones, so re-run the backfill part right before 4b goes live, or have 4b dual-write).

### Hand-off to 4b

`getComments`: `findMany({ where: { familyPostId }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], cursor/take })`; `addComment`: `create({ data: { familyPostId, authorId, authorName, body, parentId } })` (validate parent belongs to the same post); `deleteComment`: `delete` (replies cascade); `commentCount`: `count`. Keep the socket payloads' `comment` shape = `{id, authorId, authorName, body, parentId, createdAt(ISO)}`.

## Task 4b notes

Branch: `fix/4b`, based on `fix/4a` (needs the `FamilyPostComment` model; no `main` exists). Leftover `fix/1a`..`fix/4a` are all unmerged and "in progress" — none marked done, nothing merged by housekeeping.

### What was replaced in `timeline.service.ts`

| Method | Before (JSON workaround) | Now |
|---|---|---|
| `getComments` (TODO "Task-3" removed) | parse `FamilyPost.reactions`, sort + slice in memory | `familyPostComment.findMany` ordered `createdAt asc, id asc`, `take limit+1`, cursor = comment id. Unknown/foreign cursor is ignored (as before) via a `findFirst` scoped to the post |
| `addComment` | push into JSON, rewrite whole `reactions` string, `commentCount = comments.length` | parent must be a `FamilyPostComment` on the SAME post (404 otherwise); `create` row (cuid id) + `FamilyPost.updatedAt` bump in one `$transaction`; returns/emits the same `{id, authorId, authorName, body, parentId, createdAt(ISO)}` |
| `deleteComment` | filter JSON (comment + direct replies) | comment looked up by `(id, familyPostId)` (404), same authorization, `delete` row + `updatedAt` bump in one `$transaction`; replies go via the `parentId` ON DELETE CASCADE |
| `getTimeline`, `getHomeFeed` | returned stored `reactions` JSON incl. `commentCount` + `comments` | select `_count.comments`; `reactions` string is rewritten with the live `commentCount` and `comments: []`; `_count` is not exposed |
| `toggleReaction` | returned JSON incl. stale `commentCount`/`comments` | `familyPostComment.count` -> returned object has live `commentCount`, `comments: []`. The persisted JSON write is unchanged (emoji data only changes) |
| `parseReactions` / `ReactionsData` / `CommentData` | | kept (emoji data still lives in the JSON); `commentCount`/`comments` documented as LEGACY. `generateId()` removed (cuid default replaces `cmt_...` ids) |

`updatedAt` bump: `SyncService` delta-syncs `FamilyPost` by `updatedAt`, and the old JSON write bumped it implicitly. Without the explicit bump, comment changes would never reach synced clients.

### Behaviour differences to be aware of

- Feed / timeline / reaction responses now carry `comments: []` inside the `reactions` JSON (previously the full inline list). Flutter does not read it (grep), but confirm for any other client.
- `deleteComment` cascade now removes replies of replies too (FK cascade); the JSON version removed direct replies only.
- `addComment` for an author id with no `User` row now fails the FK (previously saved with name "Unknown"). Author ids come from the JWT, so this should not occur.

### DEPLOY ORDER (important)

4a's backfill copies comments out of the JSON when the migration is applied. Comments written between applying 4a and deploying 4b exist ONLY in the JSON, so after 4b they are invisible (and 404 on delete). Re-run the backfill block of `20261120140000_create_familypostcomment.sql` (idempotent, skips existing ids) right before/at the 4b deploy. No dual-write was added.

### Still reads the old JSON shape elsewhere (NOT changed, out of scope)

- `server/src/modules/sync/sync.service.ts` (~line 96): selects `FamilyPost.reactions` and ships it as-is, so synced clients get the frozen `commentCount`/`comments` from the JSON. Should apply the same live count (`_count.comments`) as `toFeedPost`.
- Pre-existing, unrelated key mismatch: `Daxelo-Kinrel-App/lib/features/feed/providers/feed_provider.dart:99` (`reactions['comment']`) and `server/src/pulse/collectors/feed-highlight.collector.ts` (`comment?: number`) read a `comment` key that the timeline JSON (`commentCount`) never wrote.

### Pre-existing issues noticed in this file (not fixed)

- `deleteComment`: `post.authorId` is a PERSON id (`FamilyPost.authorId`), compared with the caller's USER id, so the "post author can delete" branch is effectively dead.
- `getComments` / `addComment` / `deleteComment` only check that the post exists, not that the caller is a member of `post.familyId` (the controller passes `userId` only for add/delete). `toggleReaction` does not check the post belongs to `familyId`.

### Expected behaviour to test manually

`GET .../posts/:postId/comments` -> oldest first, `nextCursor` = last returned id when more exist; unknown post 404.
`POST .../comments` -> 201 with the comment; `parentId` on another post or unknown -> 404 "Parent comment not found".
`DELETE .../comments/:commentId`: comment author -> 200; family `owner`/`admin` -> 200; plain `member`/`viewer` who is not the author -> 403; unknown comment (or one on another post) -> 404. Replies disappear with the parent.
Feed/timeline: `JSON.parse(post.reactions).commentCount` equals the number of rows.

### Verification

- `npx prisma generate` with the dummy-engine bypass (see 4a notes) -> client generated; `tsc --noEmit` -> exactly the 5 PRE-EXISTING errors in `predictions.scheduler.ts`, same as on `fix/4a`; none in `modules/timeline` or the specs. So "tsc passes" is NOT literally true (those 5 are outside this task's file list).
- `jest src/modules/timeline src/modules/share src/__tests__/agent03-integration.spec.ts`: timeline spec 44/44 pass; agent03 spec has the same 3 failures as on `fix/4a` (2 Sparq feed tests, share lifecycle; unrelated to timeline), all timeline tests there pass.
- Not covered by any test: the real Prisma queries (mocks only; no DB in the sandbox). The `familyPostComment` queries are type-checked against the generated client; behaviour against Postgres is not exercised.
