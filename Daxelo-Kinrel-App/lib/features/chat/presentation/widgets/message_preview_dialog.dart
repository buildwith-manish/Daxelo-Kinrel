// lib/features/chat/presentation/widgets/message_preview_dialog.dart
//
// DAXELO KINREL — Shared message peek-preview dialog (group + DM)
//
// Tier 3 / Peek Preview — a full-screen overlay showing a message in a
// larger format (especially useful for long text messages that are
// truncated in the bubble). Tap anywhere to dismiss.
//
// EXTRACTED (moved, not rewritten) from chat_screen.dart's
// _showMessagePreview so the DM long-press sheet can offer the SAME
// "Preview" action as the group chat. The rendering is byte-for-byte
// identical to the previous inline version; the group chat now
// delegates to this function.
//
// Works for any ChatMessage regardless of origin (group row or DM
// adapter conversion): photo/gif paths render the media URL when
// present, everything else renders selectable text.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/image_cache_manager.dart';
import '../../providers/chat_provider.dart';

/// Opens the peek-preview overlay for [message].
///
/// Call from any chat screen's message-action sheet. Dismiss on tap.
void showMessagePeekPreview(BuildContext context, ChatMessage message) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.of(ctx).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: GestureDetector(
            onTap: () {}, // prevent tap-through dismissal when
            // tapping the card itself
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(ctx).size.width * 0.85,
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF11132A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: sender name + timestamp
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              KinrelColors.ember.withValues(alpha: 0.15),
                          child: Text(
                            (message.senderName.isNotEmpty
                                ? message.senderName[0]
                                : '?')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.ember,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.senderName,
                                style: const TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: KinrelColors.textWhite,
                                ),
                              ),
                              Text(
                                message.formattedTime,
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
                    const SizedBox(height: 16),
                    // Content — render based on message type
                    if (message.messageType == MessageType.photo &&
                        message.mediaUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: message.mediaUrl!,
                          cacheManager: KinrelImageCacheManager.instance,
                          fit: BoxFit.contain,
                          // Phase 4 — cap decode at the info-sheet's
                          // visible width (sheet is ~screen-wide × 0.85,
                          // so use screenWidth × DPR × 0.9 as a safe
                          // upper bound for the decoded bitmap).
                          memCacheWidth: (MediaQuery.sizeOf(ctx).width *
                                  MediaQuery.devicePixelRatioOf(ctx) *
                                  0.9)
                              .round(),
                          placeholder: (_, __) => Container(
                            height: 200,
                            color: const Color(0xFF0A0B16),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: KinrelColors.ember),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 200,
                            color: const Color(0xFF0A0B16),
                            child: const Center(
                              child: Icon(Icons.broken_image,
                                  color: KinrelColors.textDim, size: 40),
                            ),
                          ),
                        ),
                      )
                    else if (message.messageType == MessageType.gif &&
                        message.mediaUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: message.mediaUrl!,
                          cacheManager: KinrelImageCacheManager.instance,
                          fit: BoxFit.contain,
                          // Phase 4 — cap decode at 360×360*DPR (the
                          // sheet is wider than the bubble, so the cap
                          // is slightly higher than the bubble's 220).
                          memCacheWidth:
                              (360 * MediaQuery.devicePixelRatioOf(ctx))
                                  .round(),
                          memCacheHeight:
                              (360 * MediaQuery.devicePixelRatioOf(ctx))
                                  .round(),
                        ),
                      )
                    else
                      SelectableText(
                        message.content,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 16,
                          color: KinrelColors.textWhite,
                          height: 1.6,
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Footer: close hint
                    const Center(
                      child: Text(
                        'Tap anywhere to close',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: KinrelColors.textDim,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
