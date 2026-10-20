// lib/features/chat/presentation/chat_inbox_screen.dart
//
// DAXELO KINREL — Unified Chat Inbox (top-level tab)
//
// feat(unified-inbox): ONE list sorted by last activity, with a filter
// chip bar at the top (All / Unread / Groups / Direct). No section
// headers. Reuses the existing row visuals via UnifiedChatRow. Moves
// the group last-message + unread logic OUT of the row widget into
// the unifiedInboxProvider (batched — no N+1 loading).
//
// Realtime: subscribes to a Supabase realtime channel for ChatMessage
// INSERT events. When a new message arrives (in any chat), the inbox
// provider is invalidated so the list re-sorts and the chat with the
// new message moves to the top LIVE — no pull-to-refresh needed.
//
// Archived entries are filtered out and shown via an Archived row at
// the bottom (same UX as before). Swipe-to-archive is preserved for
// both kinds (group + direct) via the UnifiedChatRow's Dismissible.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/direct_group_service.dart';
import '../providers/unified_inbox_provider.dart';
import '../presentation/widgets/chat_inbox_filter_bar.dart';
import '../presentation/widgets/unified_chat_row.dart';
import '../../../l10n/app_localizations.dart';
// Phase 2 — Circles: the create-circle bottom sheet + the circle
// inbox provider key (for invalidation after circle creation).
import '../../circle/presentation/create_circle_sheet.dart'
    show showCreateCircleSheet;

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  Set<String> _archivedGroupIds = {};
  RealtimeChannel? _inboxRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadArchivedGroups();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _inboxRealtimeChannel?.unsubscribe();
    _inboxRealtimeChannel = null;
    super.dispose();
  }

  /// feat(unified-inbox): subscribes to a Supabase realtime channel that
  /// listens for ChatMessage INSERT events across ALL the user's
  /// families. When a new message arrives (in any chat — group or DM),
  /// the inbox provider is invalidated so the list re-sorts and the
  /// chat with the new message moves to the top LIVE.
  void _subscribeToRealtime() {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) return;

      _inboxRealtimeChannel = client.channel('inbox-realtime');
      _inboxRealtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'ChatMessage',
        callback: (payload) {
          if (mounted) ref.invalidate(unifiedInboxProvider);
        },
      );
      // Phase 2 — also listen for CircleMessage INSERTs so the
      // inbox re-sorts when a new circle message arrives.
      _inboxRealtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'CircleMessage',
        callback: (payload) {
          if (mounted) ref.invalidate(unifiedInboxProvider);
        },
      );
      _inboxRealtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('⚠️ inbox realtime subscribe failed: $e');
    }
  }

  Future<void> _loadArchivedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final archived = <String>{};
      for (final k in keys.where((k) => k.startsWith('group_archived_'))) {
        if (prefs.getBool(k) == true) {
          archived.add(k.substring('group_archived_'.length));
        }
      }
      if (mounted) setState(() => _archivedGroupIds = archived);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context)!;
    final inboxAsync = ref.watch(unifiedInboxProvider);
    final currentFilter = ref.watch(unifiedInboxFilterProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KinrelSpacing.base, 16, KinrelSpacing.base, 4,
              ),
              child: Row(
                children: [
                  const Text(
                    'Chats',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.search_rounded,
                        color: KinrelColors.textSilver, size: 24),
                    onPressed: () => context.push('/search'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: KinrelColors.textSilver, size: 24),
                    onPressed: _showCreateMenu,
                  ),
                ],
              ),
            ),
            // ── Filter chip bar ──────────────────────────────────────
            ChatInboxFilterBar(
              unreadCount: _computeUnreadTotal(inboxAsync),
            ),
            // ── Unified list ─────────────────────────────────────────
            Expanded(
              child: inboxAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange),
                ),
                error: (e, _) => DKErrorState(
                  message: 'Could not load chats: $e',
                  onRetry: () => ref.invalidate(unifiedInboxProvider),
                ),
                data: (entries) {
                  final archivedCount = _computeArchivedCount();
                  if (entries.isEmpty && archivedCount == 0) {
                    return _buildEmptyState();
                  }
                  final filtered = _applyFilter(entries, currentFilter);
                  if (filtered.isEmpty) {
                    return _buildFilterEmptyState(currentFilter, l10n);
                  }
                  final rows = <Widget>[];
                  for (final entry in filtered) {
                    rows.add(UnifiedChatRow(
                      entry: entry,
                      onArchived: () => _archiveEntry(entry),
                    ));
                  }
                  if (archivedCount > 0) {
                    rows.add(const SizedBox(height: 8));
                    rows.add(ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: KinrelColors.darkElevated,
                        child: Icon(Icons.archive_outlined,
                            color: KinrelColors.textSilver, size: 22),
                      ),
                      title: Text(l10n.chatInboxArchived,
                          style: const TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite)),
                      subtitle: Text(l10n.chatInboxArchivedCount(archivedCount),
                          style: const TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              color: KinrelColors.textDim)),
                      onTap: () => context.push('/chats/archived'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: KinrelSpacing.base, vertical: 4),
                    ));
                  }
                  rows.add(const SizedBox(height: 80));
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => rows[index],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _computeUnreadTotal(AsyncValue<List<UnifiedChatEntry>> inboxAsync) {
    return inboxAsync.maybeWhen(
      data: (entries) =>
          entries.fold(0, (sum, e) => sum + e.unreadCount),
      orElse: () => 0,
    );
  }

  int _computeArchivedCount() {
    final groupArchived = _archivedGroupIds.length;
    final dmItems = ref.read(directGroupInboxProvider).maybeWhen(
      data: (items) => items,
      orElse: () => <DirectGroupInboxItem>[],
    );
    final dmArchived = dmItems.where((d) => d.isArchived).length;
    return groupArchived + dmArchived;
  }

  List<UnifiedChatEntry> _applyFilter(
    List<UnifiedChatEntry> entries,
    UnifiedInboxFilter filter,
  ) {
    switch (filter) {
      case UnifiedInboxFilter.all:
        return entries;
      case UnifiedInboxFilter.unread:
        return entries.where((e) => e.unreadCount > 0).toList();
      case UnifiedInboxFilter.groups:
        return entries.where((e) => e.kind == UnifiedChatKind.group).toList();
      case UnifiedInboxFilter.direct:
        return entries.where((e) => e.kind == UnifiedChatKind.direct).toList();
      case UnifiedInboxFilter.circles:
        return entries.where((e) => e.kind == UnifiedChatKind.circle).toList();
    }
  }

  Widget _buildFilterEmptyState(UnifiedInboxFilter filter, S l10n) {
    final message = switch (filter) {
      UnifiedInboxFilter.unread => l10n.chatInboxEmptyUnread,
      UnifiedInboxFilter.groups => l10n.chatInboxEmptyGroups,
      UnifiedInboxFilter.direct => l10n.chatInboxEmptyDirect,
      UnifiedInboxFilter.circles => 'No circles yet. Tap + to create one.',
      UnifiedInboxFilter.all => l10n.chatInboxEmptyUnread,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveEntry(UnifiedChatEntry entry) async {
    switch (entry.kind) {
      case UnifiedChatKind.group:
        await _archiveGroup(entry.id);
      case UnifiedChatKind.direct:
        await _archiveDm(entry.otherUserId ?? entry.id);
      case UnifiedChatKind.circle:
        await _archiveCircle(entry.circleId ?? entry.id);
    }
  }

  Future<void> _archiveGroup(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('group_archived_$familyId', true);
    if (mounted) {
      setState(() => _archivedGroupIds.add(familyId));
      ref.invalidate(unifiedInboxProvider);
    }
  }

  Future<void> _archiveDm(String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dm_archived_$otherUserId', true);
    if (mounted) {
      ref.invalidate(directGroupInboxProvider);
      ref.invalidate(unifiedInboxProvider);
    }
  }

  // ── Phase 2 — Circle archive (per-member, database-backed) ────
  // Circles use the CircleMember.isArchived column (unlike groups
  // which use SharedPreferences as a workaround). The database
  // UPDATE ensures the archive state persists across devices.
  Future<void> _archiveCircle(String circleId) async {
    try {
      final client = Supabase.instance.client;
      final myUserId = client.auth.currentUser?.id;
      if (myUserId != null) {
        await client
            .from('CircleMember')
            .update({'isArchived': true})
            .eq('circleId', circleId)
            .eq('userId', myUserId);
      }
    } catch (e) {
      debugPrint('⚠️ archiveCircle failed: $e');
    }
    if (mounted) {
      ref.invalidate(unifiedInboxProvider);
    }
  }

  // ── New message / New circle popup menu (Phase 2) ───────────

  void _showCreateMenu() {
    HapticService.tap();
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'New',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    KinrelColors.orange.withValues(alpha: 0.15),
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    color: KinrelColors.orange, size: 22),
              ),
              title: const Text('New message',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite)),
              subtitle: const Text('Start a direct message',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
              onTap: () {
                Navigator.pop(ctx);
                _showNewDmPicker();
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    KinrelColors.orange.withValues(alpha: 0.15),
                child: const Icon(Icons.group_rounded,
                    color: KinrelColors.orange, size: 22),
              ),
              title: const Text('New circle',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite)),
              subtitle: const Text(
                  'Create a cross-family group chat',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
              onTap: () {
                Navigator.pop(ctx);
                showCreateCircleSheet(context, ref: ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── New DM picker (kept from the old screen) ─────────────────────

  void _showNewDmPicker() {
    final familiesAsync = ref.read(familyListProvider);
    final myUserId = Supabase.instance.client.auth.currentUser?.id;

    familiesAsync.whenData((families) async {
      final familyIds = families.map((f) => f.id).toList();
      if (familyIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Join a family first to start a DM.'),
              backgroundColor: KinrelColors.darkCard,
            ),
          );
        }
        return;
      }
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
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('New Message',
                          style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite)),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: KinrelColors.orange),
                    )
                  else if (snapshot.data == null ||
                      snapshot.data!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No members available to message.',
                          style: TextStyle(color: KinrelColors.textDim)),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(context).size.height * 0.5,
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
                              child: Text(m.initials,
                                  style: const TextStyle(
                                      fontFamily:
                                          KinrelTypography.displayFont,
                                      fontWeight: FontWeight.w700,
                                      color: KinrelColors.orange)),
                            ),
                            title: Text(m.name,
                                style: const TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    color: KinrelColors.textWhite)),
                            onTap: () {
                              Navigator.pop(ctx);
                              openDirectChat(context, otherUserId: m.userId);
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
            userId: userId, name: name, avatarUrl: avatarUrl);
      }
      final list = byUserId.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
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
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 56, color: KinrelColors.textDim),
            const SizedBox(height: 16),
            const Text('No chats yet',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite)),
            const SizedBox(height: 8),
            const Text(
                'Create or join a family, or start a DM to begin chatting',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/families/create'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Family'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberPick {
  final String userId;
  final String name;
  final String? avatarUrl;
  String get initials => name.isNotEmpty
      ? name.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
      : '?';

  _MemberPick({required this.userId, required this.name, this.avatarUrl});
}
