// test/features/sparq_tray/family_sparq_tray_item_test.dart
//
// Unit tests for the Family Sparq tray's pure grouping logic:
//   • buildPetals — member → family join, own group excluded,
//     expired/capsule handling, ordering, 8-slot cap.
//   • countUnseenForFamily — unseen counts excluding locked capsules.
//   • isSparqLiveForTray / isSparqUnseenForTray — drop rules.
//
// These tests do NOT touch Riverpod or Supabase — they exercise the
// pure functions exported from family_sparq_tray_item.dart. They run
// under `flutter test` because SparqModel.moodColor returns a
// Flutter Color.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/sparq_tray/data/family_sparq_tray_item.dart';
import 'package:kinrel/features/social/data/models/sparq_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isSparqLiveForTray', () {
    test('drops expired Sparqs', () {
      final s = SparqModel(
        id: 's1',
        userId: 'u1',
        type: 'TEXT',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(isSparqLiveForTray(s), isFalse);
    });

    test('drops unrevealed time capsules', () {
      final s = SparqModel(
        id: 's2',
        userId: 'u1',
        type: 'TEXT',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isTimeCapsule: true,
        isRevealed: false,
      );
      expect(isSparqLiveForTray(s), isFalse);
    });

    test('keeps a normal live Sparq', () {
      final s = SparqModel(
        id: 's3',
        userId: 'u1',
        type: 'TEXT',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(isSparqLiveForTray(s), isTrue);
    });

    test('keeps a REVEALED time capsule (it is now playable)', () {
      final s = SparqModel(
        id: 's4',
        userId: 'u1',
        type: 'TEXT',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isTimeCapsule: true,
        isRevealed: true,
      );
      expect(isSparqLiveForTray(s), isTrue);
    });
  });

  group('isSparqUnseenForTray', () {
    test('locked time capsules are never unseen', () {
      final s = SparqModel(
        id: 's1',
        userId: 'u1',
        type: 'TEXT',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isTimeCapsule: true,
        isRevealed: false,
      );
      expect(isSparqUnseenForTray(s, false), isFalse);
      expect(isSparqUnseenForTray(s, true), isFalse);
    });

    test('a non-capsule Sparq is unseen until locally seen', () {
      final s = SparqModel(
        id: 's2',
        userId: 'u1',
        type: 'TEXT',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(isSparqUnseenForTray(s, false), isTrue);
      expect(isSparqUnseenForTray(s, true), isFalse);
    });
  });

  group('buildPetals — member → family join', () {
    test('a person in two families appears in both rings', () {
      final shared = _group(
        userId: 'u_shared',
        sparqIds: const ['s1'],
        createdAt: DateTime(2026, 1, 1),
      );
      final feed = [shared];

      // Family A's member set includes the shared user.
      final petalsA = buildPetals(
        feed: feed,
        memberUserIds: const {'u_shared', 'u_other'},
        moment: null,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );
      // Family B's member set ALSO includes the shared user.
      final petalsB = buildPetals(
        feed: feed,
        memberUserIds: const {'u_shared'},
        moment: null,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );

      expect(petalsA, hasLength(1));
      expect(petalsB, hasLength(1));
      expect(petalsA.first.userId, 'u_shared');
      expect(petalsB.first.userId, 'u_shared');
    });

    test('the viewer never appears in a family ring', () {
      final me = _group(
        userId: 'viewer',
        sparqIds: const ['me_s1'],
        createdAt: DateTime(2026, 1, 1),
      );
      final other = _group(
        userId: 'u_other',
        sparqIds: const ['o_s1'],
        createdAt: DateTime(2026, 1, 1),
      );

      final petals = buildPetals(
        feed: [me, other],
        memberUserIds: const {'viewer', 'u_other'},
        moment: null,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );

      expect(petals, hasLength(1));
      expect(petals.first.userId, 'u_other');
    });

    test('members with no live Sparqs get no petal', () {
      // Expired Sparq for a member → no petal for them.
      final expired = SparqModel(
        id: 'exp',
        userId: 'u_expired',
        type: 'TEXT',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final gExpired = UserSparqGroup(
        userId: 'u_expired',
        userName: 'Expired Member',
        sparqs: [expired],
      );

      // Active Sparq for another member → one petal.
      final live = _group(
        userId: 'u_live',
        sparqIds: const ['live_s1'],
        createdAt: DateTime.now(),
      );

      final petals = buildPetals(
        feed: [gExpired, live],
        memberUserIds: const {'u_expired', 'u_live'},
        moment: null,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );

      expect(petals, hasLength(1));
      expect(petals.first.userId, 'u_live');
    });
  });

  group('buildPetals — ordering', () {
    test('Moment petal goes to slot 0 when present', () {
      final moment = MomentSparq(
        id: 'm1',
        familyId: 'fam',
        headline: 'Dadi turns 78 today',
        relationLine: 'Your Dadi',
        eventType: MomentEventType.birthday,
        date: DateTime(2026, 1, 1),
      );

      final member = _group(
        userId: 'u_member',
        sparqIds: const ['m_s1'],
        createdAt: DateTime(2026, 1, 1),
      );

      final petals = buildPetals(
        feed: [member],
        memberUserIds: const {'u_member'},
        moment: moment,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );

      expect(petals.first.isMoment, isTrue);
      expect(petals.first.color, const Color(0xFFD4AF37));
    });

    test('unseen petals come before seen petals', () {
      final unseen = _group(
        userId: 'u_unseen',
        sparqIds: const ['un1'],
        createdAt: DateTime(2026, 1, 1),
      );
      final seen = _group(
        userId: 'u_seen',
        sparqIds: const ['se1'],
        createdAt: DateTime(2026, 1, 1),
      );

      final petals = buildPetals(
        feed: [unseen, seen],
        memberUserIds: const {'u_unseen', 'u_seen'},
        moment: null,
        isSeen: (id) => id == 'se1',
        excludeUserId: 'viewer',
      );

      expect(petals, hasLength(2));
      expect(petals[0].userId, 'u_unseen');
      expect(petals[0].seen, isFalse);
      expect(petals[1].userId, 'u_seen');
      expect(petals[1].seen, isTrue);
    });

    test('most-recent member goes first within the unseen bucket', () {
      final older = _group(
        userId: 'u_older',
        sparqIds: const ['older'],
        createdAt: DateTime(2026, 1, 1),
      );
      final newer = _group(
        userId: 'u_newer',
        sparqIds: const ['newer'],
        createdAt: DateTime(2026, 1, 2),
      );

      final petals = buildPetals(
        feed: [older, newer], // feed order is older-first
        memberUserIds: const {'u_older', 'u_newer'},
        moment: null,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );

      expect(petals[0].userId, 'u_newer');
      expect(petals[1].userId, 'u_older');
    });
  });

  group('buildPetals — 8-slot cap', () {
    test('caps at 8 petals, including the Moment petal', () {
      final moment = MomentSparq(
        id: 'm1',
        familyId: 'fam',
        headline: 'h',
        relationLine: '',
        eventType: MomentEventType.birthday,
        date: DateTime(2026, 1, 1),
      );

      final feed = [
        for (var i = 0; i < 12; i++)
          _group(
            userId: 'u_$i',
            sparqIds: ['s_$i'],
            createdAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
          ),
      ];

      final petals = buildPetals(
        feed: feed,
        memberUserIds: {for (var i = 0; i < 12; i++) 'u_$i'},
        moment: moment,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );

      expect(petals, hasLength(8));
      // Slot 0 is the Moment petal (gold).
      expect(petals.first.isMoment, isTrue);
      // The 7 most-recent member petals fill the remaining slots.
      // (Feed sorted by createdAt desc — the most recent 7 win.)
      expect(petals.skip(1).every((p) => !p.isMoment), isTrue);
    });

    test('seen members do NOT bump unseen members off the ring', () {
      // 5 unseen + 5 seen = 10 total → cap to 8, but unseen must stay.
      final feed = [
        for (var i = 0; i < 5; i++)
          _group(
            userId: 'u_unseen_$i',
            sparqIds: ['un_$i'],
            createdAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
          ),
        for (var i = 0; i < 5; i++)
          _group(
            userId: 'u_seen_$i',
            sparqIds: ['se_$i'],
            createdAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
          ),
      ];

      final seenIds = {for (var i = 0; i < 5; i++) 'se_$i'};

      final petals = buildPetals(
        feed: feed,
        memberUserIds: {
          for (var i = 0; i < 5; i++) 'u_unseen_$i',
          for (var i = 0; i < 5; i++) 'u_seen_$i',
        },
        moment: null,
        isSeen: (id) => seenIds.contains(id),
        excludeUserId: 'viewer',
      );

      expect(petals, hasLength(8));
      // The 5 unseen petals come first and MUST all be present.
      expect(petals.take(5).every((p) => !p.seen), isTrue);
      // Followed by 3 seen petals (5 + 3 = 8 cap).
      expect(petals.skip(5).every((p) => p.seen), isTrue);
    });
  });

  group('buildPetals — petal color + intensity', () {
    test('petal color = member\'s latest Sparq moodColor', () {
      final g = _group(
        userId: 'u1',
        sparqIds: const ['s1'],
        createdAt: DateTime(2026, 1, 1),
        mood: 'love',
        intensity: 'fire',
      );
      final petals = buildPetals(
        feed: [g],
        memberUserIds: const {'u1'},
        moment: null,
        isSeen: (_) => false,
        excludeUserId: 'viewer',
      );
      expect(petals.single.color, const Color(0xFFE91E63)); // love
      expect(petals.single.intensity, 'fire');
    });
  });

  group('countUnseenForFamily', () {
    test('excludes locked time capsules and seen Sparqs', () {
      final groups = [
        UserSparqGroup(
          userId: 'u1',
          userName: 'u1',
          sparqs: [
            // unseen normal
            SparqModel(
              id: 's1',
              userId: 'u1',
              type: 'TEXT',
              expiresAt: DateTime.now().add(const Duration(hours: 12)),
              createdAt: DateTime.now(),
            ),
            // seen normal
            SparqModel(
              id: 's2',
              userId: 'u1',
              type: 'TEXT',
              expiresAt: DateTime.now().add(const Duration(hours: 12)),
              createdAt: DateTime.now(),
            ),
            // locked time capsule (never counts)
            SparqModel(
              id: 's3',
              userId: 'u1',
              type: 'TEXT',
              expiresAt: DateTime.now().add(const Duration(hours: 12)),
              createdAt: DateTime.now(),
              isTimeCapsule: true,
              isRevealed: false,
            ),
            // expired (never counts — dropped upstream of countUnseen,
            // but the helper should also be defensive)
            SparqModel(
              id: 's4',
              userId: 'u1',
              type: 'TEXT',
              expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
              createdAt: DateTime.now().subtract(const Duration(hours: 2)),
            ),
          ],
        ),
      ];

      final n = countUnseenForFamily(
        memberGroups: groups,
        isSeen: (id) => id == 's2',
      );

      expect(n, 1); // only s1
    });
  });
}

/// Helper to build a UserSparqGroup with N Sparqs at a given time,
/// defaulting to happy/warm. Lets tests stay terse.
UserSparqGroup _group({
  required String userId,
  required List<String> sparqIds,
  required DateTime createdAt,
  String mood = 'happy',
  String intensity = 'warm',
}) {
  return UserSparqGroup(
    userId: userId,
    userName: userId,
    sparqs: [
      for (final id in sparqIds)
        SparqModel(
          id: id,
          userId: userId,
          type: 'TEXT',
          expiresAt: DateTime.now().add(const Duration(hours: 12)),
          createdAt: createdAt,
          mood: mood,
          intensity: intensity,
        ),
    ],
  );
}
