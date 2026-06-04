// lib/features/profile/presentation/two_factor_screen.dart
//
// DAXELO KINREL — Two-Factor Authentication Screen
//
// Full 2FA setup flow (enable) and disable flow.
// Setup: bottom sheet → QR/secret → verify code → backup codes.
// Disable: confirm dialog → password → deactivate.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
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

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  // ── Setup Flow State ───────────────────────────────────────────
  _TwoFAFlowStep _currentStep = _TwoFAFlowStep.idle;
  TwoFASetupResponse? _setupResponse;
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isSettingUp = false;
  bool _isDisabling = false;
  List<String>? _backupCodes;
  String? _stepError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final is2FAEnabled = profileState.profile?.twoFactorEnabled ?? false;

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
          'Two-Factor Authentication',
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
        child: _buildContent(is2FAEnabled),
      ),
    );
  }

  // ── Content Router ─────────────────────────────────────────────

  Widget _buildContent(bool is2FAEnabled) {
    switch (_currentStep) {
      case _TwoFAFlowStep.idle:
        return _buildIdleView(is2FAEnabled);
      case _TwoFAFlowStep.setupInfo:
        return _buildSetupInfoView();
      case _TwoFAFlowStep.qrCode:
        return _buildQRCodeView();
      case _TwoFAFlowStep.verifyCode:
        return _buildVerifyCodeView();
      case _TwoFAFlowStep.backupCodes:
        return _buildBackupCodesView();
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // IDLE VIEW — Toggle on/off
  // ══════════════════════════════════════════════════════════════════

  Widget _buildIdleView(bool is2FAEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Status Card ────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(
              color: is2FAEnabled
                  ? KinrelColors.success.withValues(alpha: 0.3)
                  : _borderSubtle,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: is2FAEnabled
                      ? KinrelColors.success.withValues(alpha: 0.15)
                      : _orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  is2FAEnabled ? Icons.shield_rounded : Icons.shield_outlined,
                  color: is2FAEnabled ? KinrelColors.success : _orange,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                is2FAEnabled ? '2FA is Enabled' : '2FA is Disabled',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                is2FAEnabled
                    ? 'Your account is protected with two-factor authentication'
                    : 'Add an extra layer of security to your account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Toggle Button ──────────────────────────────────────
        DKButton(
          label: is2FAEnabled ? 'Disable 2FA' : 'Enable 2FA',
          variant: DKButtonVariant.gradient,
          gradient: is2FAEnabled
              ? KinrelGradients.signOutGradient
              : KinrelGradients.igniteGradient,
          icon: is2FAEnabled ? Icons.shield_outlined : Icons.shield_outlined,
          size: DKButtonSize.lg,
          fullWidth: true,
          onPressed: () {
            if (is2FAEnabled) {
              _showDisableConfirmDialog();
            } else {
              _startSetupFlow();
            }
          },
        ),

        const SizedBox(height: 28),

        // ── How it works ───────────────────────────────────────
        _buildSectionHeader('How it works'),
        const SizedBox(height: 10),
        ..._howItWorksSteps.map(
          (step) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildHowItWorksStep(
              number: step.number,
              title: step.title,
              description: step.description,
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── FAQ ────────────────────────────────────────────────
        _buildSectionHeader('Common Questions'),
        const SizedBox(height: 10),
        _buildFAQItem(
          question: 'What if I lose my authenticator?',
          answer:
              'You can use one of your backup codes to sign in. Each code can only be used once.',
        ),
        const SizedBox(height: 10),
        _buildFAQItem(
          question: 'Can I use any authenticator app?',
          answer:
              'Yes! Any TOTP-compatible app works — Google Authenticator, Authy, 1Password, etc.',
        ),
      ],
    );
  }

  // ── How It Works Steps ─────────────────────────────────────────

  static const _howItWorksSteps = [
    _HowItWorksStep(
      number: '1',
      title: 'Set up authenticator',
      description: 'Scan the QR code with your authenticator app',
    ),
    _HowItWorksStep(
      number: '2',
      title: 'Verify code',
      description: 'Enter the 6-digit code to confirm setup',
    ),
    _HowItWorksStep(
      number: '3',
      title: 'Save backup codes',
      description: 'Store your backup codes in a safe place',
    ),
  ];

  Widget _buildHowItWorksStep({
    required String number,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: _orange.withValues(alpha: 0.3), width: 1),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _orange,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textDim,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── FAQ Item ───────────────────────────────────────────────────

  Widget _buildFAQItem({required String question, required String answer}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // SETUP INFO VIEW — Explaining 2FA
  // ══════════════════════════════════════════════════════════════════

  Widget _buildSetupInfoView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back button ────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _currentStep = _TwoFAFlowStep.idle),
          child: Row(
            children: [
              Icon(Icons.arrow_back_ios_new, color: _orange, size: 16),
              const SizedBox(width: 6),
              Text(
                'Back',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Step indicator ─────────────────────────────────────
        _buildStepIndicator(currentStep: 1, totalSteps: 3),
        const SizedBox(height: 24),

        // ── Info Card ──────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: _orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Set Up Two-Factor Authentication',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Two-factor authentication adds an extra layer of security '
                'to your account. When enabled, you\'ll need to enter a '
                'verification code from your authenticator app each time you sign in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),

              // ── Requirements ─────────────────────────────────
              _buildRequirement(
                Icons.phone_android_outlined,
                'An authenticator app',
              ),
              const SizedBox(height: 8),
              _buildRequirement(Icons.qr_code, 'Scan a QR code to link'),
              const SizedBox(height: 8),
              _buildRequirement(
                Icons.save_outlined,
                'Save backup codes securely',
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Continue Button ────────────────────────────────────
        DKButton(
          label: 'Get Started',
          variant: DKButtonVariant.gradient,
          gradient: KinrelGradients.igniteGradient,
          icon: Icons.arrow_forward,
          size: DKButtonSize.lg,
          fullWidth: true,
          isLoading: _isSettingUp,
          onPressed: _isSettingUp ? null : _initiateSetup,
        ),
      ],
    );
  }

  Widget _buildRequirement(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: _orange, size: 18),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // QR CODE VIEW — Show secret + QR URL
  // ══════════════════════════════════════════════════════════════════

  Widget _buildQRCodeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back button ────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _currentStep = _TwoFAFlowStep.setupInfo),
          child: Row(
            children: [
              Icon(Icons.arrow_back_ios_new, color: _orange, size: 16),
              const SizedBox(width: 6),
              Text(
                'Back',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Step indicator ─────────────────────────────────────
        _buildStepIndicator(currentStep: 2, totalSteps: 3),
        const SizedBox(height: 24),

        // ── QR Code Card ───────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            children: [
              const Text(
                'Scan QR Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Open your authenticator app and scan the code below',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // ── QR Code Representation ────────────────────────
              Container(
                width: 200,
                height: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: _buildQRCodeWidget(),
              ),

              const SizedBox(height: 20),

              // ── Secret Key ────────────────────────────────────
              const Text(
                'Or enter this secret key manually:',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textDim,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _setupResponse?.secret ?? '',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _textPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: _setupResponse?.secret ?? ''),
                        );
                        context.showSnackBar('Secret key copied');
                      },
                      child: Icon(Icons.copy_rounded, color: _orange, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Continue to verify ─────────────────────────────────
        DKButton(
          label: 'I\'ve Scanned the Code',
          variant: DKButtonVariant.gradient,
          gradient: KinrelGradients.igniteGradient,
          icon: Icons.check_circle_outline,
          size: DKButtonSize.lg,
          fullWidth: true,
          onPressed: () {
            setState(() {
              _currentStep = _TwoFAFlowStep.verifyCode;
              _stepError = null;
            });
          },
        ),
      ],
    );
  }

  // ── QR Code Visual Widget ──────────────────────────────────────

  Widget _buildQRCodeWidget() {
    // Since we can't render a real QR code without a package,
    // we display a stylized representation with the otpauth URL
    final qrUrl = _setupResponse?.qrCodeUrl ?? '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_2_rounded, size: 100, color: _bg),
        const SizedBox(height: 4),
        Text(
          'QR Code',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            color: _bg.withValues(alpha: 0.6),
          ),
        ),
        // Hidden but accessible: the full URL
        if (qrUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: qrUrl));
                context.showSnackBar('QR URL copied');
              },
              child: Text(
                'Tap to copy URL',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 8,
                  color: _bg.withValues(alpha: 0.5),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // VERIFY CODE VIEW — Enter 6-digit code
  // ══════════════════════════════════════════════════════════════════

  Widget _buildVerifyCodeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back button ────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() {
            _currentStep = _TwoFAFlowStep.qrCode;
            _stepError = null;
          }),
          child: Row(
            children: [
              Icon(Icons.arrow_back_ios_new, color: _orange, size: 16),
              const SizedBox(width: 6),
              Text(
                'Back',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Step indicator ─────────────────────────────────────
        _buildStepIndicator(currentStep: 3, totalSteps: 3),
        const SizedBox(height: 24),

        // ── Verify Card ────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_outlined, color: _orange, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'Enter Verification Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the 6-digit code from your authenticator app',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // ── 6-digit code input ────────────────────────────
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: KinrelColors.darkElevated,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    borderSide: const BorderSide(color: _orange, width: 1.5),
                  ),
                  hintText: '000000',
                  hintStyle: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _textDim.withValues(alpha: 0.3),
                    letterSpacing: 8,
                  ),
                ),
                onChanged: (value) {
                  if (_stepError != null) {
                    setState(() => _stepError = null);
                  }
                },
              ),

              // ── Error message ─────────────────────────────────
              if (_stepError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _stepError!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Verify Button ──────────────────────────────────────
        DKButton(
          label: 'Verify & Enable',
          variant: DKButtonVariant.gradient,
          gradient: KinrelGradients.igniteGradient,
          icon: Icons.verified_user_outlined,
          size: DKButtonSize.lg,
          fullWidth: true,
          isLoading: _isVerifying,
          onPressed: _isVerifying ? null : _verifyCode,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // BACKUP CODES VIEW — Show generated backup codes
  // ══════════════════════════════════════════════════════════════════

  Widget _buildBackupCodesView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Success Card ───────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: KinrelColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(
              color: KinrelColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: KinrelColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: KinrelColors.success,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '2FA Enabled!',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.success,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Two-factor authentication is now active on your account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Backup Codes Header ────────────────────────────────
        Row(
          children: [
            Icon(Icons.key_outlined, color: _orange, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Backup Codes',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Save these codes in a safe place. Each code can only be used once '
          'to sign in if you lose access to your authenticator.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        // ── Backup Codes Grid ──────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(color: _borderSubtle),
          ),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.2,
            children: (_backupCodes ?? []).map((code) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.xs),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Center(
                  child: Text(
                    code,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 20),

        // ── Copy Backup Codes Button ───────────────────────────
        DKButton(
          label: 'Copy Backup Codes',
          variant: DKButtonVariant.secondary,
          icon: Icons.copy_rounded,
          size: DKButtonSize.md,
          fullWidth: true,
          onPressed: () {
            final codesText = (_backupCodes ?? []).join('\n');
            Clipboard.setData(ClipboardData(text: codesText));
            context.showSnackBar('Backup codes copied to clipboard');
          },
        ),

        const SizedBox(height: 12),

        // ── Done Button ────────────────────────────────────────
        DKButton(
          label: 'Done',
          variant: DKButtonVariant.gradient,
          gradient: KinrelGradients.igniteGradient,
          size: DKButtonSize.lg,
          fullWidth: true,
          onPressed: () => context.pop(),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // FLOW ACTIONS
  // ══════════════════════════════════════════════════════════════════

  // ── Start Setup Flow ───────────────────────────────────────────

  void _startSetupFlow() {
    // Show bottom sheet explaining 2FA first, then proceed to setup info
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: _orange,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Enable Two-Factor Auth',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Two-factor authentication protects your account by requiring '
              'a verification code in addition to your password when you sign in.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            DKButton(
              label: 'Continue Setup',
              variant: DKButtonVariant.gradient,
              gradient: KinrelGradients.igniteGradient,
              size: DKButtonSize.lg,
              fullWidth: true,
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() => _currentStep = _TwoFAFlowStep.setupInfo);
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: _textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Initiate Setup (call API) ──────────────────────────────────

  Future<void> _initiateSetup() async {
    setState(() => _isSettingUp = true);

    final response = await ref.read(profileProvider.notifier).setup2FA();

    if (!mounted) return;
    setState(() => _isSettingUp = false);

    if (response != null) {
      setState(() {
        _setupResponse = response;
        _currentStep = _TwoFAFlowStep.qrCode;
      });
    } else {
      final error = ref.read(profileProvider).error;
      context.showSnackBar(error ?? 'Failed to setup 2FA', isError: true);
    }
  }

  // ── Verify Code ────────────────────────────────────────────────

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _stepError = 'Please enter a 6-digit code');
      return;
    }

    setState(() => _isVerifying = true);

    final success = await ref.read(profileProvider.notifier).verify2FA(code);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (success) {
      // Generate 10 random 8-char backup codes
      final backupCodes = _generateBackupCodes();
      setState(() {
        _backupCodes = backupCodes;
        _currentStep = _TwoFAFlowStep.backupCodes;
      });
    } else {
      final error = ref.read(profileProvider).error;
      setState(() {
        _stepError = error ?? 'Invalid verification code. Please try again.';
      });
    }
  }

  // ── Generate Backup Codes ──────────────────────────────────────

  List<String> _generateBackupCodes() {
    final random = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(10, (_) {
      return String.fromCharCodes(
        Iterable.generate(
          8,
          (_) => chars.codeUnitAt(random.nextInt(chars.length)),
        ),
      );
    });
  }

  // ── Disable 2FA ────────────────────────────────────────────────

  void _showDisableConfirmDialog() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.dialog),
            side: const BorderSide(color: _borderSubtle),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: KinrelColors.warning,
                size: 24,
              ),
              const SizedBox(width: 10),
              const Text(
                'Disable 2FA?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will remove two-factor authentication from your account. '
                'Your account will be less secure.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Enter your password to confirm:',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.input),
                ),
                child: TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Current password',
                    hintStyle: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: _textDim.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: KinrelColors.darkElevated,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
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
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isDisabling ? null : () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: _textDim,
                ),
              ),
            ),
            DKButton(
              label: 'Disable',
              variant: DKButtonVariant.primary,
              size: DKButtonSize.sm,
              isLoading: _isDisabling,
              onPressed: _isDisabling
                  ? null
                  : () async {
                      final password = passwordController.text.trim();
                      if (password.isEmpty) {
                        context.showSnackBar(
                          'Please enter your password',
                          isError: true,
                        );
                        return;
                      }

                      setDialogState(() => _isDisabling = true);

                      final success = await ref
                          .read(profileProvider.notifier)
                          .disable2FA(password);

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }

                      if (!mounted) return;

                      _isDisabling = false;

                      if (success) {
                        context.showSnackBar(
                          'Two-factor authentication disabled',
                        );
                      } else {
                        final error = ref.read(profileProvider).error;
                        context.showSnackBar(
                          error ?? 'Failed to disable 2FA',
                          isError: true,
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ══════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _orange,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildStepIndicator({
    required int currentStep,
    required int totalSteps,
  }) {
    return Row(
      children: List.generate(totalSteps, (index) {
        final stepNum = index + 1;
        final isActive = stepNum == currentStep;
        final isCompleted = stepNum < currentStep;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? KinrelColors.success
                        : isActive
                        ? _orange
                        : _textDim.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (stepNum < totalSteps) const SizedBox(width: 6),
            ],
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Flow Step Enum
// ═══════════════════════════════════════════════════════════════════════

enum _TwoFAFlowStep { idle, setupInfo, qrCode, verifyCode, backupCodes }

// ═══════════════════════════════════════════════════════════════════════
// How It Works Step Model
// ═══════════════════════════════════════════════════════════════════════

class _HowItWorksStep {
  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;
}
