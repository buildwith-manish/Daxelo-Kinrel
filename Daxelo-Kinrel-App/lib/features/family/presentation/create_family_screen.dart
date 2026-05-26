import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';

class CreateFamilyScreen extends ConsumerStatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  ConsumerState<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends ConsumerState<CreateFamilyScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static int _totalSteps = 3;
  bool _isSubmitting = false;

  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  SupportedLanguage? _selectedLanguage;
  String _selectedRegion = 'North India';
  bool _isCustomCode = false;

  _PrivacyMode _privacyMode = _PrivacyMode.inviteOnly;

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
    chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
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
        duration: Duration(milliseconds: 400),
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
    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _prevStep,
        ),
        title: Text(
          'Create Family',
          style: const TextStyle(
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
  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            final lineIndex = index ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: lineIndex < currentStep
                      ? DKColors.brandPurple
                      : DKColors.brandPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < currentStep;
          final isCurrent = stepIndex == currentStep;

          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? DKColors.brandPurple
                  : isCurrent
                      ? DKColors.brandPurple.withValues(alpha: 0.2)
                      : DKColors.elevatedColor(context),
              border: isCurrent
                  ? Border.all(color: DKColors.brandPurple, width: 2)
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? DKColors.brandPurple
                            : DKColors.textSecondary(context),
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

  final TextEditingController nameController;
  final TextEditingController codeController;
  final String fullFamilyCode;
  final SupportedLanguage? selectedLanguage;
  final String selectedRegion;
  final ValueChanged<SupportedLanguage?> onLanguageChanged;
  final ValueChanged<String> onRegionChanged;
  final VoidCallback onEditCode;
  final bool canProceed;


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative family illustration
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    DKColors.brandPurple.withValues(alpha: 0.15),
                    DKColors.brandViolet.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: DKColors.brandPurple.withValues(alpha: 0.2),
                  width: 2,
                ),),
              child: Icon(
                Icons.family_restroom_rounded,
                size: 36,
                color: DKColors.brandPurple,
              ),
            ),
          )
              .animate(onPlay: (c) => c.forward())
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          SizedBox(height: 24),

          // Section header
          Text(
            'Family Identity',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Give your family a name and choose your settings',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          SizedBox(height: 32),

          // Family Name
          Text(
            'Family Name',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: nameController,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
              height: 1.3,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Sharma Family',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: DKColors.textSecondary(context).withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            autofocus: true,
          ),
          SizedBox(height: 16),

          // Family Code
          Row(
            children: [
              Text(
                'Family Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: DKColors.textSecondary(context),
                ),
              ),
              Spacer(),
              GestureDetector(
                onTap: onEditCode,
                child: Text(
                  'Edit',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: DKColors.brandPurple,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DKCard(
            padding: 12,
            borderColor: DKColors.brandPurple.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.link_rounded,
                    size: 16, color: DKColors.textSecondary(context)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fullFamilyCode.isEmpty ? 'kinrel.co/f/' : fullFamilyCode,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 13,
                      color: fullFamilyCode.isEmpty
                          ? DKColors.textSecondary(context)
                          : DKColors.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),

          // Language Selector
          Text(
            'Primary Language',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          _LanguageDropdown(
            selectedLanguage: selectedLanguage,
            onChanged: onLanguageChanged,
          ),
          SizedBox(height: 20),

          // Region Dropdown
          Text(
            'Region',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
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
  const _Step2PrivacySetup({
    required this.privacyMode,
    required this.onPrivacyChanged,
    required this.familyName,
  });

  final _PrivacyMode privacyMode;
  final ValueChanged<_PrivacyMode> onPrivacyChanged;
  final String familyName;


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy & Setup',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Control who can see and join your family',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          SizedBox(height: 32),

          Text(
            'Privacy Mode',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          SizedBox(height: 12),

          _PrivacyCard(
            icon: Icons.lock_outline_rounded,
            title: 'Private',
            description: 'Only you can see and manage this family',
            mode: _PrivacyMode.private,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.private),
          ),
          SizedBox(height: 10),
          _PrivacyCard(
            icon: Icons.mail_outline_rounded,
            title: 'Invite-Only',
            description:
                'Family members can join by invitation or family code',
            mode: _PrivacyMode.inviteOnly,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.inviteOnly),
          ),
          SizedBox(height: 10),
          _PrivacyCard(
            icon: Icons.link_rounded,
            title: 'Link-Sharing',
            description:
                'Anyone with the family link can request to join',
            mode: _PrivacyMode.linkSharing,
            selectedMode: privacyMode,
            onTap: () => onPrivacyChanged(_PrivacyMode.linkSharing),
          ),

          SizedBox(height: 32),

          // Avatar picker
          Text(
            'Family Avatar',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          SizedBox(height: 12),
          Center(
            child: DKAvatar(
              initials: familyName.isNotEmpty ? familyName[0].toUpperCase() : '',
              size: DKAvatarSize.xl,
              borderColor: DKColors.brandGold.withValues(alpha: 0.4),
              backgroundColor: DKColors.brandPurple,
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Uses initials by default',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: DKColors.textSecondary(context),
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
  _Step3AddYourself({
    required this.nameController,
    required this.birthYearController,
    required this.selectedGender,
    required this.onGenderChanged,
    required this.canProceed,
  });

  final TextEditingController nameController;
  final TextEditingController birthYearController;
  final String? selectedGender;
  final ValueChanged<String?> onGenderChanged;
  final bool canProceed;


  @override
  Widget build(BuildContext context) {
    final genders = ['Male', 'Female', 'Non-Binary', 'Prefer not to say'];

    return SingleChildScrollView(
      padding: EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Yourself',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'You are the anchor of this family tree',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: DKColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          SizedBox(height: 32),

          // Person icon with purple glow
          Center(
            child: DKAvatar(
              initials: nameController.text.isNotEmpty
                  ? nameController.text[0].toUpperCase()
                  : '',
              size: DKAvatarSize.xl,
              backgroundColor: DKColors.brandPurple,
              showGlow: true,
              borderColor: DKColors.brandGold,
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Who are you in this family?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          SizedBox(height: 28),

          // Name
          Text(
            'Your Name *',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: nameController,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: DKColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Rahul Sharma',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: DKColors.textSecondary(context).withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            autofocus: true,
          ),
          SizedBox(height: 20),

          // Birth Year
          Text(
            'Birth Year (optional)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: birthYearController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: DKColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'e.g., 1990',
              hintStyle: TextStyle(
                  color: DKColors.textSecondary(context).withValues(alpha: 0.5)),
              filled: true,
              fillColor: DKColors.elevatedColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          SizedBox(height: 20),

          // Gender chips
          Text(
            'Gender (optional)',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genders.map((gender) {
              final isSelected = selectedGender == gender;
              return DKSuggestionChip(
                label: gender,
                isSelected: isSelected,
                onTap: () =>
                    onGenderChanged(isSelected ? null : gender),
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
  const _BottomNav({
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
    required this.onNext,
    required this.canProceed,
    required this.isSubmitting,
  });

  final int currentStep;
  final int totalSteps;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool canProceed;
  final bool isSubmitting;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: DKColors.cardColor(context),
        border: Border(
          top: BorderSide(color: DKColors.borderColor(context), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (currentStep > 0)
              Expanded(
                child: DKButton(
                  label: 'Back',
                  variant: DKButtonVariant.secondary,
                  onPressed: onBack,
                  size: DKButtonSize.md,
                ),
              ),
            if (currentStep > 0) SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DKButton(
                label: currentStep == totalSteps - 1
                    ? 'Create Family'
                    : 'Next',
                variant: currentStep == totalSteps - 1
                    ? DKButtonVariant.gradient
                    : DKButtonVariant.primary,
                onPressed: canProceed && !isSubmitting ? onNext : null,
                isLoading: isSubmitting,
                fullWidth: true,
                size: DKButtonSize.lg,
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
  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.mode,
    required this.selectedMode,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final _PrivacyMode mode;
  final _PrivacyMode selectedMode;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    final isSelected = mode == selectedMode;
    return DKCard(
      borderColor: isSelected
          ? DKColors.brandPurple.withValues(alpha: 0.5)
          : DKColors.borderColor(context),
      backgroundColor: isSelected
          ? DKColors.brandPurple.withValues(alpha: 0.06)
          : null,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? DKColors.brandPurple.withValues(alpha: 0.15)
                  : DKColors.elevatedColor(context),
            ),
            child: Icon(icon,
                size: 20,
                color: isSelected
                    ? DKColors.brandPurple
                    : DKColors.textSecondary(context)),
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
                        ? DKColors.textPrimary(context)
                        : DKColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: DKColors.textSecondary(context),
                    height: 1.4,
            ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle_rounded,
                color: DKColors.brandPurple, size: 22),
        ],
      ),
    );
  }
}

// ── Language Dropdown ─────────────────────────────────────────────

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.selectedLanguage,
    required this.onChanged,
  });

  final SupportedLanguage? selectedLanguage;
  final ValueChanged<SupportedLanguage?> onChanged;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: DKColors.elevatedColor(context),
        borderRadius: BorderRadius.circular(KinrelRadius.input),
        border: Border.all(
            color: DKColors.brandPurple.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SupportedLanguage>(
          value: selectedLanguage,
          hint: Text(
            'Select language',
            style: TextStyle(color: DKColors.textSecondary(context)),
          ),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: DKColors.brandPurple),
          dropdownColor: DKColors.cardColor(context),
          items: SupportedLanguage.values.map((lang) {
            return DropdownMenuItem(
              value: lang,
              child: Row(
                children: [
                  Text(
                    lang.nativeName,
                    style: TextStyle(
                      color: DKColors.textPrimary(context),
                      fontFamily: KinrelTypography.bodyFont,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '(${lang.name})',
                    style: TextStyle(
                      color: DKColors.textSecondary(context),
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
  const _RegionDropdown({
    required this.selectedRegion,
    required this.onChanged,
  });

  final String selectedRegion;
  final ValueChanged<String> onChanged;

  static _regions = [
    'North India',
    'South India',
    'East India',
    'West India',
    'Central India',
    'North-East India',
    'Diaspora (Global)',
  ];


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: DKColors.elevatedColor(context),
        borderRadius: BorderRadius.circular(KinrelRadius.input),
        border: Border.all(
            color: DKColors.brandPurple.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedRegion,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: DKColors.brandPurple),
          dropdownColor: DKColors.cardColor(context),
          items: _regions.map((region) {
            return DropdownMenuItem(
              value: region,
              child: Text(
                region,
                style: TextStyle(
                  color: DKColors.textPrimary(context),
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
