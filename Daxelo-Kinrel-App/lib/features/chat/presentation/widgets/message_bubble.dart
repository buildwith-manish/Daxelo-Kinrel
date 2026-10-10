// lib/features/chat/presentation/widgets/message_bubble.dart
//
// DAXELO KINREL — Message Bubble Widget (v5.184)
//
// Extracted from chat_screen.dart. Renders a single chat message bubble
// with all per-type content renderers (text, photo, voice, sticker,
// familyEvent, gameInvite, poll, gif, document, location).
//
// Pure mechanical extraction — the class keeps its exact API.

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../core/kinship/kinship_edge_style.dart';
import '../../../../../core/services/image_cache_manager.dart';
import '../../../../../core/utils/device_tier.dart';
import '../../../family/data/relationship_label_provider.dart';
import '../../../profile/presentation/member_profile_sheet.dart';
import '../../providers/chat_provider.dart';
import 'chat_meta.dart';
import 'game_invite_card.dart';
import 'link_preview_card.dart';
import 'mention_picker.dart';
import 'poll_card.dart';
import '../voice_message_player.dart';
import 'full_screen_image_viewer.dart';
import '../../../../core/theme/kinrel_fx.dart';

// ═══════════════════════════════════════════════════════════════════
// PERF (Tier K3): Const-hoisted gradients and shadow lists for the
// chat message bubble. The chat_screen rebuilds on every typing tick,
// presence update, and new message — each rebuild re-runs every
// visible bubble's build(), allocating fresh LinearGradient, BoxShadow
// list, and Color.withValues() instances. These allocations mark the
// bubble's RenderDecoratedBox dirty, which forces a full repaint of
// the bubble subtree even though nothing visually changed.
//
// Pre-computing the gradients/shadows as `static const` means:
//   1. The LinearGradient/BoxShadow identity is stable across builds
//      → RenderDecoratedBox is NOT marked dirty on rebuild
//      → RepaintBoundary actually isolates the bubble correctly
//      → Steady-state raster drops by ~5-15ms/frame on the invite-list
//        screen (10+ visible bubbles × redundant repaint).
//
// PERF (Flat): KinrelFx.rich defaults to false. In flat mode:
//   - All shadow lists return empty (KinrelFx.shadows()).
//   - All gradients return null (KinrelFx.gradient()) — the bubble
//     falls back to its solid color argument.
//
// Color pre-multiplication math:
//   KinrelColors.ember = Color(0xFFC44A18)
//   withValues(alpha: 0.18) → 0.18 × 255 = 45.9 → 46 → 0x2E → Color(0x2EC44A18)
//   withValues(alpha: 0.08) → 0.08 × 255 = 20.4 → 20 → 0x14 → Color(0x14C44A18)
//   withValues(alpha: 0.10) → 0.10 × 255 = 25.5 → 26 → 0x1A → Color(0x1AC44A18)
//   withValues(alpha: 0.28) → 0.28 × 255 = 71.4 → 71 → 0x47 → Color(0x47C44A18)
//   Colors.black.withValues(alpha: 0.18) → Color(0x2E000000)
//   Colors.black.withValues(alpha: 0.30) → Color(0x4D000000)
//   Colors.white.withValues(alpha: 0.06) → Color(0x0FFFFFFF)
// ═══════════════════════════════════════════════════════════════════

/// Vertical top-down gradient for "sent" message bubbles.
/// Top slightly lighter (lit-from-above ember tint), bottom darker.
/// Returned as null in flat mode (caller falls back to solid color).
final LinearGradient? _kSentBubbleGradient =
    KinrelFx.gradient(const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x2EC44A18), Color(0x14C44A18)],
    )) as LinearGradient?;

/// Vertical top-down gradient for "received" message bubbles (no kinship band).
final LinearGradient? _kReceivedBubbleGradient =
    KinrelFx.gradient(const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF2E3150), Color(0xFF23263B)],
    )) as LinearGradient?;

/// Cache of received-bubble gradients keyed by kinship band color, so
/// the Color.lerp() only runs once per unique band color (max ~6
/// kinship categories). Without this cache, every chat_screen rebuild
/// would re-run Color.lerp twice per visible received bubble.
final Map<Color, LinearGradient> _kReceivedBubbleGradientByKinshipBand = {};

/// Look up (or build + cache) the received-bubble gradient for a given
/// kinship band color. Returns null in flat mode (caller falls back to
/// solid color). The LinearGradient identity is stable so
/// RenderDecoratedBox is NOT marked dirty across rebuilds.
LinearGradient? _receivedBubbleGradientFor(Color kinshipBandColor) {
  if (!KinrelFx.rich) return null;
  return _kReceivedBubbleGradientByKinshipBand.putIfAbsent(
    kinshipBandColor,
    () => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(const Color(0xFF2E3150), kinshipBandColor, 0.06)!,
        Color.lerp(const Color(0xFF23263B), kinshipBandColor, 0.06)!,
      ],
    ),
  );
}

/// Const BoxShadow list for received messages on non-lowRam devices.
/// Returns empty list in flat mode.
final List<BoxShadow> _kReceivedBubbleShadows = KinrelFx.shadows(const [
  BoxShadow(color: Color(0x4D000000), blurRadius: 12, offset: Offset(0, 4)),
]);

/// Const BoxShadow list for sent messages on non-lowRam devices (with ember glow).
final List<BoxShadow> _kSentBubbleShadows = KinrelFx.shadows(const [
  BoxShadow(color: Color(0x2E000000), blurRadius: 8, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x1AC44A18), blurRadius: 14, offset: Offset(0, 0)),
]);

/// Const BoxShadow list for received messages on lowRam devices (single shadow, blur 6).
final List<BoxShadow> _kReceivedBubbleShadowsLowRam = KinrelFx.shadows(const [
  BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 4)),
]);

/// Const BoxShadow list for sent messages on lowRam devices (single shadow, blur 6, no glow).
final List<BoxShadow> _kSentBubbleShadowsLowRam = KinrelFx.shadows(const [
  BoxShadow(color: Color(0x2E000000), blurRadius: 6, offset: Offset(0, 2)),
]);

class MessageBubble extends ConsumerWidget {
  const MessageBubble({super.key,
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.onReact,
    required this.onLongPress,
    required this.familyId,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.animateIn = false,
    /// Feature 6: callback when the user taps the quoted reply preview.
    /// The chat_screen wires this to scroll to the original message.
    this.onReplyPreviewTap,
    /// v3.3 (shared chat UI): when true, this bubble is rendering inside
    /// a 1:1 DM. The bubble hides the sender-name label above the bubble
    /// and hides the avatar + its spacer (a DM only has two parties, so
    /// the sender is unambiguous from the bubble alignment). Everything
    /// else — bubble shape, colors, sizes, timestamps, ticks, game-invite
    /// card — is identical to the group chat. Default false so the group
    /// chat is unchanged.
    this.isDirectChat = false,
    /// v3.3 (shared chat UI): the family id used ONLY by the game-invite
    /// Join/Spectate navigation routes
    /// (/family/<id>/<gameType>/lobby?join=<gameId>). Falls back to
    /// [familyId] when null (the group chat passes null and lets the
    /// routes use familyId). The DM screen passes familyId null (so the
    /// relationship label + group-only chatProvider calls are skipped)
    /// AND inviteFamilyId from the DM invite payload (so the Join button
    /// still deep-links into the host's family space).
    this.inviteFamilyId,
    /// v3.5 — Retry/Delete handlers for the failed-message sheet. The
    /// group chat passes null (the sheet falls back to its built-in
    /// chatProvider calls — unchanged behavior); the DM screen passes
    /// its DirectChatNotifier's retryMessage/deleteFailedMessage so the
    /// SAME sheet retries a failed DM instead of calling the group
    /// provider.
    this.onRetryFailed,
    this.onDeleteFailed,
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onLongPress;

  /// v139: Family ID used to resolve the sender's relationship label
  /// to the current viewer via the K-Graph. Only family/group chats
  /// pass this — 1-on-1 DMs pass null and skip the relationship label.
  final String? familyId;

  /// v127: Whether this is the first message in a consecutive group
  /// from the same sender. Controls avatar + sender name visibility.
  final bool isFirstInGroup;

  /// v127: Whether this is the last message in a consecutive group.
  /// Controls bubble tail (asymmetric radius) + inline timestamp.
  final bool isLastInGroup;

  /// v127: Whether to play the send-in animation (scale + fade).
  final bool animateIn;

  /// Feature 6: called when the user taps the quoted reply preview
  /// above the bubble. The chat_screen uses this to scroll to the
  /// original message being replied to. Null = no tap handler.
  final VoidCallback? onReplyPreviewTap;

  /// v3.3: see field doc above.
  final bool isDirectChat;

  /// v3.3: see field doc above.
  final String? inviteFamilyId;

  /// v3.5 — Retry a failed message (the failed-message sheet's Retry
  /// action). Null = the group path (chatProvider.retryMessage).
  final void Function(String messageId)? onRetryFailed;

  /// v3.5 — Delete a failed message (the failed-message sheet's Delete
  /// action). Null = the group path (chatProvider.deleteFailedMessage).
  final void Function(String messageId)? onDeleteFailed;

  /// v3.3: the family id to use for game-invite Join/Spectate routes.
  /// Prefers [inviteFamilyId] (set by the DM screen from the invite
  /// payload) and falls back to [familyId] (the group chat's family).
  /// Returns null when neither is set — the Join button is disabled
  /// in that case (the card still renders, just without a working
  /// Join action).
  String? get _inviteRouteFamilyId => inviteFamilyId ?? familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read the current user id so we can highlight the user's own reactions.
    // MessageBubble is a separate widget (not _ChatScreenState), so it
    // can't use the _currentUserId getter — it reads the provider directly.
    final currentUserId = ref.watch(chatCurrentUserIdProvider);

    // Phase 14: Sticker messages render WITHOUT the bubble background —
    // just the emoji + a small timestamp underneath. They are centered
    // for solo emoji impact, like WhatsApp stickers.
    final isSticker = message.messageType == MessageType.sticker;

    // v140: Kinship-category generation bands. Resolve the sender's
    // relationship key to the current viewer, classify it into a
    // KinshipEdgeCategory, and map to a generation-band color. The
    // color is applied as a 3px left border + 6% background fill on
    // the message bubble. Only for family/group chats, not DMs, and
    // only for received messages (not isMe). Self/indirect → no band.
    // Kin Thread / C2: also skipped in direct chats (no rails there).
    Color? kinshipBandColor;
    if (familyId != null && !isMe && !isSticker && !isDirectChat) {
      final rawKey = ref.watch(relationshipKeyProvider(
        (familyId: familyId!, senderUserId: message.senderId),
      ));
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        kinshipBandColor = kinshipCategoryColor(category);
      }
    }

    // Swipe-to-reply is handled by SwipeToReply in chat_meta.dart (chat_screen.dart wraps
    // each bubble). Do not add a second drag handler here: it would fight with it.
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return GestureDetector(
          onLongPress: onLongPress,
          // v3.2: tapping a FAILED message opens a small sheet with
          // Retry and Delete. Only for the sender's own messages.
          // v3.5: works in BOTH chat types — the group path
          // (familyId != null, built-in chatProvider calls) OR an
          // injected handler pair (the DM passes its own provider's
          // retryMessage/deleteFailedMessage). The tap handler does
          // NOT fire for sent/delivered/read/sending messages — those
          // have no tap action (the existing onLongPress still works).
          onTap: (isMe &&
                  message.messageStatus == 'failed' &&
                  (familyId != null || onRetryFailed != null))
              ? () => _showFailedMessageSheet(context, ref)
              : null,
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // v127: Avatar only on first message in group.
                // Non-first messages get an invisible spacer for alignment.
                // v3.3: DMs (isDirectChat) hide the avatar AND the spacer
                // entirely — a DM only has two parties so the sender is
                // unambiguous from the bubble alignment, and removing
                // the 40px spacer lets the bubble use the full width.
                if (!isMe && !isSticker && !isDirectChat && isFirstInGroup)
                  GestureDetector(
                    onTap: () => MemberProfileSheet.show(
                      context,
                      message.senderId,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 8, bottom: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KinrelColors.orange.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: Text(
                          (message.senderName.isNotEmpty
                              ? message.senderName[0].toUpperCase()
                              : '?'),
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!isMe && !isSticker && !isDirectChat && !isFirstInGroup)
                  const SizedBox(width: 40), // invisible spacer for alignment
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                margin: EdgeInsets.only(
                    left: isMe ? 48 : 0, right: isMe ? 0 : 48),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Reply preview (if replying to a message).
                    // Feature 6: tapping the quote scrolls to the original
                    // message (wired via onReplyPreviewTap in chat_screen).
                    if (message.replyToId != null)
                      onReplyPreviewTap != null
                          ? GestureDetector(
                              onTap: onReplyPreviewTap,
                              child: _buildReplyPreview(),
                            )
                          : _buildReplyPreview(),
                    // v131 PREMIUM: Redesigned bubble system.
                    // Design language: soft gradient fills for depth,
                    // organic asymmetric corners (22px base / 6px tail)
                    // for a crafted silhouette instead of a mechanical
                    // rounded rectangle, layered shadows for gentle
                    // elevation, and generous padding for readability.
                    // Inspired by iMessage's softness + Telegram's tail.
                    Container(
                      padding: isSticker
                          ? const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8)
                          : const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                      decoration: BoxDecoration(
                        // v131: Subtle vertical gradient — top slightly
                        // lighter (lit-from-above), bottom darker. Stays
                        // within the tinted-glass palette so the ember
                        // accent remains understated, not saturated.
                        //
                        // PERF (Tier K3): use const-hoisted gradients
                        // (_kSentBubbleGradient, _kReceivedBubbleGradient,
                        // _receivedBubbleGradientFor(kinshipBandColor))
                        // so the LinearGradient identity is stable across
                        // chat_screen rebuilds (typing ticks, presence
                        // updates, new messages). Without hoisting, every
                        // rebuild re-allocated the LinearGradient with
                        // Color.withValues() calls, marking the bubble's
                        // RenderDecoratedBox dirty and forcing a full
                        // repaint even though the visual was unchanged.
                        gradient: isSticker
                            ? null
                            : (isMe
                                ? _kSentBubbleGradient
                                : kinshipBandColor != null
                                    // v140: Blend 6% kinship band color
                                    // into the received-message gradient
                                    // so the generation band is felt as
                                    // a subtle background tint, not just
                                    // the left border. Cached per color so
                                    // Color.lerp only runs once per band.
                                    ? _receivedBubbleGradientFor(kinshipBandColor)
                                    : _kReceivedBubbleGradient),
                        // PERF (Flat): when KinrelFx.rich is false, the
                        // gradient resolves to null. Fall back to a flat
                        // solid color: sent = ember tint, received = dark
                        // surface. The hairline border (defined below)
                        // provides visual separation without shadows.
                        color: isSticker
                            ? Colors.transparent
                            : (KinrelFx.rich
                                ? null
                                : (isMe
                                    ? const Color(0x2EC44A18) // ember @ 0.18 (matches _kSentBubbleGradient)
                                    : kinshipBandColor != null
                                        ? Color.lerp(const Color(0xFF2E3150), kinshipBandColor, 0.06)!
                                        : const Color(0xFF282B45))), // average of _kReceivedBubbleGradient
                        // v131: Organic corners — 22px base, tail corner
                        // drops to 6px on isLastInGroup. Less mechanical
                        // than equal radii; mirrors Telegram's silhouette.
                        // Stickers get a soft 18px pill so they feel
                        // integrated rather than floating.
                        borderRadius: isSticker
                            ? BorderRadius.circular(18)
                            : BorderRadius.only(
                                topLeft: const Radius.circular(22),
                                topRight: const Radius.circular(22),
                                bottomLeft: Radius.circular(
                                    isMe ? 22 : (isLastInGroup ? 6 : 22)),
                                bottomRight: Radius.circular(
                                    isMe ? (isLastInGroup ? 6 : 22) : 22),
                              ),
                        // v131: Hairline border for definition. Sent:
                        // ember at 28% (softer than v129's 35%). Received:
                        // white at 6% (subtle edge to lift off wallpaper).
                        // v140: When a kinship band color is resolved,
                        // replace the uniform border with an asymmetric
                        // Border that has a 3px left side in the kinship
                        // color + hairline on the other 3 sides.
                        border: isSticker
                            ? null
                            : (isMe
                                ? Border.all(
                                    color: KinrelColors.ember
                                        .withValues(alpha: 0.28),
                                    width: 0.75,
                                  )
                                : kinshipBandColor != null
                                    ? Border(
                                        left: BorderSide(
                                            color: kinshipBandColor,
                                            width: 3),
                                        top: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            width: 0.75),
                                        right: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            width: 0.75),
                                        bottom: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            width: 0.75),
                                      )
                                    : Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.06),
                                        width: 0.75,
                                      )),
                        // v131: Layered elevation shadows for soft depth.
                        // Received: deeper shadow anchors it to the wall.
                        // Sent: gentler shadow lifts it + a faint ember
                        // ambient glow for warmth. Stickers: none.
                        //
                        // PERF (Part E4): On low-RAM phones, collapse to a
                        // single shadow with blurRadius capped at 6 (per
                        // spec) and skip the ember glow on sent bubbles.
                        // Strong phones keep both shadows as before.
                        //
                        // PERF (Tier K3): use const-hoisted shadow lists
                        // so the List<BoxShadow> identity is stable across
                        // rebuilds. Combined with clampBoxShadows() the
                        // mid-tier budget (sigma 6, single-shadow) is
                        // applied at runtime without re-allocating the
                        // source list. Steady-state: bubble RenderDecoratedBox
                        // is NOT marked dirty on chat_screen rebuild.
                        boxShadow: isSticker
                            ? null
                            : clampBoxShadows(
                                DeviceTierCache.instance.lowRam
                                    ? (isMe
                                        ? _kSentBubbleShadowsLowRam
                                        : _kReceivedBubbleShadowsLowRam)
                                    : (isMe
                                        ? _kSentBubbleShadows
                                        : _kReceivedBubbleShadows),
                              ),
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // v127: Sender name only on first message in group
                          // v3.3: DMs (isDirectChat) hide the sender name —
                          // a DM only has two parties so the name is redundant.
                          // Kin Thread / PR2 T1: the relationship pill is
                          // tinted with the sender's kinship band color.
                          if (!isMe && !isSticker && !isDirectChat && isFirstInGroup)
                            _buildSenderName(ref, kinshipBandColor),
                          // Tier 1 / Forwarded label — show a small
                          // "Forwarded from <name>" tag above the content
                          // when the message is a forwarded copy. The
                          // forwardedFrom field is set by fn_forward_message
                          // on the new copy; the original keeps null.
                          if (message.forwardedFrom != null &&
                              message.forwardedFrom!.isNotEmpty)
                            _buildForwardedLabel(),
                          // Message content
                          _buildMessageContent(context, ref, currentUserId),
                          // v127: Inline timestamp only on last-in-group
                          if (!isSticker && isLastInGroup) _buildTimeRow(),
                          if (isSticker) _buildStickerTimeRow(),
                        ],
                      ),
                    ),
                    // v127: Reaction chips positioned overlapping bubble bottom
                    if (message.reactions.isNotEmpty)
                      _buildReactionChips(currentUserId),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ); // close GestureDetector
      }, // close StatefulBuilder builder
    ); // close StatefulBuilder
  }

  /// v3.2: Shows a small modal bottom sheet with Retry and Delete
  /// options when the user taps a failed message. The sheet calls
  /// `retryMessage` or `deleteFailedMessage` on the chatProvider, then
  /// dismisses. Does not change the bubble layout, sizes, or colors —
  /// the sheet is a standard Material bottom sheet.
  void _showFailedMessageSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded,
                    color: KinrelColors.orange, size: 22),
                title: const Text('Retry',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  // v3.5 — injected handler (DM) or the built-in group
                  // provider call — identical sheet, identical UX.
                  if (onRetryFailed != null) {
                    onRetryFailed!(message.id);
                  } else {
                    ref
                        .read(chatProvider(familyId!).notifier)
                        .retryMessage(message.id);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400, size: 22),
                title: const Text('Delete',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  // v3.5 — injected handler (DM) or the built-in group
                  // provider call — identical sheet, identical UX.
                  if (onDeleteFailed != null) {
                    onDeleteFailed!(message.id);
                  } else {
                    ref
                        .read(chatProvider(familyId!).notifier)
                        .deleteFailedMessage(message.id);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReplyPreview() {
    // v131: Premium reply preview — softer background, refined accent
    // bar, gentler radius. Sits naturally above the bubble without
    // feeling like a separate floating card.
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
              color: KinrelColors.orange.withValues(alpha: 0.7), width: 2.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSenderName ?? '',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToContent ?? '',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver.withValues(alpha: 0.85),
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSenderName(WidgetRef ref, Color? kinshipColor) {
    // v131: Premium sender label — slightly larger, letter-spaced,
    // with a refined online dot. Reads as a quiet header above the
    // message rather than competing with it.
    //
    // v139: Relationship-aware sender labels — Kinrel's signature
    // differentiator. For family/group chats (familyId != null),
    // resolve the sender's relationship to the current viewer from
    // the K-Graph (e.g. "Chacha", "Bhaiya", "Nani"). The relationship
    // label appears as a small tag BEFORE the sender's name.
    // Falls back to sender name only if no relationship is found.
    //
    // Kin Thread / PR2 Task 1: the pill now uses the sender's KINSHIP
    // BAND COLOR (12% tinted background, the color for the text, and
    // a 0.5px border) instead of ember for everyone — so the pill,
    // the 3px left band, and the graph edge all speak the same color
    // language. Falls back to a neutral silver pill when a
    // relationship resolves but its kinship category has no color
    // (self/indirect). No relationship → name in orange, no pill,
    // neutral band (today's fallback, unchanged).
    //
    // Viewer-specific: the label changes based on who is logged in.
    // Not applied to 1-on-1 DMs (familyId == null).
    String? relationshipLabel;
    if (familyId != null && !isMe) {
      relationshipLabel = ref.watch(relationshipLabelProvider(
        (familyId: familyId!, senderUserId: message.senderId),
      ));
    }

    // The pill color: the sender's kinship band color when available,
    // otherwise a neutral silver (self/indirect relationships).
    final Color pillColor = kinshipColor ?? KinrelColors.textSilver;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Online dot — softer presence dot, slightly larger for elegance
          if (message.isOnline)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.success,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.success.withValues(alpha: 0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          // v139 / Kin Thread T1: Relationship pill (kinship-band colored,
          // small, before the name) — the Kinrel signature differentiator.
          // Only shown for family/group chats where a relationship was
          // resolved. Format: Relationship · Name.
          if (relationshipLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: pillColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: pillColor.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Text(
                relationshipLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: pillColor,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '·',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ],
          Text(
            message.senderName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: relationshipLabel != null
                  ? KinrelColors.textSilver.withValues(alpha: 0.85)
                  : KinrelColors.orange,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Tier 1 / Forwarded label — a small "Forwarded from <name>" tag
  /// rendered above the message content when `message.forwardedFrom`
  /// is set (i.e. this message is a forwarded copy). The forwarder's
  /// own name is in `senderName` (rendered above this label by
  /// _buildSenderName); `forwardedFrom` is the ORIGINAL sender's name.
  Widget _buildForwardedLabel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forward_rounded,
              size: 11, color: KinrelColors.textDim),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Forwarded from ${message.forwardedFrom}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textDim,
                letterSpacing: 0.3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, WidgetRef ref, String? currentUserId) {
    switch (message.messageType) {
      case MessageType.text:
        // v131: Premium typography — comfortable line height (1.5),
        // generous size (15px), subtle letter-spacing for elegance.
        // Reads effortlessly across long paragraphs without fatigue.
        //
        // Phase 22 / Task 3 — if the message carries @mention refs,
        // render with MentionText so the @Name spans are highlighted
        // (tinted background + primary color for self-mentions). The
        // fallback to a plain Text widget for mention-free messages
        // keeps the per-message cost unchanged.
        //
        // Tier 1 / Link Previews — wrap the text widget with
        // wrapWithLinkPreviews so any URL in the content gets a styled
        // preview card below the text. The wrapper is a no-op (returns
        // the text widget unchanged) when there are no URLs, so
        // mention-free + link-free messages pay zero extra cost.
        final textWidget = message.mentions.isNotEmpty
            ? MentionText(
                content: message.content,
                mentions: message.mentions,
                currentUserId: currentUserId ?? '',
                baseStyle: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
                mentionStyle: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.ember,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
                selfMentionStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.ember,
                  backgroundColor: KinrelColors.ember.withValues(alpha: 0.18),
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
              )
            : Text(
                message.content,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
              );
        // Wrap with link previews. Max width ~280px so the card doesn't
        // overflow the bubble's typical width (the bubble itself caps
        // at ~85% of screen width, minus padding).
        return wrapWithLinkPreviews(
          content: message.content,
          textWidget: textWidget,
          maxWidth: 280,
        );

      case MessageType.photo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo — render the actual image if mediaUrl is present,
            // otherwise fall back to the placeholder. Mirrors the
            // voiceNote case below which correctly branches on
            // mediaUrl. Previously this ALWAYS showed the placeholder
            // and never checked message.mediaUrl.
            if (message.mediaUrl != null &&
                message.mediaUrl!.isNotEmpty)
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => FullScreenImageViewer.show(
                    ctx,
                    imageUrl: message.mediaUrl!,
                    senderName: message.senderName,
                    timestamp: message.timestamp,
                  ),
                  child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: message.mediaUrl!,
                  cacheManager: KinrelImageCacheManager.instance,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  // Bubble caps at ~85% of screen width. Decode at
                  // the screen width × DPR (slightly larger than the
                  // actual bubble display, but well below a 4K decode).
                  memCacheWidth: (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
                  memCacheHeight:
                      (200 * MediaQuery.devicePixelRatioOf(context))
                          .toInt(),
                  placeholder: (context, url) => Container(
                    width: double.infinity,
                    height: 200,
                    color: const Color(0xFF202338),
                    child: const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF202338),
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 36,
                          color: KinrelColors.textSilver
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Failed to load',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textSilver
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                ),
              )
            else
              // Legacy message with no mediaUrl — keep the placeholder.
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF202338),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 36,
                      color: KinrelColors.textSilver.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Photo',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            if (message.content.isNotEmpty &&
                message.content != 'Photo placeholder') ...[
              const SizedBox(height: 8),
              Text(
                message.content,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14.5,
                  color: KinrelColors.textWhite,
                  height: 1.45,
                ),
              ),
            ],
          ],
        );

      case MessageType.voiceNote:
        // Phase 13: real voice message player
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
          return VoiceMessagePlayer(
            messageId: message.id,
            mediaUrl: message.mediaUrl!,
            durationSeconds: message.durationSeconds,
            isMe: isMe,
          );
        }
        // Fallback: placeholder if no media URL (e.g. legacy message)
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play button
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                ),
                child: const Icon(Icons.play_arrow, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        28,
                        (i) => Container(
                          width: 2.5,
                          height: 6 + (i % 5) * 4.0,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: isMe
                                ? KinrelColors.orange.withValues(alpha: 0.5)
                                : KinrelColors.textSilver.withValues(
                                    alpha: 0.3,
                                  ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${message.durationSeconds ?? 0}s',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case MessageType.sticker:
        // v131: Reduced from 64→46px so emoji feels integrated into
        // the chat rhythm rather than floating as an oversized anomaly.
        // Still expressive, now proportional to the bubble padding.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            message.content,
            style: const TextStyle(
              fontSize: 46,
              height: 1.0,
            ),
          ),
        );

      case MessageType.familyEvent:
        // Phase 18: Thinking of You messages are stored as familyEvent
        // with messageSubType='thinking_of_you'. Render them with a
        // special heart-themed bubble instead of the generic celebration
        // card, so recipients immediately recognize the message type.
        if (message.messageSubType == 'thinking_of_you') {
          return _buildThinkingOfYouBubble();
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Event icon and type
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: const Icon(
                      Icons.celebration,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Family Event',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.orange,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Event title
              if (message.eventTitle != null)
                Text(
                  message.eventTitle!,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              const SizedBox(height: 3),
              // Event date
              if (message.eventDate != null)
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: KinrelColors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      message.eventDate!,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ],
                ),
              if (message.content.isNotEmpty &&
                  message.content != 'Event shared') ...[
                const SizedBox(height: 6),
                Text(
                  message.content,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ],
          ),
        );

      case MessageType.gameInvite:
        // Kin Thread / PR2 Task 5: the ONE shared invite card (active
        // invites = slim card with 40px icon, title, players count and
        // the Join/status button; expired/completed = one-line row).
        // Extracted from this file into game_invite_card.dart so group
        // + direct chat share it with no duplicate invite-card code.
        return GameInviteCard(
          message: message,
          isMe: isMe,
          routeFamilyId: _inviteRouteFamilyId,
        );

      case MessageType.poll:
        // Phase 22 / Task 5 — Poll card. Reuses the gameInvite card
        // pattern (distinct card surface, tappable rows, live counts
        // via realtime). The actual rendering lives in widgets/poll_card.dart
        // so chat_screen.dart doesn't grow further.
        return PollCard(
          message: message,
          currentUserId: currentUserId ?? '',
          onVote: (optionIndex) {
            // MessageBubble carries the familyId (passed from the
            // chat thread so it's never null inside a family chat).
            // The DM screen doesn't render polls, so this branch is
            // only reachable from the family chat.
            if (familyId == null || familyId!.isEmpty) return;
            ref
                .read(chatProvider(familyId!).notifier)
                .votePoll(message.id, optionIndex);
          },
        );

      case MessageType.gif:
        // Tier 2 / GIF search — render the GIF image inline in the
        // bubble. The GIF's URL is stored in message.mediaUrl (the
        // high-res original); the content holds the Giphy title for
        // accessibility. Cap at ~220x220 so it doesn't dominate the
        // thread.
        //
        // ── Phase 4 / image cache ─────────────────────────────────────
        // Previously this branch used a bare CachedNetworkImage with
        // NO cacheManager and NO memCacheWidth/memCacheHeight, so a
        // 480p GIF decoded at full native resolution (and got cached
        // in the shared ImageCache at that full size — evicting other
        // thumbnails). Now we route through the consolidated
        // KinrelImageCacheManager and cap the decode at 220×220*DPR
        // — matching the photo-bubble branch's pattern.
        final gifDpr = MediaQuery.devicePixelRatioOf(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
            child: message.mediaUrl != null && message.mediaUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: message.mediaUrl!,
                    cacheManager: KinrelImageCacheManager.instance,
                    fit: BoxFit.cover,
                    // Cap decode at the on-screen display size × DPR so
                    // we don't burn memory decoding a 480p GIF to a 4×
                    // oversized bitmap just to downscale it on the GPU.
                    memCacheWidth: (220 * gifDpr).round(),
                    memCacheHeight: (220 * gifDpr).round(),
                    placeholder: (_, __) => Container(
                      color: const Color(0xFF11132A),
                      height: 120,
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: KinrelColors.ember),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF11132A),
                      height: 120,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined,
                          color: KinrelColors.textDim),
                    ),
                  )
                : Container(
                    color: const Color(0xFF11132A),
                    height: 120,
                    alignment: Alignment.center,
                    child: const Icon(Icons.gif_box_outlined,
                        color: KinrelColors.textDim),
                  ),
          ),
        );

      case MessageType.document:
        // Tier 2 / Document attachments — render a file card with the
        // filename + size + a download/open icon. Tap → open the URL
        // via url_launcher (or download to device on mobile).
        return _buildDocumentCard(context);

      case MessageType.location:
        // Tier 2 / Live location sharing — render a small map pin card
        // with the lat/lng. Tap → open in the system maps app.
        // (A future v2 would render an inline mini-map.)
        return _buildLocationCard(context);

      case MessageType.system:
        // Kin Thread / PR 1: system rows (join notices) never reach the
        // bubble — ChatMessageList short-circuits them into
        // ChatSystemNotice pills before any bubble is built. This case
        // only exists so the switch stays exhaustive over the enum.
        return const SizedBox.shrink();
    }
  }

  /// Tier 2 / Document attachments — file card for MessageType.document.
  ///
  /// Renders the filename + a download/open icon. Tap → open the URL
  /// via url_launcher (the URL is in message.mediaUrl; the filename
  /// is in message.content for the preview).
  Widget _buildDocumentCard(BuildContext context) {
    final fileName = message.content.isNotEmpty ? message.content : 'Document';
    final url = message.mediaUrl ?? '';
    final ext = _fileExtension(fileName);
    final iconData = _iconForExtension(ext);

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: url.isEmpty ? null : () => _openUrl(url),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KinrelColors.ember.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconData, size: 18, color: KinrelColors.ember),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      ext.isEmpty ? 'File' : ext.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.download_rounded,
                  size: 18, color: KinrelColors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  /// Tier 2 / Live location sharing — map pin card for MessageType.location.
  ///
  /// Renders a map pin icon + "Shared location" label + the lat/lng.
  /// Tap → open the system maps app at the shared coordinates.
  /// (A future v2 would render an inline MapLibre mini-map.)
  Widget _buildLocationCard(BuildContext context) {
    // For v1, the lat/lng are stored in message.content as a JSON
    // string: {"lat": 12.34, "lng": 56.78, "label": "..."}. We parse
    // defensively — if the format isn't recognized, fall back to a
    // generic "Shared location" card.
    double? lat;
    double? lng;
    String label = 'Shared location';
    try {
      final decoded = jsonDecode(message.content);
      if (decoded is Map<String, dynamic>) {
        lat = (decoded['lat'] as num?)?.toDouble();
        lng = (decoded['lng'] as num?)?.toDouble();
        final l = decoded['label'] as String?;
        if (l != null && l.isNotEmpty) label = l;
      }
    } catch (_) {
      // Not JSON — treat content as the label
      if (message.content.isNotEmpty) label = message.content;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.ember.withValues(alpha: 0.25),
          width: 0.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: lat != null && lng != null
              ? () => _openMaps(lat!, lng!, label)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KinrelColors.ember.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on_rounded,
                    size: 18, color: KinrelColors.ember),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (lat != null && lng != null)
                      Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: KinrelColors.textDim,
                          letterSpacing: 0.3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.map_outlined, size: 18, color: KinrelColors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  String _fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  IconData _iconForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'txt':
      case 'md':
        return Icons.article_rounded;
      case 'json':
      case 'csv':
        return Icons.data_object_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _openUrl(String url) async {
    // Best-effort: copy to clipboard + snackbar (matches the
    // LinkPreviewCard behavior). A future task can wire url_launcher
    // here (it's already in pubspec).
    try {
      await Clipboard.setData(ClipboardData(text: url));
      debugPrint('📎 Document URL copied: $url');
    } catch (_) {/* best-effort */}
  }

  Future<void> _openMaps(double lat, double lng, String label) async {
    // Open in the system maps app. Use the geo: URI scheme on Android,
    // https://maps.apple.com on iOS, https://www.google.com/maps on web.
    String url;
    if (Platform.isAndroid) {
      url = 'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})';
    } else if (Platform.isIOS) {
      url = 'https://maps.apple.com/?ll=$lat,$lng&q=${Uri.encodeComponent(label)}';
    } else {
      url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    try {
      await Clipboard.setData(ClipboardData(text: url));
      debugPrint('📍 Maps URL copied: $url');
    } catch (_) {/* best-effort */}
  }

  /// Phase 18: Thinking of You bubble — a warm, heart-themed card that
  /// stands out from regular text messages. Renders the sender's name
  /// and the warm message in a soft pink/orange card.
  Widget _buildThinkingOfYouBubble() {
    // Use a warm pink-coral accent for Thinking of You (distinct from
    // the orange used for regular family events).
    const accent = Color(0xFFE91E63); // pink
    const accentDim = Color(0x1FE91E63); // 12% alpha
    const accentBorder = Color(0x33E91E63); // 20% alpha

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentDim,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: accentBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Heart icon in a pink circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
              border: Border.all(
                color: accent.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.favorite,
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          // Message text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thinking of You',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // Phase 22 fix: the RPC now stores the FULL grammatical
                  // sentence in content (e.g. "Manish is thinking of you."),
                  // so we render it as-is. The previous code prepended
                  // senderName.split(' ').first — which produced broken
                  // output ("You is thinking of you.") when the sender's
                  // name resolved to the "You" fallback. See migration
                  // 20260906150000_fix_thinking_of_you_grammar_and_per_receiver_cooldown.sql.
                  message.content,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textWhite,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow() {
    // v131: Refined timestamp — smaller, dimmer, letter-spaced.
    // Reads as supporting information, not a primary element.
    // Aligned tightly with the read-receipt for visual balance.
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Text(
            message.formattedTime,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9.5,
              color: KinrelColors.textDim.withValues(alpha: 0.85),
              letterSpacing: 0.3,
            ),
          ),
          // Read receipts (only for sent messages)
          if (isMe) ...[
            const SizedBox(width: 4),
            ReadReceipt(
              isRead: message.isRead,
              messageStatus: message.messageStatus,
            ),
          ],
        ],
      ),
    );
  }

  /// Phase 14: A minimal time row for stickers — right-aligned below the
  /// emoji, no read receipts (stickers don't need delivery confirmation).
  Widget _buildStickerTimeRow() {
    // v131: Sticker timestamp matches the refined text-bubble timestamp
    // style for consistency across message types.
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          message.formattedTime,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9.5,
            color: KinrelColors.textDim.withValues(alpha: 0.85),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// v127: Reaction chips positioned overlapping the bubble's bottom edge.
  /// Uses a Transform.translate to shift the chips down so they overlap.
  Widget _buildReactionChips(String? currentUserId) {
    final grouped = message.groupedReactions;
    return Transform.translate(
      offset: const Offset(0, 10),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          children: grouped.entries.map((entry) {
            final hasMyReaction = message.reactions.any(
              (r) => r.emoji == entry.key && r.userId == currentUserId,
            );
            return GestureDetector(
              onTap: onReact,
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: hasMyReaction
                      ? KinrelColors.orange.withValues(alpha: 0.15)
                      : const Color(0xFF202338),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: hasMyReaction
                        ? KinrelColors.orange.withValues(alpha: 0.3)
                        : const Color(0xFF3A3A4A),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 12)),
                    if (entry.value > 1) ...[
                      const SizedBox(width: 2),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: hasMyReaction
                              ? KinrelColors.orange
                              : KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Read Receipt (WhatsApp-style ticks)
// v109.11: single tick (sent) → double tick (delivered) → blue tick (read)
// ═══════════════════════════════════════════════════════════════════════
