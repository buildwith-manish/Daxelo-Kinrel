# Task 3-c: Database Schema Fixes

## Agent: Database Schema Fix Agent

## Summary
Applied all Phase 3 database schema fixes to `server/prisma/schema.prisma`.

## Changes Made

### 1. onDelete Constraints (C-1 through C-10)
| Model | Relation | onDelete | Rationale |
|-------|----------|----------|-----------|
| SupportEscalation | ticket → SupportTicket | Cascade | Escalations belong to ticket |
| SupportCSAT | ticket → SupportTicket | Cascade | CSAT belongs to ticket |
| SLATracking | ticket → SupportTicket | SetNull | SLA records survive for reporting |
| Incident | author → User | Cascade | Incidents by deleted user removed |
| FamilyMember | user → User | Cascade | Memberships removed on user delete |
| Invitation | inviter → User | Cascade | Invitations removed on user delete |
| Invitation | family → Family | Cascade | Invitations removed on family delete |
| UserModerationStatus | user → User | Cascade | Moderation status removed on user delete |
| Comment | author → User | Cascade | Comments removed on user delete |
| CommunityPost | author → User | Cascade | Posts removed on user delete |

### 2. Unique Constraint Check (H-1/H-2)
- Project uses PostgreSQL → `@unique` on nullable fields allows multiple NULLs
- Family.username `@unique` kept (safe on PostgreSQL)
- Person.username has no `@unique` attribute; enforced at application level
- Updated comments to document PostgreSQL-specific behavior

### 3. New Indexes
- Notification: `@@index([familyId])`
- Person: `@@index([phone])`
- Person: `@@index([familyId, deletedAt])` already existed from prior work

### 4. Missing updatedAt Fields
- OnCallSchedule: added `updatedAt DateTime @updatedAt`
- SupportCSAT: added `updatedAt DateTime @updatedAt`

### 5. FamilyPost.reactions Type Change
- Changed from `String @default("{}")` to `Json @default("{}") @db.JsonB`
- Enables proper PostgreSQL JSONB querying for structured reaction data

## Verification
- `prisma validate`: PASSED
- `npx tsc --noEmit`: 0 errors
- `prisma format`: completed
- `db:push`: Could not run (no local DB, remote Supabase unreachable) — deploy via `prisma migrate deploy`
