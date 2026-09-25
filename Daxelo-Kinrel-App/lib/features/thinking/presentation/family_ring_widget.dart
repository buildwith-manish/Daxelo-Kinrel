// lib/features/thinking/presentation/family_ring_widget.dart
//
// "Thinking of You" — horizontal ring of family member faces.
// Tap any face to send a silent "Thinking of You" signal.
//
// Phase 3.25 — Next-level improvements:
//   1. Emotion selection: tap an avatar → bottom sheet with 4 emotions
//      (💛 Love, 🤗 Hug, 🙏 Gratitude, 🌟 Proud). Each emotion has a
//      different glow color on the avatar ring + a different warm
//      confirmation message.
//   2. Time-of-day greeting: contextual header that changes with the
//      time of day ("Good morning! Who's on your mind?" / "Good
//      evening! Send some warmth before bed" / "Late night? Someone's
//      probably thinking of you too").
//   3. "Received from" indicator: small gold dot on avatars who have
//      sent YOU a Thinking of You in the last 24h, so you can
//      reciprocate. Drives reciprocity (Cialdini).
//
// Phase 3.24 (preserved from previous):
//   - Variable reward messages (random warm confirmation per send)
//   - Heart particle burst animation on send
//   - Daily streak counter ("🔥 N days")
//   - Sent/received stats on header
//   - Branded warm header with heart icon

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
import '../data/thinking_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.25: Emotion types
// ═══════════════════════════════════════════════════════════════════════

enum ThinkingEmotion {
  love('💛', 'Love', Color(0xFFE8612A)),
  hug('🤗', 'Hug', Color(0xFFF59240)),
  gratitude('🙏', 'Gratitude', Color(0xFF4CAF7A)),
  proud('🌟', 'Proud', Color(0xFF8B5CF6));

  const ThinkingEmotion(this.emoji, this.label, this.color);
  final String emoji;
  final String label;
  final Color color;
}

const _emotionWarmMessages = {
  ThinkingEmotion.love: [
    "Your love just traveled across the family",
    "They'll feel your warmth when they see this",
    "A little love sent across the distance",
  ],
  ThinkingEmotion.hug: [
    "You just sent a virtual hug",
    "They'll feel wrapped in warmth",
    "A hug just crossed the screen for them",
  ],
  ThinkingEmotion.gratitude: [
    "You just expressed gratitude — that's beautiful",
    "They'll feel appreciated when they see this",
    "Gratitude travels well — they'll feel it",
  ],
  ThinkingEmotion.proud: [
    "You just showed you're proud of them",
    "They'll feel validated and seen",
    "Pride is a gift — you just gave it",
  ],
};

String _randomWarmMessageFor(ThinkingEmotion emotion) {
  final messages = _emotionWarmMessages[emotion]!;
  final rng = Random();
  return messages[rng.nextInt(messages.length)];
}

/// Time-of-day greeting based on the current IST hour.
String _timeOfDayGreeting() {
  final now = DateTime.now().toUtc();
  final istHour = (now.hour + 5) % 24; // UTC + 5 (approximate IST)
  if (istHour >= 5 && istHour < 12) {
    return 'Good morning! Who\'s on your mind?';
  } else if (istHour >= 12 && istHour < 17) {
    return 'Good afternoon! Send some warmth';
  } else if (istHour >= 17 && istHour < 22) {
    return 'Good evening! Send some love before bed';
  } else {
    return 'Late night? Someone\'s probably thinking of you too';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.25: "Received from" provider — IDs of users who sent YOU a
// Thinking of You in the last 24h. Used to show a gold dot on their
// avatars in the ring, so you can reciprocate.
// ═══════════════════════════════════════════════════════════════════════

final receivedFromProvider =
    FutureProvider.family<Set<String>, String>((ref, familyId) async {
  final client = ref.read(supabaseProvider);
  if (client == null || client.auth.currentUser == null) return {};
  try {
    // Phase 3.26 fix: use the correct table name (thinking_of_you_taps,
    // lowercase) and the correct column name (tappedAt, not createdAt).
    final since = DateTime.now().subtract(const Duration(hours: 24)).toUtc().toIso8601String();
    final rows = await client
        .from('thinking_of_you_taps')
        .select('senderId')
        .eq('receiverId', client.auth.currentUser!.id)
        .eq('familyId', familyId)
        .gte('tappedAt', since);
    return (rows as List).map((r) => (r as Map)['senderId'] as String).toSet();
  } catch (e) {
    debugPrint('⚠️ receivedFromProvider error: $e');
    return {};
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.26: Unread tap count provider (for the badge on the header)
// ═══════════════════════════════════════════════════════════════════════

final unreadTapCountProvider =
    FutureProvider.family<int, String>((ref, familyId) async {
  final client = ref.read(supabaseProvider);
  if (client == null || client.auth.currentUser == null) return 0;
  try {
    final resp = await client.rpc('fn_get_unread_tap_count', params: {
      'p_user_id': client.auth.currentUser!.id,
      'p_family_id': familyId,
    });
    if (resp is Map && resp['ok'] == true) {
      return (resp['unread_count'] ?? 0) as int;
    }
  } catch (e) {
    debugPrint('⚠️ unreadTapCountProvider error: $e');
  }
  return 0;
});

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

    // Phase 3.25: Show emotion selection sheet instead of immediately sending
    final emotion = await _showEmotionSheet(context, member);
    if (emotion == null || !mounted) return; // user cancelled

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
        // Phase 3.25: Emotion-specific warm message
        final warmMessage = _randomWarmMessageFor(emotion);
        final receiverName = result.receiverName ?? member.name.split(' ').first;

        // Heart particle burst with emotion color
        setState(() => _showHeart = true);
        _heartController.forward(from: 0);

        HapticFeedback.mediumImpact();

        _showSnack(context, '$warmMessage — $receiverName will see it soon ${emotion.emoji}');

        // Refresh stats + received-from
        ref.invalidate(thinkingStatsProvider(widget.familyId));
        ref.invalidate(receivedFromProvider(widget.familyId));
        ref.invalidate(unreadTapCountProvider(widget.familyId));

        final expiresAt = result.cooldownExpiresAtUtc;
        if (expiresAt != null) {
          setState(() {
            _cooldownUntil[userId] = expiresAt.toLocal();
          });
          _ensureCountdownTimer();
        }

        // Phase 3.27: Navigate to the personal chat (DM) with the
        // recipient so the sender can see the Thinking of You message
        // in context. This makes the feature feel personal — the user
        // taps an avatar → picks an emotion → is taken to the 1:1
        // chat where they can continue the conversation.
        //
        // Wait 1.5s so the heart particle animation + SnackBar are
        // visible before navigating. The user sees the celebration,
        // THEN lands in the chat.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            context.push('/dm/${member.userId}');
          }
        });
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

  /// Phase 3.25: Show the emotion selection bottom sheet.
  /// Returns the selected emotion, or null if cancelled.
  Future<ThinkingEmotion?> _showEmotionSheet(
    BuildContext context,
    FamilyKinrelMember member,
  ) async {
    final firstName = member.name.split(' ').first;
    return showModalBottomSheet<ThinkingEmotion>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: KinrelColors.textDim.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Send to $firstName',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'How are you feeling about them?',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
            // Emotion grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ThinkingEmotion.values.map((e) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, e),
                    child: _EmotionChip(emotion: e),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
    final receivedFromAsync = ref.watch(receivedFromProvider(widget.familyId));
    final unreadCountAsync = ref.watch(unreadTapCountProvider(widget.familyId));

    return membersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (members) {
        if (members.isEmpty) return _buildEmptyState(context);

        final stats = statsAsync.valueOrNull ??
            {'totalSent': 0, 'totalReceived': 0, 'dailyStreak': 0};
        final receivedFrom = receivedFromAsync.valueOrNull ?? {};
        final unreadCount = unreadCountAsync.valueOrNull ?? 0;

        return Stack(
          children: [
            _buildRing(context, members, stats, receivedFrom, unreadCount),
            if (_showHeart)
              Positioned.fill(
                child: IgnorePointer(
                  child: _HeartParticleOverlay(animation: _heartAnimation),
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

  Widget _buildRing(BuildContext context, List<FamilyKinrelMember> members, Map<String, int> stats, Set<String> receivedFrom, int unreadCount) {
    final displayMembers = members.take(10).toList();
    final dailyStreak = stats['dailyStreak'] ?? 0;
    final totalSent = stats['totalSent'] ?? 0;
    final totalReceived = stats['totalReceived'] ?? 0;
    final greeting = _timeOfDayGreeting();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 3.26: Warm header with time-of-day greeting + stats + unread badge
        // The header is tappable to open the Thinking of You inbox screen
        // when there are unread received taps.
        GestureDetector(
          onTap: unreadCount > 0
              ? () => context.push('/family/${widget.familyId}/thinking-inbox')
              : null,
          child: _WarmHeader(
            dailyStreak: dailyStreak,
            totalSent: totalSent,
            totalReceived: totalReceived,
            greeting: greeting,
            unreadCount: unreadCount,
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
              final hasReceivedFrom = receivedFrom.contains(userId);

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
                                  // Phase 3.25: "Received from" gold dot —
                                  // this person sent you a Thinking of You
                                  // in the last 24h. Shown as a small pulsing
                                  // gold dot on the top-right corner.
                                  if (hasReceivedFrom && !onCooldown)
                                    Positioned(
                                      right: 0, top: 0,
                                      child: Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: KinrelColors.orange,
                                          border: Border.all(color: KinrelColors.darkCard, width: 1.5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: KinrelColors.orange.withValues(alpha: 0.6),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            ),
                                          ],
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
  const _WarmHeader({
    this.dailyStreak = 0,
    this.totalSent = 0,
    this.totalReceived = 0,
    this.greeting,
    this.unreadCount = 0,
  });
  final int dailyStreak;
  final int totalSent;
  final int totalReceived;
  final String? greeting;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Heart icon in orange circle
              Container(
                width: 24, height: 24,
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
              // Phase 3.26: Unread badge — pulsing orange dot with count
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$unreadCount new',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
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
          // Phase 3.25: Time-of-day greeting
          if (greeting != null && greeting!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                greeting!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textDim,
                ),
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

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.25: Emotion selection chip
// ═══════════════════════════════════════════════════════════════════════

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.emotion});
  final ThinkingEmotion emotion;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: emotion.color.withValues(alpha: 0.12),
            border: Border.all(
              color: emotion.color.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: emotion.color.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(emotion.emoji, style: const TextStyle(fontSize: 24)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          emotion.label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: emotion.color,
          ),
        ),
      ],
    );
  }
}
