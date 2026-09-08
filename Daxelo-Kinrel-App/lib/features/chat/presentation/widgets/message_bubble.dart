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
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../core/family/family_provider.dart';
import '../../../../../core/kinship/kinship_edge_style.dart';
import '../../../family/data/relationship_label_provider.dart';
import '../../../games/shared/icons/game_icons.dart';
import '../../../games/shared/models/game_invite.dart';
import '../../../profile/presentation/member_profile_sheet.dart';
import '../../providers/chat_provider.dart';
import 'chat_meta.dart';
import 'link_preview_card.dart';
import 'mention_picker.dart';
import 'poll_card.dart';
import '../voice_message_player.dart';
import 'full_screen_image_viewer.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.onReact,
    required this.onLongPress,
    required this.familyId,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.animateIn = false,
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
    Color? kinshipBandColor;
    if (familyId != null && !isMe && !isSticker) {
      final rawKey = ref.watch(relationshipKeyProvider(
        (familyId: familyId!, senderUserId: message.senderId),
      ));
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        kinshipBandColor = kinshipCategoryColor(category);
      }
    }

    // v122: Swipe-to-reply — user can swipe right on any message to
    // quote-reply to it. Uses a horizontal drag gesture with a
    // threshold. When the swipe exceeds the threshold, onReply is
    // called (which calls setReplyTo in the provider). A visual
    // reply icon appears during the drag for feedback.
    double _dragX = 0;
    bool _replyTriggered = false;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return GestureDetector(
          onLongPress: onLongPress,
          onHorizontalDragUpdate: (details) {
            if (details.delta.dx > 0 && !_replyTriggered) {
              _dragX += details.delta.dx;
              if (_dragX > 40) {
                _replyTriggered = true;
                onReply();
                HapticFeedback.selectionClick();
              }
            }
          },
          onHorizontalDragEnd: (_) {
            _dragX = 0;
            _replyTriggered = false;
          },
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // v122: Reply icon shown during swipe (left side).
                if (_dragX > 5 && !isSticker)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.reply_rounded,
                      size: 20,
                      color: KinrelColors.orange
                          .withValues(alpha: (_dragX / 40).clamp(0.0, 1.0)),
                    ),
                  ),
                // v127: Avatar only on first message in group.
                // Non-first messages get an invisible spacer for alignment.
                if (!isMe && !isSticker && isFirstInGroup)
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
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!isMe && !isSticker && !isFirstInGroup)
                  const SizedBox(width: 40), // invisible spacer for alignment
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                margin: EdgeInsets.only(
                    left: isMe ? 48 : 0, right: isMe ? 0 : 48),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Reply preview (if replying to a message)
                    if (message.replyToId != null) _buildReplyPreview(),
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
                        gradient: isSticker
                            ? null
                            : (isMe
                                ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      KinrelColors.ember.withValues(alpha: 0.18),
                                      KinrelColors.ember.withValues(alpha: 0.08),
                                    ],
                                  )
                                : kinshipBandColor != null
                                    // v140: Blend 6% kinship band color
                                    // into the received-message gradient
                                    // so the generation band is felt as
                                    // a subtle background tint, not just
                                    // the left border.
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color.lerp(
                                            const Color(0xFF2E3150),
                                            kinshipBandColor,
                                            0.06)!,
                                          Color.lerp(
                                            const Color(0xFF23263B),
                                            kinshipBandColor,
                                            0.06)!,
                                        ],
                                      )
                                    : const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0xFF2E3150),
                                          Color(0xFF23263B),
                                        ],
                                      )),
                        color: isSticker ? Colors.transparent : null,
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
                        boxShadow: isSticker
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: isMe ? 0.18 : 0.30),
                                  blurRadius: isMe ? 8 : 12,
                                  offset: Offset(0, isMe ? 2 : 4),
                                ),
                                if (isMe)
                                  BoxShadow(
                                    color: KinrelColors.ember
                                        .withValues(alpha: 0.10),
                                    blurRadius: 14,
                                    offset: const Offset(0, 0),
                                  ),
                              ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // v127: Sender name only on first message in group
                          if (!isMe && !isSticker && isFirstInGroup)
                            _buildSenderName(ref),
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

  Widget _buildSenderName(WidgetRef ref) {
    // v131: Premium sender label — slightly larger, letter-spaced,
    // with a refined online dot. Reads as a quiet header above the
    // message rather than competing with it.
    //
    // v139: Relationship-aware sender labels — Kinrel's signature
    // differentiator. For family/group chats (familyId != null),
    // resolve the sender's relationship to the current viewer from
    // the K-Graph (e.g. "Chacha", "Bhaiya", "Nani"). The relationship
    // label appears as a small amber tag BEFORE the sender's name.
    // Falls back to sender name only if no relationship is found.
    //
    // Viewer-specific: the label changes based on who is logged in.
    // Not applied to 1-on-1 DMs (familyId == null).
    String? relationshipLabel;
    if (familyId != null && !isMe) {
      relationshipLabel = ref.watch(relationshipLabelProvider(
        (familyId: familyId!, senderUserId: message.senderId),
      ));
    }

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
          // v139: Relationship label (amber, small, before the name)
          // — the Kinrel signature differentiator. Only shown for
          // family/group chats where a relationship was resolved.
          if (relationshipLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: KinrelColors.ember.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.30),
                  width: 0.5,
                ),
              ),
              child: Text(
                relationshipLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.ember,
                  letterSpacing: 0.3,
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
          Icon(Icons.forward_rounded,
              size: 11, color: KinrelColors.textDim),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Forwarded from ${message.forwardedFrom}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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
                baseStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
                mentionStyle: TextStyle(
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
                style: TextStyle(
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
                child: Image.network(
                  message.mediaUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: double.infinity,
                      height: 200,
                      color: const Color(0xFF202338),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            value: loadingProgress.expectedTotalBytes !=
                                    null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
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
                style: TextStyle(
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                ),
                child: Icon(Icons.play_arrow, size: 18, color: Colors.white),
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
                      style: TextStyle(
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: Icon(
                      Icons.celebration,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
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
                  style: TextStyle(
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
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: KinrelColors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      message.eventDate!,
                      style: TextStyle(
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
                  style: TextStyle(
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
        // Persistent game-invite card — the second, durable surface for a
        // game-room invite (the first being the realtime GameInviteListener
        // popup that only reaches members who are online right now).
        // Rendered full width within the normal bubble constraints.
        return _buildGameInviteCard(context);

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
        return ClipRRect(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
            child: message.mediaUrl != null && message.mediaUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: message.mediaUrl!,
                    fit: BoxFit.cover,
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
                      child: Icon(Icons.broken_image_outlined,
                          color: KinrelColors.textDim),
                    ),
                  )
                : Container(
                    color: const Color(0xFF11132A),
                    height: 120,
                    alignment: Alignment.center,
                    child: Icon(Icons.gif_box_outlined,
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
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      ext.isEmpty ? 'File' : ext.toUpperCase(),
                      style: TextStyle(
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
              Icon(Icons.download_rounded,
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
                child: Icon(Icons.location_on_rounded,
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
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (lat != null && lng != null)
                      Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style: TextStyle(
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
              Icon(Icons.map_outlined, size: 18, color: KinrelColors.textDim),
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

  /// Game-invite card bubble (MessageType.gameInvite).
  ///
  /// Distinct card inside the standard bubble: game icon + display name,
  /// "<current>/<max> players", the room code as a small mono chip, and a
  /// primary Join button that navigates exactly like
  /// GameInviteListener._acceptInvite (same '/family/<id>/<gameType>/lobby?
  /// join=<gameId>' route). The button is disabled ("Full") once the room
  /// is full, and "Started"/"Ended" once the invite's lifecycle closes
  /// (gameInviteStatus accepted/expired/cancelled). The sender's own card
  /// never shows Join — they are already in the game — and shows a
  /// waiting/status label instead.
  Widget _buildGameInviteCard(BuildContext context) {
    final rawGameType = message.gameType ?? '';
    final parsedGameType = GameTypeX.fromRouteSegment(rawGameType);
    final displayName =
        parsedGameType?.displayName ?? _titleCaseSegment(rawGameType);
    final maxPlayers = message.gameMaxPlayers ?? 2;
    final currentPlayers = message.gameCurrentPlayers ?? 1;
    final roomCode = (message.roomCode ?? '').trim();
    final status = message.gameInviteStatus ?? 'pending';
    final isFull = currentPlayers >= maxPlayers;

    // Disabled-button label resolution: null → enabled "Join".
    String? disabledLabel;
    if (isFull) {
      disabledLabel = 'Full';
    } else if (status == 'accepted') {
      disabledLabel = 'Started';
    } else if (status == 'expired' || status == 'cancelled') {
      disabledLabel = 'Ended';
    }

    final canJoin =
        !isMe && disabledLabel == null && (message.gameId ?? '').isNotEmpty;

    // Sender-side status line (replaces the Join button on isMe cards).
    String waitingLabel;
    if (status == 'accepted') {
      waitingLabel = 'Game started';
    } else if (status == 'expired' || status == 'cancelled') {
      waitingLabel = 'Game ended';
    } else if (isFull) {
      waitingLabel = 'Room full';
    } else {
      waitingLabel = 'Waiting for players…';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KinrelSpacing.md),
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
          // Header: game icon + game display name
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: parsedGameType != null
                    ? GameIcon(gameId: rawGameType, size: 40)
                    : const Icon(Icons.sports_esports,
                        size: 26, color: KinrelColors.orange),
              ),
              const SizedBox(width: KinrelSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'GAME INVITE',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.orange,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.sm),
          // Players + room code chip
          Row(
            children: [
              Icon(
                Icons.group_outlined,
                size: 13,
                color: KinrelColors.textSilver.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 4),
              Text(
                '$currentPlayers/$maxPlayers players',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textSilver,
                ),
              ),
              if (roomCode.isNotEmpty) ...[
                const SizedBox(width: KinrelSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.3),
                      width: 0.75,
                    ),
                  ),
                  child: Text(
                    roomCode,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.orange,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Fallback text ("<sender> started a <game> game") if present
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: KinrelSpacing.sm - 2),
            Text(
              message.content,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver.withValues(alpha: 0.85),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: KinrelSpacing.sm + 2),
          if (isMe)
            // Sender is already in the game — status label, no Join button.
            Row(
              children: [
                Icon(
                  status == 'accepted'
                      ? Icons.play_circle_outline
                      : (status == 'expired' || status == 'cancelled')
                          ? Icons.event_busy
                          : Icons.hourglass_top,
                  size: 14,
                  color: KinrelColors.textDim,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    waitingLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ),
              ],
            )
          else
            // Join button — same route as GameInviteListener._acceptInvite.
            SizedBox(
              width: double.infinity,
              child: Material(
                color: canJoin
                    ? KinrelColors.orange
                    : KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.sm),
                child: InkWell(
                  onTap: canJoin ? () => _joinGameFromCard(context) : null,
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        canJoin ? 'Join' : (disabledLabel ?? 'Join'),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: canJoin
                              ? KinrelColors.textWhite
                              : KinrelColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Navigate into the game lobby from a chat invite card.
  ///
  /// Replicates GameInviteListener._acceptInvite's join route exactly
  /// (GameInvite.joinRoute): '/family/<familyId>/<gameType>/lobby?join=<gameId>'.
  /// The lobby screen picks up the `join` query param and joins the room.
  void _joinGameFromCard(BuildContext context) {
    final gameType = message.gameType ?? '';
    final gameId = message.gameId ?? '';
    if (gameType.isEmpty || gameId.isEmpty || familyId == null) return;
    context.go('/family/$familyId/$gameType/lobby?join=$gameId');
  }

  /// Title-case fallback for game types not in the GameType enum
  /// (e.g. 'somegame' → 'Somegame', 'my-game' → 'My Game').
  String _titleCaseSegment(String s) {
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'[-_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
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
                Text(
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
                  style: TextStyle(
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

  Widget _buildReactions(String? currentUserId) {
    final grouped = message.groupedReactions;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasMyReaction
                    ? KinrelColors.orange.withValues(alpha: 0.12)
                    : const Color(0xFF202338),
                borderRadius: BorderRadius.circular(KinrelRadius.xl),
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
                  Text(entry.key, style: TextStyle(fontSize: 13)),
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
