# Task 3-d: Flutter Fix Agent

## Task: Phase 3 Flutter fixes (6 items)

### Work Completed

#### Fix 1: familyListProvider error propagation (Flutter #27)
- Changed `familyListErrorProvider` from `Provider<Object?>` to `StateProvider<String?>` in `family_provider.dart`
- In `familyListProvider` catch block: sets `familyListErrorProvider` with error message when both network and Isar cache fail; clears error on Isar cache hit
- On successful data load (line ~530): clears `familyListErrorProvider`
- In `family_list_screen.dart`: added `ref.watch(familyListErrorProvider)` check; when error is non-null and families is empty, shows `DKErrorState` with the error message and retry button; retry clears error and invalidates `familyListProvider`

#### Fix 2: Duplicate archive buttons (Flutter #42)
- Merged two "Archive Family" ListTiles into one conditional block in `family_list_screen.dart`
- If `isCreator`: shows only "Archive Family" (warning color) → `_confirmDeleteFromList`
- If `!isCreator`: shows "Leave Family" (gold color, exit icon) → `_confirmArchiveFamily`
- Removed the non-creator info text about "Only the family creator can archive this family"

#### Fix 3: Misleading snackbar on permanent delete (Flutter #43)
- Changed snackbar message from "Family archived successfully" to "Family permanently deleted" in `family_detail_screen.dart` line 676

#### Fix 4: Deduplicate _generateId() (Flutter #39)
- Created `lib/core/utils/id_generator.dart` with shared `generateId()` function (full ID, no truncation)
- Replaced local `_generateId()` in `family_provider.dart` with import + `generateId()` call; removed `dart:math` import
- Replaced local `static _generateId()` in `offline_family_repository.dart` with import + `generateId()` call
- Replaced local `_generateId()` in `feed_provider.dart` with import + `generateId()` call; removed `dart:math` import
- Feed provider previously truncated to 25 chars — now uses full ID to avoid collisions

#### Fix 5: AI chat response type check (Flutter #25)
- In `ai_chat_provider.dart` line ~130: replaced `final data = response.data as Map<String, dynamic>` with type-safe check
- Added `is! Map<String, dynamic>` check that throws `FormatException('Unexpected response format from AI service')`

#### Fix 6: Notifications state error field (Flutter #28)
- Added `String? error` and `bool isLoading` fields to `NotificationsState` class
- Updated `copyWith` to include `isLoading` and `error` parameters (error uses `String? Function()` pattern for nullability)
- In `loadNotifications()`: sets `isLoading: true, error: null` on start; sets `isLoading: false, error: null` on success; sets `error: e.toString(), isLoading: false` on catch

### Files Modified
1. `Daxelo-Kinrel-App/lib/core/family/family_provider.dart` — error propagation + generateId dedup
2. `Daxelo-Kinrel-App/lib/features/family/presentation/family_list_screen.dart` — error UI + duplicate archive fix
3. `Daxelo-Kinrel-App/lib/features/family/presentation/family_detail_screen.dart` — snackbar fix
4. `Daxelo-Kinrel-App/lib/core/utils/id_generator.dart` — NEW: shared ID generator
5. `Daxelo-Kinrel-App/lib/core/database/repositories/offline_family_repository.dart` — generateId dedup
6. `Daxelo-Kinrel-App/lib/features/feed/providers/feed_provider.dart` — generateId dedup
7. `Daxelo-Kinrel-App/lib/features/ai_chat/providers/ai_chat_provider.dart` — type check
8. `Daxelo-Kinrel-App/lib/features/notifications/providers/notifications_provider.dart` — error + isLoading fields
