// lib/features/occasions/presentation/family_calendar_screen.dart
//
// Full calendar screen scoped to one family. Adapts from occasions_screen.dart
// but uses familyOccasionsProvider instead of the global provider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/occasion_reminders_provider.dart';
import '../../family/presentation/add_person_sheet.dart';

class FamilyCalendarScreen extends ConsumerWidget {
  const FamilyCalendarScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occasions = ref.watch(familyOccasionsProvider(familyId));
    final detailAsync = ref.watch(familyDetailProvider(familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Family Calendar',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: detailAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => DKErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(familyDetailProvider(familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Family not found'));
          }

          final missingDob = detail.members
              .where((p) =>
                  p.deletedAt == null &&
                  (p.dateOfBirth == null || p.dateOfBirth!.isEmpty))
              .toList();

          if (occasions.isEmpty && missingDob.isEmpty) {
            return DKEmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'No Occasions Yet',
              subtitle:
                  'Add birthdays and anniversaries to your family members\nto see upcoming occasions here.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            children: [
              if (occasions.isNotEmpty) ...[
                Text(
                  'Upcoming Occasions',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 12),
                ...occasions.map((occasion) => _buildOccasionTile(occasion)),
              ],
              if (missingDob.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: KinrelColors.textDim.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: KinrelColors.textDim),
                          const SizedBox(width: 6),
                          Text(
                            'Missing Info',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...missingDob.map((person) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GestureDetector(
                              onTap: () {
                                AddPersonSheet.show(
                                  context,
                                  familyId: familyId,
                                  existingPerson: person,
                                );
                              },
                              child: Row(
                                children: [
                                  Icon(Icons.cake_outlined,
                                      size: 16, color: KinrelColors.textDim),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Add ${person.name}\'s birthday',
                                      style: TextStyle(
                                        fontFamily: KinrelTypography.bodyFont,
                                        fontSize: 13,
                                        color: KinrelColors.textDim,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildOccasionTile(OccasionItem occasion) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
            backgroundImage: occasion.photoUrl != null
                ? NetworkImage(occasion.photoUrl!)
                : null,
            child: occasion.photoUrl == null
                ? Icon(
                    occasion.type == OccasionType.birthday
                        ? Icons.cake_outlined
                        : Icons.favorite_outline,
                    size: 20,
                    color: KinrelColors.orange,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  occasion.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  occasion.type == OccasionType.birthday
                      ? 'Birthday · ${occasion.nextOccurrence.month}/${occasion.nextOccurrence.day}'
                      : 'Anniversary · ${occasion.nextOccurrence.month}/${occasion.nextOccurrence.day}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: occasion.daysUntil <= 7
                  ? KinrelColors.orange.withValues(alpha: 0.15)
                  : KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              occasion.daysUntil == 0
                  ? 'Today!'
                  : occasion.daysUntil == 1
                      ? 'Tomorrow'
                      : '${occasion.daysUntil} days',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: occasion.daysUntil <= 7
                    ? KinrelColors.orange
                    : KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
