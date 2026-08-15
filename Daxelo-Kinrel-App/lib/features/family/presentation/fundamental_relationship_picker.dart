// lib/features/family/presentation/fundamental_relationship_picker.dart
//
// DAXELO KINREL — Fundamental Relationship Picker (v5.0)
//
// A SIMPLIFIED picker that surfaces only the FOUR fundamental edge types
//   parent, child, spouse, sibling
// (with gender-specific labels like "Father" / "Mother" / "Husband" /
// "Wife" / "Brother" / "Sister"). Derived kinship terms (uncle, cousin,
// grandfather, etc.) are NEVER stored directly — they are derived at
// runtime by the Deterministic Kinship Engine from the fundamental
// edges.
//
// Why fundamental only?
//   Storing derived keys (e.g. "paternal_grandfather") breaks the
//   engine's BFS traversal — the engine walks only parent/spouse/
//   adoptive_parent/step_parent edges, so derived edges become
//   invisible to the resolver. By always storing the FUNDAMENTAL edge
//   that connects the two people, the engine can derive "uncle",
//   "cousin", "grandfather" and 5,000+ other terms at query time.
//
// Auto-confirm: tapping any option immediately calls Navigator.pop
// with the chosen key. No "Select This Relationship" button, no
// language selector, no extra taps.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

/// A fundamental relationship option presented in the picker.
class FundamentalOption {
  FundamentalOption({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  /// The kinship key that will be stored in the Relationship row.
  /// Always one of: father, mother, parent, son, daughter, child,
  /// husband, wife, spouse, brother, sister, sibling.
  final String key;

  /// Short human-readable label, e.g. "Father".
  final String label;

  /// Helper text describing the relationship direction.
  final String description;

  /// Icon to display.
  final IconData icon;

  /// Accent color for the icon + chip background.
  final Color color;
}

/// Shows a simplified bottom-sheet picker for the FUNDAMENTAL
/// relationship between [personB] and [personA].
///
/// Header: "How is [personB] related to [personA]?"
/// The returned key is the answer to that question — i.e. it is
/// the relationship from personA's perspective: "personB is my X".
/// Storage convention: fromPersonId = personA, toPersonId = personB,
/// relationshipKey = returned key.
///
/// Returns null if the user cancels.
class FundamentalRelationshipPicker {
  FundamentalRelationshipPicker._();

  static Future<String?> show(
    BuildContext context, {
    required String personAName,
    required String personBName,
    String? personAGender,
    String? personBGender,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) => _FundamentalPickerSheet(
        personAName: personAName,
        personBName: personBName,
        personAGender: personAGender,
        personBGender: personBGender,
      ),
    );
  }
}

class _FundamentalPickerSheet extends StatelessWidget {
  const _FundamentalPickerSheet({
    required this.personAName,
    required this.personBName,
    required this.personAGender,
    required this.personBGender,
  });

  final String personAName;
  final String personBName;
  final String? personAGender;
  final String? personBGender;

  @override
  Widget build(BuildContext context) {
    final options = _buildOptions();
    final subtitle = '$personBName is the ___ of $personAName';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
            child: Container(
              width: 40.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: KinrelColors.textDim,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 4.0),
            child: Text(
              'Connect $personBName',
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          // Subtitle: "X is the ___ of Y"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          const Divider(color: Color(0x1AFFFFFF), height: 1.0),

          // Options list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: options.length,
              itemBuilder: (ctx, i) {
                final opt = options[i];
                return _OptionTile(
                  option: opt,
                  onTap: () => Navigator.of(context).pop(opt.key),
                );
              },
            ),
          ),
          const SizedBox(height: 8.0),
        ],
      ),
    );
  }

  /// Build the fundamental relationship options.
  ///
  /// The relationship key returned is from PERSON A'S perspective:
  /// "personB is my X" — so we store fromPersonId=personA,
  /// toPersonId=personB, relationshipKey=X.
  ///
  /// Gender-aware: if personB is female, show "Mother" instead of
  /// "Father" for the parent option, etc. If gender is unknown, show
  /// both gendered variants.
  List<FundamentalOption> _buildOptions() {
    final list = <FundamentalOption>[];
    final bGender = personBGender?.toLowerCase();

    // ── Parent options (personB is the parent of personA) ──
    if (bGender == 'female') {
      list.add(FundamentalOption(
        key: 'mother',
        label: 'Mother',
        description: '$personBName is the mother of $personAName',
        icon: Icons.female,
        color: KinrelColors.nodeParent,
      ));
    } else if (bGender == 'male') {
      list.add(FundamentalOption(
        key: 'father',
        label: 'Father',
        description: '$personBName is the father of $personAName',
        icon: Icons.male,
        color: KinrelColors.nodeParent,
      ));
    } else {
      list.add(FundamentalOption(
        key: 'father',
        label: 'Father',
        description: '$personBName is the father of $personAName',
        icon: Icons.male,
        color: KinrelColors.nodeParent,
      ));
      list.add(FundamentalOption(
        key: 'mother',
        label: 'Mother',
        description: '$personBName is the mother of $personAName',
        icon: Icons.female,
        color: KinrelColors.nodeParent,
      ));
      list.add(FundamentalOption(
        key: 'parent',
        label: 'Parent',
        description: '$personBName is a parent of $personAName (gender unknown)',
        icon: Icons.person,
        color: KinrelColors.nodeParent,
      ));
    }

    // ── Child options (personB is the child of personA) ──
    if (bGender == 'female') {
      list.add(FundamentalOption(
        key: 'daughter',
        label: 'Daughter',
        description: '$personBName is the daughter of $personAName',
        icon: Icons.female,
        color: KinrelColors.nodeChild,
      ));
    } else if (bGender == 'male') {
      list.add(FundamentalOption(
        key: 'son',
        label: 'Son',
        description: '$personBName is the son of $personAName',
        icon: Icons.male,
        color: KinrelColors.nodeChild,
      ));
    } else {
      list.add(FundamentalOption(
        key: 'son',
        label: 'Son',
        description: '$personBName is the son of $personAName',
        icon: Icons.male,
        color: KinrelColors.nodeChild,
      ));
      list.add(FundamentalOption(
        key: 'daughter',
        label: 'Daughter',
        description: '$personBName is the daughter of $personAName',
        icon: Icons.female,
        color: KinrelColors.nodeChild,
      ));
      list.add(FundamentalOption(
        key: 'child',
        label: 'Child',
        description: '$personBName is a child of $personAName (gender unknown)',
        icon: Icons.person,
        color: KinrelColors.nodeChild,
      ));
    }

    // ── Spouse options (personB is the spouse of personA) ──
    if (bGender == 'female') {
      list.add(FundamentalOption(
        key: 'wife',
        label: 'Wife',
        description: '$personBName is the wife of $personAName',
        icon: Icons.favorite,
        color: KinrelColors.nodeSpouse,
      ));
    } else if (bGender == 'male') {
      list.add(FundamentalOption(
        key: 'husband',
        label: 'Husband',
        description: '$personBName is the husband of $personAName',
        icon: Icons.favorite,
        color: KinrelColors.nodeSpouse,
      ));
    } else {
      list.add(FundamentalOption(
        key: 'husband',
        label: 'Husband',
        description: '$personBName is the husband of $personAName',
        icon: Icons.favorite,
        color: KinrelColors.nodeSpouse,
      ));
      list.add(FundamentalOption(
        key: 'wife',
        label: 'Wife',
        description: '$personBName is the wife of $personAName',
        icon: Icons.favorite,
        color: KinrelColors.nodeSpouse,
      ));
      list.add(FundamentalOption(
        key: 'spouse',
        label: 'Spouse',
        description: '$personBName is the spouse of $personAName (gender unknown)',
        icon: Icons.favorite,
        color: KinrelColors.nodeSpouse,
      ));
    }

    // ── Sibling options (personB is the sibling of personA) ──
    if (bGender == 'female') {
      list.add(FundamentalOption(
        key: 'sister',
        label: 'Sister',
        description: '$personBName is the sister of $personAName',
        icon: Icons.people,
        color: KinrelColors.nodeSibling,
      ));
    } else if (bGender == 'male') {
      list.add(FundamentalOption(
        key: 'brother',
        label: 'Brother',
        description: '$personBName is the brother of $personAName',
        icon: Icons.people,
        color: KinrelColors.nodeSibling,
      ));
    } else {
      list.add(FundamentalOption(
        key: 'brother',
        label: 'Brother',
        description: '$personBName is the brother of $personAName',
        icon: Icons.people,
        color: KinrelColors.nodeSibling,
      ));
      list.add(FundamentalOption(
        key: 'sister',
        label: 'Sister',
        description: '$personBName is the sister of $personAName',
        icon: Icons.people,
        color: KinrelColors.nodeSibling,
      ));
      list.add(FundamentalOption(
        key: 'sibling',
        label: 'Sibling',
        description: '$personBName is a sibling of $personAName (gender unknown)',
        icon: Icons.people,
        color: KinrelColors.nodeSibling,
      ));
    }

    return list;
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.onTap});

  final FundamentalOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20.0,
          vertical: 12.0,
        ),
        child: Row(
          children: [
            Container(
              width: 40.0,
              height: 40.0,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(option.icon, color: option.color, size: 20.0),
            ),
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    option.description,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.5,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8.0),
            Icon(
              Icons.chevron_right,
              color: KinrelColors.textDim.withValues(alpha: 0.6),
              size: 22.0,
            ),
          ],
        ),
      ),
    );
  }
}
