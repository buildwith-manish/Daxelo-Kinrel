// lib/features/profile/presentation/change_password_screen.dart
//
// DAXELO KINREL — Change Password Screen
//
// Allows users to change their password with full validation.
// Google OAuth users see a special message instead of the form.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _currentPasswordFocusNode = FocusNode();
  final _newPasswordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  // ── Validators ─────────────────────────────────────────────────

  String? _validateCurrentPassword(String? value) {
    return requiredField(value, 'Current password');
  }

  String? _validateNewPassword(String? value) {
    final baseError = passwordValidator(value);
    if (baseError != null) return baseError;
    if (value == _currentPasswordController.text) {
      return 'New password must be different from current';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    return confirmPasswordValidator(value, _newPasswordController.text);
  }

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final success = await ref
        .read(profileProvider.notifier)
        .changePassword(
          _currentPasswordController.text,
          _newPasswordController.text,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      context.showSnackBar('Password changed successfully');
      context.pop();
    } else {
      final error = ref.read(profileProvider).error;
      if (error != null) {
        final fieldErrors = mapApiError(error);
        if (fieldErrors != null) {
          final formError = fieldErrors['form'] ?? fieldErrors['currentPassword'];
          if (formError != null) {
            context.showSnackBar(formError, isError: true);
          } else {
            context.showSnackBar(
              fieldErrors.values.first,
              isError: true,
            );
          }
        } else if (error.toLowerCase().contains('incorrect')) {
          context.showSnackBar('Current password is incorrect', isError: true);
        } else {
          context.showSnackBar(
            error,
            isError: true,
          );
        }
      } else {
        context.showSnackBar(
          'Failed to change password',
          isError: true,
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final isGoogleUser = profileState.profile?.authProvider == 'google';

    return DKScaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: _textPrimary,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.md,
        ),
        child: isGoogleUser ? _buildGoogleUserMessage() : _buildForm(),
      ),
    );
  }

  // ── Google User Message ────────────────────────────────────────

  Widget _buildGoogleUserMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 16),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: _borderSubtle),
              ),
              child: const Icon(
                Icons.g_mobiledata_rounded,
                size: 40,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'You signed in with Google',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'You signed in with Google. Use \'Forgot Password\' to set a password.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: DKButton(
                label: 'Forgot Password',
                variant: DKButtonVariant.primary,
                size: DKButtonSize.md,
                fullWidth: true,
                onPressed: () {
                  // Navigate to forgot password or trigger reset flow
                  context.showSnackBar('Password reset email will be sent');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Password Form ──────────────────────────────────────────────

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Current Password ──────────────────────────────────
          _buildSectionLabel('Current Password'),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: _currentPasswordController,
            focusNode: _currentPasswordFocusNode,
            hintText: 'Enter current password',
            obscure: _obscureCurrent,
            textInputAction: TextInputAction.next,
            onToggleObscure: () =>
                setState(() => _obscureCurrent = !_obscureCurrent),
            validator: _validateCurrentPassword,
            onFieldSubmitted: (_) {
              _newPasswordFocusNode.requestFocus();
            },
          ),

          const SizedBox(height: 24),

          // ── New Password ──────────────────────────────────────
          _buildSectionLabel('New Password'),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: _newPasswordController,
            focusNode: _newPasswordFocusNode,
            hintText: 'Enter new password',
            obscure: _obscureNew,
            textInputAction: TextInputAction.next,
            onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
            validator: _validateNewPassword,
            onFieldSubmitted: (_) {
              _confirmPasswordFocusNode.requestFocus();
            },
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Minimum 8 characters with letters and numbers',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _textDim,
                height: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Confirm New Password ──────────────────────────────
          _buildSectionLabel('Confirm New Password'),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocusNode,
            hintText: 'Re-enter new password',
            obscure: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onToggleObscure: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
            validator: _validateConfirmPassword,
            onFieldSubmitted: (_) => _handleSubmit(),
          ),

          const SizedBox(height: 40),

          // ── Submit Button ─────────────────────────────────────
          DKButton(
            label: 'Change Password',
            variant: DKButtonVariant.gradient,
            gradient: KinrelGradients.igniteGradient,
            size: DKButtonSize.lg,
            fullWidth: true,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : _handleSubmit,
          ),

          const SizedBox(height: 20),

          // ── Forgot Password Link ──────────────────────────────
          Center(
            child: TextButton(
              onPressed: () {
                context.showSnackBar('Password reset email will be sent');
              },
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _orange,
                  decoration: TextDecoration.underline,
                  decorationColor: _orange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Label ──────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Password Field ─────────────────────────────────────────────

  Widget _buildPasswordField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String? Function(String?) validator,
    TextInputAction textInputAction = TextInputAction.done,
    void Function(String)? onFieldSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.input),
        border: Border.all(color: _borderSubtle),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        validator: validator,
        textInputAction: textInputAction,
        textCapitalization: TextCapitalization.none,
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
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.input),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.input),
            borderSide: const BorderSide(color: _orange, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.input),
            borderSide: const BorderSide(color: KinrelColors.error, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.input),
            borderSide: const BorderSide(color: KinrelColors.error, width: 1.5),
          ),
          errorStyle: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.error,
          ),
          suffixIcon: GestureDetector(
            onTap: onToggleObscure,
            child: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _textDim,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
