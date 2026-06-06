# Task 3-b: Backend Architecture Fix Agent

## Summary
Implemented 5 backend architecture and code quality fixes for V2 Phase 3.

## Fixes Applied

1. **H-3: Deduplicate ROLE_HIERARCHY** — Moved the identical `ROLE_HIERARCHY` constant (viewer:1, member:2, editor:3, admin:4) from 3 service files (families.service.ts, members.service.ts, relationships.service.ts) to the shared `server/src/common/constants.ts`. Each service now imports from the shared location.

2. **H-5: Ticket number race condition** — Wrapped `generateTicketNumber()` in `this.prisma.$transaction()` with collision detection. Changed format from DK-YYYY-NNNNN to TK-YYYYMMDD-NNNN for tighter daily scope. If a collision is detected, finds the highest existing ticket number and increments past it.

3. **H-6: JwtStrategy transaction** — Wrapped the Supabase auto-creation block (user.create → family.create → familyMember.create) in `this.prisma.$transaction()`. Uses `tx` for all operations inside the transaction to prevent orphaned records.

4. **H-1: N+1 search connections_only** — Replaced the per-user `findFirst` query inside the loop with a single batched `findMany` query. Collects connections_only user IDs, queries all at once, builds a Set, then uses O(1) `.has()` lookups.

5. **M-13: Case-insensitive admin search** — Added `mode: 'insensitive'` to `contains` filters for email, name, and username in `admin.service.ts listUsers()`. Phone field left as exact match.

## Verification
- TypeScript compilation: 0 errors (`npx tsc --noEmit` passes cleanly)
- No new packages installed
