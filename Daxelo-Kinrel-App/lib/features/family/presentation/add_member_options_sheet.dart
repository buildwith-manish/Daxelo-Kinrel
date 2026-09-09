// lib/features/family/presentation/add_member_options_sheet.dart
//
// DAXELO KINREL — Add Member Options Bottom Sheet (v5.194)
//
// Shows a 2-option bottom sheet when the user taps "Add Member":
//   1. Add Manually      → existing add_person_sheet flow (full form:
//                         name, gender, photo, relationship, save)
//   2. Find on Kinrel    → Kinrel user search → tap result →
//                         Relationship Quick-Pick chips → immediate add
//                         with Undo snackbar (no form, no submit)
//
// "From Contacts" was removed in v5.194 per the new Add Member flow spec.
//
// Styled to match the app's dark theme (#131416 bg, #191B2C cards,
// #E8612A orange accent).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import 'add_member_source.dart';
import 'add_person_sheet.dart';
import 'kinrel_user_search_screen.dart';
import 'relationship_quick_pick_sheet.dart' show RelationshipQuickPickSheet;

/// Shows the 2-option "Add Family Member" bottom sheet.
///
/// Each option leads to a different flow:
///   - "Add Manually" → AddPersonSheet (full form with name/gender/photo/
///     relationship/save — for a person who doesn't yet exist on Kinrel).
///   - "Find on Kinrel" → KinrelUserSearchScreen → on user tap, opens
///     [RelationshipQuickPickSheet] which immediately commits the
///     relationship on chip tap (with an Undo snackbar — no submit).
///
/// [fromGraph] — v5.41: When true, graph-originated invites are routed
/// to the pending invitations system. Set this to true when the sheet
/// is opened from the Family Graph screen; false (default) when opened
/// from the Family Space / detail screen.
Future<void> showAddMemberOptions(
  BuildContext context, {
  required String familyId,
  bool fromGraph = false,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.xxl),
      ),
    ),
    builder: (context) => _AddMemberOptionsSheet(
      familyId: familyId,
      fromGraph: fromGraph,
    ),
  );
}

class _AddMemberOptionsSheet extends ConsumerWidget {
  const _AddMemberOptionsSheet({
    required this.familyId,
    this.fromGraph = false,
  });
  final String familyId;
  final bool fromGraph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: KinrelColors.darkBackground,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KinrelColors.textDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.person_add,
                      color: KinrelColors.orange, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Add Family Member',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(
                color: KinrelColors.darkElevated, height: 1, thickness: 1),

            // Option 1: Add Manually
            _OptionTile(
              icon: Icons.edit_outlined,
              iconColor: KinrelColors.orange,
              title: 'Add Manually',
              subtitle: 'Enter details yourself',
              onTap: () => _handleManual(context),
            ),

            const Divider(color: KinrelColors.darkElevated, height: 1),

            // Option 2: Find on Kinrel
            _OptionTile(
              icon: Icons.search,
              iconColor: KinrelColors.orange,
              title: 'Find on Kinrel',
              subtitle: 'Search existing users',
              onTap: () => _handleFindOnKinrel(context),
            ),

            const SizedBox(height: KinrelSpacing.base),
          ],
        ),
      ),
    );
  }

  // ── Option Handlers ──────────────────────────────────────────────

  /// Option 1: Add Manually — opens the existing full-form flow.
  /// Used when the person doesn't exist on Kinrel yet (no account).
  /// The form collects name, gender, photo, and relationship, then
  /// saves via the existing AddPersonSheet._submit() path.
  void _handleManual(BuildContext context) {
    Navigator.of(context).pop();
    AddPersonSheet.show(
      context,
      familyId: familyId,
      source: AddMemberSource.manual,
      fromGraph: fromGraph,
    );
  }

  /// Option 2: Find on Kinrel — opens the KinrelUserSearchScreen.
  ///
  /// v5.194 (NEW FLOW): When the user taps a search result, the new
  /// [RelationshipQuickPickSheet] opens instead of AddPersonSheet. The
  /// quick-pick sheet shows kinship chips (Parent / Sibling / Spouse /
  /// Child / Grandparent / More). Tapping a chip IMMEDIATELY creates
  /// the graph pending invitation — there is no form, no editable
  /// name/gender, and no submit button. An Undo snackbar reverses the
  /// addition if the user taps Undo within 6 seconds.
  ///
  /// Gendered labels are inferred automatically from the selected
  /// user's stored gender (e.g. Sibling + male → Brother, Parent +
  /// female → Mother).
  void _handleFindOnKinrel(BuildContext context) {
    Navigator.of(context).pop();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => KinrelUserSearchScreen(
          familyId: familyId,
          onUserSelected: (KinrelUser user) {
            // v5.194: The search screen already popped itself; now open
            // the Relationship Quick-Pick bottom sheet directly (no
            // AddPersonSheet — the user already exists on Kinrel).
            RelationshipQuickPickSheet.show(
              context,
              familyId: familyId,
              selectedUser: user,
              fromGraph: fromGraph,
            );
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _OptionTile — a single tappable option row
// ═══════════════════════════════════════════════════════════════════════

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron
              Icon(Icons.chevron_right,
                  color: KinrelColors.textDim, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
