import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';

class CreateFamilyScreen extends ConsumerStatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  ConsumerState<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends ConsumerState<CreateFamilyScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 3;
  bool _isSubmitting = false;

  // Step 1: Family Identity
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  SupportedLanguage? _selectedLanguage;
  String _selectedRegion = 'North India';
  bool _isCustomCode = false;

  // Step 2: Privacy & Setup
  _PrivacyMode _privacyMode = _PrivacyMode.inviteOnly;

  // Step 3: Add Yourself
  final _personNameController = TextEditingController();
  final _birthYearController = TextEditingController();
  String? _selectedGender;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _codeController.dispose();
    _personNameController.dispose();
    _birthYearController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!_isCustomCode) {
      final slug = _nameController.text
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final suffix = _generateCodeSuffix();
      _codeController.text = slug.isEmpty ? '' : '$slug-$suffix';
    }
  }

  String _generateCodeSuffix() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  String get _fullFamilyCode => 'kinrel.co/f/${_codeController.text}';

  bool get _canProceedStep1 =>
      _nameController.text.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty;

  bool get _canProceedStep3 => _personNameController.text.trim().isNotEmpty;

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      setState(() => _currentStep--    );
    } else {
      context.pop();
    }
  }

  Future<void> _submit() async {
    if (_personNameController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      // Step 1: Create the family
      final family = await createFamily(
        ref: ref,
        name: _nameController.text.trim(),
        description: null,
        primaryLanguage: _selectedLanguage?.code,
        region: _selectedRegion,
        privacyMode: _privacyMode == _PrivacyMode.private
            ? 'private'
            : _privacyMode == _PrivacyMode.inviteOnly
                ? 'invite'
                : 'link',
      );

      // Step 2: Create the anchor person
      final birthYear = int.tryParse(_birthYearController.text.trim());
      await createPerson(
        ref: ref,
        familyId: family.id,
        name: _personNameController.text.trim(),
        gender: _selectedGender?.toLowerCase(),
        birthYear: birthYear,
        isAnchor: true,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      context.showSnackBar('Family "${family.name}" created! You\'re the anchor!');
      context.go('/family/${family.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);

        String errorMsg = e.toString();
        if (errorMsg.startsWith('Exception: ')) {
          errorMsg = errorMsg.substring(11);
        }
        if (errorMsg.contains('row-level security')) {
          errorMsg = 'Permission denied. Please contact support.';
        } else if (errorMsg.contains('JWT expired')) {
          errorMsg = 'Session expired. Please sign in again.';
        } else if (errorMsg.contains('SocketException')) {
          errorMsg = 'No internet connection. Please try again.';
        } else if (errorMsg.contains('timed out')) {
          errorMsg = 'Connection timed out. Please try again.';
        }

        context.showSnackBar('Failed: $errorMsg', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _prevStep,
        ),
        title: Text(
          'Create Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          _StepIndicator(currentStep: _currentStep, totalSteps: _totalSteps),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1FamilyIdentity(
                  nameController: _nameController,
                  codeController: _codeController,
                  fullFamilyCode: _fullFamilyCode,
                  selectedLanguage: _selectedLanguage,
                  selectedRegion: _selectedRegion,
                  onLanguageChanged: (lang) =>
                      setState(() => _selectedLanguage = lang),
                  onRegionChanged: (region) =>
                      setState(() => _selectedRegion = region),
                  onEditCode: () {
                    setState(() => _isCustomCode = true);
                  },
                  canProceed: _canProceedStep1,
                ),
                _Step2PrivacySetup(
                  privacyMode: _privacyMode,
                  onPrivacyChanged: (mode) =>
                      setState(() => _privacyMode = mode),
                  familyName: _nameController.text.trim(),
                ),
                _Step3AddYourself(
                  nameController: _personNameController,
                  birthYearController: _birthYearController,
                  selectedGender: _selectedGender,
                  onGenderChanged: (g) =>
                      setState(() => _selectedGender = g),
                  canProceed: _canProceedStep3,
                ),
              ],
            ),
          ),

          // Bottom navigation
          _BottomNav(
            currentStep: _currentStep,
            totalSteps: _totalSteps,
            onBack: _prevStep,
            onNext: _nextStep,
            canProceed: _currentStep == 0
                ? _canProceedStep1
                : _currentStep == 2
                    ? _canProceedStep3
                    : true,
            isSubmitting: _isSubmitting,
          ),
        ],
      ),
    );
  }
}

// ── Step Indicator ────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            // Connector line
            final lineIndex = index ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: lineIndex < currentStep
                      ? KinrelColors.orange
                      : KinrelColors.darkSurface,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }
          // Dot
          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < currentStep;
          final isCurrent = stepIndex == currentStep;

          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? KinrelColors.orange
                  : isCurrent
                      ? KinrelColors.orange.withValues(alpha: 0.2)
                      : KinrelColors.darkElevated,
              border: isCurrent
                  ? Border.all(color: KinrelColors.orange, width: 2)
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? KinrelColors.orange
                            : KinrelColors.textDim,
                      ),
                    ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Step 1: Family Identity ──────────────────────────────────────

class _Step1FamilyIdentity extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController codeController;
  final String fullFamilyCode;
  final SupportedLanguage? selectedLanguage;
  final String selectedRegion;
  final ValueChanged<SupportedLanguage?> onLanguageChanged;
  final ValueChanged<String> onRegionChanged;
  final VoidCallback onEditCode;
  final bool canProceed;

  const _Step1FamilyIdentity({
    required this.nameController,
    required this.codeController,
    required this.fullFamilyCode,
    required this.selectedLanguage,
    required this.selectedRegion,
    required this.onLanguageChanged,
    required this.onRegionChanged,
    required this.onEditCode,
    required this.canProceed,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Text(
            'Family Identity',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Give your family a name and choose your settings',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Family Name (large, Instagram-style)
          Text(
            'Family Name',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nameController,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Sharma Family',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textDim.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Family Code
          Row(
            children: [
              Text(
                'Family Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textSilver,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onEditCode,
                child: Text(
                  'Edit',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.input),
              border: Border.all(color: KinrelColors.darkSurface),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded,
                    size: 16, color: KinrelColors.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fullFamilyCode.isEmpty ? 'kinrel.co/f/' : fullFamilyCode,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      color: fullFamilyCode.isEmpty
                          ? KinrelColors.textDim
                          : KinrelColors.textSilver,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Language Selector
          Text(
            'Primary Language',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _LanguageDropdown(
            selectedLanguage: selectedLanguage,
            onChanged: onLanguageChanged,
          ),
          const SizedBox(height: 20),

          // Region Dropdown
          Text(
            'Region',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _RegionDropdown(
            selectedRegion: selectedRegion,
            onChanged: onRegionChanged,
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Privacy & Setup ──────────────────────────────────────

enum _PrivacyMode { private, inviteOnly, linkSharing }

class _Step2PrivacySetup extends StatelessWidget {
  final _PrivacyMode privacyMode;
  final ValueChanged<_PrivacyMode> onPrivacyChanged;
  final String familyName;

  const _Step2PrivacySetup({
    required this.privacyMode,
    required this.onPrivacyChanged,
    required this.familyName,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy & Setup',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Control who can see and join your family',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Privacy mode cards
          Text(
            'Privacy Mode',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 12),

          _PrivacyCard(
            icon: Icons.lock_outline_rounded,
            title: 'Private',
            description: 'Only you can see and manage this family',
            mode: _PrivacyMode.private,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.private),
          ),
          const SizedBox(height: 10),
          _PrivacyCard(
            icon: Icons.mail_outline_rounded,
            title: 'Invite-Only',
            description:
                'Family members can join by invitation or family code',
            mode: _PrivacyMode.inviteOnly,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.inviteOnly),
          ),
          const SizedBox(height: 10),
          _PrivacyCard(
            icon: Icons.link_rounded,
            title: 'Link-Sharing',
            description:
                'Anyone with the family link can request to join',
            mode: _PrivacyMode.linkSharing,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.linkSharing),
          ),

          const SizedBox(height: 32),

          // Avatar picker
          Text(
            'Family Avatar',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () {
                // TODO: Implement avatar upload
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Avatar upload coming soon!')),
                );
              },
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.darkElevated,
                  border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.3),
                      width: 2),
                ),
                child: familyName.isNotEmpty
                    ? Center(
                        child: Text(
                          familyName[0].toUpperCase(),
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.camera_alt_outlined,
                        size: 32,
                        color: KinrelColors.textDim,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Tap to upload or use initials',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Add Yourself ─────────────────────────────────────────

class _Step3AddYourself extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController birthYearController;
  final String? selectedGender;
  final ValueChanged<String?> onGenderChanged;
  final bool canProceed;

  const _Step3AddYourself({
    required this.nameController,
    required this.birthYearController,
    required this.selectedGender,
    required this.onGenderChanged,
    required this.canProceed,
  });

  @override
  Widget build(BuildContext context) {
    final genders = ['Male', 'Female', 'Non-Binary', 'Prefer not to say'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Yourself',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You are the anchor of this family tree',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Person icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KinrelGradients.igniteGradient,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Who are you in this family?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Name
          Text(
            'Your Name *',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nameController,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Rahul Sharma',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 20),

          // Birth Year
          Text(
            'Birth Year (optional)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: birthYearController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: KinrelColors.textWhite,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., 1990',
              hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),

          // Gender chips
          Text(
            'Gender (optional)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genders.map((gender) {
              final isSelected = selectedGender == gender;
              return GestureDetector(
                onTap: () =>
                    onGenderChanged(isSelected ? null : gender),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KinrelColors.orange.withValues(alpha: 0.2)
                        : KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? KinrelColors.orange
                          : KinrelColors.darkSurface,
                    ),
                  ),
                  child: Text(
                    gender,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? KinrelColors.orange
                          : KinrelColors.textSilver,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Navigation ────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool canProceed;
  final bool isSubmitting;

  const _BottomNav({
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
    required this.onNext,
    required this.canProceed,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          top: BorderSide(color: KinrelColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Back button
            if (currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KinrelColors.textSilver,
                    side: BorderSide(color: KinrelColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KinrelRadius.button),
                    ),
                  ),
                  child: Text(
                    'Back',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (currentStep > 0) const SizedBox(width: 12),

            // Next / Create button
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: canProceed && !isSubmitting ? onNext : null,
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      KinrelColors.orange.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelRadius.button),
                  ),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        currentStep == totalSteps - 1
                            ? 'Create Family'
                            : 'Next',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Privacy Card ─────────────────────────────────────────────────

class _PrivacyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final _PrivacyMode mode;
  final _PrivacyMode selectedMode;
  final VoidCallback onTap;

  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.mode,
    required this.selectedMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == selectedMode;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.08)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.card),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange.withValues(alpha: 0.5)
                : KinrelColors.darkSurface,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.darkElevated,
              ),
              child: Icon(icon,
                  size: 20,
                  color: isSelected
                      ? KinrelColors.orange
                      : KinrelColors.textDim),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? KinrelColors.textWhite
                          : KinrelColors.textSilver,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: KinrelColors.orange, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Language Dropdown ─────────────────────────────────────────────

class _LanguageDropdown extends StatelessWidget {
  final SupportedLanguage? selectedLanguage;
  final ValueChanged<SupportedLanguage?> onChanged;

  const _LanguageDropdown({
    required this.selectedLanguage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.input),
        border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SupportedLanguage>(
          value: selectedLanguage,
          hint: Text(
            'Select language',
            style: TextStyle(color: KinrelColors.textDim),
          ),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: KinrelColors.orange),
          dropdownColor: KinrelColors.darkElevated,
          items: SupportedLanguage.values.map((lang) {
            return DropdownMenuItem(
              value: lang,
              child: Row(
                children: [
                  Text(
                    lang.nativeName,
                    style: TextStyle(
                      color: KinrelColors.textWhite,
                      fontFamily: KinrelTypography.bodyFont,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${lang.name})',
                    style: TextStyle(
                      color: KinrelColors.textDim,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Region Dropdown ──────────────────────────────────────────────

class _RegionDropdown extends StatelessWidget {
  final String selectedRegion;
  final ValueChanged<String> onChanged;

  static const _regions = [
    'North India',
    'South India',
    'East India',
    'West India',
    'Central India',
    'North-East India',
    'Diaspora (Global)',
  ];

  const _RegionDropdown({
    required this.selectedRegion,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.input),
        border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedRegion,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: KinrelColors.orange),
          dropdownColor: KinrelColors.darkElevated,
          items: _regions.map((region) {
            return DropdownMenuItem(
              value: region,
              child: Text(
                region,
                style: TextStyle(
                  color: KinrelColors.textWhite,
                  fontFamily: KinrelTypography.bodyFont,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }
}
