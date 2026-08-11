// lib/features/family/presentation/family_chat_list_screen.dart
//
// DAXELO KINREL — Family Chat List Screen (v115)
//
// The Chat tab destination inside Family Space. Shows a unified list of
// conversations: the Family Group Chat (pinned at top) + all 1:1 DM
// conversations with family members. Filter tabs let the user switch
// between All / Family / Direct.
//
// Tapping a conversation pushes the conversation screen (full-screen,
// no Family bottom nav) — matching WhatsApp/Telegram/Instagram DM UX.
//
// Route: /family/:id/chats  (plural — distinguishes from /family/:id/chat
// which is the group conversation itself)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../chat/data/direct_message_provider.dart';
import '../../chat/providers/chat_provider.dart';
import 'family_space_floating_nav.dart';

/// Filter tab for the chat list.
enum _ChatFilter { all, family, direct }

class FamilyChatListScreen extends ConsumerStatefulWidget {
  const FamilyChatListScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilyChatListScreen> createState() =>
      _FamilyChatListScreenState();
}

class _FamilyChatListScreenState extends ConsumerState<FamilyChatListScreen> {
  _ChatFilter _filter = _ChatFilter.all;

  @override
  Widget build(BuildContext context) {
    final familyAsync = ref.watch(familyDetailProvider(widget.familyId));
    final dmInboxAsync = ref.watch(dmInboxProvider);

    final familyName = familyAsync.valueOrNull?.family.name ?? 'Family';
    final familyAvatarUrl = familyAsync.valueOrNull?.family.avatarUrl;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Chats',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      bottomNavigationBar:
          FamilySpaceFloatingNav(familyId: widget.familyId),
      body: Column(
        children: [
          // ── Filter tabs: All / Family / Direct ──────────────────
          _buildFilterTabs(),

          // ── Chat list ───────────────────────────────────────────
          Expanded(
            child: dmInboxAsync.when(
              loading: () => Center(
                child:
                    CircularProgressIndicator(color: KinrelColors.orange),
              ),
              error: (_, __) => Center(
                child: Text(
                  'Could not load chats',
                  style: TextStyle(color: KinrelColors.textDim),
                ),
              ),
              data: (dmItems) {
                final activeDms =
                    dmItems.where((d) => !d.isArchived).toList();

                return ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    // ── Family Group Chat (pinned at top) ──────────
                    if (_filter == _ChatFilter.all ||
                        _filter == _ChatFilter.family)
                      _GroupChatRow(
                        familyId: widget.familyId,
                        familyName: familyName,
                        familyAvatarUrl: familyAvatarUrl,
                      ),

                    // ── Direct Messages ────────────────────────────
                    if (_filter == _ChatFilter.all ||
                        _filter == _ChatFilter.direct) ...[
                      if (_filter == _ChatFilter.all &&
                          activeDms.isNotEmpty)
                        _buildSectionHeader('Direct Messages'),
                      ...activeDms.map((dm) => _DmRow(
                            item: dm,
                          )),
                    ],

                    // ── Empty state ────────────────────────────────
                    if (activeDms.isEmpty &&
                        _filter == _ChatFilter.direct)
                      _buildEmptyState('No direct messages yet'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the All / Family / Direct filter tab row.
  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      child: Row(
        children: [
          _filterTab('All', _ChatFilter.all),
          _filterTab('Family', _ChatFilter.family),
          _filterTab('Direct', _ChatFilter.direct),
        ],
      ),
    );
  }

  Widget _filterTab(String label, _ChatFilter filter) {
    final isSelected = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? KinrelColors.orange
                : Colors.transparent,
            borderRadius: BorderRadius.circular(KinrelRadius.button - 4),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : KinrelColors.textSilver,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base, 12, KinrelSpacing.base, 4,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KinrelColors.orange,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: KinrelColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Family Group Chat Row
// ═══════════════════════════════════════════════════════════════════════

/// The Family Group Chat row — pinned at the top of the chat list.
/// Loads the latest message + unread count from the ChatMessage table.
class _GroupChatRow extends ConsumerStatefulWidget {
  const _GroupChatRow({
    required this.familyId,
    required this.familyName,
    this.familyAvatarUrl,
  });

  final String familyId;
  final String familyName;
  final String? familyAvatarUrl;

  @override
  ConsumerState<_GroupChatRow> createState() => _GroupChatRowState();
}

class _GroupChatRowState extends ConsumerState<_GroupChatRow> {
  ChatMessage? _lastMessage;
  int _unreadCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;

      // Latest message
      final response = await client
          .from('ChatMessage')
          .select()
          .eq('familyId', widget.familyId)
          .eq('isDeletedForEveryone', false)
          .order('createdAt', ascending: false)
          .limit(1);

      if (response.isNotEmpty && mounted) {
        setState(() {
          _lastMessage = ChatMessage.fromJson(
              response.first as Map<String, dynamic>);
        });
      }

      // Unread count
      final myUserId = client.auth.currentUser?.id;
      if (myUserId != null) {
        final unreadResponse = await client
            .from('ChatMessage')
            .select('id')
            .eq('familyId', widget.familyId)
            .eq('isDeletedForEveryone', false)
            .eq('isRead', false)
            .neq('senderId', myUserId)
            .count();

        if (mounted) {
          setState(() {
            _unreadCount = unreadResponse.count;
            _isLoading = false;
          });
        }
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _unreadCount > 0;

    return ListTile(
      onTap: () => context.push(
        '/family/${widget.familyId}/chat?name=${Uri.encodeComponent(widget.familyName)}',
      ),
      leading: widget.familyAvatarUrl != null &&
              widget.familyAvatarUrl!.isNotEmpty
          ? CircleAvatar(
              radius: 26,
              backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: widget.familyAvatarUrl!,
                  fit: BoxFit.cover,
                  width: 52,
                  height: 52,
                  placeholder: (_, __) => Center(
                    child: Text(
                      widget.familyName.isNotEmpty
                          ? widget.familyName[0].toUpperCase()
                          : 'F',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Center(
                    child: Text(
                      widget.familyName.isNotEmpty
                          ? widget.familyName[0].toUpperCase()
                          : 'F',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : CircleAvatar(
              radius: 26,
              backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
              child: Text(
                widget.familyName.isNotEmpty
                    ? widget.familyName[0].toUpperCase()
                    : 'F',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
      title: Row(
        children: [
          Icon(Icons.group_rounded,
              size: 16, color: KinrelColors.orange.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.familyName,
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
          if (_lastMessage != null)
            Text(
              _formatTime(_lastMessage!.timestamp),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: hasUnread
                    ? KinrelColors.orange
                    : KinrelColors.textDim,
                fontWeight:
                    hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
        ],
      ),
      subtitle: _lastMessage != null
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    _lastMessagePreview(_lastMessage!),
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: hasUnread
                          ? KinrelColors.textSilver
                          : KinrelColors.textDim,
                      fontWeight:
                          hasUnread ? FontWeight.w500 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasUnread)
                  DKBadge(count: _unreadCount, color: KinrelColors.orange),
              ],
            )
          : Text(
              _isLoading ? 'Loading…' : 'Tap to start chatting',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
            ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    }
    if (diff.inDays < 2) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }

  String _lastMessagePreview(ChatMessage msg) {
    switch (msg.messageType) {
      case MessageType.photo:
        return 'Photo';
      case MessageType.voiceNote:
        final secs = msg.durationSeconds ?? 0;
        final m = (secs ~/ 60).toString();
        final s = (secs % 60).toString().padLeft(2, '0');
        return 'Voice message ($m:$s)';
      case MessageType.familyEvent:
        if (msg.messageSubType == 'thinking_of_you') {
          final senderFirst = msg.senderName.split(' ').first;
          return 'Thinking of You from $senderFirst';
        }
        return msg.eventTitle ?? 'Family Event';
      case MessageType.sticker:
        return msg.content;
      case MessageType.text:
      default:
        return msg.content;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DM Row
// ═══════════════════════════════════════════════════════════════════════

/// A single DM conversation row in the chat list.
class _DmRow extends StatelessWidget {
  const _DmRow({required this.item});
  final DmInboxItem item;

  @override
  Widget build(BuildContext context) {
    final hasUnread = item.unreadCount > 0;

    return ListTile(
      onTap: () => context.push('/dm/${item.otherUserId}'),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
        backgroundImage: item.otherUserAvatar != null &&
                item.otherUserAvatar!.isNotEmpty
            ? CachedNetworkImageProvider(item.otherUserAvatar!)
            : null,
        child: item.otherUserAvatar == null ||
                item.otherUserAvatar!.isEmpty
            ? Text(
                _initials(item.otherUserName),
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.otherUserName,
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
            _formatTime(item.lastMessageTime),
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: hasUnread
                  ? KinrelColors.orange
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
              item.lastMessage,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: hasUnread
                    ? KinrelColors.textSilver
                    : KinrelColors.textDim,
                fontWeight:
                    hasUnread ? FontWeight.w500 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasUnread)
            DKBadge(count: item.unreadCount, color: KinrelColors.orange),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    }
    if (diff.inDays < 2) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }
}
