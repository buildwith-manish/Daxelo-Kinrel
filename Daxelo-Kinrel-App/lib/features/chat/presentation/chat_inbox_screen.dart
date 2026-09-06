// lib/features/chat/presentation/chat_inbox_screen.dart
//
// DAXELO KINREL — Unified Chat Inbox (top-level tab)
//
// v113 — Rewritten with two sections (Groups + Direct Messages),
// swipe-to-archive (Dismissible), an Archived row at the bottom, and
// header action buttons (search + compose new DM). Matches the
// WhatsApp/Telegram inbox layout.
//
// Shows a unified inbox across ALL families the user belongs to PLUS
// all 1:1 DM conversations. Each row shows the latest message, sender
// name, timestamp, and unread badge. Tapping a group row opens that
// family's ChatScreen; tapping a DM row opens the DirectChatScreen.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/direct_message_provider.dart';
import '../providers/chat_provider.dart';

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  Set<String> _archivedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _loadArchivedGroups();
  }

  /// Loads the set of archived group-chat family IDs from
  /// shared_preferences so the inbox can filter them out.
  Future<void> _loadArchivedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final groupKeys = keys.where((k) => k.startsWith('group_archived_'));
      final archived = <String>{};
      for (final k in groupKeys) {
        if (prefs.getBool(k) == true) {
          archived.add(k.substring('group_archived_'.length));
        }
      }
      if (mounted) setState(() => _archivedGroupIds = archived);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);
    final dmInboxAsync = ref.watch(dmInboxProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header with title + action buttons ──────────────────
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
                  const Spacer(),
                  // v113: Search button
                  IconButton(
                    icon: Icon(
                      Icons.search_rounded,
                      color: KinrelColors.textSilver,
                      size: 24,
                    ),
                    onPressed: () => context.push('/search'),
                  ),
                  // v113: Compose new DM — opens a bottom sheet to pick
                  // a family member to start a DM with.
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      color: KinrelColors.textSilver,
                      size: 24,
                    ),
                    onPressed: () => _showNewDmPicker(),
                  ),
                ],
              ),
            ),
            // ── Unified inbox list ──────────────────────────────────
            Expanded(
              child: familiesAsync.when(
                loading: () => Center(
                  child:
                      CircularProgressIndicator(color: KinrelColors.orange),
                ),
                error: (e, _) => DKErrorState(
                  message: 'Could not load chats: $e',
                  onRetry: () => ref.invalidate(familyListProvider),
                ),
                data: (families) {
                  if (families.isEmpty && dmInboxAsync.isLoading) {
                    return Center(
                      child: CircularProgressIndicator(
                          color: KinrelColors.orange),
                    );
                  }

                  // Filter out archived group chats.
                  final activeGroups = families
                      .where((f) => !_archivedGroupIds.contains(f.id))
                      .toList();

                  // DM section data.
                  final dmItems = dmInboxAsync.valueOrNull ?? [];
                  final activeDms =
                      dmItems.where((d) => !d.isArchived).toList();

                  // Archived count (groups + DMs).
                  final archivedGroupCount =
                      families.length - activeGroups.length;
                  final archivedDmCount =
                      dmItems.where((d) => d.isArchived).length;
                  final totalArchived = archivedGroupCount + archivedDmCount;

                  if (families.isEmpty && activeDms.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView(
                    children: [
                      // ── Section 1: Groups ──
                      if (activeGroups.isNotEmpty) ...[
                        _buildSectionHeader('Groups'),
                        ...activeGroups.map((family) => _FamilyChatRow(
                              family: family,
                              onArchived: () => _archiveGroup(family.id),
                            )),
                      ],
                      // ── Section 2: Direct Messages ──
                      if (activeDms.isNotEmpty) ...[
                        _buildSectionHeader('Direct Messages'),
                        ...activeDms.map((dm) => _DmChatRow(
                              item: dm,
                              onArchived: () => _archiveDm(dm.otherUserId),
                            )),
                      ],
                      // ── Archived row (only if there are archived items) ──
                      if (totalArchived > 0) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: KinrelColors.darkElevated,
                            child: Icon(
                              Icons.archive_outlined,
                              color: KinrelColors.textSilver,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            'Archived',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite,
                            ),
                          ),
                          subtitle: Text(
                            '$totalArchived ${totalArchived == 1 ? "conversation" : "conversations"}',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              color: KinrelColors.textDim,
                            ),
                          ),
                          onTap: () => context.push('/chats/archived'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: KinrelSpacing.base,
                            vertical: 4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 80),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a small section subheader (e.g. "Groups", "Direct Messages").
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

  /// v113: Archives a group chat by setting a shared_preferences flag.
  Future<void> _archiveGroup(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('group_archived_$familyId', true);
    if (mounted) {
      setState(() => _archivedGroupIds.add(familyId));
    }
  }

  /// v113: Archives a DM by setting a shared_preferences flag, then
  /// invalidates the dmInboxProvider so the list refreshes.
  Future<void> _archiveDm(String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dm_archived_$otherUserId', true);
    if (mounted) ref.invalidate(dmInboxProvider);
  }

  /// v113: Opens a bottom sheet listing all family members (across all
  /// families) so the user can pick someone to start a new DM with.
  /// Deduplicates by userId and excludes the current user.
  void _showNewDmPicker() {
    final familiesAsync = ref.read(familyListProvider);
    final myUserId = Supabase.instance.client.auth.currentUser?.id;

    familiesAsync.whenData((families) async {
      // We need to load members for each family. Since familyListProvider
      // only returns Family (no members), we'll query the FamilyMember
      // table directly to get all members across all families.
      final client = Supabase.instance.client;
      final familyIds = families.map((f) => f.id).toList();
      if (familyIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Join a family first to start a DM.'),
              backgroundColor: KinrelColors.darkCard,
            ),
          );
        }
        return;
      }

      // Show a loading sheet while we fetch members.
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: KinrelColors.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KinrelRadius.bottomSheet),
          ),
        ),
        builder: (ctx) => FutureBuilder<List<_MemberPick>>(
          future: _loadAllMembers(familyIds, myUserId),
          builder: (ctx, snapshot) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'New Message',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: KinrelColors.orange),
                    )
                  else if (snapshot.data == null || snapshot.data!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No members available to message.',
                        style: TextStyle(color: KinrelColors.textDim),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: snapshot.data!.length,
                        itemBuilder: (ctx, index) {
                          final m = snapshot.data![index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  KinrelColors.orange.withValues(alpha: 0.15),
                              child: Text(
                                m.initials,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.orange,
                                ),
                              ),
                            ),
                            title: Text(
                              m.name,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              context.push('/dm/${m.userId}');
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      );
    });
  }

  /// Loads all members across the given families, deduplicated by userId,
  /// excluding the current user. Queries the FamilyMember + User tables.
  Future<List<_MemberPick>> _loadAllMembers(
    List<String> familyIds,
    String? myUserId,
  ) async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('FamilyMember')
          .select('userId, user:User(name, avatarUrl)')
          .inFilter('familyId', familyIds)
          .timeout(const Duration(seconds: 10));

      final byUserId = <String, _MemberPick>{};
      for (final row in response as List) {
        final userId = row['userId'] as String? ?? '';
        if (userId.isEmpty || userId == myUserId) continue;
        if (byUserId.containsKey(userId)) continue;
        final user = row['user'] as Map<String, dynamic>?;
        final name = (user?['name'] as String?) ?? 'Member';
        final avatarUrl = user?['avatarUrl'] as String?;
        byUserId[userId] = _MemberPick(
          userId: userId,
          name: name,
          avatarUrl: avatarUrl,
        );
      }

      final list = byUserId.values.toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    } catch (_) {
      return [];
    }
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
              'No chats yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a family, or start a DM to begin chatting',
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

/// Simple data holder for the new-DM member picker.
class _MemberPick {
  const _MemberPick({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });
  final String userId;
  final String name;
  final String? avatarUrl;

  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Group Chat Row (with swipe-to-archive)
// ═══════════════════════════════════════════════════════════════════════

/// A single family chat row in the unified inbox, wrapped in a
/// Dismissible for swipe-to-archive.
class _FamilyChatRow extends ConsumerStatefulWidget {
  const _FamilyChatRow({required this.family, required this.onArchived});
  final Family family;
  final VoidCallback onArchived;

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
          .eq('isDeletedForEveryone', false)
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

    return Dismissible(
      key: ValueKey('group_${family.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onArchived(),
      background: Container(
        alignment: Alignment.centerRight,
        color: KinrelColors.orange,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.archive_outlined, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Archive',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: ListTile(
        onTap: () => context.push(
          '/family/${family.id}/chat?name=${Uri.encodeComponent(family.name)}',
        ),
        leading: family.avatarUrl != null && family.avatarUrl!.isNotEmpty
            ? CircleAvatar(
                radius: 26,
                backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: family.avatarUrl!,
                    fit: BoxFit.cover,
                    width: 52,
                    height: 52,
                    placeholder: (_, __) => Center(
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
                    errorWidget: (_, __, ___) => Center(
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
                  ),
                ),
              )
            : CircleAvatar(
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
                  if (hasUnread) DKBadge(count: _unreadCount, color: KinrelColors.orange),
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

  /// Phase 13: build a short preview string for the latest message in
  /// a chat row. Handles photo, voice, family-event, sticker, and text messages.
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
        // Phase 18: Thinking of You messages are familyEvent with
        // messageSubType='thinking_of_you'. Show a heart-themed preview
        // so the inbox row is immediately recognizable.
        if (msg.messageSubType == 'thinking_of_you') {
          final senderFirst = msg.senderName.split(' ').first;
          return 'Thinking of You from $senderFirst';
        }
        return msg.eventTitle ?? 'Family Event';
      case MessageType.sticker:
        // Show the emoji directly — it's instantly recognizable
        return msg.content;
      case MessageType.gameInvite:
        return msg.gameType != null
            ? 'Game invite · ${msg.roomCode ?? ''}'.trim()
            : 'Game invite';
      case MessageType.poll:
        // Phase 22 / Task 5 — poll preview. Show the question (which
        // is mirrored into `content` by the RPC) with a "Poll: " prefix
        // so the row is distinguishable from regular text messages.
        // Include total votes if any to surface engagement at a glance.
        final total = msg.pollTotalVotes;
        final prefix = total > 0 ? 'Poll ($total ${total == 1 ? 'vote' : 'votes'}) · ' : 'Poll · ';
        return prefix + (msg.pollQuestion ?? msg.content);
      case MessageType.text:
      default:
        return msg.content;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DM Chat Row (with swipe-to-archive)
// ═══════════════════════════════════════════════════════════════════════

/// A single DM conversation row, wrapped in a Dismissible for
/// swipe-to-archive.
class _DmChatRow extends StatelessWidget {
  const _DmChatRow({required this.item, required this.onArchived});
  final DmInboxItem item;
  final VoidCallback onArchived;

  @override
  Widget build(BuildContext context) {
    final hasUnread = item.unreadCount > 0;

    return Dismissible(
      key: ValueKey('dm_${item.otherUserId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onArchived(),
      background: Container(
        alignment: Alignment.centerRight,
        color: KinrelColors.orange,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.archive_outlined, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Archive',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: ListTile(
        onTap: () => context.push('/dm/${item.otherUserId}'),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
          backgroundImage: item.otherUserAvatar != null &&
                  item.otherUserAvatar!.isNotEmpty
              ? CachedNetworkImageProvider(item.otherUserAvatar!)
              : null,
          child: item.otherUserAvatar == null || item.otherUserAvatar!.isEmpty
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
            if (hasUnread) DKBadge(count: item.unreadCount, color: KinrelColors.orange),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: 4,
        ),
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
