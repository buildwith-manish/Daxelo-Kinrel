# Task: Memory Vault Feature — Daxelo-Kinrel App

## Task ID: memory-vault-feature
## Agent: Main Agent
## Status: Completed

## Summary

Created 5 files for the Memory Vault feature of the Daxelo-Kinrel Flutter app:

### Files Created

1. **`lib/features/memory_vault/data/memory_model.dart`**
   - `MemoryModel` class with all required fields (id, familyId, uploaderId, uploaderName, caption, photoUrl, mediaType, takenAt, taggedPersonIds, createdAt, updatedAt)
   - `fromJson` factory constructor for Supabase row parsing
   - `copyWith` method for immutable updates
   - `isOnThisDay` getter — returns true if takenAt month+day matches today
   - Derived getters: `formattedDate`, `yearsAgo`, `uploaderInitials`
   - `toJson()` for serialization, proper `taggedPersonIds` UUID[] parsing

2. **`lib/features/memory_vault/providers/memory_vault_provider.dart`**
   - `MemoryVaultState` with memories list, onThisDayMemories (derived), isUploading, uploadProgress, isLoading, error
   - `MemoryVaultNotifier` extends StateNotifier with:
     - `loadMemories()` — fetches from Supabase `family_memories` table, falls back to Drift cache if offline via ConnectivityService
     - `uploadMemory()` — compresses image via compute isolate, uploads to Supabase Storage `family-memories` bucket, inserts metadata row, updates local cache, prepends to list
     - `deleteMemory()` — optimistic removal from Storage, Supabase table, Drift cache, and in-memory list with rollback on failure
   - Uses `withRetry` pattern from supabase_service.dart
   - Uses `familyListProvider` to get current familyId
   - Derived providers: `onThisDayMemoriesProvider`, `memoryVaultIsLoadingProvider`, `memoryVaultIsUploadingProvider`, `memoryVaultCountProvider`

3. **`lib/features/memory_vault/presentation/memory_vault_screen.dart`**
   - Full screen with AppBar: "Memory Vault" title with lock icon, orange upload action button
   - Two custom chip-style tabs: "All Photos" and "On This Day" (NOT default TabBar)
   - All Photos tab: GridView with 3 columns, 2px spacing, CachedNetworkImage tiles with shimmer placeholder. Long-press shows context menu (View, Delete if owner). Tap → detail screen.
   - On This Day tab: Vertical list of DKCard items with 16:9 photo, caption, date, uploader name. Empty state if no matches.
   - Upload flow: Bottom sheet with Camera/Gallery picker, caption TextField (200 char), date picker "When was this taken?" (defaults today), member tag picker (horizontal scroll of InitialsAvatar circles from family members, toggle on/off), confirm button with progress text.
   - Premium gating: Checks `PremiumService.isPremium()` — if not premium, shows paywall card instead of upload sheet.

4. **`lib/features/memory_vault/presentation/memory_detail_screen.dart`**
   - Full-screen viewer with Hero widget on image keyed on memoryId
   - Photo fills top portion (55% of screen height)
   - Below: caption in DMSans, takenAt date with years-ago badge, uploader name with avatar, tagged members as small circular avatar chips with names
   - Share icon in top-right using ShareHelper.shareProfile
   - AppBar with transparent background over image

5. **`lib/features/memory_vault/data/supabase_migration.sql`**
   - Creates `family_memories` table with UUID PK, family_id FK, uploader fields, caption, photo_url, media_type, taken_at DATE, tagged_person_ids UUID[], timestamps
   - Enables RLS with 4 policies: SELECT for family members, INSERT for family members, UPDATE for uploader only, DELETE for uploader only
   - Creates `family-memories` Storage bucket (public read)
   - 3 Storage policies: upload for family members, public read, delete for uploader only
   - Performance indexes on family_id, created_at, uploader_id, taken_at
   - Auto-update trigger for updated_at timestamp

## Design System Compliance
- Uses KinrelColors (orange, amber, ember, darkBackground, darkCard, darkElevated, textWhite, textSilver, textDim, gold)
- Uses KinrelTypography (displayFont: Outfit, bodyFont: DMSans) with proper styles
- Uses KinrelSpacing (base, md, lg, xl) and KinrelRadius (lg, md, full, xxl)
- Uses DK components: DKScaffold, DKCard, DKButton, DKAvatar, DKLoadingShimmer
- Uses CachedAvatar and InitialsAvatar from core/widgets/cached_avatar.dart
- Dark theme styling throughout
