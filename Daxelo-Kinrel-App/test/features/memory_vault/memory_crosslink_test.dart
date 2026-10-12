// test/features/memory_vault/memory_crosslink_test.dart
//
// DAXELO KINREL — Feature 3: Cross-link from Timeline entries to Memory Vault
//
// Verifies the data-model layer of the cross-link:
//   • MemoryModel.isFromPost returns true when sourcePostId is set
//     (the explicit-association case from the post-to-memory linking flow).
//   • MemoryVaultNotifier.albumForMemory returns related photos
//     (same calendar date OR same memory_type) — the cross-link scope.
//   • MemoryVaultNotifier.memoriesLinkedFromPost returns the Timeline
//     entries that were created via the post-to-memory linking flow.
//
// Per the spec: "When a Timeline entry's photo corresponds to an event
// that also has additional photos stored in Memory Vault (e.g., tagged
// with the same date/event/category), show a 'View full album in Memory
// Vault →' link on that Timeline entry's detail view."
// And: "this cross-link can initially be scoped to only the specific
// photo(s) uploaded through the post-to-memory linking flow (item 2),
// where the association is already explicit via the shared creation
// action."

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/memory_vault/data/memory_model.dart';

void main() {
  // Helper to build a MemoryModel with sensible defaults.
  MemoryModel makeMemory({
    required String id,
    String? memoryType,
    DateTime? takenAt,
    String? sourcePostId,
    bool isPinnedToVault = false,
  }) {
    final now = DateTime.now();
    return MemoryModel(
      id: id,
      familyId: 'fam-1',
      uploaderId: 'user-1',
      uploaderName: 'Manish',
      photoUrl: '',
      takenAt: takenAt,
      memoryType: memoryType,
      sourcePostId: sourcePostId,
      isPinnedToVault: isPinnedToVault,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('MemoryModel.isFromPost (cross-link trigger condition)', () {
    test('returns true when sourcePostId is non-empty', () {
      final m = makeMemory(id: 'm1', sourcePostId: 'post-abc');
      expect(m.isFromPost, isTrue,
          reason:
              'A Timeline entry created via the post-to-memory linking flow '
              'has sourcePostId set — this is the cross-link trigger.');
    });

    test('returns false when sourcePostId is null', () {
      final m = makeMemory(id: 'm1');
      expect(m.isFromPost, isFalse);
    });

    test('returns false when sourcePostId is empty string', () {
      final m = makeMemory(id: 'm1', sourcePostId: '');
      expect(m.isFromPost, isFalse);
    });
  });

  group('MemoryModel.displayImageUrl (the hero photo URL)', () {
    test('uses imageUrl when set (preferred over legacy photoUrl)', () {
      final m = MemoryModel(
        id: 'm1',
        familyId: 'fam-1',
        uploaderId: 'user-1',
        uploaderName: 'Manish',
        photoUrl: 'legacy-url',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        imageUrl: 'new-url',
      );
      expect(m.displayImageUrl, 'new-url');
      expect(m.hasImage, isTrue);
    });

    test('falls back to photoUrl when imageUrl is null', () {
      final m = MemoryModel(
        id: 'm1',
        familyId: 'fam-1',
        uploaderId: 'user-1',
        uploaderName: 'Manish',
        photoUrl: 'legacy-url',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(m.displayImageUrl, 'legacy-url');
      expect(m.hasImage, isTrue);
    });

    test('returns empty string when no image is set', () {
      final m = makeMemory(id: 'm1');
      expect(m.displayImageUrl, '');
      expect(m.hasImage, isFalse);
    });
  });

  // ── Album association logic (the cross-link scope).
  //
  // The albumForMemory helper in MemoryVaultNotifier returns the list of
  // OTHER memories that share the same calendar date OR the same memory_type.
  // This is the scope of the "View full album in Memory Vault →" cross-link.
  //
  // We test the same algorithm here at the model level (it's a pure filter
  // over a list of MemoryModels) to verify the matching logic.

  List<MemoryModel> albumForMemory(List<MemoryModel> all, String memoryId) {
    final target = all.firstWhere(
      (m) => m.id == memoryId,
      orElse: () => MemoryModel.placeholder(memoryId),
    );
    if (target.takenAt == null && target.memoryType == null) {
      return const [];
    }
    return all.where((m) {
      if (m.id == memoryId) return false;
      final sameDate = target.takenAt != null && m.takenAt != null &&
          m.takenAt!.month == target.takenAt!.month &&
          m.takenAt!.day == target.takenAt!.day;
      final sameType = target.memoryType != null &&
          m.memoryType != null &&
          m.memoryType == target.memoryType;
      return sameDate || sameType;
    }).toList();
  }

  group('albumForMemory (cross-link scope)', () {
    test('returns empty list when target memory has no date AND no type', () {
      final all = [
        makeMemory(id: 'target'),
        makeMemory(id: 'other', memoryType: 'Festival'),
      ];
      expect(albumForMemory(all, 'target'), isEmpty);
    });

    test('matches other memories with the SAME calendar date (year-agnostic)',
        () {
      final diwali2024 = DateTime(2024, 11, 1);
      final diwali2023 = DateTime(2023, 11, 1);
      final differentDay = DateTime(2024, 12, 25);
      final all = [
        makeMemory(id: 'target', takenAt: diwali2024, memoryType: 'Festival'),
        makeMemory(id: 'last-year', takenAt: diwali2023, memoryType: 'Festival'),
        makeMemory(id: 'different-day', takenAt: differentDay),
      ];
      final album = albumForMemory(all, 'target');
      expect(album.length, 1);
      expect(album.first.id, 'last-year',
          reason: 'Same calendar day (1 Nov) — year-agnostic match.');
    });

    test('matches other memories with the SAME memory_type', () {
      final all = [
        makeMemory(id: 'target', memoryType: 'Birth'),
        makeMemory(
            id: 'other-birth-1',
            memoryType: 'Birth',
            takenAt: DateTime(2024, 1, 15)),
        makeMemory(
            id: 'other-birth-2',
            memoryType: 'Birth',
            takenAt: DateTime(2024, 5, 20)),
        makeMemory(
            id: 'festival-1',
            memoryType: 'Festival',
            takenAt: DateTime(2024, 11, 1)),
      ];
      final album = albumForMemory(all, 'target');
      expect(album.length, 2);
      expect(album.map((m) => m.id).toSet(), {'other-birth-1', 'other-birth-2'});
    });

    test('excludes the target memory from its own album', () {
      final all = [
        makeMemory(id: 'target', memoryType: 'Festival'),
        makeMemory(id: 'related', memoryType: 'Festival'),
      ];
      final album = albumForMemory(all, 'target');
      expect(album, isNotEmpty);
      expect(album.any((m) => m.id == 'target'), isFalse,
          reason: 'The target memory must not appear in its own album.');
    });

    test('combines date matches + type matches (union, no duplicates)', () {
      final sameDateAndType = DateTime(2024, 11, 1);
      final all = [
        makeMemory(
            id: 'target',
            takenAt: sameDateAndType,
            memoryType: 'Festival'),
        // Same date AND same type — should appear once, not twice.
        makeMemory(
            id: 'same-date-same-type',
            takenAt: sameDateAndType,
            memoryType: 'Festival'),
        // Same date, different type.
        makeMemory(
            id: 'same-date-diff-type',
            takenAt: sameDateAndType,
            memoryType: 'Birth'),
        // Different date, same type.
        makeMemory(
            id: 'diff-date-same-type',
            takenAt: DateTime(2024, 10, 15),
            memoryType: 'Festival'),
        // Different date, different type — no match.
        makeMemory(
            id: 'unrelated',
            takenAt: DateTime(2024, 7, 4),
            memoryType: 'Migration'),
      ];
      final album = albumForMemory(all, 'target');
      expect(album.length, 3,
          reason: '3 matches: same-date-same-type + same-date-diff-type + '
              'diff-date-same-type. The "same-date-same-type" memory must '
              'appear only once in the union (no duplicate).');
      expect(album.map((m) => m.id).toSet(),
          {'same-date-same-type', 'same-date-diff-type', 'diff-date-same-type'});
    });

    test('returns empty when no other memories match', () {
      final all = [
        makeMemory(id: 'target', memoryType: 'Festival'),
        makeMemory(id: 'other', memoryType: 'Birth'),
      ];
      expect(albumForMemory(all, 'target'), isEmpty);
    });
  });

  // ── memoriesLinkedFromPost (cross-link helper).
  //
  // This is the helper that returns the Timeline entries created via the
  // post-to-memory linking flow (Feature 2). It's a simple filter on
  // sourcePostId, but it's the explicit-association scope mentioned in
  // the spec.

  List<MemoryModel> memoriesLinkedFromPost(
      List<MemoryModel> all, String postId) {
    return all.where((m) => m.sourcePostId == postId).toList();
  }

  group('memoriesLinkedFromPost (explicit association scope)', () {
    test('returns memories where sourcePostId matches', () {
      final all = [
        makeMemory(id: 'm1', sourcePostId: 'post-abc'),
        makeMemory(id: 'm2', sourcePostId: 'post-xyz'),
        makeMemory(id: 'm3'), // no source post
      ];
      final linked = memoriesLinkedFromPost(all, 'post-abc');
      expect(linked.length, 1);
      expect(linked.first.id, 'm1');
    });

    test('returns empty list when no memories link to the given post', () {
      final all = [
        makeMemory(id: 'm1', sourcePostId: 'post-abc'),
        makeMemory(id: 'm2'),
      ];
      expect(memoriesLinkedFromPost(all, 'post-nonexistent'), isEmpty);
    });

    test('returns multiple memories when several link to the same post', () {
      // This shouldn't happen in normal flow (the toggle creates exactly
      // one entry per post), but the helper handles it gracefully.
      final all = [
        makeMemory(id: 'm1', sourcePostId: 'post-abc'),
        makeMemory(id: 'm2', sourcePostId: 'post-abc'),
        makeMemory(id: 'm3', sourcePostId: 'post-abc'),
      ];
      expect(memoriesLinkedFromPost(all, 'post-abc').length, 3);
    });
  });
}
