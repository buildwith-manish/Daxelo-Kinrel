// lib/features/occasions/presentation/occasions_screen.dart
//
// DAXELO KINREL — Occasions Screen
//
// Displays birthday and anniversary reminders for all family members.
// Features filter chips (Upcoming / Birthdays / Anniversaries),
// animated occasion cards with toggle reminders, and an empty state
// with CTA to add members.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../providers/occasion_reminders_provider.dart';

// ── Filter Enum ──────────────────────────────────────────────────────

/// Available filter options for the occasions list.
enum OccasionFilter {
  upcoming,
  birthdays,
  anniversaries,
}

// ── Occasions Screen ─────────────────────────────────────────────────

/// Screen displaying all upcoming birthday and anniversary occasions.
///
/// Features:
/// - Three filter chips: Upcoming, Birthdays, Anniversaries
/// - Scrollable list of occasion cards with toggle reminders
/// - Orange glow border for today/tomorrow occasions
/// - Empty state with CTA to add members
/// - Entrance animations via flutter_animate
class OccasionsScreen extends ConsumerStatefulWidget {
  const OccasionsScreen({super.key});

  @override
  ConsumerState<OccasionsScreen> createState() => _OccasionsScreenState();
}

class _OccasionsScreenState extends ConsumerState<OccasionsScreen> {
  OccasionFilter _activeFilter = OccasionFilter.upcoming;

  @override
  Widget build(BuildContext context) {
    final occasionsAsync = ref.watch(occasionRemindersProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        title: Text(
          'Occasions',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: KinrelColors.textWhite, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: occasionsAsync.when(
        loading: () => _buildLoadingState(),
        error: (error, stack) => _buildErrorState(error),
        data: (state) {
          if (state.isLoading) return _buildLoadingState();
          if (state.error != null) return _buildErrorState(state.error);

          final filteredOccasions = _getFilteredOccasions(state);

          return Column(
            children: [
              _buildFilterChips(),
              Expanded(
                child: filteredOccasions.isEmpty
                    ? _buildEmptyState()
                    : _buildOccasionList(filteredOccasions),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Filter Chips ──────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Row(
        children: [
          _buildFilterChip(
            label: 'Upcoming',
            filter: OccasionFilter.upcoming,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          _buildFilterChip(
            label: 'Birthdays',
            filter: OccasionFilter.birthdays,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          _buildFilterChip(
            label: 'Anniversaries',
            filter: OccasionFilter.anniversaries,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required OccasionFilter filter,
  }) {
    final isActive = _activeFilter == filter;
    final bgColor =
        isActive ? KinrelColors.orange : KinrelColors.darkCard;
    final textColor =
        isActive ? KinrelColors.textWhite : KinrelColors.textSilver;
    final borderColor =
        isActive ? KinrelColors.orange : const Color(0xFF3A3A4A);

    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.lg,
          vertical: KinrelSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(KinrelRadius.xxl),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: textColor,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  // ── Occasion List ─────────────────────────────────────────────────

  Widget _buildOccasionList(List<OccasionItem> occasions) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      itemCount: occasions.length,
      separatorBuilder: (_, __) => const SizedBox(height: KinrelSpacing.md),
      itemBuilder: (context, index) {
        final occasion = occasions[index];
        return _OccasionCard(
          occasion: occasion,
          onToggle: () => _handleToggle(occasion),
        )
            .animate()
            .fadeIn(
              duration: 300.ms,
              delay: (index * 50).ms,
            )
            .slideY(
              begin: 0.05,
              end: 0,
              duration: 300.ms,
              delay: (index * 50).ms,
            );
      },
    );
  }

  // ── Occasion Card ─────────────────────────────────────────────────

  // ── Loading State ─────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Column(
        children: [
          // Shimmer filter chips
          Row(
            children: List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(right: KinrelSpacing.sm),
                child: DKLoadingShimmer(
                  width: 100,
                  height: 34,
                  radius: KinrelRadius.xxl,
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.xl),
          // Shimmer cards
          Expanded(
            child: ListView.separated(
              itemCount: 5,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: KinrelSpacing.md),
              itemBuilder: (_, __) => DKLoadingShimmer(
                width: double.infinity,
                height: 80,
                radius: KinrelRadius.lg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error State ───────────────────────────────────────────────────

  Widget _buildErrorState(Object? error) {
    return DKErrorState(
      message: error?.toString() ?? 'Failed to load occasions.',
      onRetry: () => ref.read(occasionRemindersProvider.notifier).loadOccasions(),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final filterLabel = switch (_activeFilter) {
      OccasionFilter.upcoming => 'occasions',
      OccasionFilter.birthdays => 'birthdays',
      OccasionFilter.anniversaries => 'anniversaries',
    };

    return DKEmptyState(
      icon: _activeFilter == OccasionFilter.anniversaries
          ? Icons.favorite_outline_rounded
          : Icons.cake_outlined,
      title: 'No $filterLabel yet',
      subtitle:
          'Add family members with dates of birth or anniversaries to see their special occasions here.',
      actionLabel: 'Add a Member',
      onAction: () => _navigateToAddMember(),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  List<OccasionItem> _getFilteredOccasions(OccasionRemindersState state) {
    switch (_activeFilter) {
      case OccasionFilter.upcoming:
        return state.upcoming;
      case OccasionFilter.birthdays:
        return state.birthdays;
      case OccasionFilter.anniversaries:
        return state.anniversaries;
    }
  }

  Future<void> _handleToggle(OccasionItem occasion) async {
    await ref
        .read(occasionRemindersProvider.notifier)
        .toggleReminder(occasion.personId, occasion.type);
  }

  void _navigateToAddMember() {
    final families = ref.read(familyListProvider).valueOrNull;
    if (families != null && families.isNotEmpty) {
      context.push('/family/${families.first.id}/add-person');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// OCCASION CARD WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A single occasion card displaying member info, occasion details,
/// and a reminder toggle switch.
///
/// Cards for today/tomorrow have a subtle orange glow border.
class _OccasionCard extends StatelessWidget {
  const _OccasionCard({
    required this.occasion,
    required this.onToggle,
  });

  final OccasionItem occasion;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isUrgent = occasion.daysUntil <= 1;
    final borderColor =
        isUrgent ? KinrelColors.orange.withValues(alpha: 0.4) : null;

    return DKCard(
      backgroundColor: KinrelColors.darkCard,
      borderColor: borderColor,
      padding: KinrelSpacing.base,
      child: Row(
        children: [
          // Avatar
          CachedAvatar(
            imageUrl: occasion.photoUrl,
            radius: 24,
            border: isUrgent
                ? Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.5),
                    width: 2,
                  )
                : null,
          ),
          const SizedBox(width: KinrelSpacing.md),

          // Name + Occasion info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  occasion.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),

                // Occasion label + days until
                _buildOccasionLabel(),
              ],
            ),
          ),

          const SizedBox(width: KinrelSpacing.sm),

          // Toggle switch
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                value: occasion.isReminderEnabled,
                onChanged: (_) => onToggle(),
                activeColor: KinrelColors.orange,
                activeTrackColor: KinrelColors.orange.withValues(alpha: 0.5),
                inactiveThumbColor: KinrelColors.textDim,
                inactiveTrackColor: KinrelColors.darkElevated,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the occasion label row with icon, type name, and days-until text.
  Widget _buildOccasionLabel() {
    final iconData = occasion.type == OccasionType.birthday
        ? Icons.cake_rounded
        : Icons.favorite_rounded;

    final typeLabel = occasion.type == OccasionType.birthday
        ? 'Birthday'
        : 'Anniversary';

    final daysLabel = _buildDaysLabel();
    final daysColor = _buildDaysColor();

    return Row(
      children: [
        Icon(
          iconData,
          size: 14,
          color: daysColor,
        ),
        const SizedBox(width: 4),
        Text(
          typeLabel,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: KinrelColors.textSilver,
            height: 1.4,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '·',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
            height: 1.4,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          daysLabel,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: daysColor,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// Returns the display string for days until the occasion.
  String _buildDaysLabel() {
    if (occasion.daysUntil == 0) return 'Today';
    if (occasion.daysUntil == 1) return 'Tomorrow';
    return 'in ${occasion.daysUntil} days';
  }

  /// Returns the color for the days-until label based on urgency.
  Color _buildDaysColor() {
    if (occasion.daysUntil == 0) return KinrelColors.orange;
    if (occasion.daysUntil == 1) return KinrelColors.amber;
    return KinrelColors.textSilver;
  }
}
