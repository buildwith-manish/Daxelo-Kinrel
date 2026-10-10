// lib/features/chat/presentation/widgets/saved_messages_inbox_row.dart
//
// DAXELO KINREL — Tier 1 Feature 1.1: Saved Messages — Inbox Row
//
// Renders the "Saved Messages" row at the top of the DM section in
// chat_inbox_screen.dart. Tapping it opens the DirectChatScreen with
// otherUserId = currentUserId (a self-DM).
//
// The row always shows (even when hasSavedMessages is false) so the
// user can discover the feature — matches WhatsApp's behavior.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../data/saved_messages_provider.dart';

class SavedMessagesInboxRow extends ConsumerStatefulWidget {
  const SavedMessagesInboxRow({super.key});

  @override
  ConsumerState<SavedMessagesInboxRow> createState() =>
      _SavedMessagesInboxRowState();
}

class _SavedMessagesInboxRowState extends ConsumerState<SavedMessagesInboxRow> {
  @override
  void initState() {
    super.initState();
    // Kick off the first fetch on first build. The StateNotifier's
    // state starts as null — we render a placeholder until refresh()
    // returns the actual preview (or an empty row when there's no DM).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(savedMessagesProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(savedMessagesProvider);
    return _Row(preview: preview);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.preview});

  final SavedMessagesPreview? preview;

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    final lastMessage = preview?.lastMessageContent;
    final lastTime = preview?.lastMessageCreatedAt != null
        ? DateTime.tryParse(preview!.lastMessageCreatedAt!)
        : null;

    return InkWell(
      onTap: () {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId == null || currentUserId.isEmpty) return;
        // Open the DM screen with the user themselves as the "other" user.
        // DirectChatScreen uses otherUserId to fetch the conversation; for
        // a self-DM, the otherUserId is the current user's id.
        context.push('/dm/$currentUserId');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: 12,
        ),
        child: Row(
          children: [
            // ── Bookmark-style avatar (NOT the user's profile pic —
            // matches WhatsApp's Saved Messages bookmark icon).
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: KinrelColors.igniteOrange.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_rounded,
                color: KinrelColors.igniteOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saved Messages',
                    style: TextStyle(
                      color: KinrelColors.textWhite,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: KinrelTypography.bodyFont,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lastMessage ?? 'Forward messages here to keep them',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: KinrelColors.textSilver.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // ── Time (right-aligned) ──────────────────────────────
            if (lastTime != null)
              Text(
                _shortTime(lastTime),
                style: TextStyle(
                  color: KinrelColors.textSilver.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Render a short relative-or-clock time string for the inbox row.
/// "Now", "5m", "10:30 AM", "Yesterday", "M/D" — matches the existing
/// inbox row format.
String _shortTime(DateTime when) {
  final now = DateTime.now();
  final diff = now.difference(when);
  if (diff.inMinutes < 1) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && now.day == when.day) {
    final hour = when.hour > 12 ? when.hour - 12 : (when.hour == 0 ? 12 : when.hour);
    final minute = when.minute.toString().padLeft(2, '0');
    final ampm = when.hour >= 12 ? 'AM' : 'PM';
    return '$hour:$minute $ampm';
  }
  if (diff.inDays < 2) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${when.month}/${when.day}';
}
