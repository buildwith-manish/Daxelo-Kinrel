# Task 2 — ANR Fix Agent

## Task
Fix remaining ANR/force-stop bugs in Flutter/Riverpod app — `ref.watch(... .future)` anti-pattern, cascading rebuilds, redundant API calls, socket debounce, deferred service timing.

## Files Modified
1. `lib/features/explore/presentation/explore_screen.dart` — Removed 2 `.future` anti-patterns
2. `lib/core/kinship/kinship_provider.dart` — Removed `.future` from all 7 providers
3. `lib/core/family/family_provider.dart` — Eliminated redundant API call in familyDetailProvider
4. `lib/core/network/socket_service.dart` — Added 100ms debounce timer for provider invalidation
5. `lib/main.dart` — Added 3-second delay before starting SyncEngine and SocketService

## Verification
- Ran `grep -rn "ref.watch.*\.future" lib/ | grep -v "//"` → zero results
- All anti-patterns eliminated from codebase
