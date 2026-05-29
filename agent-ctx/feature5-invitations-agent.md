# Task: Feature 5 — Invitations with Family ID, QR Code, and Link Sharing

## Summary

Implemented the complete invitation system for the Daxelo-Kinrel platform with 3 invite methods (Family ID, QR Code, Shareable Link) across 4 files.

## Files Created / Modified

### 1. `/home/z/my-project/server/src/modules/invitations/dto/invitation-v2.dto.ts` (NEW)
- **Enums**: `InviteChannel` (family_id, qr_code, link), `InviteStatus` (pending, accepted, rejected, expired, cancelled), `MemberRole` (admin, editor, member, viewer)
- **DTOs**: `CreateFamilyIdInviteDto`, `CreateQrCodeInviteDto`, `CreateLinkInviteDto`, `AcceptInviteDto`, `RejectInviteDto`
- **Result Types**: `InviteResult`, `QrInviteResult`, `LinkInviteResult`, `AcceptInviteResult`, `InvitationDetail`
- All DTOs use class-validator decorators (`@IsString`, `@IsEnum`, `@IsInt`, `@Min`, `@Max`, `@IsOptional`, etc.)

### 2. `/home/z/my-project/server/src/modules/invitations/invitations-v2.service.ts` (NEW)
Complete service with all methods:
- `createFamilyIdInvite()` — Validates family, ensures kinFamilyId exists, creates FamilyInvite record (inviteType=family_id)
- `createQrCodeInvite()` — Generates invite code, creates FamilyInvite record (inviteType=qr_code), returns deep link `kinrel://invite/{inviteCode}`
- `createLinkInvite()` — Creates both FamilyInvite and Invitation records in a transaction, returns share URL `https://kinrel.app/invite/{token}`
- `acceptInvite()` — Looks up by inviteCode (FamilyInvite) or token (Invitation), creates FamilyMember + Person records in transaction, emits WebSocket events (member:joined, person:created, graph:updated), handles idempotency
- `rejectInvite()` — Rejects by invite code or token
- `getPendingInvitations()` — Gets pending invitations for a user by matching email/phone
- `getFamilyInvitations()` — Gets all invitations for a family (admin/member only), merges FamilyInvite + Invitation records
- `revokeInvite()` — Revokes with permission check (inviter or family admin)
- `expireOldInvitations()` — Cron job support to expire old pending invites in both models

Key implementation details:
- Uses both `FamilyInvite` and `Invitation` Prisma models as specified
- QR deep link: `kinrel://invite/{inviteCode}`
- Share URL: `https://kinrel.app/invite/{token}`
- Default expiry: 7 days
- QR max uses: 10 (configurable)
- Link max uses: 0 = unlimited (configurable)
- Idempotent accept: returns existing membership if already a member
- WebSocket events: `member:joined`, `person:created`, `graph:updated`

### 3. `/home/z/my-project/server/src/modules/invitations/invitations-v2.controller.ts` (NEW)
REST API endpoints (all behind `@UseGuards(JwtAuthGuard)`):
- `POST /invitations/v2/family-id` — Create Family ID invite
- `POST /invitations/v2/qr-code` — Create QR code invite
- `POST /invitations/v2/link` — Create shareable link invite
- `POST /invitations/v2/accept` — Accept an invitation
- `POST /invitations/v2/:id/reject` — Reject an invitation
- `GET /invitations/v2/pending` — Get pending invitations for current user
- `GET /invitations/v2/family/:id` — Get invitations for a family
- `DELETE /invitations/v2/:id` — Revoke an invitation

Features:
- JwtAuthGuard on all endpoints
- CurrentUser decorator to extract authenticated user ID
- DTO validation with class-validator
- Expiry parsing helper (supports "7d", "7", ISO date)

### 4. `/home/z/my-project/server/src/modules/invitations/invitations.module.ts` (MODIFIED)
- Added imports: `FamiliesModule`, `GatewayModule`
- Added providers: `InvitationsV2Service`
- Added controllers: `InvitationsV2Controller`
- Both old and new services/controllers coexist

## Validation
- TypeScript compilation: No errors in invitation files
- Lint: No new lint errors introduced
- Existing pre-built dist/ files have pre-existing lint warnings (not related to this change)
- The only TS errors in the project are in `graph-engine.service.ts` (pre-existing)
