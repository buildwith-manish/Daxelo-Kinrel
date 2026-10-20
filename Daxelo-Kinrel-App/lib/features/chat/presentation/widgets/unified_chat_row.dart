// lib/features/chat/presentation/widgets/unified_chat_row.dart
//
// DAXELO KINREL — Unified Chat Row (Groups + Directs)
//
// A single row widget that renders EITHER a group-chat row OR a direct-
// chat row depending on the UnifiedChatEntry.kind. Reuses the existing
// visual treatment (avatar, name, preview, time, DKBadge unread badge,
// preview formatting, time formatting) so rows look identical to today.
//
// Behavior:
//   • Group row: shows the family name + family avatar + a small
//     people-icon badge at the bottom-right of the avatar. The preview
//     is prefixed with "Name: message" when the sender is known and is
//     not the current viewer (entry.previewSenderName != null).
//   • Direct row: shows the other person's name + avatar + the preview
//     as-is (no prefix — DMs already show the other person's name in
//     the title).
//   • Swipe-to-archive: Dismissible end-to-start, both kinds.
//   • Semantic label: "Group chat, <name>, <N> unread" or "Direct
//     message, <name>, <N> unread".
//   • Tap: navigates to the chat screen (group → /family/<id>/chat,
//     direct → openDirectChat helper).
//
// This widget does NOT do its own network queries. All last-message
// + unread state comes from the UnifiedChatEntry passed in by the
// parent. This eliminates the N+1 loading the old _FamilyChatRow had.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/image_cache_manager.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/direct_group_service.dart' show openDirectChat;
import '../../providers/unified_inbox_provider.dart';
import '../../../../shared/widgets/dk_components.dart';

/// A single unified chat row. Renders either a group row or a direct
/// row based on entry.kind. Wrapped in a Dismissible for swipe-to-archive.
class UnifiedChatRow extends ConsumerWidget {
  const UnifiedChatRow({
    super.key,
    required this.entry,
    required this.onArchived,
  });

  final UnifiedChatEntry entry;
  final VoidCallback onArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnread = entry.unreadCount > 0;
    final l10n = S.of(context)!;

    // ── Preview text ──────────────────────────────────────────────
    // For group + circle chats: prefix with "Name: " when the
    // sender is known and is not the current viewer. For direct
    // chats: just the preview as-is.
    String previewText = entry.lastMessage;
    if ((entry.kind == UnifiedChatKind.group ||
            entry.kind == UnifiedChatKind.circle) &&
        entry.previewSenderName != null &&
        entry.previewSenderName!.isNotEmpty &&
        previewText.isNotEmpty) {
      previewText = '${entry.previewSenderName}: $previewText';
    }

    // ── Semantic label for screen readers ─────────────────────────
    final semanticLabel = switch (entry.kind) {
      UnifiedChatKind.group =>
        l10n.chatInboxRowSemanticGroup(entry.title, entry.unreadCount),
      UnifiedChatKind.direct =>
        l10n.chatInboxRowSemanticDirect(entry.title, entry.unreadCount),
      UnifiedChatKind.circle =>
        'Circle, ${entry.title}, ${entry.unreadCount} unread',
    };

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Dismissible(
        key: ValueKey(
            '${entry.kind == UnifiedChatKind.group ? 'group' : entry.kind == UnifiedChatKind.circle ? 'circle' : 'dm'}_${entry.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onArchived(),
        background: Container(
          alignment: Alignment.centerRight,
          color: KinrelColors.ember,
          padding: const EdgeInsets.only(right: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.archive_outlined, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(
                l10n.chatInboxArchiveAction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: KinrelTypography.bodyFont,
                ),
              ),
            ],
          ),
        ),
        child: ListTile(
          onTap: () => _navigateToChat(context),
          leading: _buildAvatar(context, hasUnread),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight:
                        hasUnread ? FontWeight.w700 : FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatTime(entry.lastMessageTime),
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: hasUnread
                      ? KinrelColors.ember
                      : KinrelColors.textDim,
                  fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  previewText.isEmpty ? l10n.chatInboxNoMessages : previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: hasUnread
                        ? KinrelColors.textWhite
                        : KinrelColors.textSilver,
                    fontWeight:
                        hasUnread ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: KinrelSpacing.xs),
                DKBadge(
                  count: entry.unreadCount,
                  color: KinrelColors.ember,
                ),
              ],
            ],
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: 6,
          ),
        ),
      ),
    );
  }

  /// Builds the avatar. For groups: includes a small people-icon badge
  /// at the bottom-right (a 18x18 circle with an orange tint + a
  /// people icon). For directs: just the avatar.
  Widget _buildAvatar(BuildContext context, bool hasUnread) {
    final avatarUrl = entry.avatarUrl;
    final fallbackInitial =
        entry.title.isNotEmpty ? entry.title[0].toUpperCase() : '?';

    final avatar = (avatarUrl != null && avatarUrl.isNotEmpty)
        ? CircleAvatar(
            radius: 26,
            backgroundColor: KinrelColors.ember.withValues(alpha: 0.15),
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl,
                cacheManager: KinrelImageCacheManager.instance,
                fit: BoxFit.cover,
                width: 52,
                height: 52,
                memCacheWidth:
                    (52 * MediaQuery.devicePixelRatioOf(context)).round(),
                memCacheHeight:
                    (52 * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (_, __) => _initialsWidget(fallbackInitial),
                errorWidget: (_, __, ___) => _initialsWidget(fallbackInitial),
              ),
            ),
          )
        : CircleAvatar(
            radius: 26,
            backgroundColor: KinrelColors.ember.withValues(alpha: 0.15),
            child: _initialsWidget(fallbackInitial),
          );

    // Group rows get the people-icon badge at bottom-right.
    // Circle rows get a rounded-square icon tile instead of a
    // circular avatar (per mockup 12).
    if (entry.kind == UnifiedChatKind.circle) {
      // Circle: render a rounded-square tile with the circle's icon
      final iconKey = entry.iconKey ?? 'default';
      final icon = _iconForKey(iconKey);
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: KinrelGradients.igniteGradient,
        ),
        child: Center(
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      );
    }
    if (entry.kind == UnifiedChatKind.group) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: KinrelColors.darkBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: KinrelColors.darkSurface,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.people_outline,
                size: 10,
                color: KinrelColors.ember,
              ),
            ),
          ),
        ],
      );
    }
    return avatar;
  }

  Widget _initialsWidget(String initial) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: KinrelColors.ember,
        ),
      ),
    );
  }

  /// Formats the last-message time for the row (mirrors the existing
  /// _formatTime helper in chat_inbox_screen.dart).
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(msgDay).inDays;
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    if (diffDays == 0) {
      return '$displayHour:$minute $period';
    }
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) return '${diffDays}d';
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  void _navigateToChat(BuildContext context) {
    switch (entry.kind) {
      case UnifiedChatKind.group:
        final familyId = entry.familyId ?? entry.id;
        context.push(
          '/family/$familyId/chat?name=${Uri.encodeComponent(entry.title)}',
        );
      case UnifiedChatKind.direct:
        openDirectChat(
          context,
          otherUserId: entry.otherUserId ?? entry.id,
          familyId: entry.familyId ?? '',
        );
      case UnifiedChatKind.circle:
        // Phase 2: the circle conversation screen is Phase 3.
        // For now, navigate to a placeholder that shows a friendly
        // message. Phase 3 will add the full circle conversation
        // (parameterized ChatScreen with scope=circle).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Circle conversations are coming in Phase 3.'),
            backgroundColor: KinrelColors.darkCard,
          ),
        );
    }
  }

  /// Returns the IconData for a circle icon key.
  IconData _iconForKey(String key) {
    switch (key) {
      case 'family':
        return Icons.family_restroom_rounded;
      case 'travel':
        return Icons.flight_takeoff_rounded;
      case 'celebration':
        return Icons.celebration_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'elders':
        return Icons.elderly_rounded;
      case 'cousins':
        return Icons.people_alt_rounded;
      case 'heart':
        return Icons.favorite_rounded;
      default:
        return Icons.group_rounded;
    }
  }
}
