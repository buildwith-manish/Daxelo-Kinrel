// lib/features/thinking/presentation/family_ring_widget.dart
//
// "Who are you thinking of?" — horizontal ring of family member faces.
// Tap any face to send a silent "Thinking of You" signal.
//
// v109.4: Data source changed from the Person table (which includes
// custom graph-only nodes, manually-created relationship entries, and
// placeholder people) to a JOIN of FamilyMember + User. This ensures
// ONLY real, registered Kinrel users who are actual members of the
// family appear in the ring.
//
// v109.6 (fix): The server RPC already excludes the current user via
// `u.id <> auth.uid()`, but we ALSO filter client-side as a safety net.
// If the RPC ever returns the current user (e.g., due to a stale JWT or
// an auth.uid() edge case), the UI will still hide them. Duplicates are
// also deduped client-side by userId.
//
// Excludes (enforced BOTH server-side and client-side):
//   ❌ The current user (you can't "think of" yourself)
//   ❌ Duplicate members (deduplicated by userId)
//   ❌ Custom graph people (linkedUserId = null in Person table)
//   ❌ Placeholder people (no FamilyMember record)
//   ❌ Non-Kinrel persons (not in the User table)
//   ❌ Deleted users (deletedAt IS NOT NULL in User table)
//   ❌ Users with no name
//
// Empty state: if the family has only one member (the current user),
// the section shows a "No other family members available" message
// instead of hiding entirely, so the user understands why it's empty.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../data/thinking_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// v109.4: Family Kinrel Members Provider
// ═══════════════════════════════════════════════════════════════════════
// Queries FamilyMember JOIN User directly (NOT the Person table) so
// only real registered Kinrel users who are actual family members
// appear. This is the correct data source for "Who are you thinking
// of?" — the Person table contains custom graph-only nodes that should
// NEVER appear in this section.

/// A real Kinrel user who is a member of a family.
class FamilyKinrelMember {
  const FamilyKinrelMember({
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    this.photoThumb,
  });

  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? photoThumb;

  /// Get initials for avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}

/// Provider that fetches ONLY real Kinrel users who are members of the
/// given family. Uses a SECURITY DEFINER RPC (fn_get_family_kinrel_members)
/// that bypasses User table RLS — the old direct JOIN query returned null
/// for other users' User data because RLS only lets you read YOUR OWN row.
///
/// This is the CORRECT data source:
///   ✅ Queries FamilyMember (real family members only)
///   ✅ JOINs User (real registered Kinrel accounts)
///   ✅ Bypasses User table RLS via SECURITY DEFINER
///   ✅ Excludes deleted users + the current user (server-side AND client-side)
///   ✅ Deduplicates by userId (server-side DISTINCT ON + client-side set)
///   ❌ NEVER queries the Person table (custom graph nodes)
final familyKinrelMembersProvider =
    FutureProvider.family<List<FamilyKinrelMember>, String>((ref, familyId) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return [];
  if (client.auth.currentUser == null) return [];

  // The current user's ID — used as a CLIENT-SIDE safety net to filter
  // them out even if the server RPC somehow returns them (e.g., stale
  // JWT, auth.uid() edge case, or a race condition during sign-in).
  final currentUserId = client.auth.currentUser!.id;

  try {
    // v109.6: Use the SECURITY DEFINER RPC to bypass User table RLS.
    // The old direct JOIN (FamilyMember.select('User(...)')) returned
    // null for other users' User data because the User table's RLS
    // policy only lets you read YOUR OWN row. The RPC runs as the
    // function owner (postgres) so it can see ALL users' data.
    final response = await client.rpc(
      'fn_get_family_kinrel_members',
      params: {'p_family_id': familyId},
    ).timeout(const Duration(seconds: 8));

    final members = <FamilyKinrelMember>[];
    final seenUserIds = <String>{};

    for (final row in response as List) {
      final userId = row['user_id'] as String?;
      if (userId == null || userId.isEmpty) continue;

      // ── Client-side safety net #1: exclude the current user ──
      // The server RPC already does `u.id <> auth.uid()::text`, but
      // if there's ANY mismatch (stale JWT, auth.uid() returning NULL
      // inside SECURITY DEFINER, case sensitivity, etc.), this catches
      // it. You should NEVER be able to "think of" yourself.
      if (userId == currentUserId) continue;

      // ── Client-side safety net #2: deduplicate by userId ──
      // The server RPC uses DISTINCT ON, but we also dedupe here in
      // case the RPC returns duplicates due to a JOIN fan-out or a
      // schema change.
      if (seenUserIds.contains(userId)) continue;
      seenUserIds.add(userId);

      final name = row['name'] as String?;
      if (name == null || name.isEmpty || name == 'null') continue;

      members.add(FamilyKinrelMember(
        userId: userId,
        name: name,
        username: row['username'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        photoThumb: row['photo_thumb'] as String?,
      ));
    }

    // Sort by name for consistent display
    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return members;
  } catch (e) {
    debugPrint('⚠️ familyKinrelMembersProvider error: $e');
    return [];
  }
});

class FamilyRingWidget extends ConsumerStatefulWidget {
  const FamilyRingWidget({
    super.key,
    required this.familyId,
  });

  final String familyId;

  @override
  ConsumerState<FamilyRingWidget> createState() => _FamilyRingWidgetState();
}

class _FamilyRingWidgetState extends ConsumerState<FamilyRingWidget> {
  final Map<String, DateTime> _tappedUntil = {};
  final Set<String> _cooldown = {};

  bool _isTapped(String userId) {
    final expiry = _tappedUntil[userId];
    return expiry != null && DateTime.now().isBefore(expiry);
  }

  Future<void> _onTap(BuildContext context, FamilyKinrelMember member) async {
    final userId = member.userId;

    if (_cooldown.contains(userId)) {
      _showSnack(context, 'You recently sent a Thinking of You. Try again later.');
      return;
    }

    HapticFeedback.lightImpact();

    // Optimistic UI: show tapped state immediately
    setState(() {
      _tappedUntil[userId] = DateTime.now().add(const Duration(seconds: 3));
    });

    try {
      final service = ref.read(thinkingServiceProvider);
      final result = await service.sendTap(
        receiverId: userId,
        familyId: widget.familyId,
      );

      if (!mounted) return;

      if (result.success) {
        // Show the personalized message returned by the RPC
        _showSnack(context, result.message ?? '${member.name} knows you\'re thinking of them');
      } else if (result.error == 'cooldown') {
        // Cooldown active — add to local cooldown set + show message
        setState(() {
          _tappedUntil.remove(userId);
          _cooldown.add(userId);
        });
        // Remove from cooldown after 60s (UI-only, the real cooldown
        // is 12 hours on the server, but we don't want to block the UI
        // for that long — the server will reject if they try again)
        Future.delayed(const Duration(seconds: 60), () {
          if (mounted) setState(() => _cooldown.remove(userId));
        });
        _showSnack(context, result.message ?? 'Already sent — try again later.');
      } else {
        // Other error — revert the tap animation
        setState(() => _tappedUntil.remove(userId));
        _showSnack(context, 'Something went wrong. Try again.');
      }
    } catch (e) {
      setState(() => _tappedUntil.remove(userId));
      if (mounted) _showSnack(context, 'Something went wrong. Try again.');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KinrelColors.darkCard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v109.4: Use the NEW familyKinrelMembersProvider which queries
    // FamilyMember JOIN User — NOT the Person table. This ensures
    // only real registered Kinrel users who are actual family members
    // appear. Custom graph nodes, placeholder people, and manually-
    // created relationship entries are NEVER shown.
    final membersAsync = ref.watch(familyKinrelMembersProvider(widget.familyId));

    return membersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (members) {
        // v109.6: If there are no OTHER family members (e.g., the user
        // is the only member, or all other members are deleted), show
        // a friendly empty-state message instead of hiding the section
        // entirely. This helps the user understand WHY it's empty rather
        // than wondering if the feature is broken.
        if (members.isEmpty) return _buildEmptyState(context);
        return _buildRing(context, members);
      },
    );
  }

  /// Empty-state message shown when the family has no other members to
  /// send "Thinking of You" signals to. This is NOT an error — it just
  /// means the user is the only Kinrel member in this family.
  Widget _buildEmptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            'Who are you thinking of?',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textDim,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.darkCard,
                  border: Border.all(
                    color: KinrelColors.border,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 20,
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No other family members available.\nInvite members to send them a Thinking of You.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRing(BuildContext context, List<FamilyKinrelMember> members) {
    final displayMembers = members.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            'Who are you thinking of?',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textDim,
            ),
          ),
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayMembers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final member = displayMembers[index];
              final userId = member.userId;
              final tapped = _isTapped(userId);
              final onCooldown = _cooldown.contains(userId);

              return GestureDetector(
                onTap: () => _onTap(context, member),
                child: AnimatedScale(
                  scale: tapped ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: tapped
                                  ? [
                                      BoxShadow(
                                        color: KinrelColors.orange
                                            .withValues(alpha: 0.5),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : [],
                              border: Border.all(
                                color: tapped
                                    ? KinrelColors.orange
                                    : onCooldown
                                        ? Colors.white24
                                        : Colors.white12,
                                width: tapped ? 2 : 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: ColorFiltered(
                                colorFilter: onCooldown
                                    ? const ColorFilter.mode(
                                        Colors.grey, BlendMode.saturation)
                                    : const ColorFilter.mode(
                                        Colors.transparent,
                                        BlendMode.saturation),
                                child: (member.avatarUrl != null &&
                                        member.avatarUrl!.isNotEmpty)
                                    ? Image.network(
                                        member.avatarUrl!,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _Placeholder(name: member.name),
                                      )
                                    : _Placeholder(name: member.name),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 56,
                        child: Text(
                          member.name.split(' ').first,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String name;
  const _Placeholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: KinrelColors.darkElevated,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: KinrelColors.orange,
        ),
      ),
    );
  }
}
