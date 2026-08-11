// lib/features/chat/presentation/archived_chats_screen.dart
//
// DAXELO KINREL — Archived Chats Screen
//
// Shows all archived conversations (both group chats and DMs) with
// swipe-to-unarchive support. Reached via /chats/archived from the
// "Archived" row at the bottom of the chat inbox.
//
// v113 — initial implementation.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/direct_message_provider.dart';

class ArchivedChatsScreen extends ConsumerStatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  ConsumerState<ArchivedChatsScreen> createState() =>
      _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends ConsumerState<ArchivedChatsScreen> {
  Set<String> _archivedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _loadArchivedGroups();
  }

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
      appBar: AppBar(
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chat');
            }
          },
        ),
        title: Text(
          'Archived',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: familiesAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: KinrelColors.orange),
          ),
          error: (_, __) => Center(
            child: Text(
              'Could not load archived chats',
              style: TextStyle(color: KinrelColors.textDim),
            ),
          ),
          data: (families) {
            // Archived groups.
            final archivedGroups = families
                .where((f) => _archivedGroupIds.contains(f.id))
                .toList();

            // Archived DMs.
            final dmItems = dmInboxAsync.valueOrNull ?? [];
            final archivedDms =
                dmItems.where((d) => d.isArchived).toList();

            if (archivedGroups.isEmpty && archivedDms.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 56,
                      color: KinrelColors.textDim,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No archived chats',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Swipe left on a chat to archive it',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              children: [
                if (archivedGroups.isNotEmpty) ...[
                  _buildSectionHeader('Groups'),
                  ...archivedGroups.map((family) => _ArchivedGroupRow(
                        family: family,
                        onUnarchived: () => _unarchiveGroup(family.id),
                      )),
                ],
                if (archivedDms.isNotEmpty) ...[
                  _buildSectionHeader('Direct Messages'),
                  ...archivedDms.map((dm) => _ArchivedDmRow(
                        item: dm,
                        onUnarchived: () => _unarchiveDm(dm.otherUserId),
                      )),
                ],
                const SizedBox(height: 80),
              ],
            );
          },
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

  Future<void> _unarchiveGroup(String familyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('group_archived_$familyId', false);
    if (mounted) {
      setState(() => _archivedGroupIds.remove(familyId));
    }
  }

  Future<void> _unarchiveDm(String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dm_archived_$otherUserId', false);
    if (mounted) ref.invalidate(dmInboxProvider);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Archived Group Row (swipe-to-unarchive)
// ═══════════════════════════════════════════════════════════════════════

class _ArchivedGroupRow extends ConsumerStatefulWidget {
  const _ArchivedGroupRow({required this.family, required this.onUnarchived});
  final Family family;
  final VoidCallback onUnarchived;

  @override
  ConsumerState<_ArchivedGroupRow> createState() => _ArchivedGroupRowState();
}

class _ArchivedGroupRowState extends ConsumerState<_ArchivedGroupRow> {
  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('archived_group_${widget.family.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onUnarchived(),
      background: Container(
        alignment: Alignment.centerRight,
        color: KinrelColors.darkElevated,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.unarchive_outlined, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Unarchive',
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
          '/family/${widget.family.id}/chat?name=${Uri.encodeComponent(widget.family.name)}',
        ),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
          child: Text(
            widget.family.name.isNotEmpty
                ? widget.family.name[0].toUpperCase()
                : 'F',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ),
        title: Text(
          widget.family.name,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Group chat',
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
}

// ═══════════════════════════════════════════════════════════════════════
// Archived DM Row (swipe-to-unarchive)
// ═══════════════════════════════════════════════════════════════════════

class _ArchivedDmRow extends StatelessWidget {
  const _ArchivedDmRow({required this.item, required this.onUnarchived});
  final DmInboxItem item;
  final VoidCallback onUnarchived;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('archived_dm_${item.otherUserId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onUnarchived(),
      background: Container(
        alignment: Alignment.centerRight,
        color: KinrelColors.darkElevated,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.unarchive_outlined, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Unarchive',
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
        title: Text(
          item.otherUserName,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.lastMessage,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
}
