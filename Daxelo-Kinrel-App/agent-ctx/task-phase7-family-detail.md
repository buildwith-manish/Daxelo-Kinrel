# Task: Phase 7 - FamilyDetailScreen Modifications

## Task ID: phase7-family-detail
## Agent: Z.ai Code

## Summary

Modified `FamilyDetailScreen` to add Phase 7 features: Invite Members button, Leave Family option, and member role labels.

## Changes Made

### 1. `lib/core/family/family_provider.dart`

- **Added `FamilyMembership` model** (lines ~334-380):
  - Fields: `id`, `familyId`, `userId`, `role`, `joinedAt`
  - `fromJson` factory for Supabase/API deserialization
  - `displayRole` getter: Maps role strings to display labels (Admin, Editor, Member, Viewer)
  - `isAdmin` getter: Returns true for 'admin' or 'owner' roles

- **Added `familyMembershipsProvider`** (lines ~827-873):
  - `FutureProvider.family<List<FamilyMembership>, String>`
  - Tries NestJS API first (`GET /api/families/:familyId/members`)
  - Falls back to Supabase direct query on `FamilyMember` table
  - Graceful error handling with empty list fallback

- **Added `currentUserFamilyRoleProvider`** (lines ~875-891):
  - `Provider.family<String?, String>`
  - Derives the current user's role from `familyMembershipsProvider`
  - Matches current Supabase auth user ID with membership entries

### 2. `lib/features/family/presentation/family_detail_screen.dart`

- **Added import** for `dio_client.dart` (for `dioProvider` used in leave family API call)

- **Modified `_showFamilySettings` method**:
  - Added role detection logic using `familyMembershipsProvider`
  - Computed `isAdminOrOwner` from `isCreator` or membership role
  - Computed `adminCount` and `isOnlyAdmin` for leave restriction
  - **Added "Invite Members" tile** (BEFORE "Share Family Code"):
    - Icon: `Icons.person_add_outlined`
    - Only visible for admin/owner users
    - Navigates to `/family-invite/${widget.familyId}`
  - **Added "Leave Family" tile** (AFTER archive option):
    - Icon: `Icons.exit_to_app_outlined`
    - Marked as `isDestructive: true`
    - Shows confirmation dialog with warning styling
    - Hidden if user is the only admin (shows transfer info instead)

- **Added `_confirmLeaveFamily` method** (lines ~778-877):
  - Warning-styled confirmation dialog (orange/warning theme)
  - Shows info box about irreversibility and need for re-invitation
  - Cancel and "Leave Family" buttons

- **Added `_performLeaveFamily` method** (lines ~879-933):
  - Shows loading indicator
  - Calls `DELETE /api/families/:familyId/leave` via Dio
  - On success: invalidates `familyListProvider` and `familyMembershipsProvider`, navigates to `/`
  - On failure: shows error snackbar

- **Modified `_MembersTab` build method**:
  - Added `ref.watch(familyMembershipsProvider(widget.familyId))` to get role data
  - **Added "Team Members" section** with role chips above the member list
  - Shows `Wrap` of `_RoleChip` widgets for each membership entry

- **Added `_RoleChip` widget** (lines ~2249-2302):
  - Small, rounded chip with subtle background color
  - Color mapping: Admin (orange), Editor (blue), Member (grey/dim), Viewer (silver)
  - Consistent with Kinrel design language

## Design Decisions

1. **Role detection**: Uses both `createdBy` check AND `FamilyMember` role lookup for robustness
2. **Leave restriction**: Prevents sole admins from leaving; shows informative message about transferring role
3. **API fallback**: `familyMembershipsProvider` tries NestJS API first, falls back to Supabase direct query
4. **Safe defaults**: If memberships data is unavailable, invite button only shows for creator, and leave option is available (backend handles authorization)
5. **Role chip colors**: Follows the spec - Admin (orange/KinrelColors.orange), Editor (blue/KinrelColors.blue), Member (grey/KinrelColors.textDim), Viewer (silver/KinrelColors.textSilver)
