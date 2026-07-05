// lib/features/family/presentation/add_member_options_sheet.dart
//
// DAXELO KINREL — Add Member Options Bottom Sheet
//
// Shows a 3-option bottom sheet when the user taps "Add Member":
//   1. Add Manually      → existing add_person_sheet flow (Step 1→2→3→4)
//   2. From Contacts     → contact picker → Step 1 prefilled → 2→3→4
//   3. Find on Kinrel    → Kinrel user search → Step 2→3→4 (skip Step 1)
//
// Styled to match the app's dark theme (#131416 bg, #191B2C cards,
// #E8612A orange accent).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/permission_service.dart';
import 'add_member_source.dart';
import 'add_person_sheet.dart';
import 'contact_picker_helper.dart';
import 'kinrel_user_search_screen.dart';

/// Shows the 3-option "Add Family Member" bottom sheet.
///
/// Each option leads to the same AddPersonSheet but with different
/// pre-filled data and a different [AddMemberSource] that controls
/// which step the flow starts on.
Future<void> showAddMemberOptions(
  BuildContext context, {
  required String familyId,
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
    builder: (context) => _AddMemberOptionsSheet(familyId: familyId),
  );
}

class _AddMemberOptionsSheet extends ConsumerWidget {
  const _AddMemberOptionsSheet({required this.familyId});
  final String familyId;

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

            // Option 2: From Contacts
            _OptionTile(
              icon: Icons.contacts_outlined,
              iconColor: KinrelColors.orange,
              title: 'From Contacts',
              subtitle: 'Import from phone',
              onTap: () => _handleFromContacts(context, ref),
            ),

            const Divider(color: KinrelColors.darkElevated, height: 1),

            // Option 3: Find on Kinrel
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

  /// Option 1: Add Manually — opens the existing flow from Step 1.
  void _handleManual(BuildContext context) {
    Navigator.of(context).pop();
    AddPersonSheet.show(
      context,
      familyId: familyId,
      source: AddMemberSource.manual,
    );
  }

  /// Option 2: From Contacts — requests contacts permission, opens
  /// the native contact picker, then opens AddPersonSheet with the
  /// contact's data pre-filled.
  Future<void> _handleFromContacts(
      BuildContext context, WidgetRef ref) async {
    // Close the options sheet first
    Navigator.of(context).pop();

    // Request contacts permission
    final result = await PermissionService.requestContacts(context);
    if (result != PermissionResult.granted) {
      // Permission denied — show a message and fall back to manual
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Contacts permission denied. You can still add manually.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // Fall back to manual flow
      if (context.mounted) {
        AddPersonSheet.show(
          context,
          familyId: familyId,
          source: AddMemberSource.manual,
        );
      }
      return;
    }

    // Permission granted — open the contact picker
    // We use flutter_contacts to pick a single contact.
    // The import is deferred to avoid pulling in the package on web
    // (flutter_contacts doesn't support web).
    if (context.mounted) {
      await _openContactPicker(context);
    }
  }

  /// Opens the flutter_contacts picker and forwards the selected
  /// contact's data to AddPersonSheet.
  Future<void> _openContactPicker(BuildContext context) async {
    try {
      final contactData = await pickContact();
      if (contactData == null) return; // user cancelled

      if (context.mounted) {
        AddPersonSheet.show(
          context,
          familyId: familyId,
          source: AddMemberSource.fromContacts,
          prefilledName: contactData.name,
          prefilledPhone: contactData.phone,
          prefilledEmail: contactData.email,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Contact picker error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open contacts: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
        // Fall back to manual
        AddPersonSheet.show(
          context,
          familyId: familyId,
          source: AddMemberSource.manual,
        );
      }
    }
  }

  /// Option 3: Find on Kinrel — opens the KinrelUserSearchScreen.
  /// When the user selects a Kinrel user, it opens AddPersonSheet
  /// starting at Step 2 (Relationship) with the selected user's data.
  void _handleFindOnKinrel(BuildContext context) {
    Navigator.of(context).pop();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => KinrelUserSearchScreen(
          familyId: familyId,
          onUserSelected: (KinrelUser user) {
            // The search screen already popped itself; now open
            // AddPersonSheet starting at Step 2 (Relationship).
            AddPersonSheet.show(
              context,
              familyId: familyId,
              source: AddMemberSource.findOnKinrel,
              preselectedKinrelUser: user,
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
