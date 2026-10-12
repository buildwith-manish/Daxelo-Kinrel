// lib/features/chat/presentation/direct_chat_entry_screen.dart
//
// DAXELO KINREL — Direct Chat Entry Screen (Kin Thread / Part C2)
//
// A thin resolver: finds/creates the PRIVATE 2-person direct group via
// the fn_get_or_create_direct_group RPC (Part C1 migration), then
// renders the SAME group ChatScreen with the direct capabilities
// applied. While resolving it shows a spinner; if the RPC is missing
// (C1 not applied yet) or the pair shares no family, it shows a clear
// error instead of a broken screen.
//
// Routes:
//   • /family/:id/direct/:otherUserId — the new canonical entry point
//     (family context known).
//   • /dm/:otherUserId — the LEGACY route, kept as a redirect so old
//     deep links, notifications, and the graph "Message" action keep
//     working (the RPC resolves the family when it is null).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../data/direct_group_service.dart';
import 'chat_screen.dart';

class DirectChatEntryScreen extends ConsumerStatefulWidget {
  const DirectChatEntryScreen({
    super.key,
    required this.otherUserId,
    this.familyId,
  });

  /// The other person's user id.
  final String otherUserId;

  /// The family the chat was started from. Null = resolve the oldest
  /// shared family via the RPC (the legacy /dm route does this).
  final String? familyId;

  @override
  ConsumerState<DirectChatEntryScreen> createState() =>
      _DirectChatEntryScreenState();
}

class _DirectChatEntryScreenState extends ConsumerState<DirectChatEntryScreen> {
  DirectGroupInfo? _group;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final group = await getOrCreateDirectGroup(
      otherUserId: widget.otherUserId,
      familyId: widget.familyId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _group = group;
      _error = group == null
          ? 'Direct chat is unavailable right now.\n'
              'This needs the pending database update (or you share no '
              'family with this person).'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: KinrelColors.darkBackground,
        body: Center(
          child: CircularProgressIndicator(color: KinrelColors.ember),
        ),
      );
    }

    final group = _group;
    if (group == null) {
      return Scaffold(
        backgroundColor: KinrelColors.darkBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: KinrelColors.textSilver),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 40,
                  color: KinrelColors.textDim,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Direct chat is unavailable right now.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textSilver,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // The SAME group chat screen — direct capabilities applied.
    return ChatScreen(
      key: ValueKey('direct_chat_${group.groupId}'),
      familyId: group.familyId,
      familyName: group.otherUserName,
      groupId: group.groupId,
      groupName: group.otherUserName,
      showFamilyNav: false,
      isDirectChat: true,
      directOtherUserId: widget.otherUserId,
    );
  }
}
