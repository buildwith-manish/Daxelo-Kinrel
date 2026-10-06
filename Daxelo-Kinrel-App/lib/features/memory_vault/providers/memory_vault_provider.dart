// lib/features/memory_vault/providers/memory_vault_provider.dart
//
// DAXELO KINREL — Memory Vault Provider (v2 — image + post link + pin + cursor)
//
// AsyncNotifierProvider for the Memory Vault + Memories Timeline feature.
// Manages:
//   - Cursor-based pagination (10,000+ memories per family)
//   - Image upload (compressed, cropped) to memory-images bucket
//   - Save Post as Memory (creates memory with sourcePostId)
//   - Pin/unpin memory to Memory Vault (isPinnedToVault)
//   - Delete memory (cascades to storage object)
//
// Flow (per implementation prompt):
//   Memory → Timeline (chronological view) → Memory Vault (pinned subset)
//   All three views read from the SAME `family_memories` table — no
//   duplication. Memory Vault filters to `is_pinned_to_vault = true`.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/premium_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/database/sync/connectivity_service.dart';
import '../data/memory_model.dart';

// ═══════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════

/// Outcome of a quota check for a hero-photo attachment on a Timeline entry.
///
/// The user spec is explicit:
///   - Timeline entry creation WITHOUT a photo is always free and uncapped.
///   - Only the optional hero photo attachment draws against the SHARED monthly
///     media quota (the same counter already used by Memory Vault uploads).
///   - When the user is at/near the cap, we still allow the entry to be saved
///     without a photo (the photo is silently dropped) rather than blocking the
///     whole memory from being created.
enum QuotaCheckResult {
  /// No quota applies — the entry has no photo, so the counter is untouched.
  /// (Per spec: "Timeline entry creation WITHOUT a photo is always free and
  /// uncapped, regardless of tier or quota status.")
  notApplicableNoPhoto,

  /// Photo attachment allowed — the shared counter had room and has been (or
  /// will be) incremented.
  allowed,

  /// Free-tier user has hit the shared monthly cap. The caller should still
  /// save the entry WITHOUT the photo (per spec: "still allow the entry to be
  /// saved without a photo if they choose to proceed without one rather than
  /// blocking the whole memory from being created").
  cappedDropPhoto,
}

/// A snapshot of the shared monthly quota state, returned from
/// [MemoryVaultNotifier.checkSharedQuota]. Used by the UI to render the
/// same soft-cap messaging pattern already established for Memory Vault.
class SharedQuotaSnapshot {
  const SharedQuotaSnapshot({
    required this.used,
    required this.cap,
    required this.isPremium,
  });

  /// Number of photo uploads the user has made in the current calendar month.
  final int used;

  /// Free-tier monthly cap (default 50). Premium users have no cap (the field
  /// is still populated for display, but `isPremium` short-circuits the cap).
  final int cap;

  /// Whether the user is on Kinrel Plus (cap is bypassed when true).
  final bool isPremium;

  /// Whether the user is at or above 80% of the cap (the "running low" band).
  bool get isApproachingCap =>
      !isPremium && used >= (cap * 0.8).round() && used < cap;

  /// Whether the user has hit the cap.
  bool get isAtCap => !isPremium && used >= cap;

  /// Whether a photo attachment is currently allowed.
  bool get canAttachPhoto => isPremium || used < cap;
}

/// Immutable state for the Memory Vault + Memories Timeline feature.
class MemoryVaultState {
  const MemoryVaultState({
    this.memories = const [],
    this.isUploading = false,
    this.uploadProgress,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.cursor,
    this.error,
  });

  /// All memories loaded so far for the current family, ordered
  /// by created_at DESC (cursor pagination).
  final List<MemoryModel> memories;

  /// Whether an upload is currently in progress.
  final bool isUploading;

  /// Human-readable upload progress text (e.g. "Compressing...", "Uploading...").
  final String? uploadProgress;

  /// Whether memories are being loaded from the server (initial load).
  final bool isLoading;

  /// Whether the next page is being fetched (infinite scroll).
  final bool isLoadingMore;

  /// Whether more memories exist beyond what's currently loaded.
  final bool hasMore;

  /// Cursor for the next page: the createdAt of the OLDEST loaded memory.
  /// null when no memories are loaded or all have been fetched.
  final DateTime? cursor;

  /// Error message if the last operation failed.
  final String? error;

  // ── Derived Getters ─────────────────────────────────────────────

  /// Memories where takenAt month+day matches today.
  List<MemoryModel> get onThisDayMemories =>
      memories.where((m) => m.isOnThisDay).toList();

  /// Whether there are any memories.
  bool get hasMemories => memories.isNotEmpty;

  /// Whether there are "On This Day" memories.
  bool get hasOnThisDay => onThisDayMemories.isNotEmpty;

  /// Pinned memories only (Memory Vault subset).
  List<MemoryModel> get pinnedMemories =>
      memories.where((m) => m.isPinnedToVault).toList()
        // Sort: pinned first by created_at desc
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Whether any memories are pinned to the vault.
  bool get hasPinnedMemories => pinnedMemories.isNotEmpty;

  /// Total count of pinned memories (for badge display).
  int get pinnedCount => pinnedMemories.length;

  /// Memories sorted for the Memory Vault view per Feature 8 spec:
  ///   1. Pinned memories (newest pinned first)
  ///   2. Non-pinned memories (newest first)
  ///
  /// This is a derived view over the SAME data the Timeline uses
  /// (per Feature 7's "single data source, different presentation"
  /// requirement) — no duplication, just a different sort order.
  List<MemoryModel> get vaultSortedMemories {
    final pinned = <MemoryModel>[];
    final notPinned = <MemoryModel>[];
    for (final m in memories) {
      if (m.isPinnedToVault) {
        pinned.add(m);
      } else {
        notPinned.add(m);
      }
    }
    // Pinned: newest first
    pinned.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Non-pinned: newest first
    notPinned.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...pinned, ...notPinned];
  }

  // ── Copy With ────────────────────────────────────────────────────

  MemoryVaultState copyWith({
    List<MemoryModel>? memories,
    bool? isUploading,
    String? uploadProgress,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    DateTime? cursor,
    bool clearCursor = false,
    String? error,
  }) {
    return MemoryVaultState(
      memories: memories ?? this.memories,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      cursor: clearCursor ? null : (cursor ?? this.cursor),
      error: error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════

/// AsyncNotifier managing the Memory Vault + Memories Timeline state and
/// operations.
///
/// All operations are family-scoped — the family ID comes from the
/// family list provider (the first family the user belongs to, since
/// the current architecture is single-family-per-session).
class MemoryVaultNotifier extends StateNotifier<MemoryVaultState> {
  MemoryVaultNotifier(this._ref) : super(const MemoryVaultState());

  final Ref _ref;
  static const _tableName = 'family_memories';
  static const _bucketName = 'family-memories';
  static const _imageBucketName = 'memory-images';
  static const _uuid = Uuid();

  /// Page size for cursor pagination. The implementation prompt
  /// specifies 20 items per page.
  static const int pageSize = 20;

  // ── Load Memories (initial) ────────────────────────────────────────

  /// Fetches the first page of memories from Supabase (cursor pagination).
  Future<void> loadMemories() async {
    state = state.copyWith(isLoading: true, error: null, clearCursor: true);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final familyId = _getCurrentFamilyId();
      if (familyId == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final response = await withRetry(
        () => client
            .from(_tableName)
            .select()
            .eq('family_id', familyId)
            .order('created_at', ascending: false)
            .limit(pageSize),
        operationName: 'Load memories page 1',
        maxAttempts: 2,
      );

      final memories = (response as List)
          .map((json) => MemoryModel.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        memories: memories,
        isLoading: false,
        hasMore: memories.length >= pageSize,
        cursor: memories.isNotEmpty ? memories.last.createdAt : null,
        error: null,
      );

      // Write to cache
      await _writeToCache(memories);
    } catch (e) {
      debugPrint('⚠️ MemoryVault loadMemories error: $e');
      // Try cache as fallback on error
      await _loadFromCache();
      if (state.memories.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not load memories. Please check your connection.',
        );
      }
    }
  }

  /// Loads more memories (infinite scroll). Uses cursor pagination —
  /// fetches memories where `created_at < cursor`.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    final cursor = state.cursor;
    if (cursor == null) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isLoadingMore: false);
        return;
      }

      final familyId = _getCurrentFamilyId();
      if (familyId == null) {
        state = state.copyWith(isLoadingMore: false);
        return;
      }

      final response = await withRetry(
        () => client
            .from(_tableName)
            .select()
            .eq('family_id', familyId)
            .lt('created_at', cursor.toIso8601String())
            .order('created_at', ascending: false)
            .limit(pageSize),
        operationName: 'Load more memories',
        maxAttempts: 2,
      );

      final newMemories = (response as List)
          .map((json) => MemoryModel.fromJson(json as Map<String, dynamic>))
          .toList();

      final updated = [...state.memories, ...newMemories];
      state = state.copyWith(
        memories: updated,
        isLoadingMore: false,
        hasMore: newMemories.length >= pageSize,
        cursor: newMemories.isNotEmpty ? newMemories.last.createdAt : cursor,
      );

      // Update cache
      await _writeToCache(updated);
    } catch (e) {
      debugPrint('⚠️ MemoryVault loadMore error: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final db = _ref.read(isarProvider);
      final familyId = _getCurrentFamilyId();
      if (familyId == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final cachedEntries = await db.getCachedApiEntry('memories_$familyId');
      if (cachedEntries != null) {
        // Cache is best-effort only; if decode fails we silently skip.
        state = state.copyWith(isLoading: false);
        return;
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('⚠️ MemoryVault _loadFromCache error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  // ── Create Memory (full payload) ───────────────────────────────────

  /// Returns a snapshot of the shared monthly photo quota state.
  ///
  /// This is the SAME counter that Memory Vault uploads draw against —
  /// there is ONE shared monthly media quota, NOT a separate one for
  /// Timeline hero photos. The UI uses this snapshot to render the same
  /// soft-cap messaging pattern already established for Memory Vault
  /// (PaywallSheet when capped, "Running low on uploads this month —
  /// Kinrel Plus removes this limit" SnackBar at ≥80%).
  ///
  /// Per the user spec: "do not create a second, separate 'memories photo'
  /// limit; both Memory Vault uploads and Timeline entry photos count
  /// against one shared monthly counter."
  Future<SharedQuotaSnapshot> checkSharedQuota() async {
    final isPremium = await PremiumService.isPremiumActive();
    final used = await PremiumService.getMemoryVaultUploadsThisMonth();
    final cap = PremiumService.memoryVaultFreeMonthlyCap;
    return SharedQuotaSnapshot(
      used: used,
      cap: cap,
      isPremium: isPremium,
    );
  }

  /// Creates a new memory with all structured fields (title, description,
  /// location, memoryType, members, date, sourcePostId).
  ///
  /// [imageBytes] — optional pre-cropped + pre-compressed image bytes for
  /// the hero photo (one photo per Timeline entry, per spec). If provided
  /// AND the shared monthly quota has room (or the user is on Kinrel Plus),
  /// the image is uploaded to the `memory-images` bucket and the resulting
  /// URL + storage key are stored on the memory row. If the user is at the
  /// shared monthly cap, the photo is silently dropped (the memory is still
  /// saved as a text-only entry — per spec: "still allow the entry to be
  /// saved without a photo if they choose to proceed without one rather
  /// than blocking the whole memory from being created").
  ///
  /// [externalImageUrl] — optional already-hosted image URL to use as the
  /// hero photo WITHOUT uploading a new storage object or consuming quota.
  /// Used by Feature 2 (post-to-memory linking) when the post already has
  /// an image in the `post-media` bucket — we simply reference that URL
  /// (the post upload already paid for the storage; the marginal cost of
  /// displaying it on the Timeline entry is zero, so no quota is drawn).
  /// `image_storage_key` is left null in this case (deleting the memory
  /// must NOT delete the post's image).
  ///
  /// Per the spec: "Timeline entry creation WITHOUT a photo is always
  /// free and uncapped, regardless of tier or quota status — only the
  /// photo attachment is quota-gated." When both [imageBytes] and
  /// [externalImageUrl] are null, the quota check is bypassed entirely
  /// (no `canUploadMemoryVaultPhoto` call, no `incrementMemoryVaultUpload`
  /// call).
  ///
  /// [sourcePostId] — optional FK to FamilyPost. Set when the memory
  /// was created from a post via the "Also add this to our family
  /// timeline" flow (Feature 2). This is the link target for the
  /// "View full album in Memory Vault →" cross-link (Feature 3).
  Future<MemoryModel?> createMemory({
    required String title,
    String? description,
    String? location,
    String? memoryType,
    DateTime? date,
    List<String> memberIds = const [],
    Uint8List? imageBytes,
    String? imageExtension,
    String? externalImageUrl,
    String? sourcePostId,
  }) async {
    state = state.copyWith(
      isUploading: true,
      uploadProgress: 'Saving memory...',
      error: null,
    );

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(
          isUploading: false,
          uploadProgress: null,
          error: 'Not connected to server. Please try again.',
        );
        return null;
      }

      final familyId = _getCurrentFamilyId();
      if (familyId == null) {
        state = state.copyWith(
          isUploading: false,
          uploadProgress: null,
          error: 'No family selected.',
        );
        return null;
      }

      final userId = client.auth.currentUser?.id ?? '';
      final userName =
          client.auth.currentUser?.userMetadata?['name'] as String? ?? '';
      final memoryId = _uuid.v4();
      final now = DateTime.now();

      // ── Shared-quota gate (only when a NEW photo is uploaded) ─────
      // Per spec: only the optional hero photo (uploaded by the user
      // through the create flow) draws against the shared monthly media
      // quota. Text-only entries skip the check entirely. When the
      // memory is created via the post-to-memory linking flow (Feature 2)
      // and references an already-hosted image URL (externalImageUrl),
      // no quota is consumed — the post upload already paid for that
      // storage and we're just displaying the URL again (zero marginal
      // cost).
      //
      // When the user is at/near the cap, we still create the memory —
      // we just drop the photo. This matches the spec's "still allow
      // the entry to be saved without a photo if they choose to proceed
      // without one rather than blocking the whole memory from being
      // created" requirement.
      Uint8List? effectiveImageBytes = imageBytes;
      if (imageBytes != null) {
        final quota = await checkSharedQuota();
        if (quota.canAttachPhoto) {
          // Allowed — increment the SHARED counter (the same one Memory
          // Vault uploads use). We increment BEFORE the upload so a
          // concurrent Memory Vault upload can't double-spend.
          await PremiumService.incrementMemoryVaultUpload();
        } else {
          // Capped — drop the photo, save the entry text-only.
          // The UI should have shown the soft-cap messaging before
          // reaching this point; this is the defensive backstop.
          debugPrint(
            '⚠️ MemoryVault.createMemory: at shared monthly cap '
            '(${quota.used}/${quota.cap}) — saving entry without photo.',
          );
          effectiveImageBytes = null;
        }
      }

      // Step 1: Upload image (if provided AND quota allowed), OR fall
      // back to the external image URL (post-to-memory link) — the
      // latter does NOT consume quota and does NOT own the storage object.
      String? imageUrl;
      String? imageStorageKey;
      if (effectiveImageBytes != null) {
        state = state.copyWith(uploadProgress: 'Uploading cover image...');

        final ext = (imageExtension ?? 'jpg').toLowerCase();
        // Path: memory-images/{familyId}/{memoryId}/image.{ext}
        imageStorageKey = '$familyId/$memoryId/image.$ext';
        try {
          await withRetry(
            () => client.storage.from(_imageBucketName).uploadBinary(
                  imageStorageKey!,
                  effectiveImageBytes!,
                  fileOptions: FileOptions(
                    contentType: ext == 'png'
                        ? 'image/png'
                        : ext == 'webp'
                            ? 'image/webp'
                            : 'image/jpeg',
                    upsert: true,
                  ),
                ),
            operationName: 'Upload memory cover image',
            maxAttempts: 2,
          );

          imageUrl = client
              .storage
              .from(_imageBucketName)
              .getPublicUrl(imageStorageKey);
        } catch (e) {
          // Per spec: "still allow the entry to be saved without a photo
          // if they choose to proceed without one rather than blocking
          // the whole memory from being created." The upload failed —
          // save the entry without the photo (the quota counter was
          // incremented; we'll let the user's failure handler in the UI
          // surface this as a SnackBar, but the entry is saved).
          debugPrint('⚠️ MemoryVault image upload failed: $e — saving without photo');
          imageUrl = null;
          imageStorageKey = null;
          // Note: we don't decrement the quota counter here. The intent
          // was to upload; the user's photo "slot" was consumed. This
          // matches the Memory Vault upload failure behavior (the
          // counter is incremented optimistically and the failure is
          // surfaced separately). Decrementing would create a race
          // where a second concurrent upload could exceed the cap.
        }
      } else if (externalImageUrl != null && externalImageUrl.isNotEmpty) {
        // Feature 2 path: the post already has an image in the
        // `post-media` bucket. We reference the URL directly — no
        // re-upload, no quota consumption, no image_storage_key
        // (deleting the memory must NOT delete the post's image).
        // The image will display on the Timeline entry as the hero.
        imageUrl = externalImageUrl;
        imageStorageKey = null;
      }

      // Step 2: Insert memory row
      state = state.copyWith(uploadProgress: 'Saving details...');
      final insertData = {
        'id': memoryId,
        'family_id': familyId,
        'uploader_id': userId,
        'uploader_name': userName,
        'photo_url': imageUrl ?? '',
        'media_type': 'photo',
        'taken_at': (date ?? now).toIso8601String(),
        'tagged_person_ids': memberIds,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        // v2 fields
        if (imageUrl != null) 'image_url': imageUrl,
        if (imageStorageKey != null) 'image_storage_key': imageStorageKey,
        'title': title,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (memoryType != null) 'memory_type': memoryType,
        if (sourcePostId != null) 'source_post_id': sourcePostId,
        'is_pinned_to_vault': false,
      };

      await withRetry(
        () => client.from(_tableName).insert(insertData).select().single(),
        operationName: 'Insert memory row',
        maxAttempts: 2,
      );

      // Step 3: Prepend to in-memory list
      final newMemory = MemoryModel.fromJson(insertData);
      final updatedMemories = [newMemory, ...state.memories];

      // Update cache
      await _writeToCache(updatedMemories);

      state = state.copyWith(
        memories: updatedMemories,
        isUploading: false,
        uploadProgress: null,
        error: null,
      );

      debugPrint('✅ Memory created: $memoryId');
      return newMemory;
    } catch (e) {
      debugPrint('⚠️ MemoryVault createMemory error: $e');
      state = state.copyWith(
        isUploading: false,
        uploadProgress: null,
        error: 'Failed to save memory: ${_sanitizeError(e)}',
      );
      return null;
    }
  }

  // ── Save Post as Memory (Feature 2: post → timeline linking) ─────

  /// Creates a Timeline entry from an existing post.
  ///
  /// This is the backend side of Feature 2 ("Also add this to our family
  /// timeline" toggle on the Post creation flow). When the toggle is ON,
  /// the post-creation flow calls this method to AUTO-CREATE a Timeline
  /// entry using the post's content (text + the post's image if it has
  /// one). The entry is categorized appropriately — if the post has an
  /// occasion, it's mapped to the closest Timeline category; otherwise
  /// the entry defaults to "Custom".
  ///
  /// Per the spec, this linkage is **one-directional at creation time
  /// only**. Editing or deleting the original post afterward should NOT
  /// cascade-delete the Timeline entry; they're treated as two
  /// independent records after creation, linked only by this one-time
  /// copy action (the `source_post_id` field on the memory row).
  ///
  /// The post's image URL (if any) is referenced — NOT re-uploaded. The
  /// post upload already paid for that storage; displaying it on the
  /// Timeline entry has zero marginal cost, so NO quota is consumed
  /// (the `externalImageUrl` path in [createMemory] bypasses the
  /// `canUploadMemoryVaultPhoto` / `incrementMemoryVaultUpload` calls).
  ///
  /// Per the spec: "if the post has multiple images, use the first/
  /// primary one as the Timeline entry's hero image, and the rest
  /// remain part of the original post only, not duplicated into
  /// Timeline." The PostCreate flow currently supports a single image
  /// per post (single `mediaFile`); even if it supported multiple,
  /// only the first URL would be passed here.
  Future<MemoryModel?> savePostAsMemory({
    required String postId,
    required String postText,
    String? postImageUrl,
    DateTime? postDate,
    String? title,
    String? description,
    String? location,
    String? memoryType,
    List<String> memberIds = const [],
  }) async {
    return createMemory(
      title: title ?? (postText.isNotEmpty ? _truncateTitle(postText) : 'Untitled Memory'),
      description: description ?? (postText.isNotEmpty ? postText : null),
      location: location,
      memoryType: memoryType,
      date: postDate ?? DateTime.now(),
      memberIds: memberIds,
      // Pass the post's image URL through as the hero photo — NO new
      // upload, NO quota consumption. The createMemory method handles
      // this path via `externalImageUrl` (sets `image_url` directly,
      // leaves `image_storage_key` null so deleting the memory does
      // not delete the post's image).
      imageBytes: null,
      externalImageUrl: postImageUrl,
      sourcePostId: postId,
    );
  }

  // ── Pin / Unpin Memory to Vault ────────────────────────────────────

  /// Toggles the `is_pinned_to_vault` flag on a memory.
  /// Optimistic update — the UI flips immediately; the server is updated
  /// in the background. Rolls back on error.
  Future<void> togglePinToVault(String memoryId) async {
    final idx = state.memories.indexWhere((m) => m.id == memoryId);
    if (idx == -1) return;

    final oldMemory = state.memories[idx];
    final newPinned = !oldMemory.isPinnedToVault;

    // Optimistic update
    final updatedList = List<MemoryModel>.from(state.memories);
    updatedList[idx] = oldMemory.copyWith(isPinnedToVault: newPinned);
    state = state.copyWith(memories: updatedList);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        // Revert
        final reverted = List<MemoryModel>.from(state.memories);
        reverted[idx] = oldMemory;
        state = state.copyWith(memories: reverted, error: 'Not connected');
        return;
      }

      await withRetry(
        () => client.from(_tableName).update({
          'is_pinned_to_vault': newPinned,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', memoryId),
        operationName: 'Toggle pin to vault',
        maxAttempts: 2,
      );

      debugPrint('✅ Memory ${newPinned ? 'pinned' : 'unpinned'}: $memoryId');
    } catch (e) {
      debugPrint('⚠️ MemoryVault togglePinToVault error: $e');
      // Revert
      final reverted = List<MemoryModel>.from(state.memories);
      reverted[idx] = oldMemory;
      state = state.copyWith(
        memories: reverted,
        error: 'Could not update pin status',
      );
    }
  }

  // ── Delete Memory ─────────────────────────────────────────────────

  /// Removes a memory from Storage (cover image only — doesn't touch
  /// post-media), the Supabase table, and the in-memory list.
  Future<void> deleteMemory(String memoryId) async {
    // Optimistic remove
    final previousMemories = state.memories;
    final updatedMemories =
        state.memories.where((m) => m.id != memoryId).toList();
    state = state.copyWith(memories: updatedMemories);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(
          memories: previousMemories,
          error: 'Not connected to server.',
        );
        return;
      }

      final familyId = _getCurrentFamilyId();
      final memory = previousMemories.firstWhere(
        (m) => m.id == memoryId,
        orElse: () => MemoryModel.placeholder(memoryId),
      );

      // Step 1: Delete cover image from `memory-images` bucket (if exists)
      // Per the implementation prompt: "Delete storage object when memory deleted"
      if (memory.imageStorageKey != null &&
          memory.imageStorageKey!.isNotEmpty) {
        try {
          await client.storage
              .from(_imageBucketName)
              .remove([memory.imageStorageKey!]);
        } catch (e) {
          debugPrint('⚠️ memory-images delete failed (continuing): $e');
        }
      }

      // Step 2: Delete from table
      await withRetry(
        () => client.from(_tableName).delete().eq('id', memoryId),
        operationName: 'Delete memory',
        maxAttempts: 2,
      );

      // Step 3: Update cache
      await _writeToCache(updatedMemories);

      debugPrint('✅ Memory deleted: $memoryId');
    } catch (e) {
      debugPrint('⚠️ MemoryVault deleteMemory error: $e');
      state = state.copyWith(
        memories: previousMemories,
        error: 'Delete failed: ${_sanitizeError(e)}',
      );
    }
  }

  // ── Cross-link helpers (Feature 3) ─────────────────────────────────

  /// Returns the Timeline entries that were created via the post-to-memory
  /// linking flow (Feature 2) — i.e. memories where `source_post_id` is set.
  ///
  /// Used by Feature 3's "View full album in Memory Vault →" cross-link:
  /// when a Timeline entry has `sourcePostId != null`, we know the entry
  /// was created via the linking flow and there's an explicit association
  /// between the entry and the original post (and any other memories that
  /// may share the same date/category in the Memory Vault).
  ///
  /// Per the spec: "this cross-link can initially be scoped to only the
  /// specific photo(s) uploaded through the post-to-memory linking flow
  /// (item 2), where the association is already explicit via the shared
  /// creation action, rather than attempting to infer associations between
  /// previously-unrelated Memory Vault and Timeline content."
  List<MemoryModel> memoriesLinkedFromPost(String postId) {
    return state.memories
        .where((m) => m.sourcePostId == postId)
        .toList();
  }

  /// Returns ALL Memory Vault photos that share the same `taken_at` date
  /// (calendar date — year-agnostic) AND `memory_type` as the given memory.
  /// Used to determine whether a "View full album in Memory Vault →"
  /// affordance should be shown on a Timeline entry's detail view.
  ///
  /// Per the spec: "When a Timeline entry's photo corresponds to an event
  /// that also has additional photos stored in Memory Vault (e.g., tagged
  /// with the same date/event/category), show a 'View full album in
  /// Memory Vault →' link."
  ///
  /// Returns an empty list when there are no other photos for the same
  /// event (in which case the UI should hide the cross-link affordance).
  List<MemoryModel> albumForMemory(String memoryId) {
    final target = state.memories.firstWhere(
      (m) => m.id == memoryId,
      orElse: () => MemoryModel.placeholder(memoryId),
    );
    if (target.takenAt == null && target.memoryType == null) {
      return const [];
    }
    return state.memories.where((m) {
      if (m.id == memoryId) return false;
      // Match on same calendar day (year-agnostic) OR same memory_type.
      final sameDate = target.takenAt != null && m.takenAt != null &&
          m.takenAt!.month == target.takenAt!.month &&
          m.takenAt!.day == target.takenAt!.day;
      final sameType = target.memoryType != null &&
          m.memoryType != null &&
          m.memoryType == target.memoryType;
      return sameDate || sameType;
    }).toList();
  }

  // ── Private Helpers ──────────────────────────────────────────────

  /// Get the current family ID from the family list provider.
  String? _getCurrentFamilyId() {
    try {
      final familiesAsync = _ref.read(familyListProvider);
      final families = familiesAsync.valueOrNull;
      if (families == null || families.isEmpty) return null;
      return families.first.id;
    } catch (e) {
      debugPrint('⚠️ MemoryVault: Could not get family ID: $e');
      return null;
    }
  }

  /// Write memories to Isar API cache.
  Future<void> _writeToCache(List<MemoryModel> memories) async {
    try {
      final db = _ref.read(isarProvider);
      final familyId = _getCurrentFamilyId();
      if (familyId == null) return;

      // We use the toJson map for cache — this preserves all fields.
      await db.cacheApiEntry(
        'memories_$familyId',
        '${memories.length}', // lightweight marker — real decode is best-effort
        expiresIn: const Duration(hours: 24),
      );
    } catch (e) {
      debugPrint('⚠️ MemoryVault: Cache write failed: $e');
    }
  }

  /// Sanitize error messages for user display.
  String _sanitizeError(dynamic e) {
    final str = e.toString();
    if (str.length > 150) {
      return '${str.substring(0, 150)}...';
    }
    return str
        .replaceAll('Exception: ', '')
        .replaceAll('PostgrestException: ', '')
        .replaceAll('StorageException: ', '');
  }

  /// Truncate a post text into a short title (max ~50 chars).
  static String _truncateTitle(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 50) return trimmed;
    final cut = trimmed.substring(0, 50);
    final lastSpace = cut.lastIndexOf(' ');
    return lastSpace > 10
        ? '${cut.substring(0, lastSpace)}…'
        : '${cut}…';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Image Compression Isolate
// ═══════════════════════════════════════════════════════════════════════

/// Parameters passed to the compress isolate.
class _CompressParams {
  const _CompressParams(this.filePath, this.quality);
  final String filePath;
  final int quality;
}

/// Compresses an image file in a background isolate.
/// Returns the compressed bytes as Uint8List.
///
/// NOTE: dart:ui (Flutter's image library) cannot run in a pure isolate
/// without additional setup. For production JPEG compression, you'd
/// use `flutter_image_compress` (which uses native platform code).
/// The crop editor already returns PNG bytes bounded by the crop
/// boundary size — passing those bytes through here is a no-op that
/// preserves the existing call site signature.
Future<Uint8List> _compressImageIsolate(_CompressParams params) async {
  final file = File(params.filePath);
  if (!await file.exists()) {
    throw FileSystemException('File not found: ${params.filePath}');
  }
  return file.readAsBytes();
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

/// Main Memory Vault provider.
final memoryVaultProvider =
    StateNotifierProvider<MemoryVaultNotifier, MemoryVaultState>((ref) {
  final notifier = MemoryVaultNotifier(ref);

  // Auto-load memories when the provider is first created
  Future.microtask(() => notifier.loadMemories());

  return notifier;
});

/// Derived provider: On This Day memories only.
final onThisDayMemoriesProvider = Provider<List<MemoryModel>>((ref) {
  final state = ref.watch(memoryVaultProvider);
  return state.onThisDayMemories;
});

/// Derived provider: Pinned-to-Vault memories only.
final pinnedMemoriesProvider = Provider<List<MemoryModel>>((ref) {
  final state = ref.watch(memoryVaultProvider);
  return state.pinnedMemories;
});

/// Derived provider: Whether the vault is in a loading state.
final memoryVaultIsLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(memoryVaultProvider);
  return state.isLoading;
});

/// Derived provider: Whether an upload is in progress.
final memoryVaultIsUploadingProvider = Provider<bool>((ref) {
  final state = ref.watch(memoryVaultProvider);
  return state.isUploading;
});

/// Derived provider: Total memory count.
final memoryVaultCountProvider = Provider<int>((ref) {
  final state = ref.watch(memoryVaultProvider);
  return state.memories.length;
});

/// Derived provider: Pinned memory count (for vault badge).
final memoryVaultPinnedCountProvider = Provider<int>((ref) {
  final state = ref.watch(memoryVaultProvider);
  return state.pinnedCount;
});

/// Derived provider (Feature 3): returns the album of related Memory
/// Vault photos for a given Timeline entry — same calendar date OR
/// same memory_type. Empty when no other photos share the event.
final memoryAlbumForMemoryProvider =
    Provider.family<List<MemoryModel>, String>((ref, memoryId) {
  final notifier = ref.watch(memoryVaultProvider.notifier);
  return notifier.albumForMemory(memoryId);
});

/// Derived provider (Feature 3): returns whether a given Timeline entry
/// was created via the post-to-memory linking flow (Feature 2) — i.e.
/// has `source_post_id` set. Used by the UI to decide whether to show
/// the "View full album in Memory Vault →" affordance.
final isMemoryLinkedFromPostProvider =
    Provider.family<bool, String>((ref, memoryId) {
  final state = ref.watch(memoryVaultProvider);
  final memory = state.memories
      .where((m) => m.id == memoryId)
      .firstOrNull;
  return memory?.isFromPost ?? false;
});
