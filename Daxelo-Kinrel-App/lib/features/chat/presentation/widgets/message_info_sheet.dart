// lib/features/chat/presentation/widgets/message_info_sheet.dart
//
// DAXELO KINREL — Message Info Sheet (Tier 2 chat feature)
//
// A modal bottom sheet showing the delivery + read state of a single
// message, broken down per family member. Reached from the message
// long-press menu's "Info" action.
//
// Two tabs (WhatsApp-style):
//   • "Delivered to" — family members who haven't read the message yet
//     (excluding the sender). For family chat with realtime, every
//     online member receives the message instantly, so "delivered" =
//     "is a family member".
//   • "Read by" — family members who have a ChatReadReceipt row for
//     this message, with their readAt timestamp.
//
// Calls fn_get_message_info(messageId) RPC which returns both lists
// (joined with the User table for names + avatars).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';

class MessageInfoSheet extends ConsumerStatefulWidget {
  const MessageInfoSheet({super.key, required this.messageId});

  final String messageId;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String messageId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KinrelRadius.bottomSheet),
            ),
          ),
          child: MessageInfoSheet(messageId: messageId),
        ),
      ),
    );
  }

  @override
  ConsumerState<MessageInfoSheet> createState() => _MessageInfoSheetState();
}

class _MessageInfoSheetState extends ConsumerState<MessageInfoSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Not signed in';
        });
      }
      return;
    }
    try {
      final response = await client.rpc(
        'fn_get_message_info',
        params: {'p_message_id': widget.messageId},
      ).timeout(const Duration(seconds: 10));
      final result = response as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _data = result;
          _isLoading = false;
          if (result != null && result['success'] != true) {
            _error = result['error']?.toString() ?? 'Failed to load info';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 240,
        child: Center(
          child: CircularProgressIndicator(color: KinrelColors.ember),
        ),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 40, color: KinrelColors.error),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final deliveredTo = (_data?['deliveredTo'] as List?) ?? [];
    final readBy = (_data?['readBy'] as List?) ?? [];

    return Column(
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: KinrelColors.textDim.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 20, color: KinrelColors.ember),
              const SizedBox(width: 10),
              Text(
                'Message info',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ],
          ),
        ),
        // Tab bar
        TabBar(
          controller: _tabController,
          labelColor: KinrelColors.ember,
          unselectedLabelColor: KinrelColors.textDim,
          indicatorColor: KinrelColors.ember,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: 'Delivered to (${deliveredTo.length})'),
            Tab(text: 'Read by (${readBy.length})'),
          ],
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _personList(deliveredTo, 'delivered'),
              _personList(readBy, 'read'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _personList(List<dynamic> people, String kind) {
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                kind == 'delivered'
                    ? Icons.send_outlined
                    : Icons.done_all_rounded,
                size: 40,
                color: KinrelColors.textDim.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              Text(
                kind == 'delivered'
                    ? 'No one to deliver to yet'
                    : 'Not read by anyone yet',
                style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: people.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.04),
        indent: 64,
      ),
      itemBuilder: (context, index) => _personRow(people[index] as Map<String, dynamic>),
    );
  }

  Widget _personRow(Map<String, dynamic> person) {
    final name = person['name'] as String? ?? 'Member';
    final avatarUrl = person['avatarUrl'] as String?;
    final readAt = person['readAt'] as String?;
    DateTime? readAtDt;
    if (readAt != null) readAtDt = DateTime.tryParse(readAt)?.toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: KinrelColors.ember.withValues(alpha: 0.15),
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Text(
                    _initials(name),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.ember,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          // Name + read time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                if (readAtDt != null)
                  Text(
                    _formatReadAt(readAtDt),
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
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

  String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _formatReadAt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return 'Read at $displayHour:$minute $period';
    }
    if (diff.inDays == 1) return 'Read yesterday';
    if (diff.inDays < 7) return 'Read ${diff.inDays}d ago';
    return 'Read ${dt.day}/${dt.month}/${dt.year}';
  }
}
