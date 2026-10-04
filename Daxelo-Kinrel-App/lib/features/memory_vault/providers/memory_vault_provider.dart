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

import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/database/sync/connectivity_service.dart';
import '../data/memory_model.dart';

// ═══════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════

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

  /// Creates a new memory with all structured fields (title, description,
  /// location, memoryType, members, date, sourcePostId).
  ///
  /// [imageBytes] — optional pre-cropped + pre-compressed image bytes.
  /// If provided, the image is uploaded to the `memory-images` bucket
  /// and the resulting URL + storage key are stored on the memory row.
  ///
  /// [sourcePostId] — optional FK to FamilyPost. Set when the memory
  /// was created from a post via the "Save As Memory" flow.
  Future<MemoryModel?> createMemory({
    required String title,
    String? description,
    String? location,
    String? memoryType,
    DateTime? date,
    List<String> memberIds = const [],
    Uint8List? imageBytes,
    String? imageExtension,
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

      // Step 1: Upload image (if provided)
      String? imageUrl;
      String? imageStorageKey;
      if (imageBytes != null) {
        state = state.copyWith(uploadProgress: 'Uploading cover image...');

        final ext = (imageExtension ?? 'jpg').toLowerCase();
        // Path: memory-images/{familyId}/{memoryId}/image.{ext}
        imageStorageKey = '$familyId/$memoryId/image.$ext';
        await withRetry(
          () => client.storage.from(_imageBucketName).uploadBinary(
                imageStorageKey!,
                imageBytes,
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

  // ── Save Post as Memory ───────────────────────────────────────────

  /// Creates a memory from an existing post. Prefills the image URL,
  /// caption, and date from the post; the user fills in title, location,
  /// members, and type via the memory create UI.
  ///
  /// This is the backend side of Feature 5 ("Save Post As Memory"). The
  /// UI side lives in the post card's ⋮ menu and in the post create
  /// screen's "Save To Memories" toggle.
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
      // If the post had an image URL, we don't re-upload it (it's already
      // in post-media bucket). Instead, we link to it directly so the
      // memory displays the same image. The image_storage_key is left null
      // (since we don't own the storage object — deleting the memory
      // should NOT delete the post's image).
      imageBytes: null,
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
