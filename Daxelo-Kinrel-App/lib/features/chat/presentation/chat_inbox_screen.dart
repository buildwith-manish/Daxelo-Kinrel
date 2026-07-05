// lib/features/chat/presentation/chat_inbox_screen.dart
//
// DAXELO KINREL — Unified Chat Inbox (top-level tab)
//
// Shows a unified inbox across ALL families the user belongs to.
// Each family appears as a row with the latest message, sender name,
// timestamp, and unread badge. Tapping a family row opens that
// family's ChatScreen.
//
// This replaces the old per-family chat-only entry point — now chat
// is a standalone top-level tab (position 2, right after Home).

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
import '../providers/chat_provider.dart';

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KinrelSpacing.base, 16, KinrelSpacing.base, 12,
              ),
              child: Row(
                children: [
                  Text(
                    'Chats',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),
            // Inbox list
            Expanded(
              child: familiesAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange),
                ),
                error: (e, _) => DKErrorState(
                  message: 'Could not load chats: $e',
                  onRetry: () => ref.invalidate(familyListProvider),
                ),
                data: (families) {
                  if (families.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView.builder(
                    itemCount: families.length,
                    itemBuilder: (context, index) {
                      final family = families[index];
                      return _FamilyChatRow(family: family);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 56,
              color: KinrelColors.textDim,
            ),
            const SizedBox(height: 16),
            Text(
              'No families yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a family to start chatting',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/families/create'),
              icon: Icon(Icons.add, size: 18),
              label: Text('Create Family'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single family chat row in the unified inbox.
class _FamilyChatRow extends ConsumerStatefulWidget {
  const _FamilyChatRow({required this.family});
  final Family family;

  @override
  ConsumerState<_FamilyChatRow> createState() => _FamilyChatRowState();
}

class _FamilyChatRowState extends ConsumerState<_FamilyChatRow> {
  ChatMessage? _lastMessage;
  int _unreadCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLatestMessage();
  }

  Future<void> _loadLatestMessage() async {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;

      // Fetch the latest message for this family
      final response = await client
          .from('ChatMessage')
          .select()
          .eq('familyId', widget.family.id)
          .eq('isDeleted', false)
          .order('createdAt', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final row = response.first as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _lastMessage = ChatMessage.fromJson(row);
          });
        }
      }

      // Fetch unread count (messages not sent by me, not yet read)
      final myUserId = client.auth.currentUser?.id;
      if (myUserId != null) {
        final unreadResponse = await client
            .from('ChatMessage')
            .select('id')
            .eq('familyId', widget.family.id)
            .eq('isDeleted', false)
            .eq('isRead', false)
            .neq('senderId', myUserId)
            .count();

        if (mounted) {
          setState(() {
            _unreadCount = unreadResponse.count;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    final hasUnread = _unreadCount > 0;

    return ListTile(
      onTap: () => context.push(
        '/family/${family.id}/chat?name=${Uri.encodeComponent(family.name)}',
      ),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
        child: Text(
          family.name.isNotEmpty
              ? family.name[0].toUpperCase()
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
          Expanded(
            child: Text(
              family.name,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
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
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
        ],
      ),
      subtitle: _lastMessage != null
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    _lastMessage!.messageType == MessageType.photo
                        ? '📷 Photo'
                        : _lastMessage!.content,
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            )
          : Text(
              _isLoading ? 'Loading…' : 'No messages yet',
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
}
