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
import '../../../family/data/relationship_label_provider.dart';
import '../../providers/chat_provider.dart';
import '../chat_ui_tokens.dart';
import 'chat_meta.dart';
import 'deleted_message_ghost.dart';
import 'game_invite_card.dart';
import 'link_preview_card.dart';
import 'mention_picker.dart';
import 'poll_card.dart';
import '../voice_message_player.dart';
import 'full_screen_image_viewer.dart';

// ═══════════════════════════════════════════════════════════════════
// Chat UI Reference (Kin Thread) — flat bubbles:
//   • Solid fills only: sent = ChatUi.chatSent (#34201A), received =
//     ChatUi.chatReceived (#2A2D48). No gradients, no shadows, no blur.
//   • Radius 14 on all four corners (no tails).
//   • All colors, sizes and typography come from chat_ui_tokens.dart
//     (class ChatUi) — nothing is hard-coded here.
// ═══════════════════════════════════════════════════════════════════

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
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

    /// v6.0 — Selection mode state (Image 3 reference).
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
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

  /// v6.0 — When true, the bubble is in selection mode. Tapping the
  /// bubble toggles selection instead of opening the action sheet.
  /// A selection checkbox is shown overlapping the leading edge.
  final bool selectionMode;

  /// v6.0 — Whether THIS bubble is currently selected. Renders an
  /// orange ring + filled checkbox.
  final bool isSelected;

  /// v6.0 — Callback to toggle this message's selection state. Only
  /// invoked when [selectionMode] is true.
  final VoidCallback? onToggleSelection;

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

    // v143: If this message is a reply to a message that has since been
    // deleted-for-everyone, swap the reply preview's quoted content for
    // a safe "deleted" reference so the original content is not exposed
    // through the reply preview. (Section G will rebuild the reply
    // preview with the new look; this lookup stays so it can use it.)
    // We ALSO capture the replied-to sender's userId + whether the
    // relationship resolved + the relationship label, so §G's band
    // color + "RELATIONSHIP, NAME" title can use them.
    bool replyTargetDeleted = false;
    String? replyTargetSenderId;
    if (message.replyToId != null && familyId != null) {
      try {
        final chatState = ref.read(chatProvider(familyId!));
        final target =
            chatState.messages.firstWhere((m) => m.id == message.replyToId);
        replyTargetDeleted = target.isDeletedForEveryone;
        replyTargetSenderId = target.senderId;
      } catch (_) {
        // Reply target not in the local 50-message cache — assume
        // not-deleted. The denormalized replyToContent snapshot is
        // still safe to show because the deletion RPC doesn't scrub
        // denormalized reply snapshots.
        replyTargetDeleted = false;
      }
    }

    // Sticker messages render WITHOUT the bubble background — just the
    // emoji + a small timestamp underneath.
    final isSticker = message.messageType == MessageType.sticker;

    // "Thinking of you" moments render as a CENTERED card (D11) — no
    // bubble, no band, no sender line, no avatar.
    final isThinkingOfYou =
        message.messageType == MessageType.familyEvent &&
        message.messageSubType == 'thinking_of_you';

    // Terminal game invites (expired / cancelled / completed) render as
    // a quiet one-line row with NO bubble (D18c).
    final _inviteStatus = message.gameInviteStatus ?? 'pending';
    final isTerminalInvite =
        message.messageType == MessageType.gameInvite &&
        (_inviteStatus == 'expired' ||
            _inviteStatus == 'cancelled' ||
            _inviteStatus == 'completed');

    // v140/D3: Kinship-category generation bands. Resolve the sender's
    // relationship key to the current viewer, classify it into a
    // KinshipEdgeCategory, and map to a generation-band color. The color
    // is applied as a 3 dp left band strip painted as a Positioned
    // overlay inside the bubble's rounded clip. Only for family/group
    // chats, not DMs, and only for received messages (not isMe).
    // Unresolved relationship → extended band color (D3) + orange name.
    Color? kinshipBandColor;
    var kinshipResolved = false;
    if (familyId != null && !isMe && !isSticker && !isDirectChat) {
      final rawKey = ref.watch(
        relationshipKeyProvider((
          familyId: familyId!,
          senderUserId: message.senderId,
        )),
      );
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        final color = kinshipCategoryColor(category);
        if (color != null) {
          kinshipBandColor = color;
          kinshipResolved = true;
        }
      }
      if (!kinshipResolved) {
        // D3: unresolved relationship → band color extended #64748B.
        kinshipBandColor = KinrelColors.nodeExtended;
      }
    }

    // Swipe-to-reply is handled by SwipeToReply in chat_meta.dart (chat_screen.dart wraps
    // each bubble). Do not add a second drag handler here: it would fight with it.
    return StatefulBuilder(
      builder: (context, setLocalState) {
        // v6.0 — In selection mode, tapping the bubble toggles its
        // selection state. The normal failed-message tap handler is
        // disabled in selection mode (the user is bulk-selecting, not
        // retrying a single failed send).
        final VoidCallback? tapHandler = selectionMode
            ? onToggleSelection
            : (isMe &&
                  message.messageStatus == 'failed' &&
                  (familyId != null || onRetryFailed != null))
            ? () => _showFailedMessageSheet(context, ref)
            : null;

        // ── D11: thinking-of-you → centered card, no bubble ──────────
        if (isThinkingOfYou) {
          return GestureDetector(
            onLongPress: onLongPress,
            onTap: tapHandler,
            child: Align(
              alignment: Alignment.center,
              widthFactor: 1,
              child: _buildThinkingOfYouMoment(),
            ),
          );
        }

        // ── D18c: terminal invite → quiet one-line row, no bubble ────
        if (isTerminalInvite) {
          return GestureDetector(
            onLongPress: onLongPress,
            onTap: tapHandler,
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: GameInviteCard(
                message: message,
                isMe: isMe,
                routeFamilyId: _inviteRouteFamilyId,
                isGroup: familyId != null && !isDirectChat,
                kinshipColor: kinshipBandColor,
              ),
            ),
          );
        }

        // ── v143 / Signature §B: deleted-for-everyone → Kinrel ghost
        // bubble. Replaces the inline placeholder from the merge step
        // with the proper DeletedMessageGhost widget (dashed border,
        // linked-nodes icon, personalized wording, kinship band, time
        // row, cross-fade transition). The collapsed-rows variant
        // (3+ adjacent ghosts) is handled at the chat_message_list
        // level — here we just render one ghost per row.
        if (message.isDeletedForEveryone) {
          // Resolve the relationship label + band color for received
          // group messages. Mirrors the logic used by the normal
          // bubble's _buildSenderName (D6) — kept in sync.
          String? relationshipLabel;
          if (familyId != null && !isMe && !isDirectChat) {
            relationshipLabel = ref.watch(relationshipLabelProvider(
              (familyId: familyId!, senderUserId: message.senderId),
            ));
          }
          // Decide who deleted it. Today only the original author can
          // delete-for-everyone, so `isMe` (which is author-vs-viewer)
          // is a reliable proxy. When `deletedByUserId` is set we use
          // it precisely.
          final bool deletedByMe = (message.deletedByUserId != null &&
                  currentUserId != null &&
                  message.deletedByUserId == currentUserId) ||
              isMe;

          return DeletedMessageGhostTransition(
            deleted: true,
            normalChild: const SizedBox.shrink(),
            ghostChild: DeletedMessageGhost(
              isMe: deletedByMe,
              senderName: message.senderName,
              timestamp: message.formattedTime,
              onLongPress: onLongPress,
              selectionMode: selectionMode,
              isSelected: isSelected,
              onToggleSelection: onToggleSelection,
              isDirectChat: isDirectChat,
              familyId: familyId,
              relationshipLabel: relationshipLabel,
              kinshipColor: kinshipBandColor,
              kinshipResolved: kinshipResolved,
            ),
          );
        }

        return GestureDetector(
          onLongPress: onLongPress,
          onTap: tapHandler,
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.sizeOf(context).width *
                          ChatUi.bubbleMaxWidthFactor,
                    ),
                    margin: EdgeInsets.only(
                      left: isMe ? 48 : 0,
                      right: isMe ? 0 : 48,
                    ),
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
                                  child: _buildReplyPreview(
                                      ref,
                                      currentUserId,
                                      replyTargetDeleted,
                                      replyTargetSenderId),
                                )
                              : _buildReplyPreview(
                                  ref,
                                  currentUserId,
                                  replyTargetDeleted,
                                  replyTargetSenderId),
                        // Chat UI Reference D3/D4/D5 — flat bubble:
                        // solid fill, radius 14 on all four corners,
                        // spec padding, no shadows, no gradients.
                        Stack(
                          children: [
                            Container(
                              padding: _bubblePadding(isSticker: isSticker),
                              decoration: BoxDecoration(
                                color: isSticker
                                    ? Colors.transparent
                                    : (isMe
                                          ? ChatUi.chatSent
                                          : ChatUi.chatReceived),
                                borderRadius: BorderRadius.circular(
                                  ChatUi.bubbleRadius,
                                ),
                                border: isSticker
                                    ? null
                                    : (isMe
                                          ? Border.all(
                                              color: ChatUi.chatSentBorder,
                                              width: ChatUi.sentBorderWidth,
                                            )
                                          : null),
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
                                  if (!isMe &&
                                      !isSticker &&
                                      !isDirectChat &&
                                      isFirstInGroup)
                                    _buildSenderName(
                                      ref,
                                      kinshipBandColor,
                                      kinshipResolved,
                                    ),
                                  // Tier 1 / Forwarded label — show a small
                                  // "Forwarded from <name>" tag above the content
                                  // when the message is a forwarded copy.
                                  if (message.forwardedFrom != null &&
                                      message.forwardedFrom!.isNotEmpty)
                                    _buildForwardedLabel(),
                                  // Message content
                                  _buildMessageContent(
                                    context,
                                    ref,
                                    currentUserId,
                                  ),
                                  // v127: Inline timestamp only on last-in-group
                                  if (!isSticker && isLastInGroup)
                                    _buildTimeRow(),
                                  if (isSticker) _buildStickerTimeRow(),
                                ],
                              ),
                            ),
                            // D3: Kinship band — a 3 dp strip pinned to the
                            // bubble's left edge, inside the rounded clip
                            // (the Stack is clipped by the bubble's radius
                            // via a ClipRRect-equivalent decoration on the
                            // Positioned child). Received-family only:
                            // kinshipBandColor is null for isMe / stickers /
                            // DMs. IgnorePointer: purely decorative overlay.
                            if (kinshipBandColor != null)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: ChatUi.bandWidth,
                                    decoration: BoxDecoration(
                                      color: kinshipBandColor,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(
                                          ChatUi.bubbleRadius,
                                        ),
                                        bottomLeft: Radius.circular(
                                          ChatUi.bubbleRadius,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ), // close Stack
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
        );
      }, // close StatefulBuilder builder
    ); // close StatefulBuilder
  }

  /// D3/D4/D5 bubble padding:
  ///   • received group: left 14, top 6, right 10, bottom 5
  ///   • received direct: left 10, top 6, right 10, bottom 5
  ///   • sent (both): left 10, top 6, right 10, bottom 5
  ///   • stickers keep their looser symmetric padding.
  EdgeInsets _bubblePadding({required bool isSticker}) {
    if (isSticker) {
      return const EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    }
    return EdgeInsets.only(
      left: (!isMe && !isDirectChat) ? 14 : 10,
      top: 6,
      right: 10,
      bottom: 5,
    );
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
                leading: const Icon(
                  Icons.refresh_rounded,
                  color: KinrelColors.orange,
                  size: 22,
                ),
                title: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                  size: 22,
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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

  Widget _buildReplyPreview(
      WidgetRef ref,
      String? currentUserId, [
      bool replyTargetDeleted = false,
      String? replyTargetSenderId,
      ]) {
    // v143 / Signature §G — reply quote with relationship band.
    // Container: radius 8, background black at 22 percent alpha
    // (plain color via blendOver, NOT a Flutter Opacity layer — flat
    // style), padding 4 top, 8 right, 4 bottom, 12 left, bottom margin
    // 4. A 3 dp band on the left in the replied-to sender's kinship
    // color (own messages: orange; unresolved: extended).
    //
    // Title row: 11/500 in the readable text variant of that color
    // (ChatUi.readableKinshipLabel), reading "RELATIONSHIP, NAME" (for
    // example "Papa, Father") when the relationship resolved, OR "You"
    // for the current user's own message, OR just the name in orange
    // when no relationship resolved.
    //
    // Quoted text: 12/400/textSecondary, max 2 lines with ellipsis.
    // When [replyTargetDeleted] is true, the quoted text is replaced
    // with "This message was deleted." (italic, textSubtitle @ 0.6).
    //
    // Tap behavior (jump to message) is unchanged — handled by the
    // parent GestureDetector that wraps _buildReplyPreview's output.
    final bool replyOwnsTarget = replyTargetSenderId != null &&
        currentUserId == replyTargetSenderId;

    // Resolve the replied-to sender's relationship band color.
    Color? replyBandColor;
    bool replyKinshipResolved = false;
    String? replyRelationshipLabel;
    if (familyId != null && replyTargetSenderId != null && !replyOwnsTarget) {
      final rawKey = ref.watch(relationshipKeyProvider(
        (familyId: familyId!, senderUserId: replyTargetSenderId),
      ));
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        final color = kinshipCategoryColor(category);
        if (color != null) {
          replyBandColor = color;
          replyKinshipResolved = true;
        }
      }
      if (!replyKinshipResolved) {
        replyBandColor = KinrelColors.nodeExtended;
      }
      replyRelationshipLabel = ref.watch(relationshipLabelProvider(
        (familyId: familyId!, senderUserId: replyTargetSenderId),
      ));
    }

    // Determine the title-row color + text.
    final Color titleColor;
    final String titleText;
    if (replyOwnsTarget) {
      // Own message replied to → orange band, "You" title.
      replyBandColor = KinrelColors.orange;
      titleColor = KinrelColors.orange;
      titleText = 'You';
    } else if (replyKinshipResolved && replyRelationshipLabel != null) {
      titleColor =
          ChatUi.readableKinshipLabel(replyBandColor!);
      titleText = '$replyRelationshipLabel, ${message.replyToSenderName ?? ''}';
    } else {
      // Unresolved → orange name, just the name (no relationship prefix).
      replyBandColor = KinrelColors.orange;
      titleColor = KinrelColors.orange;
      titleText = message.replyToSenderName ?? '';
    }

    // Quoted content + style — handle the deleted-target case.
    final String previewContent = replyTargetDeleted
        ? 'This message was deleted.'
        : (message.replyToContent ?? '');
    final TextStyle previewStyle = replyTargetDeleted
        ? TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: ChatUi.textSubtitle.withValues(alpha: 0.6),
            height: 1.3,
          )
        : ChatUi.replyQuoteText;

    // Background: black at 22% alpha over the chat wallpaper (a solid
    // opaque color via blendOver — flat style, no Opacity layer).
    final Color quoteBackground = ChatUi.blendOver(
        ChatUi.chatBackground, Colors.black, 0.22);

    // Simpler layout: a Container with a BoxDecoration that includes a
    // 3 dp left Border in the band color. Achieves the band-on-left
    // look without an IntrinsicHeight+Row+Expanded structure (which
    // can blow up inside the unbounded-height ListView the chat lives
    // in). The Container's height is determined by its Column child
    // (title + content). The 3 dp left border paints the band flush
    // against the rounded-rect clip.
    return Container(
      margin: const EdgeInsets.only(bottom: ChatUi.replyBottomMargin),
      padding: const EdgeInsets.only(
        top: ChatUi.replyTopPad,
        right: ChatUi.replyRightPad,
        bottom: ChatUi.replyBottomPad,
        left: ChatUi.replyLeftPad,
      ),
      decoration: BoxDecoration(
        color: quoteBackground,
        borderRadius: BorderRadius.circular(ChatUi.replyRadius),
        border: Border(
          left: BorderSide(
            color: replyBandColor ?? KinrelColors.orange,
            width: ChatUi.replyBandWidth,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titleText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: titleColor,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            previewContent,
            style: previewStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSenderName(
    WidgetRef ref,
    Color? kinshipColor,
    bool kinshipResolved,
  ) {
    // D6: Sender line (group, first message of a cluster only).
    // A row with 6 gap and 2 bottom margin: the relationship tag FIRST,
    // then the name. Tag: radius full, padding 1 vertical / 6 horizontal,
    // 11/500, text in the kinship color, background the kinship color at
    // 12 percent alpha, border 0.5 dp the kinship color at 30 percent.
    // Name: sender name style (12 / 400, silver).
    //
    // D3 unresolved relationship: NO pill, sender name in orange 12/500.
    //
    // Viewer-specific: the label changes based on who is logged in.
    // Not applied to 1-on-1 DMs (familyId == null).
    String? relationshipLabel;
    if (familyId != null && !isMe) {
      relationshipLabel = ref.watch(
        relationshipLabelProvider((
          familyId: familyId!,
          senderUserId: message.senderId,
        )),
      );
    }

    final bool showPill =
        kinshipResolved && relationshipLabel != null && !isDirectChat;
    final Color? pillColor = kinshipColor == null
        ? null
        : ChatUi.kinshipPillText(kinshipColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPill && pillColor != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: kinshipColor!.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                border: Border.all(
                  color: kinshipColor.withValues(alpha: 0.30),
                  width: 0.5,
                ),
              ),
              child: Text(
                relationshipLabel,
                style: ChatUi.relationshipTag.copyWith(color: pillColor),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            message.senderName,
            style: showPill
                ? ChatUi.senderNameText
                : ChatUi.senderNameUnresolved,
          ),
        ],
      ),
    );
  }

  /// v143 / Signature §F — Passed along label. Replaces the old
  /// "Forwarded from <name>" tag (which leaked the original author)
  /// with a neutral "Passed along" label above the message content.
  /// Layout: Row with 4 dp gap + 2 dp bottom margin, a 13 dp branch
  /// icon (Material `call_split`) + the text "Passed along", both
  /// 11 / 500 / textMeta. Does NOT show the original author — that's
  /// the whole point of the spec change. Works identically in group
  /// and direct chat.
  Widget _buildForwardedLabel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: ChatUi.passedAlongBottomMargin),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.call_split_rounded,
            size: ChatUi.passedAlongIconSize,
            color: ChatUi.textMeta,
          ),
          const SizedBox(width: ChatUi.passedAlongGap),
          Text('Passed along', style: ChatUi.passedAlongText),
        ],
      ),
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    WidgetRef ref,
    String? currentUserId,
  ) {
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
                baseStyle: ChatUi.messageText,
                mentionStyle: ChatUi.messageText.copyWith(
                  fontWeight: FontWeight.w500,
                  color: ChatUi.accent,
                ),
                selfMentionStyle: ChatUi.messageText.copyWith(
                  fontWeight: FontWeight.w500,
                  color: ChatUi.accent,
                  backgroundColor: ChatUi.accent.withValues(alpha: 0.18),
                ),
              )
            : Text(message.content, style: ChatUi.messageText);
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
            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty)
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
                      memCacheWidth:
                          (MediaQuery.sizeOf(context).width *
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
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 36,
                              color: KinrelColors.textSilver.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Failed to load',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                color: KinrelColors.textSilver.withValues(
                                  alpha: 0.5,
                                ),
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
                child: const Icon(
                  Icons.play_arrow,
                  size: 18,
                  color: Colors.white,
                ),
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
            style: const TextStyle(fontSize: 46, height: 1.0),
          ),
        );

      case MessageType.familyEvent:
        // Phase 18: Thinking of You messages are stored as familyEvent
        // with messageSubType='thinking_of_you'. Render them with a
        // special heart-themed bubble instead of the generic celebration
        // card, so recipients immediately recognize the message type.
        if (message.messageSubType == 'thinking_of_you') {
          // D11: normally intercepted by build(); kept for safety if a
          // future call path reaches the content builder.
          return _buildThinkingOfYouMoment();
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
        // v143/Step 7: pass isGroup + kinshipColor for the 3 dp band
        // (group chats only). The tile color is handled inside the
        // card (chatCardTile on received bubbles so it doesn't vanish).
        return GameInviteCard(
          message: message,
          isMe: isMe,
          routeFamilyId: _inviteRouteFamilyId,
          isGroup: familyId != null && !isDirectChat,
          kinshipColor: kinshipBandColor,
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
                          strokeWidth: 2,
                          color: KinrelColors.ember,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF11132A),
                      height: 120,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  )
                : Container(
                    color: const Color(0xFF11132A),
                    height: 120,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.gif_box_outlined,
                      color: KinrelColors.textDim,
                    ),
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
              const Icon(
                Icons.download_rounded,
                size: 18,
                color: KinrelColors.textDim,
              ),
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
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: KinrelColors.ember,
                ),
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
              const Icon(
                Icons.map_outlined,
                size: 18,
                color: KinrelColors.textDim,
              ),
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
    } catch (_) {
      /* best-effort */
    }
  }

  Future<void> _openMaps(double lat, double lng, String label) async {
    // Open in the system maps app. Use the geo: URI scheme on Android,
    // https://maps.apple.com on iOS, https://www.google.com/maps on web.
    String url;
    if (Platform.isAndroid) {
      url = 'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})';
    } else if (Platform.isIOS) {
      url =
          'https://maps.apple.com/?ll=$lat,$lng&q=${Uri.encodeComponent(label)}';
    } else {
      url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    try {
      await Clipboard.setData(ClipboardData(text: url));
      debugPrint('📍 Maps URL copied: $url');
    } catch (_) {
      /* best-effort */
    }
  }

  /// Phase 18: Thinking of You bubble — a warm, heart-themed card that
  /// stands out from regular text messages. Renders the sender's name
  /// and the warm message in a soft pink/orange card.
  /// D11: Thinking of you moment — a CENTERED card: background chatCard,
  /// border chatCardBorder 0.5, radius 12, padding 8 vertical / 12
  /// horizontal, row with 8 gap: heart icon 18 in orange, then text 13
  /// textPrimary (for example "Papa is thinking of you").
  Widget _buildThinkingOfYouMoment() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ChatUi.chatCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ChatUi.chatCardBorder,
          width: ChatUi.cardBorderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.favorite,
            size: ChatUi.iconHeart,
            color: ChatUi.accent,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              // The RPC stores the FULL grammatical sentence in content
              // (e.g. "Manish is thinking of you."), rendered as-is.
              message.content,
              style: ChatUi.thinkingText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow() {
    // D7: Time row inside every bubble — RIGHT aligned, 2 top margin,
    // 11 / textMeta; for sent messages add a 4 gap and the ticks icon
    // 13 after the time (existing tick colors and states stay as-is).
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(message.formattedTime, style: ChatUi.timeText),
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

  /// Phase 14: A minimal time row for stickers — below the emoji, no
  /// read receipts (stickers don't need delivery confirmation).
  Widget _buildStickerTimeRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(message.formattedTime, style: ChatUi.timeText),
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
