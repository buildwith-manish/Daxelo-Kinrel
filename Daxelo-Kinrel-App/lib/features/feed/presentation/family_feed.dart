// lib/features/feed/presentation/family_feed.dart
//
// DAXELO KINREL — Instagram-style Family Feed Widget
//
// 5 post types: Relationship Discovered, Member Joined,
// Milestone, Connection Added, Invite Shared.
// Each has a unique visual design using the Kinrel dark theme.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/feed_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

// ── Main Family Feed Widget ──────────────────────────────────────

class FamilyFeed extends ConsumerStatefulWidget {
  const FamilyFeed({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilyFeed> createState() => _FamilyFeedState();
}

class _FamilyFeedState extends ConsumerState<FamilyFeed> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initFeed().catchError((e) {
      debugPrint('⚠️ FamilyFeed init failed (no session?): $e');
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initFeed() async {
    try {
      final feedNotifier = ref.read(feedProvider.notifier);
      // Try to generate posts from existing data first
      await feedNotifier.generatePostsFromFamilyData(widget.familyId);
      // Then load the feed
      await feedNotifier.loadFeed(widget.familyId);
    } catch (e) {
      debugPrint('⚠️ FamilyFeed._initFeed error: $e');
      // Don't rethrow — the feed will show empty state
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(feedProvider.notifier).loadMore(widget.familyId);
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(feedProvider.notifier).loadFeed(widget.familyId);
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);

    if (feedState.isLoading) {
      return _buildLoadingShimmer();
    }

    if (feedState.error != null && feedState.posts.isEmpty) {
      return _buildErrorState(feedState.error!);
    }

    if (feedState.posts.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: _cOrange,
      backgroundColor: _cCard,
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: feedState.posts.length + (feedState.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == feedState.posts.length) {
            return _buildLoadingMoreIndicator();
          }
          return _FeedPostCard(
            post: feedState.posts[index],
            onHeart: () => ref
                .read(feedProvider.notifier)
                .toggleHeart(feedState.posts[index].id),
            onSave: () => ref
                .read(feedProvider.notifier)
                .toggleSave(feedState.posts[index].id),
          ).animate().fadeIn(duration: 300.ms, delay: (index * 50).ms);
        },
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DKLoadingShimmer(
              width: double.infinity,
              height: 280,
              radius: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: KinrelColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load feed',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _cTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            DKButton(
              label: 'Retry',
              variant: DKButtonVariant.primary,
              onPressed: _initFeed,
              size: DKButtonSize.md,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: KinrelGradients.igniteGradient.colors
                      .map((c) => c.withValues(alpha: 0.12))
                      .toList(),
                  begin: KinrelGradients.igniteGradient.begin,
                  end: KinrelGradients.igniteGradient.end,
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 36,
                color: _cOrange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No family moments yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add members and create relationships to see your family story here!',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: _cOrange),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Feed Post Card — Instagram-style with post type-specific visuals
// ═══════════════════════════════════════════════════════════════════════

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.onHeart,
    required this.onSave,
  });

  final FamilyPost post;
  final VoidCallback onHeart;
  final VoidCallback onSave;

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
            // Post Header
            _PostHeader(post: post),

            // Post Content (type-specific)
            _PostContent(post: post),

            // Post Footer
            _PostFooter(post: post, onHeart: onHeart, onSave: onSave),
          ],
        ),
      ),
    );
  }
}

// ── Post Header ──────────────────────────────────────────────────

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Row(
        children: [
          // Family avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: KinrelGradients.igniteGradient,
            ),
            child: Center(
              child: Text(
                (post.familyName ?? 'F')[0].toUpperCase(),
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

          // Family username + author
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${post.familyUsername ?? post.familyName?.toLowerCase().replaceAll(' ', '_') ?? 'family'}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
                if (post.authorName != null)
                  Text(
                    post.authorName!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: _cTextDim,
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

// ── Post Content (type-specific routing) ──────────────────────────

class _PostContent extends StatelessWidget {
  const _PostContent({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    switch (post.postType) {
      case FeedPostType.relationshipDiscovered:
        return _RelationshipDiscoveredContent(post: post);
      case FeedPostType.memberJoined:
        return _MemberJoinedContent(post: post);
      case FeedPostType.milestone:
        return _MilestoneContent(post: post);
      case FeedPostType.connectionAdded:
        return _ConnectionAddedContent(post: post);
      case FeedPostType.inviteShared:
        return _InviteSharedContent(post: post);
    }
  }
}

// ── TYPE A — Relationship Discovered ──────────────────────────────

class _RelationshipDiscoveredContent extends StatelessWidget {
  const _RelationshipDiscoveredContent({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    final personA = post.content['personA'] as String? ?? '';
    final personB = post.content['personB'] as String? ?? '';
    final kinshipTerm = post.content['kinshipTerm'] as String? ?? '';
    final terms = post.content['kinshipTerms'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFE8612A), Color(0xFF4A1A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Sparkle icon in corner
          Positioned(
            top: 0,
            right: 0,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Relationship text
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: personA),
                    TextSpan(
                      text: ' is ',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                    TextSpan(
                      text: '$personB\'s $kinshipTerm',
                      style: TextStyle(color: Color(0xFFF59240)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Language chips
              if (terms.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: terms.map<Widget>((term) {
                    final t = term as Map<String, dynamic>;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        t['term'] as String? ?? '',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── TYPE B — New Member Joined ────────────────────────────────────

class _MemberJoinedContent extends StatelessWidget {
  const _MemberJoinedContent({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    final memberName = post.content['memberName'] as String? ?? 'New Member';
    final familyUsername =
        post.content['familyUsername'] as String? ?? 'family';
    final gender = post.content['memberGender'] as String?;

    final emoji = gender == 'male'
        ? '👨'
        : gender == 'female'
        ? '👩'
        : '🧑';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _cElevated,
        border: Border.all(color: _cOrange.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _cOrange.withValues(alpha: 0.08),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Large member avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: KinrelGradients.igniteGradient,
              boxShadow: [
                BoxShadow(
                  color: _cOrange.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(child: Text(emoji, style: TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 14),

          // Member name
          Text(
            memberName,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
          const SizedBox(height: 4),

          // Joined text
          Text(
            'joined @$familyUsername',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _cTextSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Welcome button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _cOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _cOrange.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome them!',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cOrange,
                  ),
                ),
                const SizedBox(width: 6),
                Text('🙏', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TYPE C — Family Milestone ──────────────────────────────────────

class _MilestoneContent extends StatelessWidget {
  const _MilestoneContent({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    final milestoneValue = post.content['milestoneValue'] as int? ?? 1;
    final milestoneType =
        post.content['milestoneType'] as String? ?? 'generations';
    final memberNames =
        (post.content['memberNames'] as List?)?.cast<String>() ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(
          color: Color(0xFFF5A623).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Bold milestone number
          Text(
            '$milestoneValue ${milestoneType == 'generations' ? 'Generations' : 'Members'}',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Color(0xFFF5A623),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle
          Text(
            'Your family now spans $milestoneValue generations!',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _cTextSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Stacked avatars row
          if (memberNames.isNotEmpty)
            SizedBox(
              height: 36,
              child: Stack(
                children: List.generate(
                  memberNames.length.clamp(0, 5),
                  (i) => Positioned(
                    left: i * 24.0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: KinrelGradients.igniteGradient,
                        border: Border.all(
                          color: Color(0xFF0D1B2A),
                          width: 2.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          memberNames[i][0].toUpperCase(),
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
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
}

// ── TYPE D — Connection Added ──────────────────────────────────────

class _ConnectionAddedContent extends StatelessWidget {
  const _ConnectionAddedContent({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    final fromName = post.content['fromName'] as String? ?? 'Person A';
    final toName = post.content['toName'] as String? ?? 'Person B';
    final fromGender = post.content['fromGender'] as String?;
    final toGender = post.content['toGender'] as String?;
    final relationshipKey =
        post.content['relationshipKey'] as String? ?? 'related to';
    final terms = post.content['kinshipTerms'] as List? ?? [];

    final fromEmoji = fromGender == 'male'
        ? '👨'
        : fromGender == 'female'
        ? '👧'
        : '🧑';
    final toEmoji = toGender == 'male'
        ? '👨'
        : toGender == 'female'
        ? '👧'
        : '🧑';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _cElevated,
      ),
      child: Column(
        children: [
          // Two avatars with arrow
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Person A
              Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: Center(
                      child: Text(fromEmoji, style: TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fromName.split(' ').first,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _cTextPrimary,
                    ),
                  ),
                ],
              ),

              // Arrow with relationship label
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: _cOrange,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _cOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        relationshipKey.replaceAll('_', ' '),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _cOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Person B
              Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.heritageGradient,
                    ),
                    child: Center(
                      child: Text(toEmoji, style: TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    toName.split(' ').first,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _cTextPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Language chips
          if (terms.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: terms.map<Widget>((term) {
                final t = term as Map<String, dynamic>;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t['term'] as String? ?? '',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cTextSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── TYPE E — Invite Shared ──────────────────────────────────────

class _InviteSharedContent extends StatelessWidget {
  const _InviteSharedContent({required this.post});

  final FamilyPost post;

  @override
  Widget build(BuildContext context) {
    final username =
        post.content['username'] as String? ?? post.authorUsername ?? 'user';
    final inviteCode = post.content['inviteCode'] as String? ?? 'XXXX-XXXX';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _cElevated,
      ),
      child: Column(
        children: [
          // Share icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cOrange.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.ios_share_rounded, size: 22, color: _cOrange),
          ),
          const SizedBox(height: 12),

          // Text
          Text(
            '@$username shared a family invite',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _cTextSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Invite code card (ticket stub design)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // Dashed line (ticket tear)
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(
                              (constraints.maxWidth / 8).floor(),
                              (_) => Container(
                                width: 4,
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Invite code
                Text(
                  inviteCode,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _cOrange,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),

                // Copy button
                GestureDetector(
                  onTap: () {
                    // TODO: Copy invite code to clipboard
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _cOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 14, color: _cOrange),
                        const SizedBox(width: 6),
                        Text(
                          'Copy Code',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _cOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Post Footer ──────────────────────────────────────────────────

class _PostFooter extends StatefulWidget {
  const _PostFooter({
    required this.post,
    required this.onHeart,
    required this.onSave,
  });

  final FamilyPost post;
  final VoidCallback onHeart;
  final VoidCallback onSave;

  @override
  State<_PostFooter> createState() => _PostFooterState();
}

class _PostFooterState extends State<_PostFooter> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Row(
        children: [
          // Heart
          _ReactionButton(
            icon: widget.post.isHearted
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            count: widget.post.heartCount,
            isActive: widget.post.isHearted,
            activeColor: Colors.redAccent,
            onTap: widget.onHeart,
          ),
          const SizedBox(width: 16),

          // Comment
          _ReactionButton(
            icon: Icons.chat_bubble_outline_rounded,
            count: widget.post.commentCount,
            isActive: false,
            activeColor: _cOrange,
            onTap: () {},
          ),
          const SizedBox(width: 16),

          // Share
          _ReactionButton(
            icon: Icons.send_outlined,
            count: null,
            isActive: false,
            activeColor: _cOrange,
            onTap: () {},
          ),

          const Spacer(),

          // Save/Bookmark
          GestureDetector(
            onTap: widget.onSave,
            child: Icon(
              widget.post.isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              size: 22,
              color: widget.post.isSaved ? _cOrange : _cTextDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.count,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final int? count;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: isActive ? activeColor : _cTextDim),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? activeColor : _cTextDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
