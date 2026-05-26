// lib/features/memories/presentation/memories_screen.dart
//
// DAXELO KINREL — Memories & Timeline Screen
//
// Family Timeline: Vertical timeline with orange gradient line,
// glow nodes, event cards (#191B2C, radius 14px).
// "On This Day" horizontal scroll cards with date overlay.
// Filter chips: Year, Event Type, Family Member.
// FAB: Add memory (orange gradient).
//
// Orange K-Graph DNA: #13141E bg, #191B2C cards, #E8612A accent,
// timeline gradient (#E8612A → #F59240), glow nodes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/memories_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Memories & Timeline Screen
// ═══════════════════════════════════════════════════════════════════════

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen>
    with TickerProviderStateMixin {
  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: KinrelMotion.slow,
    )..forward();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoriesProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),

              // ── On This Day (if any) ──────────────────────────────
              if (state.hasOnThisDay)
                SliverToBoxAdapter(
                  child: _buildOnThisDaySection(state.onThisDayMemories),
                ),

              // ── Filter Chips ──────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildFilterChips(state),
              ),

              // ── Timeline ──────────────────────────────────────────
              if (state.filteredEvents.isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptyState(),
                )
              else
                _buildTimeline(state.filteredEvents),
            ],
          ),

          // ── FAB: Add Memory ────────────────────────────────────────
          Positioned(
            right: KinrelSpacing.base,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: _buildFAB(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Header
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.xl,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.access_time_rounded,
              color: KinrelColors.orange,
              size: 22,
            ),
          ),
          SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Text(
              'Memories & Timeline',
              style: KinrelTypography.headlineLarge.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Pin count badge
          Consumer(builder: (context, ref, _) {
            final pinnedCount = ref.watch(memoriesProvider
                .select((s) => s.events.where((e) => e.isPinned).length));
            if (pinnedCount == 0) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.push_pin_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '$pinnedCount',
                    style: KinrelTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // On This Day Section
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildOnThisDaySection(List<OnThisDayMemory> memories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            KinrelSpacing.base,
            KinrelSpacing.md,
            KinrelSpacing.base,
            KinrelSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.today_rounded,
                color: KinrelColors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'On This Day',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Text(
                  '${memories.length}',
                  style: KinrelTypography.labelSmall.copyWith(
                    color: KinrelColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _OnThisDayCard(memory: memories[index]);
            },
          ),
        ),
        SizedBox(height: KinrelSpacing.md),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Filter Chips
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFilterChips(MemoriesState state) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Year filter
              Expanded(child: _FilterChipButton(
                label: state.filter.selectedYear != null
                    ? '${state.filter.selectedYear}'
                    : 'Year',
                icon: Icons.calendar_today_rounded,
                isActive: state.filter.selectedYear != null,
                onTap: () => _showYearFilterSheet(state),
              )),
              const SizedBox(width: 8),
              // Event type filter
              Expanded(child: _FilterChipButton(
                label: state.filter.selectedType != null
                    ? state.filter.selectedType!.typeLabel
                    : 'Event Type',
                icon: Icons.filter_list_rounded,
                isActive: state.filter.selectedType != null,
                onTap: () => _showTypeFilterSheet(state),
              )),
              const SizedBox(width: 8),
              // Member filter
              Expanded(child: _FilterChipButton(
                label: state.filter.selectedMember != null
                    ? state.filter.selectedMember!.split(' ').first
                    : 'Member',
                icon: Icons.person_rounded,
                isActive: state.filter.selectedMember != null,
                onTap: () => _showMemberFilterSheet(state),
              )),
            ],
          ),
          // Clear filters
          if (!state.filter.isClear)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => ref.read(memoriesProvider.notifier).clearFilters(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: KinrelColors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Clear filters',
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Filter Sheets
  // ═══════════════════════════════════════════════════════════════════

  void _showYearFilterSheet(MemoriesState state) {
    final years = state.availableYears;
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Text(
                      'Filter by Year',
                      style: KinrelTypography.headlineMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (state.filter.selectedYear != null)
                      TextButton(
                        onPressed: () {
                          ref.read(memoriesProvider.notifier).setYearFilter(null);
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    final isSelected = state.filter.selectedYear == year;
                    return ListTile(
                      title: Text(
                        '$year',
                        style: KinrelTypography.bodyLarge.copyWith(
                          color: isSelected ? KinrelColors.orange : KinrelColors.textWhite,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: KinrelColors.orange, size: 20)
                          : null,
                      onTap: () {
                        ref.read(memoriesProvider.notifier).setYearFilter(year);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTypeFilterSheet(MemoriesState state) {
    final types = MemoryEventType.values;
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Text(
                      'Filter by Event Type',
                      style: KinrelTypography.headlineMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (state.filter.selectedType != null)
                      TextButton(
                        onPressed: () {
                          ref.read(memoriesProvider.notifier).setTypeFilter(null);
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: types.length,
                  itemBuilder: (context, index) {
                    final type = types[index];
                    final isSelected = state.filter.selectedType == type;
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: type.accentColor.withValues(alpha: 0.15),
                        ),
                        child: Icon(type.icon, size: 18, color: type.accentColor),
                      ),
                      title: Text(
                        type.typeLabel,
                        style: KinrelTypography.bodyLarge.copyWith(
                          color: isSelected ? type.accentColor : KinrelColors.textWhite,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_rounded, color: type.accentColor, size: 20)
                          : null,
                      onTap: () {
                        ref.read(memoriesProvider.notifier).setTypeFilter(type);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMemberFilterSheet(MemoriesState state) {
    final members = state.availableMembers;
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Text(
                      'Filter by Family Member',
                      style: KinrelTypography.headlineMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (state.filter.selectedMember != null)
                      TextButton(
                        onPressed: () {
                          ref.read(memoriesProvider.notifier).setMemberFilter(null);
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isSelected = state.filter.selectedMember == member;
                    final initials = member
                        .split(' ')
                        .where((s) => s.isNotEmpty)
                        .take(2)
                        .map((s) => s[0].toUpperCase())
                        .join();
                    return ListTile(
                      leading: DKAvatar(
                        initials: initials,
                        size: DKAvatarSize.sm,
                        backgroundColor: isSelected
                            ? KinrelColors.orange.withValues(alpha: 0.3)
                            : null,
                      ),
                      title: Text(
                        member,
                        style: KinrelTypography.bodyLarge.copyWith(
                          color: isSelected ? KinrelColors.orange : KinrelColors.textWhite,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: KinrelColors.orange, size: 20)
                          : null,
                      onTap: () {
                        ref.read(memoriesProvider.notifier).setMemberFilter(member);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Timeline
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTimeline(List<MemoryEvent> events) {
    return SliverList(
      delegate: SliverChildBuilderWithFooter(
        childCount: events.length,
        footer: SizedBox(height: 100), // Space for FAB
        builder: (context, index) {
          final event = events[index];
          final isFirst = index == 0;
          final isLast = index == events.length - 1;
          return _TimelineEventCard(
            event: event,
            isFirst: isFirst,
            isLast: isLast,
            onPin: () => ref.read(memoriesProvider.notifier).togglePin(event.id),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Empty State
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.orange.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  size: 40,
                  color: KinrelColors.orange,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No memories found',
                style: KinrelTypography.headlineMedium.copyWith(
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters or add\nyour first family memory!',
                textAlign: TextAlign.center,
                style: KinrelTypography.bodyMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 24),
              DKButton(
                label: 'Add First Memory',
                variant: DKButtonVariant.gradient,
                icon: Icons.add_rounded,
                size: DKButtonSize.md,
                onPressed: () => _showAddMemorySheet(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // FAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFAB() {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _fabController,
        curve: KinrelMotion.spring,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          gradient: KinrelGradients.igniteGradient,
          boxShadow: [
            BoxShadow(
              color: KinrelColors.orangeGlowIntense,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            onTap: () => _showAddMemorySheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Add Memory',
                    style: KinrelTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Add Memory Sheet
  // ═══════════════════════════════════════════════════════════════════

  void _showAddMemorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
      ),
      builder: (context) {
        return _AddMemorySheet();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// On This Day Card
// ═══════════════════════════════════════════════════════════════════════

class _OnThisDayCard extends StatelessWidget {
  const _OnThisDayCard({required this.memory});

  final OnThisDayMemory memory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo placeholder with date overlay
          Stack(
            children: [
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      memory.members.isNotEmpty
                          ? KinrelColors.orange.withValues(alpha: 0.2)
                          : KinrelColors.darkElevated,
                      KinrelColors.darkCard,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(KinrelRadius.lg),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.photo_camera_rounded,
                    size: 32,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
              // Date overlay (bottom-left)
              Positioned(
                bottom: 8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkSurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: Text(
                    memory.formattedDate,
                    style: KinrelTypography.micro.copyWith(
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ),
              ),
              // Years ago badge (top-right)
              Positioned(
                top: 8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.igniteGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                  ),
                  child: Text(
                    memory.yearsAgoLabel,
                    style: KinrelTypography.micro.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.title,
                  style: KinrelTypography.labelLarge.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (memory.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    memory.description!,
                    style: KinrelTypography.bodySmall.copyWith(
                      color: KinrelColors.textSilver,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (memory.members.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AvatarRow(members: memory.members, maxSize: 22),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Filter Chip Button
// ═══════════════════════════════════════════════════════════════════════

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? KinrelColors.orange.withValues(alpha: 0.15)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: isActive
                ? KinrelColors.orange.withValues(alpha: 0.4)
                : const Color(0xFF3A3A4A),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? KinrelColors.orange : KinrelColors.textDim,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: KinrelTypography.labelSmall.copyWith(
                  color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Timeline Event Card
// ═══════════════════════════════════════════════════════════════════════

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.onPin,
  });

  final MemoryEvent event;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline Column (line + node) ──────────────────────────
          SizedBox(
            width: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Gradient line
                if (!isLast)
                  Positioned(
                    top: isFirst ? 28 : 0,
                    bottom: 0,
                    left: 27,
                    child: Container(
                      width: 2,
                      decoration: const BoxDecoration(
                        gradient: KinrelGradients.timelineGradient,
                      ),
                    ),
                  ),
                // Top cap for first item
                if (isFirst)
                  Positioned(
                    top: 0,
                    left: 27,
                    child: Container(
                      width: 2,
                      height: 28,
                      decoration: const BoxDecoration(
                        gradient: KinrelGradients.timelineGradient,
                      ),
                    ),
                  ),
                // Glow node
                Positioned(
                  top: 20,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: event.accentColor,
                      boxShadow: [
                        BoxShadow(
                          color: event.accentColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: event.accentColor.withValues(alpha: 0.25),
                          blurRadius: 16,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Event Card ─────────────────────────────────────────────
          Expanded(
            child: Container(
              margin: EdgeInsets.only(
                top: isFirst ? 10 : 8,
                bottom: isLast ? 8 : 12,
                right: KinrelSpacing.base,
              ),
              padding: const EdgeInsets.all(KinrelSpacing.base),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                border: event.isPinned
                    ? Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.4),
                        width: 1.5,
                      )
                    : null,
                boxShadow: event.isPinned
                    ? [
                        BoxShadow(
                          color: KinrelColors.orangeGlowSubtle,
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top row: type badge + pin + date ──────────────────
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: event.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(KinrelRadius.xs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(event.icon, size: 12, color: event.accentColor),
                            const SizedBox(width: 4),
                            Text(
                              event.typeLabel,
                              style: KinrelTypography.micro.copyWith(
                                color: event.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Pin icon
                      if (event.isPinned) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.push_pin_rounded,
                          size: 14,
                          color: KinrelColors.orange,
                        ),
                      ],
                      const Spacer(),
                      // Date
                      Text(
                        event.formattedDate,
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Title ────────────────────────────────────────────
                  Text(
                    event.title,
                    style: KinrelTypography.headlineSmall.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // ── Description ──────────────────────────────────────
                  if (event.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.description!,
                      style: KinrelTypography.bodySmall.copyWith(
                        color: KinrelColors.textSilver,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // ── Location ─────────────────────────────────────────
                  if (event.location != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 13,
                          color: KinrelColors.textDim,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            style: KinrelTypography.labelSmall.copyWith(
                              color: KinrelColors.textDim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // ── Photo placeholder ────────────────────────────────
                  if (event.photoUrl != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 80,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            event.accentColor.withValues(alpha: 0.1),
                            KinrelColors.darkElevated,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_rounded,
                              size: 20,
                              color: KinrelColors.textDim,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'View Photo',
                              style: KinrelTypography.labelSmall.copyWith(
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // ── Member avatars + Pin action ──────────────────────
                  if (event.members.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _AvatarRow(members: event.members)),
                        // Pin toggle
                        GestureDetector(
                          onTap: onPin,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: event.isPinned
                                  ? KinrelColors.orange.withValues(alpha: 0.15)
                                  : KinrelColors.darkElevated,
                            ),
                            child: Icon(
                              event.isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 16,
                              color: event.isPinned
                                  ? KinrelColors.orange
                                  : KinrelColors.textDim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Pin button even without members
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onPin,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: event.isPinned
                                ? KinrelColors.orange.withValues(alpha: 0.15)
                                : KinrelColors.darkElevated,
                          ),
                          child: Icon(
                            event.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 16,
                            color: event.isPinned
                                ? KinrelColors.orange
                                : KinrelColors.textDim,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Avatar Row (overlapping circles)
// ═══════════════════════════════════════════════════════════════════════

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({
    required this.members,
    this.maxSize = 28,
  });

  final List<MemoryMember> members;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    const maxDisplay = 4;
    final displayMembers = members.take(maxDisplay).toList();
    final extraCount = members.length - maxDisplay;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...displayMembers.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          return Padding(
            padding: EdgeInsets.only(left: index > 0 ? -8.0 : 0),
            child: Container(
              width: maxSize,
              height: maxSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
                border: Border.all(
                  color: KinrelColors.darkCard,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  member.displayInitials,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: maxSize * 0.35,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                    height: 1,
                  ),
                ),
              ),
            ),
          );
        }),
        if (extraCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: -8.0),
            child: Container(
              width: maxSize,
              height: maxSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
                border: Border.all(
                  color: KinrelColors.darkCard,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '+$extraCount',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: maxSize * 0.3,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Add Memory Sheet
// ═══════════════════════════════════════════════════════════════════════

class _AddMemorySheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends ConsumerState<_AddMemorySheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  MemoryEventType _selectedType = MemoryEventType.custom;
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              'Add a Memory',
              style: KinrelTypography.headlineLarge.copyWith(
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 20),
            // Event type selector
            Text(
              'Event Type',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: MemoryEventType.values.map((type) {
                final isSelected = _selectedType == type;
                return GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: AnimatedContainer(
                    duration: KinrelMotion.fast,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? type.accentColor.withValues(alpha: 0.2)
                          : KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: isSelected
                            ? type.accentColor.withValues(alpha: 0.5)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon, size: 14, color: isSelected ? type.accentColor : KinrelColors.textDim),
                        const SizedBox(width: 4),
                        Text(
                          type.typeLabel,
                          style: KinrelTypography.labelSmall.copyWith(
                            color: isSelected ? type.accentColor : KinrelColors.textSilver,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Title input
            _buildInputField(
              controller: _titleController,
              hint: 'Memory title',
              icon: Icons.title_rounded,
            ),
            const SizedBox(height: 10),
            // Description input
            _buildInputField(
              controller: _descController,
              hint: 'Description (optional)',
              icon: Icons.notes_rounded,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            // Location input
            _buildInputField(
              controller: _locationController,
              hint: 'Location (optional)',
              icon: Icons.location_on_rounded,
            ),
            const SizedBox(height: 10),
            // Date picker
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(color: const Color(0xFF3A3A4A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 18, color: KinrelColors.textDim),
                    const SizedBox(width: 10),
                    Text(
                      _formatDate(_selectedDate),
                      style: KinrelTypography.bodyMedium.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: KinrelColors.textDim),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Create button
            SizedBox(
              width: double.infinity,
              child: DKButton(
                label: 'Create Memory',
                variant: DKButtonVariant.gradient,
                icon: Icons.add_rounded,
                size: DKButtonSize.lg,
                fullWidth: true,
                onPressed: _createMemory,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: KinrelTypography.bodyMedium.copyWith(
        color: KinrelColors.textWhite,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: KinrelTypography.bodyMedium.copyWith(
          color: KinrelColors.textDim,
        ),
        prefixIcon: Icon(icon, size: 20, color: KinrelColors.textDim),
        filled: true,
        fillColor: KinrelColors.darkElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide(color: KinrelColors.orange, width: 1.5),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkCard,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _createMemory() {
    if (_titleController.text.trim().isEmpty) return;

    final event = MemoryEvent(
      id: 'memory-${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      type: _selectedType,
      date: _selectedDate,
      description: _descController.text.trim().isNotEmpty
          ? _descController.text.trim()
          : null,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : null,
    );

    ref.read(memoriesProvider.notifier).addEvent(event);
    Navigator.pop(context);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SliverChildBuilderWithFooter — utility delegate
// ═══════════════════════════════════════════════════════════════════════

class SliverChildBuilderWithFooter extends SliverChildDelegate {
  SliverChildBuilderWithFooter({
    required this.childCount,
    required this.footer,
    required this.builder,
  });

  final int childCount;
  final Widget footer;
  final NullableIndexedWidgetBuilder builder;

  @override
  int get estimatedChildCount => childCount + 1;

  @override
  Widget? build(BuildContext context, int index) {
    if (index < childCount) {
      return builder(context, index);
    }
    if (index == childCount) {
      return footer;
    }
    return null;
  }

  @override
  bool shouldRebuild(covariant SliverChildBuilderWithFooter oldDelegate) =>
      childCount != oldDelegate.childCount ||
      footer != oldDelegate.footer;
}
