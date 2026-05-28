import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import 'relationship_picker_sheet.dart';

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
  });

  final String familyId;

  /// When non-null, the sheet is in **edit mode** for this person.
  final Person? existingPerson;

  /// When non-null (and not edit mode), the sheet opens the
  /// "Add relative" flow with this person as the anchor in Step 1.
  final Person? anchorPerson;

  /// Show as a full-screen bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    Person? existingPerson,
    Person? anchorPerson,
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
  bool _isDeceased = false;
  bool _isSubmitting = false;
  DateTime? _selectedDob;
  DateTime? _selectedDeathDate;
  bool _locationExpanded = false;
  bool _contactExpanded = false;
  bool _personalExpanded = false;
  bool _showSuccess = false;

  // ── Confetti particles ─────────────────────────────────────────
  final _confettiParticles = <_ConfettiParticle>[];
  late final AnimationController _confettiCtrl;

  bool get _isEditMode => widget.existingPerson != null;

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
    }
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _dobController.dispose();
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
        return true; // Relationship is optional
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
    final anchor = widget.anchorPerson;
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
        _selectedRelType = null; // clear simple type
        _selectedSubType = null;
      });
    }
  }

  /// Resolve the effective relationship key from type + gender + sub-type.
  String? get _effectiveRelationshipKey {
    if (_selectedRelationshipKey != null) return _selectedRelationshipKey;

    final gender = _selectedGender;
    switch (_selectedRelType) {
      case 'parent':
        return gender == 'female' ? 'mother' : 'father';
      case 'child':
        return gender == 'female' ? 'daughter' : 'son';
      case 'spouse':
        return gender == 'female' ? 'wife' : 'husband';
      case 'sibling':
        if (_selectedSubType == 'elder') {
          return gender == 'female' ? 'elder_sister' : 'elder_brother';
        } else if (_selectedSubType == 'younger') {
          return gender == 'female' ? 'younger_sister' : 'younger_brother';
        }
        return gender == 'female' ? 'sister' : 'brother';
      default:
        return null;
    }
  }

  /// Human-readable preview sentence.
  String get _relationshipPreview {
    final key = _effectiveRelationshipKey;
    if (key == null) return '';
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';
    final anchorName = widget.anchorPerson?.name ?? 'existing member';
    final label = _selectedRelationshipLabel ?? key.snakeToTitle;
    return '$anchorName will be the $label of $newName';
  }

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      Person result;

      if (_isEditMode) {
        result = await updatePerson(
          ref: ref,
          personId: widget.existingPerson!.id,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
        );
      } else {
        result = await addMemberOptimistic(
          ref: ref,
          familyId: widget.familyId,
          name: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _dobController.text.trim().isEmpty
              ? null
              : _dobController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          gotra: _gotraController.text.trim().isEmpty
              ? null
              : _gotraController.text.trim(),
          isDeceased: _isDeceased,
        );

        // Create the relationship if one was selected
        final relKey = _effectiveRelationshipKey;
        if (relKey != null && widget.anchorPerson != null) {
          try {
            await createRelationshipBetween(
              ref: ref,
              familyId: widget.familyId,
              fromPersonId: widget.anchorPerson!.id,
              toPersonId: result.id,
              relationshipKey: relKey,
            );
          } catch (e) {
            // Relationship creation is best-effort; person is already created
            debugPrint('⚠️ Relationship creation failed: $e');
          }
        }
      }

      if (!mounted) return;

      // Success celebration
      unawaited(HapticFeedback.mediumImpact());
      _launchConfetti();

      setState(() {
        _isSubmitting = false;
        _showSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 1800));

      if (!mounted) return;
      context.showSnackBar(
        _isEditMode
            ? 'Person updated successfully'
            : 'Welcome to the family, ${result.name}!',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
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
                child: AnimatedBuilder(
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
        key: GlobalKey<FormState>(),
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
          // Photo picker
          Center(child: _buildPhotoPicker()),
          SizedBox(height: 24),

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

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: () {
        // TODO: Implement camera/gallery picker with crop tool
        // Requires image_picker package
        HapticFeedback.lightImpact();
        context.showSnackBar('Photo picker coming soon');
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
          child: Center(
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
          ),
        ),
      ),
    );
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

  // ── STEP 1: Relationship ───────────────────────────────────────

  Widget _buildStep1Relationship() {
    final anchor = widget.anchorPerson;
    final newName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'New Member';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          ] else ...[
            Text(
              'Select the relationship type.',
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
                    label: _currentStep == 0 && !_canProceed()
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
