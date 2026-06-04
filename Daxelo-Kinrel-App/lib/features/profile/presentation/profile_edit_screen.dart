// lib/features/profile/presentation/profile_edit_screen.dart
//
// DAXELO KINREL — Profile Edit Screen
//
// Full edit screen for profile details with validation,
// unsaved changes dialog, and dark theme design.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/profile_provider.dart';
import '../../username/providers/username_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);
const Color _errorColor = Color(0xFFF04E2A);

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key, this.focusField});

  /// Which field to auto-focus on entry (e.g., 'bio')
  final String? focusField;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _hasChanges = false;
  String _initialDisplayName = '';
  String _initialPhone = '';
  String _initialBio = '';
  String _initialGender = '';
  DateTime? _initialDob;

  // Controllers
  late TextEditingController _displayNameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;
  late TextEditingController _usernameController;
  late FocusNode _bioFocusNode;
  late FocusNode _displayNameFocusNode;
  late FocusNode _phoneFocusNode;
  late FocusNode _usernameFocusNode;
  String _initialUsername = '';

  // State
  String _selectedGender = '';
  DateTime? _selectedDob;

  // Gender options
  static const _genderOptions = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _phoneController = TextEditingController();
    _bioController = TextEditingController();
    _usernameController = TextEditingController();
    _bioFocusNode = FocusNode();
    _displayNameFocusNode = FocusNode();
    _phoneFocusNode = FocusNode();
    _usernameFocusNode = FocusNode();

    // Load current profile data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileData();
    });
  }

  void _loadProfileData() {
    final profile = ref.read(profileProvider).profile;
    final user = ref.read(currentUserProvider);

    final displayName =
        profile?.name ?? user?.userMetadata?['name'] as String? ?? '';
    final phone = profile?.phone ?? '';
    final bio = profile?.bio ?? '';
    final gender = profile?.gender ?? '';
    final dob = profile?.dateOfBirth;
    final username = profile?.username ?? '';

    setState(() {
      _displayNameController.text = displayName;
      _phoneController.text = phone;
      _bioController.text = bio;
      _usernameController.text = username;
      _initialUsername = username;
      _selectedGender = gender;
      _selectedDob = dob;

      _initialDisplayName = displayName;
      _initialPhone = phone;
      _initialBio = bio;
      _initialGender = gender;
      _initialDob = dob;
    });

    // Auto-focus bio if requested
    if (widget.focusField == 'bio') {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _bioFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _usernameController.dispose();
    _bioFocusNode.dispose();
    _displayNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    final hasChanges =
        _usernameController.text != _initialUsername ||
        _displayNameController.text != _initialDisplayName ||
        _phoneController.text != _initialPhone ||
        _bioController.text != _initialBio ||
        _selectedGender != _initialGender ||
        _selectedDob != _initialDob;
    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Unsaved Changes',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _textPrimary,
          ),
        ),
        content: const Text(
          'You have unsaved changes. Do you want to discard them?',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancel', style: TextStyle(color: _textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Discard', style: TextStyle(color: _errorColor)),
          ),
        ],
      ),
    );

    return result == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).profile;
    final user = ref.watch(currentUserProvider);
    final email = profile?.email ?? user?.email ?? '';

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: DKScaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _textPrimary),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                context.pop();
              }
            },
          ),
          title: Text(
            'Edit Profile',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          actions: [
            if (_hasChanges && !_isSaving)
              TextButton(
                onPressed: _saveProfile,
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _orange,
                  ),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ── Display Name ────────────────────────────────────
                _buildFieldLabel('Display Name *'),
                const SizedBox(height: 6),
                _buildTextFormField(
                  controller: _displayNameController,
                  hintText: 'Enter your name',
                  focusNode: _displayNameFocusNode,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) => nameValidator(v),
                  onFieldSubmitted: (_) {
                    _phoneFocusNode.requestFocus();
                  },
                ),

                const SizedBox(height: 20),

                // ── Username ─────────────────────────────────────────
                _buildFieldLabel('Username'),
                const SizedBox(height: 6),
                _buildUsernameField(),

                const SizedBox(height: 20),

                // ── Email (display only) ─────────────────────────────
                _buildFieldLabel('Email'),
                const SizedBox(height: 6),
                _buildReadOnlyField(email),

                const SizedBox(height: 20),

                // ── Phone ────────────────────────────────────────────
                _buildFieldLabel('Phone'),
                const SizedBox(height: 6),
                _buildPhoneField(),

                const SizedBox(height: 20),

                // ── Date of Birth ────────────────────────────────────
                _buildFieldLabel('Date of Birth'),
                const SizedBox(height: 6),
                _buildDobField(),

                const SizedBox(height: 20),

                // ── Bio ──────────────────────────────────────────────
                _buildFieldLabel('Bio'),
                const SizedBox(height: 6),
                _buildBioField(),

                const SizedBox(height: 20),

                // ── Gender ───────────────────────────────────────────
                _buildFieldLabel('Gender'),
                const SizedBox(height: 6),
                _buildGenderField(),

                const SizedBox(height: 32),

                // ── Save Button ──────────────────────────────────────
                DKButton(
                  label: 'Save Changes',
                  variant: DKButtonVariant.primary,
                  size: DKButtonSize.lg,
                  fullWidth: true,
                  isLoading: _isSaving,
                  onPressed: _hasChanges ? _saveProfile : null,
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // FIELD BUILDERS
  // ══════════════════════════════════════════════════════════════════

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String hintText,
    required String? Function(String?) validator,
    int maxLines = 1,
    int? maxLength,
    FocusNode? focusNode,
    TextInputAction textInputAction = TextInputAction.done,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: (_) => _checkForChanges(),
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: _textDim.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: _cardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: const BorderSide(color: _orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: const BorderSide(color: _errorColor, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: const BorderSide(color: _errorColor, width: 1.5),
        ),
        errorStyle: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: _errorColor,
        ),
        counterStyle: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          color: _textDim,
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(KinrelRadius.input),
        border: Border.all(color: _borderSubtle),
      ),
      child: Text(
        value.isEmpty ? 'No email' : value,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: value.isEmpty ? _textDim : _textSecondary,
        ),
      ),
    );
  }

  Widget _buildUsernameField() {
    final usernameState = ref.watch(usernameProvider);
    final isValid = UsernameValidator.validate(_usernameController.text) == null;
    final isAvailable = usernameState.availability == UsernameAvailability.available;
    final isTaken = usernameState.availability == UsernameAvailability.taken;
    final isChecking = usernameState.availability == UsernameAvailability.checking;

    // Determine suffix icon
    Widget? suffixIcon;
    if (isChecking) {
      suffixIcon = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _orange),
      );
    } else if (isAvailable && isValid) {
      suffixIcon = Icon(Icons.check_circle, color: Colors.green, size: 20);
    } else if (isTaken) {
      suffixIcon = Icon(Icons.cancel, color: _errorColor, size: 20);
    }

    return TextFormField(
      controller: _usernameController,
      focusNode: _usernameFocusNode,
      onChanged: (value) {
        _checkForChanges();
        if (value.isNotEmpty) {
          ref.read(usernameProvider.notifier).checkAvailability(value.toLowerCase());
        }
      },
      textInputAction: TextInputAction.next,
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.none,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Choose a username',
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: _textDim.withValues(alpha: 0.6),
        ),
        prefixText: '@ ',
        prefixStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: _orange,
        ),
        suffixIcon: suffixIcon != null ? Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: suffixIcon,
        ) : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        filled: true,
        fillColor: _cardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: const BorderSide(color: _orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: const BorderSide(color: _errorColor, width: 1),
        ),
        helperText: '3-30 chars, lowercase letters, numbers, underscores',
        helperStyle: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          color: _textDim,
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return Row(
      children: [
        // Country code selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.input),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🇮🇳', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 4),
              Text(
                '+91',
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: _textDim, size: 18),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Phone number input
        Expanded(
          child: TextFormField(
            controller: _phoneController,
            onChanged: (_) => _checkForChanges(),
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Phone number',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: _textDim.withValues(alpha: 0.6),
              ),
              filled: true,
              fillColor: _cardBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: const BorderSide(color: _orange, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: const BorderSide(color: _errorColor, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.input),
                borderSide: const BorderSide(color: _errorColor, width: 1.5),
              ),
              errorStyle: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _errorColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDobField() {
    final dobText = _selectedDob != null
        ? '${_selectedDob!.day.toString().padLeft(2, '0')}/'
              '${_selectedDob!.month.toString().padLeft(2, '0')}/'
              '${_selectedDob!.year}'
        : '';

    return GestureDetector(
      onTap: _pickDateOfBirth,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          border: Border.all(
            color: dobText.isEmpty
                ? _borderSubtle
                : _orange.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: _textDim, size: 20),
            const SizedBox(width: 12),
            Text(
              dobText.isEmpty ? 'Select date of birth' : dobText,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: dobText.isEmpty
                    ? _textDim.withValues(alpha: 0.6)
                    : _textPrimary,
              ),
            ),
            const Spacer(),
            if (_selectedDob != null)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDob = null;
                    _checkForChanges();
                  });
                },
                child: Icon(Icons.close, color: _textDim, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateOfBirth() async {
    final maxDate = DateTime.now().subtract(const Duration(days: 5 * 365));
    final minDate = DateTime(1900);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? maxDate,
      firstDate: minDate,
      lastDate: maxDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _orange,
              onPrimary: Colors.white,
              surface: _cardBg,
              onSurface: _textPrimary,
            ),
            dialogTheme: DialogThemeData(backgroundColor: _cardBg),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _checkForChanges();
      });
    }
  }

  Widget _buildBioField() {
    return TextFormField(
      controller: _bioController,
      focusNode: _bioFocusNode,
      onChanged: (_) => _checkForChanges(),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      maxLength: 150,
      maxLines: 3,
      minLines: 2,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 15,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Tell us about yourself...',
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: _textDim.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: _cardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.input),
          borderSide: const BorderSide(color: _orange, width: 1.5),
        ),
        counterStyle: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          color: _textDim,
        ),
      ),
    );
  }

  Widget _buildGenderField() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.input),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGender.isEmpty ? null : _selectedGender,
          hint: Text(
            'Select gender',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              color: _textDim.withValues(alpha: 0.6),
            ),
          ),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: _textDim),
          dropdownColor: KinrelColors.darkElevated,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: _textPrimary,
          ),
          items: _genderOptions.map((gender) {
            return DropdownMenuItem<String>(value: gender, child: Text(gender));
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedGender = value;
                _checkForChanges();
              });
            }
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // SAVE PROFILE
  // ══════════════════════════════════════════════════════════════════

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // Build changed fields only
    final Map<String, dynamic> changedFields = {};

    if (_usernameController.text.trim().toLowerCase() != _initialUsername.toLowerCase()) {
      changedFields['username'] = _usernameController.text.trim().toLowerCase();
    }
    if (_displayNameController.text.trim() != _initialDisplayName) {
      changedFields['name'] = _displayNameController.text.trim();
    }
    if (_phoneController.text.trim() != _initialPhone) {
      changedFields['phone'] = _phoneController.text.trim();
    }
    if (_bioController.text.trim() != _initialBio) {
      changedFields['bio'] = _bioController.text.trim();
    }
    if (_selectedGender != _initialGender) {
      changedFields['gender'] = _selectedGender;
    }
    if (_selectedDob != _initialDob) {
      changedFields['dateOfBirth'] = _selectedDob?.toIso8601String();
    }

    if (changedFields.isEmpty) {
      setState(() => _isSaving = false);
      return;
    }

    final success = await ref
        .read(profileProvider.notifier)
        .updateProfile(changedFields);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        // Update initial values to reflect saved state
        setState(() {
          _initialDisplayName = _displayNameController.text.trim();
          _initialPhone = _phoneController.text.trim();
          _initialBio = _bioController.text.trim();
          _initialUsername = _usernameController.text.trim();
          _initialGender = _selectedGender;
          _initialDob = _selectedDob;
          _hasChanges = false;
        });
        context.showSnackBar('Profile updated');
      } else {
        final error =
            ref.read(profileProvider).error ?? 'Failed to update profile';
        // Try to map API errors to field-specific messages
        final fieldErrors = mapApiError(error);
        if (fieldErrors != null && fieldErrors.containsKey('form')) {
          context.showSnackBar(fieldErrors['form']!, isError: true);
        } else {
          context.showSnackBar(error, isError: true);
        }
      }
    }
  }
}
