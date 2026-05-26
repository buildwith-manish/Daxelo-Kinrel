import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_service.dart';
import 'add_person_sheet.dart';

class PersonDetailSheet extends ConsumerWidget {
  const PersonDetailSheet({
    super.key,
    required this.person,
    required this.familyId,
    this.kinshipService,
  });

  final Person person;
  final String familyId;
  final KinshipService? kinshipService;


  /// Show as bottom sheet
  static Future<void> show(
    BuildContext context, {
    required Person person,
    required String familyId,
    KinshipService? kinshipService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => PersonDetailSheet(
        person: person,
        familyId: familyId,
        kinshipService: kinshipService,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nativeTranslation = _getNativeTranslation(ref);

    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KinrelColors.darkSurface,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Avatar with gradient
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: person.isDeceased
                  ? LinearGradient(
                      colors: [
                        KinrelColors.textDim,
                        KinrelColors.darkSurface,
                      ],
                    )
                  : KinrelGradients.igniteGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            person.name,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: person.isDeceased
                  ? KinrelColors.textSilver
                  : KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 4),

          // Gender
          if (person.gender != null) ...[
            Text(
              person.const gender!.toUpperCase(),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.purple,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (nativeTranslation != null) ...[
              const SizedBox(height: 2),
              Text(
                nativeTranslation,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),

          // Detail rows
          if (person.dateOfBirth != null && person.dateOfBirth!.isNotEmpty)
            _DetailRow(
              icon: Icons.calendar_today,
              label: 'Date of Birth',
              value: person.dateOfBirth!,
            ),
          if (person.city != null && person.city!.isNotEmpty)
            _DetailRow(
              icon: Icons.location_on,
              label: 'City / Village',
              value: person.city!,
            ),
          if (person.gotra != null && person.gotra!.isNotEmpty)
            _DetailRow(
              icon: Icons.account_balance,
              label: 'Gotra',
              value: person.gotra!,
            ),

          _DetailRow(
            icon: person.isDeceased ? Icons.cloud : Icons.favorite,
            label: 'Status',
            value: person.isDeceased ? 'Deceased' : 'Alive',
            valueColor:
                person.isDeceased ? KinrelColors.textDim : KinrelColors.success,
          ),

          _DetailRow(
            icon: Icons.wc,
            label: 'Gender',
            value: (person.gender ?? 'unknown').capitalized,
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              // Edit button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    AddPersonSheet.show(
                      context,
                      familyId: familyId,
                      existingPerson: person,
                    );
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.purple,
                    side: const BorderSide(color: KinrelColors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KinrelSpacing.radiusSm),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Delete button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDelete(context, ref),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.error,
                    side: BorderSide(color: KinrelColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KinrelSpacing.radiusSm),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _getNativeTranslation(WidgetRef ref) {
    // Relationship translations now come from the Relationship table, not Person
    return null;
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        title: Text(
          'Delete ${person.name}?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textWhite,
          ),
        ),const content: Text(
          'This person will be removed from the family tree. This action cannot be undone.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            color: KinrelColors.textSilver,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close dialog
              Navigator.of(context).pop(); // Close sheet

              try {
                await deletePerson(
                  ref: ref,
                  personId: person.id,
                  familyId: familyId,
                );

                if (context.mounted) {
                  context.showSnackBar('${person.name} removed');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar(
                    'Failed to delete person: ${e.toString().split('\n').first}',
                    isError: true,
                  );
                }
              }
            },const child: Text(
              'Deleteconst ',
              style: TextStyle(color: KinrelColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: KinrelColors.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(const label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: valueColor ?? KinrelColors.textWhite,
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
