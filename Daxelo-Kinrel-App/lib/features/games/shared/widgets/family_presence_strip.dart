// lib/features/games/shared/widgets/family_presence_strip.dart
//
// FamilyPresenceStrip — a compact horizontal strip shown at the top of
// the Games hub that surfaces real-time family activity:
//
//   ┌─────────────────────────────────────────────────────┐
//   │  👤👤👤  3 online · 2 playing · 1 spectating         │
//  │     Family is active right now                       │
//   └─────────────────────────────────────────────────────┘
//
// Backed by the fn_get_family_presence Supabase RPC. Polls every 30s
// while the widget is mounted. Renders an empty state ("No family
// members online") when onlineCount == 0.
//
// Used by the Games hub screen — not for inside a specific game lobby
// (lobbies use the in-lobby _PresenceAvatarRow which tracks only
// participants in that room).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';

/// Snapshot of family-wide presence returned by fn_get_family_presence.
class FamilyPresence {
  const FamilyPresence({
    this.onlineCount = 0,
    this.playingCount = 0,
    this.spectatingCount = 0,
    this.totalMembers = 0,
    this.onlineMembers = const [],
  });

  final int onlineCount;
  final int playingCount;
  final int spectatingCount;
  final int totalMembers;
  final List<FamilyPresenceMember> onlineMembers;

  bool get isActive => onlineCount > 0 || playingCount > 0 || spectatingCount > 0;

  factory FamilyPresence.fromJson(Map<String, dynamic> json) {
    final members = (json['onlineMembers'] as List? ?? [])
        .map((e) => FamilyPresenceMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return FamilyPresence(
      onlineCount: (json['onlineCount'] as num?)?.toInt() ?? 0,
      playingCount: (json['playingCount'] as num?)?.toInt() ?? 0,
      spectatingCount: (json['spectatingCount'] as num?)?.toInt() ?? 0,
      totalMembers: (json['totalMembers'] as num?)?.toInt() ?? 0,
      onlineMembers: members,
    );
  }
}

class FamilyPresenceMember {
  const FamilyPresenceMember({
    required this.userId,
    required this.userName,
    required this.status,
  });

  final String userId;
  final String userName;
  final String status; // 'online' | 'playing' | 'spectating'

  factory FamilyPresenceMember.fromJson(Map<String, dynamic> json) {
    return FamilyPresenceMember(
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Family Member') as String,
      status: (json['status'] ?? 'online') as String,
    );
  }
}

/// Riverpod FutureProvider.family that fetches family presence.
///
/// Auto-refreshes every 30s while at least one subscriber is watching.
final familyPresenceProvider =
    FutureProvider.autoDispose.family<FamilyPresence, String>(
  (ref, familyId) async {
    final client = ref.watch(supabaseProvider);
    if (client == null) {
      return const FamilyPresence();
    }
    try {
      final result = await client.rpc(
        'fn_get_family_presence',
        params: {'p_family_id': familyId},
      );
      if (result is! Map) return const FamilyPresence();
      return FamilyPresence.fromJson(Map<String, dynamic>.from(result));
    } catch (_) {
      return const FamilyPresence();
    }
  },
);

/// The strip widget itself.
class FamilyPresenceStrip extends ConsumerStatefulWidget {
  const FamilyPresenceStrip({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyPresenceStrip> createState() =>
      _FamilyPresenceStripState();
}

class _FamilyPresenceStripState extends ConsumerState<FamilyPresenceStrip> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Poll every 30s while the strip is mounted. FutureProvider
    // autoDispose will tear down when the widget is unmounted.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(familyPresenceProvider(widget.familyId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presenceAsync = ref.watch(familyPresenceProvider(widget.familyId));
    return presenceAsync.when(
      loading: () => const _StripSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (presence) => _StripContent(presence: presence),
    );
  }
}

class _StripSkeleton extends StatelessWidget {
  const _StripSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: KinrelColors.orange.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class _StripContent extends StatelessWidget {
  const _StripContent({required this.presence});
  final FamilyPresence presence;

  @override
  Widget build(BuildContext context) {
    if (!presence.isActive) {
      return Container(
        margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
        padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm + 2),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: KinrelColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.nightlight_outlined,
                size: 18, color: KinrelColors.textDim),
            const SizedBox(width: KinrelSpacing.sm),
            Expanded(
              child: Text(
                presence.totalMembers > 0
                    ? 'No family members online right now'
                    : 'Invite family members to start playing together',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm + 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            KinrelColors.orange.withValues(alpha: 0.10),
            KinrelColors.darkCard,
          ],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // Avatar stack (up to 4)
          ..._avatarStack(presence.onlineMembers.take(4).toList()),
          const SizedBox(width: KinrelSpacing.sm),
          // Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statsLine(presence),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _activityLine(presence),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          // Live dot
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: KinrelColors.tealAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: KinrelColors.tealAccent,
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _avatarStack(List<FamilyPresenceMember> members) {
    return List.generate(members.length, (i) {
      final m = members[i];
      final dotColor = m.status == 'playing'
          ? KinrelColors.orange
          : m.status == 'spectating'
              ? KinrelColors.amber
              : KinrelColors.tealAccent;
      return Transform.translate(
        offset: Offset(-i * 8.0, 0),
        child: Stack(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: KinrelColors.darkSurface, width: 2),
              ),
              child: Center(
                child: Text(
                  m.userName.isNotEmpty ? m.userName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: KinrelColors.darkSurface, width: 2),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  String _statsLine(FamilyPresence p) {
    final parts = <String>[];
    if (p.onlineCount > 0) {
      parts.add('${p.onlineCount} online');
    }
    if (p.playingCount > 0) {
      parts.add('${p.playingCount} playing');
    }
    if (p.spectatingCount > 0) {
      parts.add('${p.spectatingCount} spectating');
    }
    return parts.isEmpty ? 'Family is here' : parts.join(' \u2022 ');
  }

  String _activityLine(FamilyPresence p) {
    if (p.playingCount > 0) {
      return 'A game is happening right now \u2014 jump in!';
    }
    if (p.spectatingCount > 0) {
      return 'Someone is watching a game \u2014 cheer them on!';
    }
    return 'Family is active right now';
  }
}
