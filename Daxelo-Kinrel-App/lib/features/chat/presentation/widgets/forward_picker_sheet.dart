// lib/features/chat/presentation/widgets/forward_picker_sheet.dart
//
// DAXELO KINREL — Forward Picker Sheet (Tier 1 chat feature)
//
// A multi-select bottom sheet for forwarding a message to one or more
// targets (family chats + DM recipients). Replaces the previous
// single-target _showForwardFamilyPicker.
//
// Behavior:
//   • Two sections: "Family chats" (with multi-select checkboxes) +
//     "Direct messages" (the user's recent DM contacts as a
//     multi-select list).
//   • Submit button shows the live count of selected targets + is
//     disabled when nothing is selected.
//   • On submit: calls ChatNotifier.forwardMessageToTargets() which
//     calls the fn_forward_message RPC. Shows a snackbar with the
//     result ("Forwarded to 3 chats").
//   • The current chat (if family chat) is excluded from the list —
//     no point forwarding to the same chat.
//
// Reachable from the message long-press menu's "Forward" action.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
// Hide the riverpod `Family` typedef so it doesn't collide with the
// `Family` model class from family_provider.dart (we render Family rows
// in the picker, so we need the model class).
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/family/family_provider.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/direct_message_provider.dart';

class ForwardPickerSheet extends ConsumerStatefulWidget {
  const ForwardPickerSheet({
    super.key,
    required this.messageId,
    this.currentFamilyId, // null when forwarding from a DM
  });

  /// The id of the ChatMessage to forward. (DMs aren't forwardable
  /// yet — this sheet is only reached from the family chat's long-
  /// press menu, so the source is always a ChatMessage.)
  final String messageId;

  /// The family chat the source message is in, if any. Excluded
  /// from the target list (no point forwarding to the same chat).
  /// Null when the sheet is opened from a DM context.
  final String? currentFamilyId;

  /// Opens the sheet as a modal bottom sheet. Returns true if a
  /// forward actually happened, false if the user dismissed.
  static Future<bool> show(
    BuildContext context, {
    required String messageId,
    String? currentFamilyId,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ForwardPickerSheet(
          messageId: messageId,
          currentFamilyId: currentFamilyId,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ForwardPickerSheet> createState() =>
      _ForwardPickerSheetState();
}

class _ForwardPickerSheetState extends ConsumerState<ForwardPickerSheet> {
  final Set<String> _selectedFamilyIds = {};
  final Set<String> _selectedDmUserIds = {};
  bool _isSending = false;

  int get _totalSelected =>
      _selectedFamilyIds.length + _selectedDmUserIds.length;

  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);
    final dmInboxAsync = ref.watch(dmInboxProvider);

    // Compute the height as ~70% of screen, capped at 600.
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.7;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: KinrelColors.textDim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Text(
                    'Forward to…',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _totalSelected > 0
                        ? '$_totalSelected selected'
                        : 'Select targets',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: _totalSelected > 0
                          ? KinrelColors.ember
                          : KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            // Body: families + DMs
            Expanded(
              child: familiesAsync.when(
                data: (families) {
                  final dmItems = dmInboxAsync.valueOrNull ?? [];
                  // Filter out the current family from the list (no
                  // point forwarding to the same chat).
                  final targetFamilies = families
                      .where((f) => f.id != widget.currentFamilyId)
                      .toList();
                  if (targetFamilies.isEmpty && dmItems.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 80),
                    children: [
                      if (targetFamilies.isNotEmpty) ...[
                        _sectionHeader('Family chats'),
                        ...targetFamilies.map((f) => _familyRow(f)),
                      ],
                      if (dmItems.isNotEmpty) ...[
                        _sectionHeader('Direct messages'),
                        ...dmItems
                            .where((d) => !d.isArchived)
                            .map((d) => _dmRow(d)),
                      ],
                    ],
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: KinrelColors.ember),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load chats: $e',
                      style: TextStyle(color: KinrelColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            // Footer: submit button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _totalSelected == 0 || _isSending
                          ? null
                          : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: KinrelColors.ember,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            KinrelColors.ember.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isSending
                            ? 'Forwarding…'
                            : 'Forward to $_totalSelected ${_totalSelected == 1 ? 'chat' : 'chats'}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textDim,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forward_to_inbox_outlined,
                size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(
              'No other chats to forward to',
              style: TextStyle(
                color: KinrelColors.textWhite,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Join or create another family, or start a DM.',
              style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _familyRow(Family f) {
    final isSelected = _selectedFamilyIds.contains(f.id);
    return InkWell(
      onTap: () => _toggleFamily(f.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Checkbox
            _Checkbox(checked: isSelected),
            const SizedBox(width: 10),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: KinrelColors.ember.withValues(alpha: 0.15),
              child: Text(
                (f.name.isNotEmpty ? f.name[0] : '?').toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.ember,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + member count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  Text(
                    '${f.memberCount} ${f.memberCount == 1 ? 'member' : 'members'}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11.5,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dmRow(DmInboxItem d) {
    final isSelected = _selectedDmUserIds.contains(d.otherUserId);
    return InkWell(
      onTap: () => _toggleDm(d.otherUserId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _Checkbox(checked: isSelected),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 20,
              backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
              backgroundImage: d.otherUserAvatar != null &&
                      d.otherUserAvatar!.isNotEmpty
                  ? CachedNetworkImageProvider(d.otherUserAvatar!)
                  : null,
              child: d.otherUserAvatar == null || d.otherUserAvatar!.isEmpty
                  ? Text(
                      (d.otherUserName.isNotEmpty
                              ? d.otherUserName[0]
                              : '?')
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                d.otherUserName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFamily(String id) {
    setState(() {
      if (_selectedFamilyIds.contains(id)) {
        _selectedFamilyIds.remove(id);
      } else {
        _selectedFamilyIds.add(id);
      }
    });
  }

  void _toggleDm(String userId) {
    setState(() {
      if (_selectedDmUserIds.contains(userId)) {
        _selectedDmUserIds.remove(userId);
      } else {
        _selectedDmUserIds.add(userId);
      }
    });
  }

  Future<void> _submit() async {
    if (_totalSelected == 0 || _isSending) return;
    setState(() => _isSending = true);

    // Call fn_forward_message directly via the Supabase client. We
    // intentionally do NOT go through chatProvider(familyId) here
    // because (a) the RPC is SECURITY DEFINER + uses auth.uid(), so
    // it doesn't need a family-scoped ChatNotifier, and (b) when
    // forwarding from a DM context, widget.currentFamilyId is null and
    // passing '' to chatProvider would create a broken ChatNotifier
    // that tries to subscribe to realtime for an empty family ID.
    final client = ref.read(supabaseProvider);
    Map<String, dynamic>? result;
    try {
      result = await client?.rpc(
        'fn_forward_message',
        params: {
          'p_message_id': widget.messageId,
          'p_target_family_ids': _selectedFamilyIds.toList(),
          'p_target_dm_user_ids': _selectedDmUserIds.toList(),
        },
      ).timeout(const Duration(seconds: 12)) as Map<String, dynamic>?;
    } catch (e) {
      result = {'success': false, 'error': e.toString()};
    }

    if (!mounted) return;
    setState(() => _isSending = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not forward — please try again'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(false);
      return;
    }

    final success = result['success'] as bool? ?? false;
    if (!success) {
      final errMsg = result['error']?.toString() ?? 'unknown error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to forward: $errMsg'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(false);
      return;
    }

    final familyCount = (result['familyChatsForwarded'] as num?)?.toInt() ?? 0;
    final dmCount = (result['dmChatsForwarded'] as num?)?.toInt() ?? 0;
    final total = familyCount + dmCount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Forwarded to $total ${total == 1 ? 'chat' : 'chats'}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop(true);
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked
            ? KinrelColors.ember
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked
              ? KinrelColors.ember
              : Colors.white.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }
}
