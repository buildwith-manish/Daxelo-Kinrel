// lib/features/chat/presentation/widgets/blocked_message_placeholder.dart
//
// Renders in place of a MessageBubble when the message's senderId is in
// the current viewer's BlockedUser list AND the chat is a family/group
// chat (NOT a direct chat — in direct chats the block is enforced
// server-side via RLS, so the message never reaches the viewer in the
// first place).
//
// Behavior:
//   • Collapsed by default: a single-line "Message from a blocked user"
//     row with a "Show" button (tappable).
//   • Expanded (after Show tap): renders the underlying MessageBubble
//     as normal — the user explicitly opted in to see the message.
//   • The expansion is per-message-id, in-memory only (resets on chat
//     re-open). This matches WhatsApp's behavior.
//   • Uses KinrelColors / KinrelTypography / KinrelSpacing — no hardcoded
//     colors or text styles. Haptics: light tap on "Show" expand.
//
// The widget does NOT itself fetch the blocked-user list. The parent
// (chat_screen / chat_message_list) passes `isBlocked` so this widget
// can render without an extra provider read per bubble.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../l10n/app_localizations.dart';

/// A collapsed-by-default placeholder shown in place of a blocked
/// sender's message in family/group chats. Tapping "Show" expands the
/// underlying bubble.
///
/// The "Show" expansion state is per-message-id, kept in this widget's
/// own [StatefulWidget] state (not in a provider) — it's a transient
/// UI affordance, not a persistent preference.
class BlockedMessagePlaceholder extends ConsumerStatefulWidget {
  const BlockedMessagePlaceholder({
    super.key,
    required this.messageId,
    required this.expandedBubble,
  });

  /// The id of the blocked message. Used only as the key for the
  /// internal expand-state map (no state is shared between instances
  /// of this widget — each instance owns its own expand toggle).
  final String messageId;

  /// The real MessageBubble to render when expanded. Built by the
  /// parent (chat_message_list) so this widget doesn't need to know
  /// about MessageBubble's many constructor params.
  final Widget expandedBubble;

  @override
  ConsumerState<BlockedMessagePlaceholder> createState() =>
      _BlockedMessagePlaceholderState();
}

class _BlockedMessagePlaceholderState
    extends ConsumerState<BlockedMessagePlaceholder> {
  bool _expanded = false;

  Future<void> _toggleExpanded() async {
    // Fire-and-forget the haptic — `setState` runs synchronously so the
    // UI updates immediately even in a test environment where the
    // platform-channel haptic is a no-op (and the async gap can race
    // with the test's pump).
    unawaited(HapticService.selection());
    if (!mounted) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    if (_expanded) {
      // Showing the real bubble. Also render a small "Hide" affordance
      // above so the user can collapse it again.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: KinrelSpacing.xs,
                horizontal: KinrelSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 14,
                    color: KinrelColors.textSilver.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: KinrelSpacing.xs),
                  Flexible(
                    child: Text(
                      S.of(context)!.chatBlockedMessageHide,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver.withValues(alpha: 0.7),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          widget.expandedBubble,
        ],
      );
    }

    // Collapsed — render the placeholder row.
    return InkWell(
      onTap: _toggleExpanded,
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: KinrelSpacing.xs,
          horizontal: KinrelSpacing.md,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: KinrelSpacing.sm,
          horizontal: KinrelSpacing.md,
        ),
        decoration: BoxDecoration(
          color: KinrelColors.darkBackground,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: KinrelColors.textSilver.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.block_rounded,
              size: 16,
              color: KinrelColors.textSilver.withValues(alpha: 0.7),
            ),
            const SizedBox(width: KinrelSpacing.sm),
            Expanded(
              child: Text(
                S.of(context)!.chatBlockedMessagePlaceholder,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Text(
              S.of(context)!.chatBlockedMessageShow,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KinrelColors.ember,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
