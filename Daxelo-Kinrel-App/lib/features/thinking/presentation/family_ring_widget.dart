import '../../../core/widgets/person_avatar.dart';
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  // ── Per-member UI state ──
  // _tappedUntil: brief 3s animation played after a successful send
  final Map<String, DateTime> _tappedUntil = {};
  // _cooldownUntil: 6-hour cooldown per receiver, populated from the RPC
  // response (cooldownExpiresAt). The button is disabled while this is
  // in the future. A 1-second timer refreshes the countdown display.
  final Map<String, DateTime> _cooldownUntil = {};
  // _pendingMember: the member we're currently sending to (shows a spinner)
  String? _pendingMember;

  /// Ticker that fires every 1 second to refresh the countdown labels.
  /// Started when there's at least one active cooldown, stopped when all
  /// cooldowns have expired.
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _ensureCountdownTimer() {
    if (_countdownTimer?.isActive ?? false) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        return;
      }
      // If all cooldowns have expired, stop the timer to save battery.
      final now = DateTime.now();
      final anyActive = _cooldownUntil.values.any((exp) => now.isBefore(exp));
      if (!anyActive) {
        _cooldownUntil.clear();
        _countdownTimer?.cancel();
      }
      setState(() {});
    });
  }

  bool _isTapped(String userId) {
    final expiry = _tappedUntil[userId];
    return expiry != null && DateTime.now().isBefore(expiry);
  }

  bool _isOnCooldown(String userId) {
    final expiry = _cooldownUntil[userId];
    if (expiry == null) return false;
    if (DateTime.now().isBefore(expiry)) return true;
    // Cooldown expired — clean up
    _cooldownUntil.remove(userId);
    return false;
  }

  /// Format the remaining cooldown as "5h 23m" or "23m" or "<1m".
  String _cooldownLabel(String userId) {
    final expiry = _cooldownUntil[userId];
    if (expiry == null) return '';
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return '';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '<1m';
  }

  Future<void> _onTap(BuildContext context, FamilyKinrelMember member) async {
    final userId = member.userId;

    // Client-side cooldown gate — prevents the RPC call entirely if the
    // user is still on cooldown. The server also enforces this.
    if (_isOnCooldown(userId)) {
      _showSnack(context, 'Available again in ${_cooldownLabel(userId)}.');
      return;
    }

    // Don't allow a second concurrent send to the same member
    if (_pendingMember == userId) return;

    HapticFeedback.lightImpact();

    // Optimistic UI: show tapped state immediately
    setState(() {
      _tappedUntil[userId] = DateTime.now().add(const Duration(seconds: 3));
      _pendingMember = userId;
    });

    try {
      final service = ref.read(thinkingServiceProvider);
      final result = await service.sendTap(
        receiverId: userId,
        familyId: widget.familyId,
      );

      if (!mounted) return;

      if (result.success) {
        // Phase 21: Show a personal success message with the recipient's
        // name. The RPC returns receiverName for this purpose.
        final receiverName = result.receiverName ?? member.name.split(' ').first;
        _showSnack(context, 'Your Thinking of You moment was sent to $receiverName');

        // Open the private 1:1 chat with the recipient so the sender can
        // see their message in context. This makes the feature feel
        // personal and confirms delivery.
        if (context.mounted) {
          context.push('/dm/${member.userId}');
        }

        // Store the cooldown expiry so the button stays disabled + shows
        // a live countdown.
        final expiresAt = result.cooldownExpiresAtUtc;
        if (expiresAt != null) {
          setState(() {
            _cooldownUntil[userId] = expiresAt.toLocal();
          });
          _ensureCountdownTimer();
        }
      } else if (result.error == 'cooldown') {
        // Server says we're on cooldown — sync the local state with the
        // server's cooldownExpiresAt so the countdown is accurate.
        final expiresAt = result.cooldownExpiresAtUtc;
        setState(() {
          _tappedUntil.remove(userId);
          if (expiresAt != null) {
            _cooldownUntil[userId] = expiresAt.toLocal();
          }
        });
        if (expiresAt != null) _ensureCountdownTimer();
        _showSnack(context, result.message ?? 'Already sent — try again later.');
      } else {
        // Other errors — show the meaningful message from the RPC.
        // The RPC now returns specific error codes with human-readable
        // messages, so we prefer those over a generic "Something went wrong".
        setState(() => _tappedUntil.remove(userId));
        _showSnack(context, result.message ?? _fallbackMessage(result.error));
      }
    } catch (e) {
      setState(() => _tappedUntil.remove(userId));
      if (mounted) {
        _showSnack(context, 'Network error. Please check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _pendingMember = null);
    }
  }

  /// Map RPC error codes to user-friendly messages (used when the RPC
  /// doesn't include a 'message' field).
  String _fallbackMessage(String? errorCode) {
    switch (errorCode) {
      case 'cannot_send_to_self':
        return 'You cannot send a Thinking of You moment to yourself.';
      case 'receiver_not_in_family':
        return 'Recipient not found in this family.';
      case 'not_authenticated':
        return 'You must be signed in to send a Thinking of You moment.';
      case 'network_error':
        return 'Network error. Please check your connection and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
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
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayMembers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final member = displayMembers[index];
              final userId = member.userId;
              final tapped = _isTapped(userId);
              final onCooldown = _isOnCooldown(userId);
              final isPending = _pendingMember == userId;
              final cooldownLabel = onCooldown ? _cooldownLabel(userId) : '';

              return GestureDetector(
                onTap: (onCooldown || isPending)
                    ? null
                    : () => _onTap(context, member),
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
                                        ? KinrelColors.textDim.withValues(alpha: 0.4)
                                        : Colors.white12,
                                width: tapped ? 2 : 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Avatar or placeholder
                                  ColorFiltered(
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
                                  // Pending spinner (while the RPC is in flight)
                                  if (isPending)
                                    Container(
                                      color: Colors.black54,
                                      child: const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: KinrelColors.orange,
                                        ),
                                      ),
                                    ),
                                  // Cooldown lock badge
                                  if (onCooldown)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: KinrelColors.darkCard,
                                          border: Border.all(
                                            color: KinrelColors.textDim,
                                            width: 1,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.lock_rounded,
                                          size: 10,
                                          color: KinrelColors.textDim,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 64,
                        child: Text(
                          member.name.split(' ').first,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: onCooldown
                                ? KinrelColors.textDim
                                : KinrelColors.textSilver,
                          ),
                        ),
                      ),
                      // Cooldown countdown label
                      if (onCooldown && cooldownLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            cooldownLabel,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: KinrelColors.orange,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 12), // keep consistent height
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
        PersonAvatar.initialsFor(name);
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
