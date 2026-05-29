# Worklog — Profile @username, Family ID, and Search Enhancements

## Summary

Extended the Daxelo Kinrel Flutter app with three tasks: adding @username display and Family ID features to the profile screen, adding a username field with real-time availability checking to the profile edit screen, and updating search to support @username and KIN-XXXXXXXX queries.

---

## Task 1: Update Profile Screen Header

**File:** `lib/features/profile/presentation/profile_screen.dart`

### Changes Made

1. **Added imports:**
   - `package:flutter/services.dart` — for `ClipboardData` / `Clipboard.setData`
   - `../../../core/family/family_id_provider.dart` — for Family ID provider reference

2. **Added @username display in `_buildHeader`:**
   - After the display name, shows `@username` in orange (Instagram-style) if the user has a username set
   - Tapping the username copies it to clipboard and shows a snackbar
   - If no username is set, shows a "Set username" link that navigates to `/profile/edit`

3. **Added "Join Family by ID" row in Family Management section:**
   - New `_SettingsRow` with `Icons.qr_code_rounded`, orange icon/label styling
   - Subtitle: "Enter KIN-XXXXXXXX to join"
   - Navigates to `/join-family` route
   - Added before "My family trees" with a divider

---

## Task 2: Add Username Section in Profile Edit Screen

**File:** `lib/features/profile/presentation/profile_edit_screen.dart`

### Changes Made

1. **Added import:**
   - `../../username/providers/username_provider.dart` — for `UsernameValidator`, `UsernameAvailability`, `usernameProvider`

2. **Added state variables:**
   - `late TextEditingController _usernameController`
   - `late FocusNode _usernameFocusNode`
   - `String _initialUsername = ''`

3. **Updated `initState`:**
   - Initialize `_usernameController` and `_usernameFocusNode`

4. **Updated `_loadProfileData`:**
   - Extract `username` from profile
   - Set `_usernameController.text` and `_initialUsername` in `setState`

5. **Updated `dispose`:**
   - Dispose `_usernameController` and `_usernameFocusNode`

6. **Updated `_checkForChanges`:**
   - Added `_usernameController.text != _initialUsername` check

7. **Added Username field in build method:**
   - After Display Name field, before Email field
   - Uses new `_buildUsernameField()` method

8. **Added `_buildUsernameField` method:**
   - Watches `usernameProvider` for real-time availability state
   - Shows `@ ` prefix in orange
   - Shows loading spinner while checking availability
   - Shows green checkmark when available, red cancel when taken
   - Helper text: "3-30 chars, lowercase letters, numbers, underscores"
   - Calls `checkAvailability` on text changes with lowercase normalization

9. **Updated `_saveProfile`:**
   - Adds `username` to `changedFields` if changed (lowercased comparison)
   - Updates `_initialUsername` after successful save

---

## Task 3: Update Search for @username and KIN-XXXXXXXX

### File: `lib/data/repositories/search_repository.dart`

1. **Updated `_matchesPerson`:**
   - Added username matching: strips `@` prefix from query, matches `person.username` (case-insensitive contains)
   - Updated doc comments

2. **Updated `_matchesFamily`:**
   - Added KIN Family ID matching: `family.kinFamilyId` (case-insensitive contains)
   - Added family username matching: strips `@` prefix from query, matches `family.username`
   - Reordered: name → kinFamilyId → username → familyCode → displayId → actualId
   - Updated doc comments

### File: `lib/features/search/presentation/search_screen.dart`

1. **Updated search hint text:**
   - Changed from `"Search by name, person ID, or family ID..."` to `"Search by name, @username, or KIN-XXXXXXXX..."`

### File: `lib/core/family/family_provider.dart`

1. **Added `kinFamilyId` to `Family` model:**
   - Added `this.kinFamilyId` to constructor
   - Added `kinFamilyId: json['kinFamilyId'] as String?` to `fromJson`
   - Added `final String? kinFamilyId` field declaration
   - Added `'kinFamilyId': kinFamilyId` to `toJson`
   - Comment: `// KIN Family ID system`

---

## Files Modified

| File | Changes |
|------|---------|
| `lib/features/profile/presentation/profile_screen.dart` | Added Clipboard import, family_id_provider import, @username display, Join Family by ID row |
| `lib/features/profile/presentation/profile_edit_screen.dart` | Added username_provider import, username state/controllers, _buildUsernameField, save logic |
| `lib/data/repositories/search_repository.dart` | Updated _matchesPerson and _matchesFamily for username/KIN-ID matching |
| `lib/features/search/presentation/search_screen.dart` | Updated search hint text |
| `lib/core/family/family_provider.dart` | Added kinFamilyId field to Family model |

---

## Design Decisions

- Kept all existing dark theme design tokens (`_bg`, `_cardBg`, `_orange`, `_textPrimary`, etc.)
- No changes to existing architecture or widget structure — only extensions
- Username in profile header follows Instagram-style (orange `@username` tag, tappable to copy)
- "Set username" shown as a fallback CTA when no username is set
- Username field uses `@ ` prefix visually (not stored) and real-time availability checking with debounce
- Search matches both `@username` and plain `username` queries by stripping the `@` prefix
- `kinFamilyId` added to Family model to support KIN-XXXXXXXX matching in search
