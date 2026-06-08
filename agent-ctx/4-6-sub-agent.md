# Task 4-6: Leave Family + Profile Visibility + Invite Permission

## Summary
All 3 parts completed successfully with zero TypeScript errors.

## Changes Made

### Part 1: Leave Family endpoint
- **families.controller.ts**: Added `DELETE /families/:familyId/leave` with JWT auth
- **families.service.ts**: Added `leaveFamily()` method with admin-only-admin check, member deletion, memberCount decrement, and WebSocket events

### Part 2: Profile Visibility enforcement
- **users.service.ts**: Enhanced `getUserByUsername()` with 3-tier visibility (public/connections_only/private) + `usersShareFamily()` helper
- **users.controller.ts**: Passes `viewerId` to `getUserByUsername()`

### Part 3: Invite Permission enforcement
- **family-id.service.ts**: Checks `invitePermission` in `joinByFamilyId()` + `userSharesFamilyWithMember()` helper
- **invitations.service.ts**: Checks invitee's `invitePermission` before creating invitation + `usersShareFamily()` helper

## Verification
- TypeScript compilation: zero errors
