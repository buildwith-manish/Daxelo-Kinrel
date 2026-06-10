// lib/features/profile/presentation/member_timeline_screen.dart
// DAXELO KINREL — Member Timeline / Milestones Screen
//
// Displays a vertical timeline of life milestones for a family member.
// Features: profile header, timeline with orange line and node dots,
// add milestone FAB (for own profile or family admins).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../family/providers/member_detail_provider.dart';
import '../providers/member_timeline_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

class MemberTimelineScreen extends ConsumerStatefulWidget {
  const MemberTimelineScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<MemberTimelineScreen> createState() =>
      _MemberTimelineScreenState();
}

class _MemberTimelineScreenState extends ConsumerState<MemberTimelineScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final detailAsync = ref.watch(memberDetailProvider(widget.memberId));
    final timelineAsync = ref.watch(memberTimelineProvider(widget.memberId));

    return Scaffold(
      backgroundColor: _cBg,
      appBar: AppBar(
        backgroundColor: _cBg,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _cCard.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 16,
              color: _cTextPrimary,
            ),
          ),
          onPressed: () => context.pop(),
        ),
        title: detailAsync.when(
          loading: () => Text(
            'Life Timeline',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
          error: (_, __) => Text('Life Timeline'),
          data: (detail) => Text(
            '${detail.name} \u2014 Life Timeline',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
        ),
      ),
      body: detailAsync.when(
        loading: () => _buildLoadingState(),
        error: (err, _) => DKErrorState(
          message: 'Failed to load member',
          onRetry: () => ref.invalidate(memberDetailProvider(widget.memberId)),
        ),
        data: (detail) => timelineAsync.when(
          loading: () => _buildLoadingState(),
          error: (err, _) => DKErrorState(
            message: 'Failed to load timeline',
            onRetry: () => ref.invalidate(memberTimelineProvider(widget.memberId)),
          ),
          data: (items) {
            if (items.isEmpty) {
              return DKEmptyState(
                icon: Icons.timeline,
                title: 'No milestones yet',
                subtitle: 'Add the first one!',
              ).animate().fadeIn(duration: 400.ms);
            }
            return RefreshIndicator(
              color: _cOrange,
              backgroundColor: _cCard,
              onRefresh: () async {
                ref.invalidate(memberTimelineProvider(widget.memberId));
              },
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Profile header
                  SliverToBoxAdapter(
                    child: _buildProfileHeader(detail)
                        .animate()
                        .fadeIn(duration: 350.ms),
                  ),

                  // Timeline items
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base,
                      vertical: 8,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _TimelineItemCard(
                            item: items[index],
                            isLast: index == items.length - 1,
                          )
                              .animate()
                              .fadeIn(
                                duration: 300.ms,
                                delay: (index * 50).ms,
                              )
                              .slideX(begin: -0.05, end: 0);
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),

                  // Bottom padding for FAB
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 100),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: _shouldShowFAB()
          ? Container(
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _cOrange.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: _showAddMilestoneSheet,
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: Icon(Icons.add, size: 28, color: Colors.white),
              ),
            )
          : null,
    );
  }

  // ── Profile Header ─────────────────────────────────────────────

  Widget _buildProfileHeader(MemberDetailModel detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Row(
        children: [
          // Avatar (80px)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: KinrelGradients.igniteGradient,
            ),
            child: Container(
              margin: EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cCard,
              ),
              child: Center(
                child: Text(
                  detail.name
                      .split(' ')
                      .where((w) => w.isNotEmpty)
                      .take(2)
                      .map((w) => w[0].toUpperCase())
                      .join(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _cOrange,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Name + kinship + join date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (detail.kinshipNameToUser != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: KinrelGradients.igniteGradient,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                    ),
                    child: Text(
                      'Your ${detail.kinshipNameToUser}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                if (detail.age != null)
                  Text(
                    '${detail.age} years old',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cTextDim,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading State ──────────────────────────────────────────────

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DKLoadingShimmer(
              width: double.infinity,
              height: 100,
              radius: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ── FAB visibility check ───────────────────────────────────────

  bool _shouldShowFAB() {
    try {
      final client = ref.read(supabaseProvider);
      final currentUserId = client?.auth.currentUser?.id;
      // Show FAB if viewing own profile
      if (currentUserId == widget.memberId) return true;
      // TODO: Check if user is family admin
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Add Milestone Bottom Sheet ─────────────────────────────────

  void _showAddMilestoneSheet() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    String selectedType = 'milestone';

    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: KinrelSpacing.base,
                right: KinrelSpacing.base,
                top: KinrelSpacing.xl,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + KinrelSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _cTextDim.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'Add Milestone',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _cTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title input
                  TextField(
                    controller: titleController,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: _cTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Milestone title',
                      hintStyle: TextStyle(color: _cTextDim),
                      filled: true,
                      fillColor: _cElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date picker
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: _cOrange,
                                surface: _cCard,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 18, color: _cOrange),
                          const SizedBox(width: 10),
                          Text(
                            selectedDate != null
                                ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                                : 'Select date',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              color: _cTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Description input
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: _cTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Description (optional)',
                      hintStyle: TextStyle(color: _cTextDim),
                      filled: true,
                      fillColor: _cElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: DKButton(
                      label: 'Add Milestone',
                      variant: DKButtonVariant.gradient,
                      size: DKButtonSize.lg,
                      fullWidth: true,
                      onPressed: () async {
                        if (titleController.text.trim().isEmpty) return;
                        HapticFeedback.mediumImpact();
                        await _submitMilestone(
                          title: titleController.text.trim(),
                          date: selectedDate ?? DateTime.now(),
                          description: descController.text.trim(),
                        );
                        if (mounted) {
                          Navigator.pop(ctx);
                          ref.invalidate(
                              memberTimelineProvider(widget.memberId));
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitMilestone({
    required String title,
    required DateTime date,
    String? description,
  }) async {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;

      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final families = ref.read(familyListProvider).valueOrNull ?? [];
      if (families.isEmpty) return;

      final familyId = families.first.id;

      await client.from('FamilyPost').insert({
        'familyId': familyId,
        'authorId': widget.memberId,
        'postType': 'milestone',
        'content': {
          'milestoneType': 'custom',
          'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
        },
        'reactions': {
          'heart': 0,
          'comment': 0,
          'isHearted': false,
          'isSaved': false,
        },
      });
    } catch (e) {
      debugPrint('⚠️ Milestone submit error: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Timeline Item Card — vertical timeline with orange line and dots
// ═══════════════════════════════════════════════════════════════════════

class _TimelineItemCard extends StatelessWidget {
  const _TimelineItemCard({
    required this.item,
    required this.isLast,
  });

  final TimelineItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line & dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Node dot
                Container(
                  width: item.isMajor ? 16 : 12,
                  height: item.isMajor ? 16 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.isMajor ? _cOrange : Colors.transparent,
                    border: item.isMajor
                        ? null
                        : Border.all(color: _cOrange, width: 2),
                    boxShadow: item.isMajor
                        ? [
                            BoxShadow(
                              color: _cOrange.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: item.isMajor
                      ? Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _cBg,
                            ),
                          ),
                        )
                      : null,
                ),
                // Vertical orange line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        gradient: KinrelGradients.timelineGradient,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Card content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getTypeColor(item.type).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type badge + year
                    Row(
                      children: [
                        // Type badge with emoji
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _getTypeColor(item.type).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(KinrelRadius.full),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.type.emoji,
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item.type.label,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.monoFont,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: _getTypeColor(item.type),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Year label
                        Text(
                          '${item.date.year}',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 11,
                            color: _cTextDim,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Title
                    Text(
                      item.title,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _cTextPrimary,
                        height: 1.3,
                      ),
                    ),

                    // Subtitle
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: _cTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(TimelineItemType type) {
    switch (type) {
      case TimelineItemType.birth:
        return KinrelColors.amber;
      case TimelineItemType.joinedFamily:
        return _cOrange;
      case TimelineItemType.relationshipAdded:
        return KinrelColors.blue;
      case TimelineItemType.milestonePost:
        return KinrelColors.gold;
      case TimelineItemType.memberJoined:
        return KinrelColors.success;
    }
  }
}
