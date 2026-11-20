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
| 1c | not started | `server/src/modules/chat/chat.service.ts`, `chat.gateway.ts`, `server/src/modules/circle/circle.service.ts` (all exist). Note: grep shows no permission-style TODO in `chat.gateway.ts`; only TODO in `circle.service.ts` (line ~811) is a notifications integration, not a permission gap. |
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
