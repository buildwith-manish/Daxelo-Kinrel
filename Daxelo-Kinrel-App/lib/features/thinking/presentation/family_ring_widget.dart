// lib/features/thinking/presentation/family_ring_widget.dart
//
// "Who are you thinking of?" — horizontal ring of family member faces.
// Tap any face to send a silent "Thinking of You" signal.
//
// Phase 3.24 — UX improvements:
//   1. Variable reward: random warm confirmation messages (reciprocity)
//   2. Emotional design: warmer header with subtle gradient + heart icon
//   3. Daily streak counter: "N day streak" badge (commitment/consistency)
//   4. Sent-received counter: "N sent · M received" stats (social proof)
//   5. Heart particle burst on successful send (emotional design)
//
// v109.4: Data source changed from the Person table (which includes
// custom graph-only nodes, manually-created relationship entries, and
// placeholder people) to a JOIN of FamilyMember + User. This ensures
// ONLY real, registered Kinrel users who are actual members of the
// family appear in the ring.

import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/local_cache.dart';
import '../data/thinking_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// v109.4: Family Kinrel Members Provider
// ═══════════════════════════════════════════════════════════════════════

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

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}

/// Provider that fetches ONLY real Kinrel users who are members of the
/// given family. Uses a SECURITY DEFINER RPC (fn_get_family_kinrel_members)
/// that bypasses User table RLS.
final familyKinrelMembersProvider =
    FutureProvider.family<List<FamilyKinrelMember>, String>((ref, familyId) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return [];
  if (client.auth.currentUser == null) return [];

  final currentUserId = client.auth.currentUser!.id;

  try {
    final response = await client.rpc(
      'fn_get_family_kinrel_members',
      params: {'p_family_id': familyId},
    );

    if (response is! List) return [];

    final members = <FamilyKinrelMember>[];
    final seen = <String>{};

    for (final row in response) {
      if (row is! Map) continue;
      final userId = row['user_id']?.toString() ?? row['id']?.toString() ?? '';
      if (userId.isEmpty || userId == currentUserId) continue;
      if (seen.contains(userId)) continue;
      seen.add(userId);

      final name = row['name']?.toString() ?? '';
      if (name.isEmpty) continue;

      members.add(FamilyKinrelMember(
        userId: userId,
        name: name,
        username: row['username'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        photoThumb: row['photo_thumb'] as String?,
      ));
    }

    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return members;
  } catch (e) {
    debugPrint('⚠️ familyKinrelMembersProvider error: $e');
    return [];
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.24: Thinking of You stats (sent count + daily streak)
// ═══════════════════════════════════════════════════════════════════════

/// Provider that fetches the user's "Thinking of You" stats:
///   - totalSent: how many taps the user has ever sent
///   - totalReceived: how many taps the user has ever received
///   - dailyStreak: how many consecutive days the user has sent at least 1 tap
///
/// Uses a SECURITY DEFINER RPC `fn_get_thinking_stats` that aggregates
/// from the ThinkingOfYouTap table. Falls back to zeros on error.
final thinkingStatsProvider =
    FutureProvider.family<Map<String, int>, String>((ref, familyId) async {
  final client = ref.read(supabaseProvider);
  if (client == null || client.auth.currentUser == null) {
    return {'totalSent': 0, 'totalReceived': 0, 'dailyStreak': 0};
  }
  try {
    final resp = await client.rpc('fn_get_thinking_stats', params: {
      'p_user_id': client.auth.currentUser!.id,
      'p_family_id': familyId,
    });
    if (resp is Map) {
      return {
        'totalSent': (resp['total_sent'] ?? 0) as int,
        'totalReceived': (resp['total_received'] ?? 0) as int,
        'dailyStreak': (resp['daily_streak'] ?? 0) as int,
      };
    }
  } catch (e) {
    debugPrint('⚠️ thinkingStatsProvider error: $e');
  }
  return {'totalSent': 0, 'totalReceived': 0, 'dailyStreak': 0};
});

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.24: Variable reward messages
// ═══════════════════════════════════════════════════════════════════════

const _warmMessages = [
  "You just made someone's day brighter",
  "They'll feel loved when they see this",
  "That's going to make them smile",
  "You just sent a little warmth across the distance",
  "Someone's about to feel special",
  "Your kindness just traveled across the family",
];

String _randomWarmMessage() {
  final rng = Random();
  return _warmMessages[rng.nextInt(_warmMessages.length)];
}

// ═══════════════════════════════════════════════════════════════════════
// FamilyRingWidget
// ═══════════════════════════════════════════════════════════════════════

class FamilyRingWidget extends ConsumerStatefulWidget {
  const FamilyRingWidget({
    super.key,
    required this.familyId,
  });

  final String familyId;

  @override
  ConsumerState<FamilyRingWidget> createState() => _FamilyRingWidgetState();
}

class _FamilyRingWidgetState extends ConsumerState<FamilyRingWidget>
    with TickerProviderStateMixin {
  // ── Per-member UI state ──
  final Map<String, DateTime> _tappedUntil = {};
  final Map<String, DateTime> _cooldownUntil = {};
  String? _pendingMember;

  // Phase 3.24: Heart particle animation
  late final AnimationController _heartController;
  late final Animation<double> _heartAnimation;
  bool _showHeart = false;

  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _heartAnimation = CurvedAnimation(
      parent: _heartController,
      curve: Curves.easeOut,
    );
    _heartController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showHeart = false);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _heartController.dispose();
    super.dispose();
  }

  void _ensureCountdownTimer() {
    if (_countdownTimer?.isActive ?? false) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        return;
      }
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
    _cooldownUntil.remove(userId);
    return false;
  }

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

    if (_isOnCooldown(userId)) {
      _showSnack(context, 'Available again in ${_cooldownLabel(userId)}.');
      return;
    }

    if (_pendingMember == userId) return;

    HapticFeedback.lightImpact();

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
        // Phase 3.24: Variable reward — random warm message
        final warmMessage = _randomWarmMessage();
        final receiverName = result.receiverName ?? member.name.split(' ').first;

        // Phase 3.24: Heart particle burst animation
        setState(() => _showHeart = true);
        _heartController.forward(from: 0);

        HapticFeedback.mediumImpact();

        _showSnack(context, '$warmMessage — $receiverName will see it soon 💛');

        // Refresh stats
        ref.invalidate(thinkingStatsProvider(widget.familyId));

        // Store cooldown
        final expiresAt = result.cooldownExpiresAtUtc;
        if (expiresAt != null) {
          setState(() {
            _cooldownUntil[userId] = expiresAt.toLocal();
          });
          _ensureCountdownTimer();
        }
      } else if (result.error == 'cooldown' || result.error == 'receiver_cooldown') {
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

  String _fallbackMessage(String? errorCode) {
    switch (errorCode) {
      case 'cannot_send_to_self':
        return 'You cannot send a Thinking of You moment to yourself.';
      case 'receiver_not_in_family':
        return 'Recipient not found in this family.';
      case 'not_authenticated':
        return 'You must be signed in to send a Thinking of You moment.';
      case 'receiver_cooldown':
        return 'This person already received a Thinking of You moment recently. Try again later.';
      case 'cooldown':
        return 'You already sent a Thinking of You to this person recently. Try again later.';
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
    final membersAsync = ref.watch(familyKinrelMembersProvider(widget.familyId));
    final statsAsync = ref.watch(thinkingStatsProvider(widget.familyId));

    return membersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (members) {
        if (members.isEmpty) return _buildEmptyState(context);

        final stats = statsAsync.valueOrNull ??
            {'totalSent': 0, 'totalReceived': 0, 'dailyStreak': 0};

        return Stack(
          children: [
            _buildRing(context, members, stats),
            // Phase 3.24: Heart particle animation overlay
            if (_showHeart)
              Positioned.fill(
                child: IgnorePointer(
                  child: _HeartParticleOverlay(
                    animation: _heartAnimation,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 3.24: Warmer header with heart icon
        _WarmHeader(),
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
                  border: Border.all(color: KinrelColors.border, width: 1),
                ),
                child: const Icon(Icons.person_outline, size: 20, color: KinrelColors.textDim),
              ),
              const SizedBox(width: 12),
              const Expanded(
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

  Widget _buildRing(BuildContext context, List<FamilyKinrelMember> members, Map<String, int> stats) {
    final displayMembers = members.take(10).toList();
    final dailyStreak = stats['dailyStreak'] ?? 0;
    final totalSent = stats['totalSent'] ?? 0;
    final totalReceived = stats['totalReceived'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 3.24: Warmer header with heart icon + stats
        _WarmHeader(
          dailyStreak: dailyStreak,
          totalSent: totalSent,
          totalReceived: totalReceived,
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
                                        color: KinrelColors.orange.withValues(alpha: 0.5),
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
                                  ColorFiltered(
                                    colorFilter: onCooldown
                                        ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                                        : const ColorFilter.mode(Colors.transparent, BlendMode.saturation),
                                    child: (member.avatarUrl != null && member.avatarUrl!.isNotEmpty)
                                        ? CachedNetworkImage(
                                            imageUrl: member.avatarUrl!,
                                            cacheManager: KinrelImageCacheManager.instance,
                                            width: 52,
                                            height: 52,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) => _Placeholder(name: member.name),
                                          )
                                        : _Placeholder(name: member.name),
                                  ),
                                  if (isPending)
                                    Container(
                                      color: Colors.black54,
                                      child: const SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange),
                                      ),
                                    ),
                                  if (onCooldown)
                                    Positioned(
                                      right: 0, bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: KinrelColors.darkCard,
                                          border: Border.all(color: KinrelColors.textDim, width: 1),
                                        ),
                                        child: const Icon(Icons.lock_rounded, size: 10, color: KinrelColors.textDim),
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
                            color: onCooldown ? KinrelColors.textDim : KinrelColors.textSilver,
                          ),
                        ),
                      ),
                      if (onCooldown && cooldownLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            cooldownLabel,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: KinrelColors.orange),
                          ),
                        )
                      else
                        const SizedBox(height: 12),
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

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.24: Warm header with heart icon + stats
// ═══════════════════════════════════════════════════════════════════════

class _WarmHeader extends StatelessWidget {
  const _WarmHeader({this.dailyStreak = 0, this.totalSent = 0, this.totalReceived = 0});
  final int dailyStreak;
  final int totalSent;
  final int totalReceived;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          // Heart icon in orange circle
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.favorite_rounded, size: 14, color: KinrelColors.orange),
          ),
          const SizedBox(width: 8),
          // Title
          const Text(
            'Thinking of You',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(width: 8),
          // Daily streak badge (if > 0)
          if (dailyStreak > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 9)),
                  const SizedBox(width: 2),
                  Text(
                    '$dailyStreak day${dailyStreak == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          // Sent / Received stats (if any)
          if (totalSent > 0 || totalReceived > 0)
            Text(
              '$totalSent sent · $totalReceived received',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: KinrelColors.textDim,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.24: Heart particle overlay animation
// ═══════════════════════════════════════════════════════════════════════

class _HeartParticleOverlay extends StatelessWidget {
  const _HeartParticleOverlay({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        return CustomPaint(
          painter: _HeartParticlePainter(animation.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _HeartParticlePainter extends CustomPainter {
  _HeartParticlePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: (1 - progress) * 0.8)
      ..style = PaintingStyle.fill;

    // Draw 6 floating hearts that expand outward + fade
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * pi;
      final distance = 20 + progress * 80;
      final dx = centerX + cos(angle) * distance;
      final dy = centerY + sin(angle) * distance - progress * 40; // drift upward
      final heartSize = (1 - progress) * 12 + 4;

      canvas.drawCircle(
        Offset(dx, dy),
        heartSize,
        paint,
      );
    }

    // Central pulse ring
    final ringPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: (1 - progress) * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(centerX, centerY),
      20 + progress * 60,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(_HeartParticlePainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════════

class _Placeholder extends StatelessWidget {
  final String name;
  const _Placeholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: KinrelColors.darkElevated,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: KinrelColors.orange,
        ),
      ),
    );
  }
}
