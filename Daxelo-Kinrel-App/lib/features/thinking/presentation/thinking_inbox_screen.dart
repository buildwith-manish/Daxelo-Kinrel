// lib/features/thinking/presentation/thinking_inbox_screen.dart
//
// Phase 3.26 — Thinking of You Inbox.
//
// Shows all received "Thinking of You" moments with the sender's
// avatar, emotion, and timestamp. The user can scroll through their
// received love, hugs, gratitude, and pride moments.
//
// Reachable by tapping the "N new" badge on the Thinking of You
// header in the family hub.
//
// On open: marks all taps as read (via fn_mark_taps_read) so the
// badge count resets.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_time.dart';
import 'family_ring_widget.dart' show ThinkingEmotion;

class ThinkingInboxScreen extends ConsumerStatefulWidget {
  const ThinkingInboxScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<ThinkingInboxScreen> createState() => _ThinkingInboxScreenState();
}

class _ThinkingInboxScreenState extends ConsumerState<ThinkingInboxScreen> {
  List<Map<String, dynamic>> _taps = const [];
  int _unreadCount = 0;
  bool _loading = true;
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadTaps();
      _markRead();
    });
  }

  Future<void> _loadTaps() async {
    setState(() => _loading = true);
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final resp = await client.rpc('fn_get_received_taps', params: {
        'p_user_id': client.auth.currentUser!.id,
        'p_family_id': widget.familyId,
        'p_limit': 50,
        'p_offset': 0,
      });
      if (mounted && resp is Map && resp['ok'] == true) {
        final taps = (resp['taps'] as List? ?? const [])
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
        setState(() {
          _taps = taps;
          _unreadCount = (resp['unread_count'] ?? 0) as int;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) return;
    setState(() => _markingRead = true);
    try {
      await client.rpc('fn_mark_taps_read', params: {
        'p_user_id': client.auth.currentUser!.id,
        'p_family_id': widget.familyId,
      });
    } catch (_) {}
    if (mounted) setState(() => _markingRead = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        title: const Text('Thinking of You', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadTaps,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : _taps.isEmpty
              ? _EmptyInbox()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _taps.length,
                  itemBuilder: (ctx, i) => _TapCard(tap: _taps[i]),
                ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧡', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'No Thinking of You moments yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When family members send you a Thinking of You, it will appear here with their emotion and a timestamp.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TapCard extends StatelessWidget {
  const _TapCard({required this.tap});
  final Map<String, dynamic> tap;

  ThinkingEmotion get _emotion {
    final emotionStr = (tap['emotion'] ?? 'love') as String;
    return ThinkingEmotion.values.firstWhere(
      (e) => e.name == emotionStr,
      orElse: () => ThinkingEmotion.love,
    );
  }

  @override
  Widget build(BuildContext context) {
    final senderName = (tap['sender_name'] ?? 'Someone') as String;
    final senderAvatar = tap['sender_avatar_url'] as String?;
    final tappedAt = DateTime.tryParse((tap['tapped_at'] ?? '').toString()) ?? DateTime.now();
    final isRead = (tap['is_read'] ?? false) as bool;
    final emotion = _emotion;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? KinrelColors.darkCard : emotion.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead ? KinrelColors.border : emotion.color.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // Sender avatar with emotion-colored glow
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: emotion.color.withValues(alpha: 0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: emotion.color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipOval(
              child: (senderAvatar != null && senderAvatar.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: senderAvatar,
                      cacheManager: KinrelImageCacheManager.instance,
                      width: 44, height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _InitialsAvatar(name: senderName),
                    )
                  : _InitialsAvatar(name: senderName),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      emotion.emoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      senderName.split(' ').first,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (!isRead) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: emotion.color,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'sent you ${emotion.label.toLowerCase()}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(tappedAt),
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final ist = AppTime.toLocalDisplay(dt);
    final now = DateTime.now();
    final diff = now.difference(ist);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[ist.month - 1]} ${ist.day}';
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: KinrelColors.darkElevated,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KinrelColors.orange),
      ),
    );
  }
}
