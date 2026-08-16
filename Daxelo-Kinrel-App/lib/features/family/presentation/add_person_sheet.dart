import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider; // v5.13
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;

import '../../../core/services/supabase_service.dart';
import 'services/photo_picker_service.dart';
import 'providers/family_graph_provider.dart' show FamilyGraphNotifier, familyGraphProvider;
import '../../../graph/interaction/relationship_validation.dart' show graphUndoProvider;
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import 'add_member_source.dart';
import 'relationship_picker_sheet.dart';
import '../providers/family_invite_provider.dart';

// ─────────────────────────────────────────────────────────────────────
// Add Person Sheet — 4-Step Wizard
//
// Step 0: Basic Info  (name, nickname, gender, DOB, photo)
// Step 1: Relationship to Existing Member
// Step 2: Additional Details (optional, collapsible)
// Step 3: Confirmation + submit
//
// Edit mode: simplified single-page flow.
// ─────────────────────────────────────────────────────────────────────

class AddPersonSheet extends ConsumerStatefulWidget {
  const AddPersonSheet({
    super.key,
    required this.familyId,
    this.existingPerson,
    this.anchorPerson,
    this.source = AddMemberSource.manual,
    this.prefilledName,
    this.prefilledPhone,
    this.prefilledEmail,
    this.preselectedKinrelUser,
  });

  final String familyId;

  /// When non-null, the sheet is in **edit mode** for this person.
  final Person? existingPerson;

  /// When non-null (and not edit mode), the sheet opens the
  /// "Add relative" flow with this person as the anchor in Step 1.
  final Person? anchorPerson;

  /// How the add-member flow was initiated. Controls which step the
  /// flow starts on and how the person is created in _submit().
  ///   - manual: Step 0 → 1 → 2 → 3 (full manual entry)
  ///   - fromContacts: Step 0 (prefilled) → 1 → 2 → 3
  ///   - findOnKinrel: Step 1 → 2 → 3 (skip Step 0, link to existing user)
  final AddMemberSource source;

  /// Pre-filled name (from contacts or Kinrel search).
  final String? prefilledName;

  /// Pre-filled phone (from contacts).
  final String? prefilledPhone;

  /// Pre-filled email (from contacts).
  final String? prefilledEmail;

  /// Pre-selected Kinrel user (from "Find on Kinrel" search).
  /// When non-null, the sheet skips Step 0 and links the new Person
  /// to this Kinrel user's auth account via `linkedUserId`.
  final KinrelUser? preselectedKinrelUser;

  /// Show as a full-screen bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    Person? existingPerson,
    Person? anchorPerson,
    AddMemberSource source = AddMemberSource.manual,
    String? prefilledName,
    String? prefilledPhone,
    String? prefilledEmail,
    KinrelUser? preselectedKinrelUser,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => AddPersonSheet(
        familyId: familyId,
        existingPerson: existingPerson,
        anchorPerson: anchorPerson,
        source: source,
        prefilledName: prefilledName,
        prefilledPhone: prefilledPhone,
        prefilledEmail: prefilledEmail,
        preselectedKinrelUser: preselectedKinrelUser,
      ),
    );
  }

  @override
  ConsumerState<AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends ConsumerState<AddPersonSheet>
    with TickerProviderStateMixin {
  // ── Step tracking ──────────────────────────────────────────────
  int _currentStep = 0;
  static const int _kStepCount = 4; // 0-3

  // ── Controllers ────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _dobController = TextEditingController();
  final _anniversaryController = TextEditingController();
  final _cityController = TextEditingController();
  final _gotraController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _occupationController = TextEditingController();
  final _bioController = TextEditingController();

  // ── State ──────────────────────────────────────────────────────
  String _selectedGender = 'male';
  String? _selectedRelType; // parent | child | spouse | sibling
  String? _selectedSubType; // elder | younger (siblings only)
  String? _selectedRelationshipKey; // full key from RelationshipPickerSheet
  String? _selectedRelationshipLabel;
  // v5.12: Target person picker — the user explicitly chooses WHICH
  // existing member the new person relates to. When null and no
  // anchorPerson was passed, the user hasn't picked a target yet.
  Person? _selectedTargetPerson;
  // v80: Custom kinship state
  String? _customKinshipName;
  int _customNodeColorValue = 0xFF64748B; // default slate
  int _customLineColorValue = 0xFF64748B; // default slate
  String _customLineType = 'solid'; // solid | dashed
  String _customDotType = 'dot'; // dot | heart | none
  bool _isDeceased = false;
  bool _isSubmitting = false;

  /// Stable key for the edit-mode form (NOT recreated on every rebuild).
  /// The previous code created GlobalKey<FormState>() inline in
  /// _buildEditModeContent, which caused the Form to lose its state on
  /// every keystroke (because onChanged → setState → rebuild → new key).
  final _editFormKey = GlobalKey<FormState>();
  DateTime? _selectedDob;
  DateTime? _selectedAnniversary;
  DateTime? _selectedDeathDate;
  bool _locationExpanded = false;
  bool _contactExpanded = false;
  bool _personalExpanded = false;
  bool _showSuccess = false;

  // ── Confetti particles ─────────────────────────────────────────
  final _confettiParticles = <_ConfettiParticle>[];
  late final AnimationController _confettiCtrl;

  bool get _isEditMode => widget.existingPerson != null;

  /// Resolve the effective anchor person for relationship creation.
  /// v5.13: Priority is now:
  ///   1. _selectedTargetPerson (user explicitly picked via UI)
  ///   2. widget.anchorPerson (passed from node context menu)
  ///   3. First existing member (anchor or oldest) — last resort fallback
  Person? get _effectiveAnchorPerson {
    // v5.13: User-selected target takes priority
    if (_selectedTargetPerson != null) return _selectedTargetPerson;
    if (widget.anchorPerson != null) return widget.anchorPerson;
    // Only auto-resolve in add mode (not edit mode)
    if (_isEditMode) return null;
    // Try to find the first existing member in the family
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    final existingMembers = membersAsync.valueOrNull;
    if (existingMembers == null || existingMembers.isEmpty) return null;
    // Prefer the anchor person, then fall back to the first member
    final anchor = existingMembers.firstWhere(
      (m) => m.isAnchor,
      orElse: () => existingMembers.first,
    );
    return anchor;
  }

  /// Whether the family members provider is still loading.
  /// Used to prevent the user from skipping Step 1 while we
  /// don't yet know if there are existing members.
  bool get _isFamilyMembersLoading {
    if (_isEditMode) return false;
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    return membersAsync.isLoading;
  }

  /// Whether the family has existing members (definitively).
  /// Returns false only when we are certain there are no members.
  /// Returns true if members exist OR if we're still loading OR if the
  /// fetch errored (conservative: assume members exist until proven otherwise).
  ///
  /// v4.7: Added hasError check. When familyMembersProvider throws (e.g. RLS
  /// permission error on an unclaimed/anonymous session), valueOrNull is null,
  /// which previously caused this to return false — meaning "no existing
  /// members" — even though the anchor person clearly exists. This caused
  /// relationships to be skipped (no Relationship row inserted, no edge drawn).
  /// Now we treat error the same as loading: conservative (assume members exist).
  bool get _familyHasExistingMembers {
    if (_isEditMode) return false;
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    // Conservative: assume members exist while loading OR if the fetch
    // errored (e.g. RLS/auth issue on an unclaimed/anonymous session).
    // Only return false when we have a definitive, successful empty result.
    if (membersAsync.hasError) return true;
    if (membersAsync.isLoading) return true;
    final existingMembers = membersAsync.valueOrNull;
    return existingMembers != null && existingMembers.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    if (_isEditMode) {
      final p = widget.existingPerson!;
      _nameController.text = p.name;
      _selectedGender = p.gender ?? 'male';
      _dobController.text = p.dateOfBirth ?? '';
      _cityController.text = p.city ?? '';
      _gotraController.text = p.gotra ?? '';
      _occupationController.text = p.occupation ?? '';
      _bioController.text = p.notes ?? '';
      _isDeceased = p.isDeceased;

      if (p.dateOfBirth != null && p.dateOfBirth!.isNotEmpty) {
        try {
          _selectedDob = DateTime.parse(p.dateOfBirth!);
        } catch (_) {}
      }
      // Hydrate anniversary date in edit mode
      _anniversaryController.text = p.anniversaryDate ?? '';
      if (p.anniversaryDate != null && p.anniversaryDate!.isNotEmpty) {
        try {
          _selectedAnniversary = DateTime.parse(p.anniversaryDate!);
        } catch (_) {}
      }
    } else {
      // ── Pre-fill data from contacts or Kinrel search ─────────────
      // For fromContacts: pre-fill name, phone, email from the picked
      // contact. The user can edit these in Step 0.
      // For findOnKinrel: pre-fill name from the selected Kinrel user
      // and skip Step 0 entirely (jump to Step 1 = Relationship).
      if (widget.prefilledName != null) {
        _nameController.text = widget.prefilledName!;
      }
      if (widget.prefilledPhone != null) {
        _phoneController.text = widget.prefilledPhone!;
      }
      if (widget.prefilledEmail != null) {
        _emailController.text = widget.prefilledEmail!;
      }

      // For findOnKinrel, also pre-fill gender if available
      if (widget.preselectedKinrelUser != null) {
        final user = widget.preselectedKinrelUser!;
        if (user.name.isNotEmpty) {
          _nameController.text = user.name;
        }
        if (user.gender != null && user.gender!.isNotEmpty) {
          _selectedGender = user.gender!;
        }
        // Skip Step 0 (Basic Info) — jump directly to Step 1 (Relationship)
        // because the person already exists on Kinrel.
        _currentStep = 1;
      }
    }
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _dobController.dispose();
    _anniversaryController.dispose();
    _cityController.dispose();
    _gotraController.dispose();
    _birthPlaceController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _occupationController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return nameValidator(_nameController.text) == null;
      case 1:
        // v5.13: Relationship + target person are both mandatory when
        // there are existing family members.
        if (_familyHasExistingMembers) {
          // Must have a target person (either user-selected or anchorPerson passed)
          final hasTarget = _selectedTargetPerson != null ||
              widget.anchorPerson != null;
          // Must have a relationship type selected
          return hasTarget && _effectiveRelationshipKey != null;
        }
        return true;
      case 2:
        return true; // Additional details are optional
      case 3:
        return true;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep < _kStepCount - 1 && _canProceed()) {
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // ── Date picking ───────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkElevated,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text = picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _pickAnniversaryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedAnniversary ?? DateTime(now.year - 5),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkElevated,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedAnniversary = picked;
        _anniversaryController.text =
            picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _pickDeathDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeathDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: KinrelColors.orange,
              surface: KinrelColors.darkElevated,
              onSurface: KinrelColors.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDeathDate = picked);
    }
  }

  // ── Relationship picking ───────────────────────────────────────

  Future<void> _pickDetailedRelationship() async {
    final anchor = _effectiveAnchorPerson;
    final result = await RelationshipPickerSheet.show(
      context,
      personAName: anchor?.name,
      personBName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
    );
    if (result != null) {
      setState(() {
        _selectedRelationshipKey = result;
        _selectedRelationshipLabel = result.snakeToTitle;
        _selectedRelType = null;   // ← clears simple card so no confusion
        _selectedSubType = null;
        _customKinshipName = null; // clear custom if user picks a standard term
      });
    }
  }

  // v80: Show the custom kinship dialog
  Future<void> _showCustomKinshipDialog() async {
    final nameController = TextEditingController(text: _customKinshipName);
    var nodeColor = _customNodeColorValue;
    var lineColor = _customLineColorValue;
    var lineType = _customLineType;
    var dotType = _customDotType;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: KinrelColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          ),
          title: Text(
            'Add Your Own Kinship',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kinship Name
                Text('Kinship Name', style: _labelStyle),
                SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: KinrelColors.textWhite, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Guru, Godfather, Chacha...',
                    hintStyle: TextStyle(color: KinrelColors.textDim),
                    filled: true,
                    fillColor: KinrelColors.darkBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: KinrelColors.textDim.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: KinrelColors.orange),
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Node Color
                Text('Node Color', style: _labelStyle),
                SizedBox(height: 6),
                _buildColorPicker(setDialogState, () => nodeColor, (c) {
                  nodeColor = c;
                  setDialogState(() {});
                }),
                SizedBox(height: 16),

                // Connection Line Color
                Text('Connection Line Color', style: _labelStyle),
                SizedBox(height: 6),
                _buildColorPicker(setDialogState, () => lineColor, (c) {
                  lineColor = c;
                  setDialogState(() {});
                }),
                SizedBox(height: 16),

                // Connection Line Type
                Text('Connection Line Type', style: _labelStyle),
                SizedBox(height: 6),
                _buildSegmentedChoice(setDialogState, () => lineType, [
                  ('Solid', 'solid'),
                  ('Dashed', 'dashed'),
                ], (v) { lineType = v; setDialogState(() {}); }),
                SizedBox(height: 16),

                // Relationship Dot
                Text('Relationship Dot', style: _labelStyle),
                SizedBox(height: 6),
                _buildSegmentedChoice(setDialogState, () => dotType, [
                  ('Dot', 'dot'),
                  ('Heart', 'heart'),
                  ('None', 'none'),
                ], (v) { dotType = v; setDialogState(() {}); }),
                SizedBox(height: 20),

                // Preview
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      // Node preview
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkSurface,
                          border: Border.all(color: Color(nodeColor), width: 3),
                        ),
                      ),
                      // Line preview
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: CustomPaint(
                            size: Size(double.infinity, 40),
                            painter: _LinePreviewPainter(
                              color: Color(lineColor),
                              isDashed: lineType == 'dashed',
                              dotType: dotType,
                            ),
                          ),
                        ),
                      ),
                      // Anchor preview
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkSurface,
                          border: Border.all(color: KinrelColors.tealAccent, width: 3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: KinrelColors.textDim)),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'nodeColor': nodeColor,
                    'lineColor': lineColor,
                    'lineType': lineType,
                    'dotType': dotType,
                  });
                }
              },
              child: Text('Save', style: TextStyle(color: KinrelColors.orange, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _customKinshipName = result['name'] as String;
        _customNodeColorValue = result['nodeColor'] as int;
        _customLineColorValue = result['lineColor'] as int;
        _customLineType = result['lineType'] as String;
        _customDotType = result['dotType'] as String;
        // Clear standard selections
        _selectedRelationshipKey = null;
        _selectedRelationshipLabel = null;
        _selectedRelType = null;
        _selectedSubType = null;
      });
    }
  }

  TextStyle get _labelStyle => TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: KinrelColors.textSilver,
  );

  // v80: Color picker row — 10 preset colors
  Widget _buildColorPicker(StateSetter setDialogState, int Function() getter, Function(int) setter) {
    const colors = [
      0xFF0D9488, // teal (self)
      0xFF3B82F6, // blue (parent)
      0xFFEC4899, // pink (child)
      0xFF8B5CF6, // purple (sibling)
      0xFFF97316, // orange (spouse)
      0xFF6366F1, // indigo (grandparent)
      0xFF06B6D4, // cyan (aunt/uncle)
      0xFF10B981, // emerald (cousin)
      0xFFF59E0B, // amber (in-law)
      0xFF64748B, // slate (extended)
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((c) {
        final isSelected = getter() == c;
        return GestureDetector(
          onTap: () { setter(c); setDialogState(() {}); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  // v80: Segmented choice for line type / dot type
  Widget _buildSegmentedChoice(
    StateSetter setDialogState,
    String Function() getter,
    List<(String, String)> options,
    Function(String) onSelect,
  ) {
    return Wrap(
      spacing: 8,
      children: options.map((opt) {
        final label = opt.$1;
        final value = opt.$2;
        final isSelected = getter() == value;
        return GestureDetector(
          onTap: () => onSelect(value),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? KinrelColors.orange.withValues(alpha: 0.15)
                  : KinrelColors.darkBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? KinrelColors.orange
                    : KinrelColors.textDim.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? KinrelColors.orange : KinrelColors.textSilver,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }



  /// Resolve the effective relationship key from type + gender + sub-type.
  /// The key describes what the ANCHOR person will be to the new person,
  /// so we use the anchor's gender for parent/child/sibling terms.
  /// Resolves the effective relationship key based on the selected
  /// relationship type and the NEW PERSON's gender.
  ///
  /// The question asked is "How is newName related to anchor?" — so
  /// the key represents the NEW PERSON's relationship TO the anchor.
  /// For example, if the user selects "Parent" and the new person is
  /// male, the key is 'father' (newPerson is the father of anchor).
  ///
  /// CRITICAL FIX: Previously this used the ANCHOR's gender, which
  /// produced the wrong key. For example, if the anchor was male and
  /// the user selected "Sibling", it returned 'brother' — but that
  /// means "anchor is the brother of newPerson", which is the OPPOSITE
  /// of what the question asks. Now it uses the new person's gender.
  String? get _effectiveRelationshipKey {
    // v80: Custom kinship — use the custom name as the key
    if (_customKinshipName != null && _customKinshipName!.isNotEmpty) {
      return 'custom_${_customKinshipName!.toLowerCase().replaceAll(' ', '_')}';
    }
    if (_selectedRelationshipKey != null) return _selectedRelationshipKey;

    // Use the NEW PERSON's gender (not the anchor's) because the
    // question is "How is newName related to anchor?".
    final newPersonGender = _selectedGender;
    switch (_selectedRelType) {
      case 'parent':
        return newPersonGender == 'female' ? 'mother' : 'father';
      case 'child':
        return newPersonGender == 'female' ? 'daughter' : 'son';
      case 'spouse':
        return newPersonGender == 'female' ? 'wife' : 'husband';
      case 'sibling':
        if (_selectedSubType == 'elder') {
          return newPersonGender == 'female' ? 'elder_sister' : 'elder_brother';
        } else if (_selectedSubType == 'younger') {
          return newPersonGender == 'female' ? 'younger_sister' : 'younger_brother';
        }
        return newPersonGender == 'female' ? 'sister' : 'brother';
      default:
        return null;
    }
  }

  /// v5.11: Maps a specific kinship key (e.g. 'father', 'brother', 'wife')
  /// to the FUNDAMENTAL edge type required by the DB constraint
  /// `relationship_fundamental_edge_check` which only allows:
  ///   'parent', 'spouse', 'adoptive_parent', 'step_parent'
  ///
  /// The specific key is still stored in `labelAtoB` (set by the trigger
  /// from `relationshipKey` → `labelAtoB`, then used by the viewer-aware
  /// RPC for perspective-based label resolution).
  ///
  /// Mapping:
  ///   father/mother/parent/son/daughter/child → 'parent'
  ///   husband/wife/spouse → 'spouse'
  ///   brother/sister/sibling → 'parent' (siblings share parents — the
  ///     fundamental edge between siblings IS the parent edge, but since
  ///     we're creating an edge BETWEEN the siblings, not between sibling
  ///     and parent, we use 'parent' as the closest fundamental type.
  ///     The labelAtoB will carry the specific 'brother'/'sister' label.)
  ///   step_father/step_mother/stepfather/stepmother → 'step_parent'
  ///   adoptive_father/adoptive_mother/adoptive_parent → 'adoptive_parent'
  ///   Everything else → 'parent' (safest fallback — covers grandfather,
  ///     uncle, cousin, etc. which are all derived from parent edges)
  static String _mapToFundamentalEdge(String? specificKey) {
    if (specificKey == null || specificKey.isEmpty) return 'parent';
    final k = specificKey.toLowerCase().trim();

    // Spouse
    if (k == 'husband' || k == 'wife' || k == 'spouse') return 'spouse';

    // Step-parent
    if (k == 'step_father' || k == 'step_mother' ||
        k == 'stepfather' || k == 'stepmother' ||
        k == 'step_parent') return 'step_parent';

    // Adoptive parent
    if (k == 'adoptive_father' || k == 'adoptive_mother' ||
        k == 'adoptive_parent') return 'adoptive_parent';

    // Everything else (father, mother, parent, son, daughter, child,
    // brother, sister, sibling, grandfather, grandmother, uncle, aunt,
    // cousin, nephew, niece, etc.) → 'parent' (the fundamental edge)
    return 'parent';
  }

  /// Human-readable preview sentence.
  /// Shows "NewPerson will be the [label] of Anchor" — matching the
  /// question "How is newName related to anchor?".
  String get _relationshipPreview {
    final key = _effectiveRelationshipKey;
    if (key == null) return '';
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';
    final anchorName = _effectiveAnchorPerson?.name ?? 'existing member';
    // v80: Use custom kinship name if set
    final label = _customKinshipName ?? _selectedRelationshipLabel ?? key.snakeToTitle;
    return '$newName will be the $label of $anchorName';
  }

  // ── Person-Specific Invite Prompt ──────────────────────────────
  // After saving a manually-added Person with phone/email, show a dialog
  // offering to send a personalized invite that references their specific
  // relationship + name (not the generic family-join link).

  Future<void> _showPersonInvitePrompt(Person person) async {
    final name = person.name;
    final relationshipLabel = _selectedRelationshipLabel ?? _selectedRelType ?? 'family member';
    final hasPhone = _phoneController.text.trim().isNotEmpty;
    final hasEmail = _emailController.text.trim().isNotEmpty;

    final shouldInvite = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Invite $name to Kinrel?',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF5F0EE),
          ),
        ),
        content: Text(
          'Send $name a personalized invite to confirm their spot as your '
          '$relationshipLabel in the family tree. '
          '${hasPhone ? '📱 ' : ''}${hasEmail ? '✉️ ' : ''}'
          'They\'ll get a link to claim their profile.',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: Color(0xFFC9B4A8),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Not Now',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Color(0xFF8A7A72),
              ),
            ),
          ),
          Material(
            color: const Color(0xFFE8612A),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => Navigator.of(ctx).pop(true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: const Text(
                  'Send Invite',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldInvite == true && mounted) {
      // Get the inviter's name + family name for the personalized message
      final client = ref.read(supabaseProvider);
      final myId = client?.auth.currentUser?.id ?? '';
      final myName = (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
          client?.auth.currentUser?.email ??
          'A family member';

      // Get the family name
      String familyName = 'Family';
      if (client != null) {
        try {
          final famResp = await client
              .from('Family')
              .select('name')
              .eq('id', widget.familyId)
              .single()
              .timeout(const Duration(seconds: 5));
          familyName = (famResp['name'] as String?) ?? 'Family';
        } catch (_) {}
      }

      await ref.read(familyInviteProvider.notifier).sharePersonInvite(
            familyId: widget.familyId,
            personId: person.id,
            personName: name,
            relationshipLabel: relationshipLabel,
            inviterName: myName,
            familyName: familyName,
            recipientPhone: hasPhone ? _phoneController.text.trim() : null,
            recipientEmail: hasEmail ? _emailController.text.trim() : null,
          );
    }
  }

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) return;

    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      Person? result;

      // v94 (EDGE BUG FIX): Track whether the relationship creation
      // failed so we can suppress the success flow (confetti,
      // "Welcome to the family") when the compound mutation is
      // incomplete. The Person was created but the edge wasn't —
      // showing success would mislead the user. Declared in the outer
      // try scope so it's visible to the success-gate below.
      var relationshipFailed = false;

      if (_isEditMode) {
        await updatePersonOptimistic(
          ref: ref,
          personId: widget.existingPerson!.id,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          anniversaryDate: _anniversaryController.text.trim().isEmpty
              ? null
              : _anniversaryController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
        );
        if (kEnablePhotoPicker && _pickedPhoto != null) {
          await _uploadPickedPhoto(widget.existingPerson!.id);
        }
      } else {
        // v20 FIX: If this is the first member of the family, set isAnchor=true
        // so the graph layout has an anchor to center on. Without an anchor,
        // the graph may render blank because the layout doesn't know where
        // to position nodes.
        //
        // v38 BUG-11 FIX: AWAIT the familyMembersProvider before deciding
        // isFirstMember. Previously, _familyHasExistingMembers returned true
        // while the provider was still loading — causing the first member
        // to be created with isAnchor=false. The graph then had no anchor
        // to center on → blank/displaced graph.
        bool isFirstMember = !_familyHasExistingMembers;
        if (!isFirstMember) {
          // The provider might still be loading — wait for it to settle
          // before making the final decision.
          try {
            final members = await ref
                .read(familyMembersProvider(widget.familyId).future);
            isFirstMember = members.isEmpty;
          } catch (e) {
            debugPrint('[ADD-MEMBER] Could not await familyMembersProvider: $e');
            // Fall back to the synchronous check — if it said "has members",
            // we trust it. If it said "no members", we also trust it.
          }
        }
        // Double-check by querying Person count directly from Supabase
        // (authoritative — the provider may have stale cached data)
        if (!isFirstMember) {
          try {
            final client = ref.read(supabaseProvider);
            if (client != null) {
              final count = await client
                  .from('Person')
                  .select('id')
                  .eq('familyId', widget.familyId)
                  .isFilter('deletedAt', null)
                  .count();
              isFirstMember = count == 0;
              debugPrint('[ADD-MEMBER] Direct Person count: $count → isFirstMember=$isFirstMember');
            }
          } catch (e) {
            debugPrint('[ADD-MEMBER] Direct Person count failed: $e');
          }
        }

        // v94 (EDGE BUG FIX): Compute the relationship key BEFORE creating
        // the Person so we can decide whether to refresh the graph during
        // Person creation. When a relationship WILL be created (non-first
        // member + relKey != null), we pass `refreshGraph: false` to
        // createPersonOptimistic so the graph does NOT refresh into a
        // Person-only intermediate state. The graph refresh happens ONCE
        // after the Relationship INSERT succeeds, via an awaited
        // authoritative refresh + optimistic upsert.
        final preComputedRelKey = _effectiveRelationshipKey;
        final willCreateRelationship =
            !isFirstMember && preComputedRelKey != null;

        result = await createPersonOptimistic(
          ref: ref,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          anniversaryDate: _anniversaryController.text.trim().isEmpty
              ? null
              : _anniversaryController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
          isAnchor: isFirstMember, // ← v20/v38: First member is always the anchor
          // v94: Don't refresh the graph between Person and Relationship
          // writes — the compound mutation will refresh once after the
          // edge is created.
          refreshGraph: !willCreateRelationship,
        );

        // ═══════════════════════════════════════════════════════════════
        // LINK TO KINREL USER (findOnKinrel source only)
        // ═══════════════════════════════════════════════════════════════
        // When the user selected an existing Kinrel user via "Find on
        // Kinrel", we link the new Person node to that user's auth
        // account by setting `linkedUserId` on the Person row. This
        // lets the linked user log in and see this family from their
        // own perspective (viewer-perspective graph).
        if (widget.source == AddMemberSource.findOnKinrel &&
            widget.preselectedKinrelUser != null &&
            result != null) {
          try {
            final client = ref.read(supabaseProvider);
            if (client != null) {
              await client
                  .from('Person')
                  .update({
                    'linkedUserId': widget.preselectedKinrelUser!.id,
                    'linkedAt': DateTime.now().toUtc().toIso8601String(),
                  })
                  .eq('id', result.id)
                  .timeout(const Duration(seconds: 10));
              debugPrint(
                  '[ADD-MEMBER] Linked Person ${result.id} to Kinrel user ${widget.preselectedKinrelUser!.id}');
            }
          } catch (e) {
            // Non-fatal — the Person was created, just the link failed.
            // The user can re-link later via the claim flow.
            debugPrint('[ADD-MEMBER] Failed to link Kinrel user: $e');
          }
        }

        // ═══════════════════════════════════════════════════════════════
        // v7 (2026-06-19): RELATIONSHIP CREATION — DIRECT SUPABASE QUERY
        // ═══════════════════════════════════════════════════════════════
        // The previous implementation relied on `_effectiveAnchorPerson`
        // which reads from `familyMembersProvider`. This provider might
        // not have loaded yet, or might have stale data, causing the
        // anchor to be null and the relationship creation to be
        // SILENTLY SKIPPED.
        //
        // New approach: query the anchor person DIRECTLY from Supabase.
        // This is 100% reliable — no provider timing issues.
        // ═══════════════════════════════════════════════════════════════
        if (kEnablePhotoPicker && _pickedPhoto != null && result != null) {
          await _uploadPickedPhoto(result.id);
        }

        final relKey = preComputedRelKey;

        if (relKey != null && !_isEditMode && result != null) {
          // v94: Capture the non-null result in a local variable so
          // dart2js doesn't lose null-promotion across the await
          // boundaries below. Without this, `result.id` triggers
          // "Property 'id' cannot be accessed on 'Person?'" because
          // dart2js can't prove `result` is still non-null after an
          // await inside a nested try block.
          final newPerson = result;
          final resultId = newPerson.id;
          final resultName = newPerson.name;
          final resultGender = newPerson.gender;
          final resultPhotoUrl = newPerson.photoUrl;
          final resultIsDeceased = newPerson.isDeceased;
          try {
            final client = ref.read(supabaseProvider);
            if (client != null && client.auth.currentSession != null) {
              debugPrint('[ADD-MEMBER] v94: Creating relationship with key=$relKey');

              // v5.12: Target person resolution — USER-SELECTED first.
              // Priority:
              //   1. _selectedTargetPerson (user explicitly picked via UI)
              //   2. widget.anchorPerson (passed from node context menu)
              //   3. DB anchor fallback (last resort — clearly indicated)
              String? linkToPersonId;

              if (_selectedTargetPerson != null) {
                // v5.12: User explicitly picked a target person
                linkToPersonId = _selectedTargetPerson!.id;
                debugPrint('[ADD-MEMBER] v5.12: Using user-selected target: ${_selectedTargetPerson!.name} ($linkToPersonId)');
              } else if (widget.anchorPerson != null) {
                // User opened Add from a specific node's context menu
                linkToPersonId = widget.anchorPerson!.id;
                debugPrint('[ADD-MEMBER] v94: Using provided anchorPerson: ${widget.anchorPerson!.name} ($linkToPersonId)');
              } else {
                // Query the Family to get anchorPersonId
                final familyData = await client
                    .from('Family')
                    .select('anchorPersonId')
                    .eq('id', widget.familyId)
                    .maybeSingle()
                    .timeout(const Duration(seconds: 5));

                linkToPersonId = familyData?['anchorPersonId'] as String?;

                // If no anchorPersonId, query ALL existing persons (not just first)
                // and pick the anchor (isAnchor=true) or the oldest by createdAt
                if (linkToPersonId == null || linkToPersonId.isEmpty || linkToPersonId == resultId) {
                  debugPrint('[ADD-MEMBER] v94: No valid anchorPersonId, querying existing members...');
                  final existingPersons = await client
                      .from('Person')
                      .select('id, name, gender, "isAnchor"')
                      .eq('familyId', widget.familyId)
                      .neq('id', resultId)
                      .isFilter('deletedAt', null)
                      .order('createdAt', ascending: true)
                      .limit(10)
                      .timeout(const Duration(seconds: 5));

                  if (existingPersons.isNotEmpty) {
                    // Prefer isAnchor=true, else first
                    final anchor = existingPersons.firstWhere(
                      (p) => p['isAnchor'] == true,
                      orElse: () => existingPersons.first,
                    );
                    linkToPersonId = anchor['id'] as String?;
                    debugPrint('[ADD-MEMBER] v94: Found link target: ${anchor['name']} ($linkToPersonId)');
                  }
                } else {
                  debugPrint('[ADD-MEMBER] v94: Using family anchorPersonId: $linkToPersonId');
                }
              }

              if (linkToPersonId != null && linkToPersonId.isNotEmpty && linkToPersonId != resultId) {
                // CRITICAL FIX: The relationship question asks "How is
                // newName related to anchor?" — so the user is saying
                // "newPerson IS the [brother/father/etc] OF anchor".
                // The relationship must be stored as:
                //   from: newPerson (resultId), to: anchor (linkToPersonId)
                //   key: relKey (e.g. 'brother' = newPerson is brother of anchor)
                debugPrint('[ADD-MEMBER] v94: Creating relationship: from=$resultId (new) to=$linkToPersonId (anchor) key=$relKey');

                // v5.11 FIX: The relationship_fundamental_edge_check DB
                // constraint ONLY allows 'parent', 'spouse',
                // 'adoptive_parent', 'step_parent' in the relationshipKey
                // column. But relKey is a SPECIFIC key like 'father',
                // 'brother', 'wife' — which would be REJECTED by the
                // constraint, silently failing the INSERT and leaving
                // the new person unlinked.
                //
                // The fix: map the specific key to the FUNDAMENTAL edge
                // type for relationshipKey, while keeping the specific
                // key in labelAtoB (which the viewer-aware RPC uses for
                // perspective-based label resolution).
                final fundamentalKey = _mapToFundamentalEdge(relKey);
                debugPrint('[ADD-MEMBER] v5.11: Mapped $relKey → $fundamentalKey (fundamental edge)');

                // v94 (EDGE BUG FIX): Create the relationship with
                // `refreshGraph: false` — we do NOT want createRelationship
                // to clear the graph cache + invalidate the provider here.
                // The compound mutation will do ONE authoritative refresh
                // after this returns, and the optimistic upsert below
                // ensures the edge appears immediately in the provider
                // state (not just the cache).
                await createRelationship(
                  ref: ref,
                  familyId: widget.familyId,
                  fromPersonId: resultId,
                  toPersonId: linkToPersonId,
                  relationshipKey: fundamentalKey,
                  // v5.11: Pass the SPECIFIC key (e.g. 'father', 'brother')
                  // as labelAtoB so the viewer-aware RPC can resolve the
                  // correct perspective label. The relationshipKey column
                  // only accepts fundamental types ('parent', 'spouse', etc.)
                  // due to the DB constraint.
                  specificLabelAtoB: relKey,
                  // v5.3: Pass genders so the inverse edge gets the
                  // correct gender-aware key (e.g. 'son' instead of
                  // 'child'). _selectedGender is the new person's gender.
                  fromPersonGender: _selectedGender,
                  toPersonGender: widget.anchorPerson?.gender,
                  // v83: Pass custom kinship colors + display name
                  customColors: _customKinshipName != null
                      ? {
                          'nodeColor': _customNodeColorValue,
                          'lineColor': _customLineColorValue,
                          'lineType': _customLineType,
                          'dotType': _customDotType,
                        }
                      : null,
                  customDisplayName: _customKinshipName,
                  // v94: Do NOT refresh the graph inside createRelationship
                  // — the compound mutation handles it below.
                  refreshGraph: false,
                );
                debugPrint('[ADD-MEMBER] v94: ✅ Relationship created successfully');

                // v94 (EDGE BUG FIX): Optimistically upsert the person +
                // edge into the CURRENT provider state via the notifier
                // instance method. Unlike the old injectOptimisticEdge
                // (which silently no-op'd when cache was null), this
                // mutates `state = AsyncData(updated)` directly so
                // Riverpod rebuilds dependents IMMEDIATELY. The edge
                // appears in the graph BEFORE the authoritative refetch
                // lands, and is robust to a null cache.
                try {
                  ref
                      .read(familyGraphProvider(widget.familyId).notifier)
                      .upsertPersonAndEdge(
                        personId: resultId,
                        personName: resultName,
                        gender: resultGender,
                        relationshipKey: relKey,
                        targetPersonId: linkToPersonId,
                        photoUrl: resultPhotoUrl,
                        isDeceased: resultIsDeceased,
                      );
                } catch (e) {
                  debugPrint('[ADD-MEMBER] v94: Optimistic upsert failed (non-fatal — refetch will recover): $e');
                }

                // v94 (EDGE BUG FIX): Perform ONE awaited authoritative
                // graph refresh. We await `ref.refresh(...).future` so we
                // can verify the new edge is present in the refreshed
                // FlatGraphResult. If it's missing (e.g. eventual-
                // consistency delay), we clear the cache + invalidate
                // again so the next read hits Supabase fresh.
                try {
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  final refreshedGraph = await ref.refresh(
                    familyGraphProvider(widget.familyId).future,
                  );
                  // Verify the edge exists in the refreshed graph.
                  final edgeExists = refreshedGraph.relationships.any((r) {
                    final from = r['fromPersonId']?.toString();
                    final to = r['toPersonId']?.toString();
                    return (from == resultId && to == linkToPersonId) ||
                        (from == linkToPersonId && to == resultId);
                  });
                  if (edgeExists) {
                    debugPrint('[ADD-MEMBER] v94: ✅ Edge verified in refreshed graph');
                  } else {
                    // The edge wasn't in the refreshed graph. The INSERT
                    // succeeded (createRelationship would have thrown
                    // otherwise), so this is likely an eventual-
                    // consistency delay. Invalidate once more so the
                    // next read picks it up. The optimistic upsert above
                    // keeps the edge visible in the interim.
                    debugPrint('[ADD-MEMBER] v94: ⚠️ Edge not yet in refreshed graph — invalidating for retry');
                    FamilyGraphNotifier.clearCache(widget.familyId);
                    ref.invalidate(familyGraphProvider(widget.familyId));
                  }
                } catch (e) {
                  debugPrint('[ADD-MEMBER] v94: Authoritative refresh failed (non-fatal — optimistic state holds): $e');
                  // The optimistic upsert above keeps the edge visible.
                  // Invalidate so the next read retries.
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  ref.invalidate(familyGraphProvider(widget.familyId));
                }
              } else {
                debugPrint('[ADD-MEMBER] v94: ⚠️ No existing member found to link to. '
                    'This is the first member — no relationship needed.');
              }
            } else {
              debugPrint('[ADD-MEMBER] v94: ⚠️ Supabase client or session not available');
            }
          } catch (e, stackTrace) {
            debugPrint('[ADD-MEMBER] v94: ❌ Relationship creation failed: $e');
            debugPrint('[ADD-MEMBER] v94: Stack: $stackTrace');
            relationshipFailed = true;
            if (mounted) {
              // v98 (Phase 0): Compensating rollback — soft-delete the
              // orphan Person so no permanent orphan survives a
              // relationship-creation failure. Uses soft-delete
              // (deletedAt timestamp) matching the existing
              // `.isFilter('deletedAt', null)` pattern, NOT hard delete
              // (Person has onDelete: Cascade from Relationship).
              try {
                final rollbackClient = ref.read(supabaseProvider);
                if (rollbackClient != null && resultId.isNotEmpty) {
                  await rollbackClient
                      .from('Person')
                      .update({
                        'deletedAt': DateTime.now().toUtc().toIso8601String(),
                      })
                      .eq('id', resultId)
                      .timeout(const Duration(seconds: 5));
                  debugPrint('[ADD-MEMBER] v98: Rolled back orphan Person $resultId (soft-deleted)');
                }
              } catch (rollbackError) {
                debugPrint('[ADD-MEMBER] v98: Rollback FAILED — orphan Person $resultId may persist: $rollbackError');
              }
              // Clear graph cache + invalidate so the orphan doesn't render.
              FamilyGraphNotifier.clearCache(widget.familyId);
              ref.invalidate(familyGraphProvider(widget.familyId));
              ref.invalidate(familyMembersProvider(widget.familyId));

              // v5.12: Show the ACTUAL error to the user, not just a generic
              // message. Silent failure of a core feature is not acceptable.
              final errorStr = e.toString();
              final shortError = errorStr.length > 100
                  ? errorStr.substring(0, 100) + '...'
                  : errorStr;
              context.showSnackBar(
                'Could not save the relationship: $shortError. '
                'The member was not added — please try again.',
                isError: true,
              );
            }
          }
        } else if (relKey == null) {
          debugPrint('[ADD-MEMBER] v7: No relationship selected — skipping relationship creation');
          // v94: If we skipped the graph refresh during Person creation
          // (because we expected a relationship), but no relationship
          // was selected, refresh the graph now so the new node appears.
          if (willCreateRelationship) {
            // willCreateRelationship was true but relKey is now null —
            // shouldn't happen, but guard against it.
            FamilyGraphNotifier.clearCache(widget.familyId);
            ref.invalidate(familyGraphProvider(widget.familyId));
          }
        }
      }

      if (!mounted) return;

      // v94 (EDGE BUG FIX): If the relationship creation failed, do NOT
      // fire confetti or show "Welcome to the family" — the compound
      // mutation is incomplete. The error snackbar was already shown in
      // the catch block above. Keep the sheet open so the user can
      // retry or dismiss manually.
      if (relationshipFailed) {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
        return;
      }

      // CRITICAL ANR FIX: Consolidated success state updates into single setState
      // Multiple setState calls in sequence caused cascading rebuilds
      unawaited(HapticFeedback.mediumImpact());
      _launchConfetti();

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _showSuccess = true;
        });
      }

      // v62.5: Reduced from 1800ms to 500ms — the success animation
      // still shows but the sheet closes much faster.
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      // v99 (Phase 7): Show success snackbar with UNDO action if an
      // undo command was pushed during relationship creation.
      final undoState = ref.read(graphUndoProvider);
      if (undoState.canUndo && !_isEditMode && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome to the family, ${result!.name}!'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () async {
                final cmd = ref.read(graphUndoProvider.notifier).pop();
                if (cmd == null) return;
                // Perform the inverse: delete the relationship.
                try {
                  final client = ref.read(supabaseProvider);
                  if (client != null && cmd.edgeId != null) {
                    await client
                        .from('Relationship')
                        .delete()
                        .eq('id', cmd.edgeId!)
                        .timeout(const Duration(seconds: 10));
                  }
                  FamilyGraphNotifier.clearCache(widget.familyId);
                  ref.invalidate(familyGraphProvider(widget.familyId));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Relationship removed.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Undo failed: $e')),
                    );
                  }
                }
              },
            ),
          ),
        );
      } else {
        context.showSnackBar(
          _isEditMode
              ? 'Person updated successfully'
              : 'Welcome to the family, ${result?.name ?? 'New member'}!',
        );
      }

      // ═══════════════════════════════════════════════════════════════
      // PERSON-SPECIFIC INVITE PROMPT
      // ═══════════════════════════════════════════════════════════════
      // After saving a manually-added or contact-imported Person (NOT
      // findOnKinrel — that path already links to a real account), if
      // the Person has a phone or email on file, offer to send a
      // personalized invite so they can claim their spot in the tree.
      if (!_isEditMode &&
          widget.source != AddMemberSource.findOnKinrel &&
          result != null &&
          (_phoneController.text.trim().isNotEmpty ||
              _emailController.text.trim().isNotEmpty)) {
        await _showPersonInvitePrompt(result);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        // CRITICAL ANR FIX: Single setState for error state
        setState(() => _isSubmitting = false);
        final fieldErrors = mapApiError(e);
        if (fieldErrors != null) {
          final formError = fieldErrors['form'];
          if (formError != null) {
            context.showSnackBar(formError, isError: true);
          } else {
            final firstError = fieldErrors.values.first;
            context.showSnackBar(
              _isEditMode
                  ? 'Failed to update person: $firstError'
                  : 'Failed to add person: $firstError',
              isError: true,
            );
          }
        } else {
          context.showSnackBar(
            _isEditMode
                ? 'Failed to update person: ${e.toString().split('\n').first}'
                : 'Failed to add person: ${e.toString().split('\n').first}',
            isError: true,
          );
        }
      }
    }
  }

  // ── Confetti ───────────────────────────────────────────────────

  void _launchConfetti() {
    final rng = math.Random();
    _confettiParticles.clear();
    for (int i = 0; i < 40; i++) {
      _confettiParticles.add(
        _ConfettiParticle(
          x: rng.nextDouble(),
          y: -0.1 - rng.nextDouble() * 0.3,
          vx: (rng.nextDouble() - 0.5) * 0.004,
          vy: 0.002 + rng.nextDouble() * 0.004,
          size: 4 + rng.nextDouble() * 6,
          color: [
            KinrelColors.orange,
            KinrelColors.amber,
            KinrelColors.brightGold,
            KinrelColors.gold,
            KinrelColors.coral,
            Colors.white,
          ][rng.nextInt(6)],
          rotation: rng.nextDouble() * math.pi * 2,
          rotationSpeed: (rng.nextDouble() - 0.5) * 0.15,
        ),
      );
    }
    _confettiCtrl.forward(from: 0);
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.94,
      child: Stack(
        children: [
          // Main content
          Padding(
            padding: EdgeInsets.only(
              left: KinrelSpacing.base,
              right: KinrelSpacing.base,
              top: KinrelSpacing.lg,
              bottom: math.max(bottomInset, KinrelSpacing.xl),
            ),
            child: Column(
              children: [
                // Handle bar
                _buildHandleBar(),
                SizedBox(height: 16),

                // Title + step indicator
                _buildHeader(),
                SizedBox(height: 16),

                // Step indicators (wizard mode only)
                if (!_isEditMode) ...[
                  _buildStepIndicators(),
                  SizedBox(height: 20),
                ],

                // Content
                Expanded(
                  child: _isEditMode
                      ? _buildEditModeContent()
                      : _buildStepContent(),
                ),

                // Bottom actions
                if (!_showSuccess) _buildBottomActions(),
              ],
            ),
          ),

          // Confetti overlay
          if (_showSuccess)
            Positioned.fill(
              child: IgnorePointer(
                child: KinrelAnimatedBuilder(
                  animation: _confettiCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ConfettiPainter(
                        particles: _confettiParticles,
                        progress: _confettiCtrl.value,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Handle bar ─────────────────────────────────────────────────

  Widget _buildHandleBar() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: KinrelColors.textDim.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _buildHeader() {
    final title = _isEditMode
        ? 'Edit Person'
        : _showSuccess
        ? 'Welcome! 🎉'
        : _stepTitle;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
        ),
        if (_currentStep > 0 && !_isEditMode && !_showSuccess)
          IconButton(
            onPressed: _prevStep,
            icon: Icon(Icons.arrow_back_ios_new, size: 18),
            color: KinrelColors.textSilver,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
          ),
      ],
    );
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Add Family Member';
      case 1:
        return 'Relationship';
      case 2:
        return 'More Details';
      case 3:
        return 'Confirm';
      default:
        return 'Add Family Member';
    }
  }

  // ── Step indicators ────────────────────────────────────────────

  Widget _buildStepIndicators() {
    return Row(
      children: List.generate(_kStepCount, (i) {
        final isActive = i == _currentStep;
        final isCompleted = i < _currentStep;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _kStepCount - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              decoration: BoxDecoration(
                color: isCompleted
                    ? KinrelColors.orange
                    : isActive
                    ? KinrelColors.orange.withValues(alpha: 0.6)
                    : KinrelColors.textDim.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Edit mode content ──────────────────────────────────────────

  Widget _buildEditModeContent() {
    return SingleChildScrollView(
      child: Form(
        key: _editFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name
            _SectionLabel('Full Name *'),
            SizedBox(height: 6),
            _buildTextField(
              controller: _nameController,
              hint: 'Full name',
              isLarge: true,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) => nameValidator(v),
            ),
            SizedBox(height: 16),

            // Gender
            _SectionLabel('Gender'),
            SizedBox(height: 8),
            _buildGenderCards(),
            SizedBox(height: 16),

            // DOB
            _SectionLabel('Date of Birth'),
            SizedBox(height: 6),
            _buildDateField(),
            SizedBox(height: 16),

            // Anniversary (optional)
            _SectionLabel('Anniversary Date (optional)'),
            SizedBox(height: 6),
            _buildAnniversaryField(),
            SizedBox(height: 16),

            // City
            _SectionLabel('City / Village'),
            SizedBox(height: 6),
            _buildTextField(
              controller: _cityController,
              hint: 'City or village',
            ),
            SizedBox(height: 16),

            // Gotra
            _SectionLabel('Gotra'),
            SizedBox(height: 6),
            _buildTextField(controller: _gotraController, hint: 'Gotra'),
            SizedBox(height: 16),

            // Occupation
            _SectionLabel('Occupation'),
            SizedBox(height: 6),
            _buildTextField(
              controller: _occupationController,
              hint: 'Occupation',
            ),
            SizedBox(height: 16),

            // Deceased
            _buildDeceasedToggle(),
            SizedBox(height: 28),

            // Save button
            _buildIgniteButton(
              label: 'Save Changes',
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step content ───────────────────────────────────────────────

  Widget _buildStepContent() {
    if (_showSuccess) return _buildSuccessView();

    switch (_currentStep) {
      case 0:
        return _buildStep0BasicInfo();
      case 1:
        return _buildStep1Relationship();
      case 2:
        return _buildStep2AdditionalDetails();
      case 3:
        return _buildStep3Confirmation();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── STEP 0: Basic Info ─────────────────────────────────────────

  Widget _buildStep0BasicInfo() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo picker (gated by kEnablePhotoPicker)
          if (kEnablePhotoPicker) ...[
            Center(child: _buildPhotoPicker()),
            SizedBox(height: 24),
          ],

          // Full name (large, prominent)
          _SectionLabel('Full Name *'),
          SizedBox(height: 6),
          _buildTextField(
            controller: _nameController,
            hint: 'Enter full name',
            isLarge: true,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: (v) => nameValidator(v),
          ),
          SizedBox(height: 16),

          // Nickname
          _SectionLabel('Nickname'),
          SizedBox(height: 6),
          _buildTextField(
            controller: _nicknameController,
            hint: 'Optional nickname',
          ),
          SizedBox(height: 20),

          // Gender
          _SectionLabel('Gender'),
          SizedBox(height: 8),
          _buildGenderCards(),
          SizedBox(height: 20),

          // Date of Birth
          _SectionLabel('Date of Birth'),
          SizedBox(height: 6),
          _buildDateField(),
        ],
      ),
    );
  }

  /// Locally-picked avatar; uploaded on submit when kEnablePhotoPicker is on.
  XFile? _pickedPhoto;

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        if (!kEnablePhotoPicker) {
          context.showSnackBar('Photo picker coming soon');
          return;
        }
        final picked = await PhotoPickerService.pickWithSheet(context);
        if (picked != null && mounted) {
          setState(() => _pickedPhoto = picked);
        }
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: KinrelGradients.igniteGradient,
        ),
        child: Container(
          margin: EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.darkElevated,
          ),
          child: ClipOval(child: _buildPhotoPickerInner()),
        ),
      ),
    );
  }

  Widget _buildPhotoPickerInner() {
    if (kEnablePhotoPicker && _pickedPhoto != null) {
      return FutureBuilder<Uint8List>(
        future: _pickedPhoto!.readAsBytes(),
        builder: (context, snap) {
          if (snap.hasData) {
            return Image.memory(
              snap.data!,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            );
          }
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt_outlined,
            color: KinrelColors.textSilver,
            size: 24,
          ),
          SizedBox(height: 2),
          Text(
            'Add Photo',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  /// Uploads the locally-picked avatar (if any) and writes its URL onto the
  /// Person row. Uses a direct Supabase update — same pattern as relationship
  /// creation in [_submit]. Never throws; falls back to initials on failure.
  Future<void> _uploadPickedPhoto(String personId) async {
    final photo = _pickedPhoto;
    if (photo == null) return;
    final url = await PhotoPickerService.uploadAvatar(photo);
    if (url == null) return;
    try {
      final client = ref.read(supabaseProvider);
      await client?.from('Person').update({'photoUrl': url}).eq('id', personId);
    } catch (e) {
      debugPrint('[ADD-MEMBER] photo url update failed: $e');
    }
  }

  Widget _buildGenderCards() {
    return Row(
      children: [
        Expanded(
          child: _GenderCard(
            label: 'Male',
            icon: Icons.male,
            selected: _selectedGender == 'male',
            onTap: () => setState(() => _selectedGender = 'male'),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _GenderCard(
            label: 'Female',
            icon: Icons.female,
            selected: _selectedGender == 'female',
            onTap: () => setState(() => _selectedGender = 'female'),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _GenderCard(
            label: 'Other',
            icon: Icons.person,
            selected: _selectedGender == 'other',
            onTap: () => setState(() => _selectedGender = 'other'),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return GestureDetector(
      onTap: _pickDate,
      child: AbsorbPointer(
        child: TextFormField(
          controller: _dobController,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.none,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textWhite,
          ),
          decoration: _inputDecoration('YYYY-MM-DD').copyWith(
            suffixIcon: Icon(
              Icons.calendar_today_outlined,
              color: KinrelColors.textDim,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnniversaryField() {
    return GestureDetector(
      onTap: _pickAnniversaryDate,
      child: AbsorbPointer(
        child: TextFormField(
          controller: _anniversaryController,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.none,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textWhite,
          ),
          decoration: _inputDecoration('YYYY-MM-DD (optional)').copyWith(
            suffixIcon: Icon(
              Icons.favorite_outline,
              color: KinrelColors.textDim,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  // ── STEP 1: Relationship ───────────────────────────────────────

  /// v5.13: Builds the "Related to" person picker control.
  /// Shows the currently selected target person (or a prompt to pick one).
  /// Tapping opens a bottom sheet listing all existing family members.
  Widget _buildTargetPersonPicker() {
    final target = _selectedTargetPerson;
    final hasSelection = target != null;

    return GestureDetector(
      onTap: _pickTargetPerson,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: hasSelection
                ? KinrelColors.orange.withValues(alpha: 0.3)
                : KinrelColors.textDim.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            // Avatar or placeholder
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasSelection
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.textDim.withValues(alpha: 0.1),
              ),
              child: Icon(
                hasSelection ? Icons.person : Icons.person_add,
                color: hasSelection ? KinrelColors.orange : KinrelColors.textDim,
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            // Name or prompt
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasSelection ? target!.name : 'Select a family member…',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hasSelection
                          ? KinrelColors.textWhite
                          : KinrelColors.textDim,
                    ),
                  ),
                  if (hasSelection && target!.isAnchor)
                    Text(
                      'Family anchor',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
            // Change icon
            Icon(
              hasSelection ? Icons.swap_horiz : Icons.chevron_right,
              color: KinrelColors.textDim,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// v5.13: Opens a bottom sheet to pick the target person.
  /// Lists all existing family members (excluding the new person being added).
  Future<void> _pickTargetPerson() async {
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    final members = membersAsync.valueOrNull ?? [];

    // Filter: exclude the person being edited (if in edit mode)
    final eligible = members
        .where((m) => m.deletedAt == null && m.id != widget.existingPerson?.id)
        .toList();

    if (eligible.isEmpty) {
      return;
    }

    // Default preselection: prefer the viewer's own Person, then the anchor
    Person? preselected;
    // Try viewer's own Person
    try {
      final viewerId = ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;
      if (viewerId != null) {
        preselected = eligible.firstWhere(
          (m) => m.id == viewerId,
          orElse: () => eligible.first,
        );
      }
    } catch (_) {}
    preselected ??= eligible.firstWhere(
      (m) => m.isAnchor,
      orElse: () => eligible.first,
    );

    final picked = await showModalBottomSheet<Person>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) => SafeArea(
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
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Who is the new member related to?',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1.0),
            // Member list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: eligible.length,
                itemBuilder: (ctx, i) {
                  final p = eligible[i];
                  final isSelected = _selectedTargetPerson?.id == p.id ||
                      (preselected?.id == p.id && _selectedTargetPerson == null);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
                      backgroundImage: p.photoUrl != null && p.photoUrl!.isNotEmpty
                          ? NetworkImage(p.photoUrl!)
                          : null,
                      child: (p.photoUrl == null || p.photoUrl!.isEmpty)
                          ? Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: KinrelColors.orange,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      p.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    subtitle: p.isAnchor
                        ? Text(
                            'Family anchor',
                            style: TextStyle(
                              fontSize: 11,
                              color: KinrelColors.textDim,
                            ),
                          )
                        : null,
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: KinrelColors.orange, size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, p),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() => _selectedTargetPerson = picked);
      debugPrint('[ADD-MEMBER] v5.13: User selected target person: ${picked.name} (${picked.id})');
    }
  }

  Widget _buildStep1Relationship() {
    final anchor = _effectiveAnchorPerson;
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';

    // v5.13: Determine if the "Related to" picker should be shown.
    // Show it when NO anchorPerson was explicitly passed (generic Add flow).
    // When anchorPerson IS passed (node context menu), show a read-only label.
    final bool showTargetPicker = widget.anchorPerson == null && !_isEditMode;
    final bool familyHasMembers = _familyHasExistingMembers;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // v5.13: "Related to" person picker — lets the user choose WHICH
          // existing member the new person relates to.
          if (familyHasMembers && showTargetPicker) ...[
            _SectionLabel('Related to *'),
            SizedBox(height: 8),
            _buildTargetPersonPicker(),
            SizedBox(height: 20),
          ] else if (widget.anchorPerson != null) ...[
            // Non-editable confirmation label when target was passed from context
            _SectionLabel('Related to'),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, color: KinrelColors.orange, size: 20),
                  SizedBox(width: 10),
                  Text(
                    widget.anchorPerson!.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
          ],

          // Question
          if (anchor != null) ...[
            Text(
              'How is $newName related to ${anchor.name}?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            SizedBox(height: 20),

            // Two portrait cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PortraitCard(
                  name: anchor.name,
                  gender: anchor.gender,
                  label: 'Existing',
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        color: KinrelColors.orange,
                        size: 28,
                      ),
                      SizedBox(height: 4),
                      Text(
                        _selectedRelType?.toUpperCase() ?? '?',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          color: KinrelColors.orange,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                _PortraitCard(
                  name: newName,
                  gender: _selectedGender,
                  label: 'New',
                  isNew: true,
                ),
              ],
            ),
            SizedBox(height: 28),
          ] else if (!familyHasMembers) ...[
            Text(
              'This is the first member of the family. No relationship needed yet.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                color: KinrelColors.textSilver,
              ),
            ),
            SizedBox(height: 20),
          ],

          // Relationship type cards
          _SectionLabel('Relationship Type'),
          SizedBox(height: 10),
          _buildRelationshipTypeCards(),
          SizedBox(height: 16),

          // Sub-type for siblings
          if (_selectedRelType == 'sibling') ...[
            SizedBox(height: 8),
            _SectionLabel('Elder or Younger?'),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SelectableCard(
                    label: 'Elder',
                    subtitle: 'Older sibling',
                    icon: Icons.arrow_upward,
                    selected: _selectedSubType == 'elder',
                    onTap: () => setState(() => _selectedSubType = 'elder'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _SelectableCard(
                    label: 'Younger',
                    subtitle: 'Younger sibling',
                    icon: Icons.arrow_downward,
                    selected: _selectedSubType == 'younger',
                    onTap: () => setState(() => _selectedSubType = 'younger'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
          ],

          // Detailed relationship picker
          SizedBox(height: 8),
          _SectionLabel('Or pick a specific kinship term'),
          SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDetailedRelationship,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.textDim.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: KinrelColors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedRelationshipLabel ?? 'Search all kinship terms…',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _selectedRelationshipLabel != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: KinrelColors.textDim,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // v80: Add Your Own Kinship
          SizedBox(height: 8),
          _SectionLabel('Or create your own'),
          SizedBox(height: 8),
          GestureDetector(
            onTap: _showCustomKinshipDialog,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: _customKinshipName != null
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : KinrelColors.textDim.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, color: KinrelColors.purple, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _customKinshipName ?? 'Add Your Own Kinship',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _customKinshipName != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ),
                  if (_customKinshipName != null) ...[
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: Color(_customNodeColorValue),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                    SizedBox(width: 4),
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: Color(_customLineColorValue),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  Icon(Icons.chevron_right, color: KinrelColors.textDim, size: 18),
                ],
              ),
            ),
          ),

          // Visual preview
          if (_relationshipPreview.isNotEmpty) ...[
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    color: KinrelColors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _relationshipPreview,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Mandatory hint when no relationship selected but family has existing members
          if (_familyHasExistingMembers && _effectiveRelationshipKey == null) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: KinrelColors.orange,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please select how they are related to proceed',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRelationshipTypeCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SelectableCard(
                label: 'Parent',
                subtitle: 'Father / Mother',
                icon: Icons.family_restroom,
                selected: _selectedRelType == 'parent',
                onTap: () => setState(() {
                  _selectedRelType = 'parent';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _SelectableCard(
                label: 'Child',
                subtitle: 'Son / Daughter',
                icon: Icons.child_care,
                selected: _selectedRelType == 'child',
                onTap: () => setState(() {
                  _selectedRelType = 'child';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SelectableCard(
                label: 'Spouse',
                subtitle: 'Husband / Wife',
                icon: Icons.favorite,
                selected: _selectedRelType == 'spouse',
                onTap: () => setState(() {
                  _selectedRelType = 'spouse';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _SelectableCard(
                label: 'Sibling',
                subtitle: 'Brother / Sister',
                icon: Icons.people,
                selected: _selectedRelType == 'sibling',
                onTap: () => setState(() {
                  _selectedRelType = 'sibling';
                  _selectedSubType = null;
                  _selectedRelationshipKey = null;
                  _selectedRelationshipLabel = null;
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── STEP 2: Additional Details ─────────────────────────────────

  Widget _buildStep2AdditionalDetails() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Collapsible sections
          _buildCollapsibleSection(
            title: 'Location Details',
            icon: Icons.location_on_outlined,
            isExpanded: _locationExpanded,
            onExpansionChanged: (v) => setState(() => _locationExpanded = v),
            children: [
              _SectionLabel('Birth Place'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _birthPlaceController,
                hint: 'Birth place',
              ),
              SizedBox(height: 14),
              _SectionLabel('Current City'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _cityController,
                hint: 'Current city',
              ),
            ],
          ),

          SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Contact Information',
            icon: Icons.phone_outlined,
            isExpanded: _contactExpanded,
            onExpansionChanged: (v) => setState(() => _contactExpanded = v),
            children: [
              _SectionLabel('Phone'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _phoneController,
                hint: 'Phone number',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
              ),
              SizedBox(height: 14),
              _SectionLabel('Email'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _emailController,
                hint: 'Email address',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
              ),
            ],
          ),

          SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Professional & Personal',
            icon: Icons.work_outline,
            isExpanded: _personalExpanded,
            onExpansionChanged: (v) => setState(() => _personalExpanded = v),
            children: [
              _SectionLabel('Occupation'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _occupationController,
                hint: 'Occupation',
              ),
              SizedBox(height: 14),
              _SectionLabel('Gotra'),
              SizedBox(height: 6),
              _buildTextField(controller: _gotraController, hint: 'Gotra'),
              SizedBox(height: 14),
              _SectionLabel('Bio / Notes'),
              SizedBox(height: 6),
              _buildTextField(
                controller: _bioController,
                hint: 'Short bio or notes',
                maxLines: 3,
              ),
            ],
          ),

          SizedBox(height: 12),

          // Deceased section (always visible)
          _buildDeceasedSection(),
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(color: KinrelColors.textDim.withValues(alpha: 0.08)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          initiallyExpanded: isExpanded,
          onExpansionChanged: onExpansionChanged,
          leading: Icon(icon, color: KinrelColors.orange, size: 20),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          trailing: Icon(
            isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: KinrelColors.textDim,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildDeceasedSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: _isDeceased
              ? KinrelColors.error.withValues(alpha: 0.3)
              : KinrelColors.textDim.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isDeceased ? Icons.cloud : Icons.cloud_outlined,
                color: _isDeceased ? KinrelColors.error : KinrelColors.textDim,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mark as Deceased',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isDeceased
                        ? KinrelColors.error
                        : KinrelColors.textWhite,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _isDeceased,
                onChanged: (v) => setState(() => _isDeceased = v),
                activeThumbColor: KinrelColors.error,
                activeTrackColor: KinrelColors.error.withValues(alpha: 0.4),
              ),
            ],
          ),
          if (_isDeceased) ...[
            SizedBox(height: 12),
            GestureDetector(
              onTap: _pickDeathDate,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: KinrelColors.textDim,
                      size: 16,
                    ),
                    SizedBox(width: 10),
                    Text(
                      _selectedDeathDate != null
                          ? 'Date of death: ${_selectedDeathDate!.toIso8601String().split('T').first}'
                          : 'Select date of death',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: _selectedDeathDate != null
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── STEP 3: Confirmation ───────────────────────────────────────

  Widget _buildStep3Confirmation() {
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';
    final anchor = widget.anchorPerson;
    final relLabel = _effectiveRelationshipKey?.snakeToTitle ?? 'Not specified';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary card
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _isDeceased
                        ? LinearGradient(
                            colors: [
                              KinrelColors.textDim,
                              KinrelColors.darkSurface,
                            ],
                          )
                        : KinrelGradients.igniteGradient,
                  ),
                  child: Center(
                    child: Text(
                      newName.isNotEmpty ? newName[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Name
                Text(
                  newName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Relationship
                if (anchor != null && _effectiveRelationshipKey != null) ...[
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${anchor.name}\'s $relLabel',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                ],

                SizedBox(height: 16),

                // Detail rows
                _ConfirmationRow(
                  icon: Icons.wc,
                  label: 'Gender',
                  value: _selectedGender.capitalized,
                ),
                if (_selectedDob != null)
                  _ConfirmationRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date of Birth',
                    value: _dobController.text,
                  ),
                if (_cityController.text.trim().isNotEmpty)
                  _ConfirmationRow(
                    icon: Icons.location_on_outlined,
                    label: 'City',
                    value: _cityController.text.trim(),
                  ),
                if (_isDeceased)
                  _ConfirmationRow(
                    icon: Icons.cloud,
                    label: 'Status',
                    value: 'Deceased',
                    valueColor: KinrelColors.error,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Success view ───────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.check_circle,
              color: KinrelColors.orange,
              size: 48,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Welcome to the family!',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '${_nameController.text.trim()} has been added',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }

  // ── Deceased toggle (edit mode) ────────────────────────────────

  Widget _buildDeceasedToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border: Border.all(color: KinrelColors.textDim.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Deceased',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          Switch.adaptive(
            value: _isDeceased,
            onChanged: (v) => setState(() => _isDeceased = v),
            activeThumbColor: KinrelColors.orange,
            activeTrackColor: KinrelColors.orange.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  // ── Bottom actions ─────────────────────────────────────────────

  Widget _buildBottomActions() {
    if (_isEditMode) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 12),
      child: Row(
        children: [
          // Skip / Back
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _prevStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.textSilver,
                  side: BorderSide(
                    color: KinrelColors.textDim.withValues(alpha: 0.3),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                  ),
                ),
                child: Text(
                  'Back',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) SizedBox(width: 12),

          // Next / Submit
          Expanded(
            flex: _currentStep > 0 ? 2 : 1,
            child: _currentStep == _kStepCount - 1
                ? _buildIgniteButton(
                    label: 'Add to Family',
                    onPressed: _isSubmitting || !_canProceed() ? null : _submit,
                    isLoading: _isSubmitting,
                  )
                : _buildIgniteButton(
                    label: _currentStep == 1 && !_canProceed()
                        ? (_selectedTargetPerson == null && widget.anchorPerson == null
                            ? 'Next (select target & relationship)'
                            : 'Next (select relationship)')
                        : _currentStep == 0 && !_canProceed()
                            ? 'Next (name required)'
                            : 'Next',
                    onPressed: _canProceed() ? _nextStep : null,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────

  Widget _buildIgniteButton({
    required String label,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    final isDisabled = onPressed == null;
    return Container(
      decoration: BoxDecoration(
        gradient: isDisabled ? null : KinrelGradients.igniteGradient,
        color: isDisabled ? KinrelColors.orange.withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool isLarge = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.done,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      // v62.5: onChanged triggers setState so the Next/Add button
      // updates immediately as the user types — no 5s delay.
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontFamily: isLarge
            ? KinrelTypography.displayFont
            : KinrelTypography.bodyFont,
        fontSize: isLarge ? 20 : 15,
        fontWeight: isLarge ? FontWeight.w600 : FontWeight.w400,
        color: KinrelColors.textWhite,
      ),
      cursorColor: KinrelColors.orange,
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: KinrelColors.textDim, // #8A7A72 per spec
        fontFamily: KinrelTypography.bodyFont,
      ),
      filled: true,
      fillColor: KinrelColors.darkElevated, // #202338 per spec
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(
          color: KinrelColors.textDim.withValues(alpha: 0.1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(color: KinrelColors.orange), // #E8612A focus
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        borderSide: BorderSide(color: KinrelColors.error),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: KinrelColors.textSilver, // #C9B4A8
      ),
    );
  }
}

/// Elegant gender card with orange border on selected.
class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.1)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: selected
                ? KinrelColors.orange
                : KinrelColors.textDim.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? KinrelColors.orange : KinrelColors.textDim,
              size: 22,
            ),
            SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? KinrelColors.orange : KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable card for relationship types (Parent, Child, Spouse, Sibling).
class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.08)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: selected
                ? KinrelColors.orange
                : KinrelColors.textDim.withValues(alpha: 0.1),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: selected ? KinrelColors.orange : KinrelColors.textDim,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? KinrelColors.orange
                          : KinrelColors.textWhite,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Portrait card showing a person in the relationship step.
class _PortraitCard extends StatelessWidget {
  const _PortraitCard({
    required this.name,
    this.gender,
    required this.label,
    this.isNew = false,
  });

  final String name;
  final String? gender;
  final String label;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isNew
                ? KinrelGradients.igniteGradient
                : LinearGradient(
                    colors: [KinrelColors.darkElevated, KinrelColors.darkCard],
                  ),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          name.length > 10 ? '${name.substring(0, 9)}…' : name,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

/// Confirmation detail row.
class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({
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
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KinrelColors.textDim),
          SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
          Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? KinrelColors.textWhite,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CONFETTI
// ═══════════════════════════════════════════════════════════════════

class _ConfettiParticle {
  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  double rotation;
  final double rotationSpeed;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Simulate movement
      final x = (p.x + p.vx * progress * size.width * 100) * size.width;
      final y = (p.y + p.vy * progress * size.height * 100) * size.height;
      final rotation = p.rotation + p.rotationSpeed * progress * 100;

      // Fade out near end
      final opacity = progress > 0.7 ? (1.0 - progress) / 0.3 : 1.0;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

/// v80: Preview painter for the custom kinship line + dot
class _LinePreviewPainter extends CustomPainter {
  final Color color;
  final bool isDashed;
  final String dotType;

  _LinePreviewPainter({
    required this.color,
    required this.isDashed,
    required this.dotType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midY = size.height / 2;
    if (isDashed) {
      double x = 0;
      const dashWidth = 6.0;
      const dashGap = 4.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, midY),
          Offset((x + dashWidth).clamp(0, size.width), midY),
          paint,
        );
        x += dashWidth + dashGap;
      }
    } else {
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);
    }

    // Draw dot/heart at midpoint
    if (dotType != 'none') {
      final midX = size.width / 2;
      if (dotType == 'heart') {
        // Simple pink heart (circle for preview)
        canvas.drawCircle(
          Offset(midX, midY),
          4,
          Paint()..color = const Color(0xFFEC4899),
        );
      } else {
        canvas.drawCircle(
          Offset(midX, midY),
          4,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePreviewPainter old) =>
      color != old.color || isDashed != old.isDashed || dotType != old.dotType;
}
