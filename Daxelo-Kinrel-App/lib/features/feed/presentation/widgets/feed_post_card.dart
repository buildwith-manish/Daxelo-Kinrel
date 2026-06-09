// lib/features/feed/presentation/widgets/feed_post_card.dart
// DAXELO KINREL — Unified Feed Post Card Widget
//
// Instagram-style post card for the unified home feed.
// Shows author info, family badge, post content (text/image),
// reaction row, comment count, and relationship context chip.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/services/image_cache_manager.dart';
import '../../providers/feed_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

/// Reaction emoji list for the post card
const _reactionEmojis = ['👍', '❤️', '😂', '😮'];

class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.onHeart,
    required this.onReact,
  });

  final FamilyPost post;
  final VoidCallback onHeart;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 6,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author header
            _FeedPostHeader(post: post),

            // Post body content
            _FeedPostBody(post: post),

            // Reaction row
            _FeedReactionRow(
              post: post,
              onHeart: onHeart,
              onReact: onReact,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.05, end: 0);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Post Header — Author avatar + name + family badge + timestamp
// ═══════════════════════════════════════════════════════════════════════

class _FeedPostHeader extends StatelessWidget {
  const _FeedPostHeader({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Row(
        children: [
          // Author avatar (36px, ignite gradient)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: KinrelGradients.igniteGradient,
            ),
            child: Center(
              child: Text(
                (post.authorName ?? post.familyName ?? 'F')[0].toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Author name + username + family badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.authorName ?? 'Family Member',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _cTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (post.authorUsername != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '@${post.authorUsername}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: _cOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Family name badge (orange pill)
                if (post.familyName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _cOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: _cOrange.withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_outlined,
                          size: 10,
                          color: _cOrange,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          post.familyName!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _cOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Timestamp
          Text(
            post.timeAgo,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: _cTextDim,
            ),
          ),

          // Three-dot menu
          IconButton(
            icon: Icon(Icons.more_horiz_rounded, size: 20, color: _cTextDim),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Post Body — Text content + optional image
// ═══════════════════════════════════════════════════════════════════════

class _FeedPostBody extends StatelessWidget {
  const _FeedPostBody({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    final text = post.content['text'] as String? ?? '';
    final mediaUrl = post.content['mediaUrl'] as String?;
    final occasion = post.content['occasion'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Occasion badge (if present)
          if (occasion != null && occasion.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KinrelColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(KinrelRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.celebration_outlined, size: 12, color: KinrelColors.gold),
                  const SizedBox(width: 4),
                  Text(
                    occasion,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: KinrelColors.gold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Post text
          if (text.isNotEmpty)
            Text(
              text,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextSecondary,
                height: 1.5,
              ),
            ),

          // Post image (if present)
          if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: CachedNetworkImage(
                  cacheManager: KinrelImageCacheManager.instance,
                  imageUrl: mediaUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: _cElevated,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _cOrange,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 120,
                    color: _cElevated,
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: _cTextDim,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Relationship context chip
          if (post.familyName != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _cElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '👨‍👩‍👧',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Member of ${post.familyName!} Family',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: _cTextDim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reaction Row — Emoji reactions + comment count + bookmark
// ═══════════════════════════════════════════════════════════════════════

class _FeedReactionRow extends StatefulWidget {
  const _FeedReactionRow({
    required this.post,
    required this.onHeart,
    required this.onReact,
  });

  final FamilyPost post;
  final VoidCallback onHeart;
  final void Function(String emoji) onReact;

  @override
  State<_FeedReactionRow> createState() => _FeedReactionRowState();
}

class _FeedReactionRowState extends State<_FeedReactionRow> {
  final Map<String, bool> _localReactions = {};

  @override
  Widget build(BuildContext context) {
    final reactions = widget.post.reactions;
    final reactionCounts = (reactions['reactionCounts'] as Map<String, dynamic>?) ?? {};

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        children: [
          // Divider
          Container(
            height: 0.5,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 10),

          // Reaction emoji row
          Row(
            children: [
              // Emoji reaction buttons
              ..._reactionEmojis.map((emoji) {
                final count = (reactionCounts[emoji] as int?) ?? 0;
                final isActive = _localReactions[emoji] ?? false;

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _localReactions[emoji] = !(_localReactions[emoji] ?? false);
                      });
                      if (emoji == '❤️') {
                        widget.onHeart();
                      } else {
                        widget.onReact(emoji);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _cOrange.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                        border: isActive
                            ? Border.all(
                                color: _cOrange.withValues(alpha: 0.3),
                                width: 0.5,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: TextStyle(fontSize: 16)),
                          if (count > 0 || isActive) ...[
                            const SizedBox(width: 3),
                            Text(
                              '${count + (isActive ? 1 : 0)}',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isActive ? _cOrange : _cTextDim,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const Spacer(),

              // Comment count chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _cElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: _cTextDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.post.commentCount}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: _cTextDim,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Share button
              GestureDetector(
                onTap: () {},
                child: Icon(
                  Icons.send_outlined,
                  size: 18,
                  color: _cTextDim,
                ),
              ),

              const SizedBox(width: 8),

              // Bookmark
              GestureDetector(
                onTap: () {},
                child: Icon(
                  widget.post.isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 18,
                  color: widget.post.isSaved ? _cOrange : _cTextDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
