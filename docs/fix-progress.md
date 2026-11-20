# Fix progress (branch: stability-fixes)

## Task 1b — admin/owner check on pinning chat messages

Status: code change done, NOT fully verified (see below).

- File: `server/src/modules/chat/chat.service.ts` (`pinMessage`)
- `assertMember()` already returns the `FamilyMember` row, so `pinMessage` now keeps it
  and rejects with `ForbiddenException('Only admins can pin messages')` unless
  `membership.role` is `'admin'` or `'owner'`.
- Pattern reused: the same `FamilyMember.role !== 'admin' && !== 'owner'` check as
  `KinrelController.assertAdmin` (`server/src/kinrel-intelligence/kinrel.controller.ts`)
  and `emotional_attachment.controller.ts`. `unpinMessage` is unchanged (anyone can unpin).
- The block comment above `pinMessage` said "admins OR the message sender can pin"; updated
  to match the new behaviour (admins/owners only).

### Verification gap (sandbox limits)
- `cd server && npx tsc --noEmit` could NOT be made to pass in this sandbox:
  - `npm ci` fails: `package-lock.json` is out of sync with `package.json`
    (missing `date-fns@4.4.0`, `date-fns-tz@3.2.0`). Pre-existing; lockfile left untouched.
  - `prisma generate` fails: proxy blocks `binaries.prisma.sh` (403), so the Prisma client
    is not generated and 16 type errors appear (chat-push.scheduler.ts, chat.service.ts
    lines ~572/573/1171, graph.service.ts, predictions.scheduler.ts, support.service.ts).
  - The 16 errors are identical with and without this change (diffed), so this change adds
    none — but a clean `tsc` pass still needs to be confirmed on a machine/CI with Prisma
    engines available.
- Follow-up for you: fix/refresh `server/package-lock.json`.
