import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/dk_components.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _cleanErrorMessage(String rawMessage) {
    var message = rawMessage;
    message = message.replaceAll('AuthException: ', '');
    message = message.replaceAll('AuthApiException: ', '');

    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('AuthRetryableFetchException') ||
        message.contains('Connection refused') ||
        message.contains('Network is unreachable') ||
        message.contains('No address associated with hostname') ||
        message.contains('Connection timed out') ||
        message.contains('TimeoutException') ||
        message.contains('timed out') ||
        message.contains('Unable to connect') ||
        message.contains('FetchException') ||
        message.contains('Connection reset')) {
      return 'Could not reach server. The server may be waking up — please check your internet connection and try again.';
    } else if (message.contains('No API key found')) {
      return 'Server configuration error. Please contact support.';
    } else if (message.contains('Invalid login credentials')) {
      return 'Incorrect email or password. Please try again.';
    } else if (message.contains('Email not confirmed')) {
      return 'Please verify your email before signing in.';
    } else if (message.contains('not available') ||
        message.contains('not available. Please restart')) {
      return 'Authentication service is not ready. Please restart the app and try again.';
    } else if (message.length > 150) {
      return 'Sign in failed. Please check your credentials and try again.';
    }
    return message;
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        context.showSnackBar(_cleanErrorMessage(e.toString()), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    // Theme-aware colors
    final bgColor = isLight ? KinrelColors.lightBackground : KinrelColors.darkBackground;
    final cardColor = isLight ? KinrelColors.lightCard : KinrelColors.darkCard;
    final inputFillColor = isLight
        ? KinrelColors.lightElevated
        : KinrelColors.darkElevated.withValues(alpha: 0.6);
    final inputBorderColor = isLight
        ? KinrelColors.lightBorder
        : const Color(0xFF3A3A4A);
    final textColor = isLight ? KinrelColors.textDark : KinrelColors.textWhite;
    final secondaryColor = isLight
        ? KinrelColors.textSecondaryLight
        : KinrelColors.textSilver;
    final accentColor = isLight ? KinrelColors.purple : KinrelColors.coral;
    final buttonColor = isLight ? KinrelColors.purple : KinrelColors.deepPurple;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.xl,
              vertical: KinrelSpacing.lg,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Decorative top illustration (dark mode only) ────
                  if (!isLight)
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: KinrelGradients.splashGradient,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.elliptical(
                            MediaQuery.of(context).size.width,
                            80,
                          ),
                        ),
                      ),
                    ),

                  // ── Welcome text ────────────────────────────────────
                  const SizedBox(height: 32),
                  Text(
                    'Welcome Back!',
                    textAlign: TextAlign.center,
                    style: KinrelTypography.displayLarge.copyWith(
                      color: textColor,
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 8),

                  Text(
                    'Sign in to continue to KinRel',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: secondaryColor,
                      height: 1.5,
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

                  const SizedBox(height: 32),

                  // ── Card containing form fields ─────────────────────
                  DKCard(
                    backgroundColor: cardColor,
                    padding: KinrelSpacing.xl,
                    radius: KinrelRadius.xxl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Email input ──────────────────────────────
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: TextStyle(
                              color: secondaryColor,
                              fontFamily: KinrelTypography.bodyFont,
                            ),
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: accentColor.withValues(alpha: 0.7),
                              size: 20,
                            ),
                            filled: true,
                            fillColor: inputFillColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide(
                                color: inputBorderColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: const BorderSide(
                                color: KinrelColors.error,
                                width: 1,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Email is required';
                              {
                            if (!v.contains('@')) return 'Enter a valid email';
                              }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // ── Password input ───────────────────────────
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: TextStyle(
                              color: secondaryColor,
                              fontFamily: KinrelTypography.bodyFont,
                            ),
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: accentColor.withValues(alpha: 0.7),
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: secondaryColor,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            filled: true,
                            fillColor: inputFillColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide(
                                color: inputBorderColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: const BorderSide(
                                color: KinrelColors.error,
                                width: 1,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Password is required';
                              {
                            if (v.length < 6)
                              }
                              return 'Password must be at least 6 characters';
                              {
                            return null;
                              }
                          },
                        ),

                        const SizedBox(height: 8),

                        // ── Forgot Password ──────────────────────────
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              // TODO: Navigate to forgot password
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: accentColor,
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Sign In button ───────────────────────────
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: buttonColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  buttonColor.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    KinrelRadius.button),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? Row(const mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 20,
                                        width: 20,
                                      const child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          colorconst : Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Connecting...',
                                        style: TextStyle(
                                          fontFamily:
                                              KinrelTypography.displayFont,
                                  const fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),),
                                    ],
                                  )
                                : Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.displayFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  const SizedBox(height: 24),

                  // ── "or" divider ───────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: inputBorderColor,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or',
                          style: TextStyle(
                            color: secondaryColor,
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: inputBorderColor,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms, delay: 300.ms),

                  const SizedBox(height: 24),

                  // ── Social login buttons ────────────────────────────
                  Row(
                    children: [
                      // Google
                      Expanded(
                        child: DKButton(
                          label: 'Google',
                          variant: DKButtonVariant.secondary,
                          icon: Icons.g_mobiledata_rounded,
                          size: DKButtonSize.md,
                          onPressed: () {
                            // TODO: Google sign in
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Apple
                      Expanded(
                        child: DKButton(
                          label: 'Apple',
                          variant: DKButtonVariant.secondary,
                          icon: Icons.apple,
                          size: DKButtonSize.md,
                          onPressed: () {
                            // TODO: Apple sign in
                          },
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms, delay: 400.ms),

                  const SizedBox(height: 20),

                  // ── Biometric options ──────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Face ID
                      _BiometricButton(
                        icon: Icons.face_outlined,
                        label: 'Face ID',
                        borderColor: inputBorderColor,
                        textColor: secondaryColor,
                        onPressed: () {
                          // TODO: Biometric auth
                        },
                      ),
                      const SizedBox(width: 24),
                      // Fingerprint
                      _BiometricButton(
                        icon: Icons.fingerprint,
                        label: 'Touch ID',
                        borderColor: inputBorderColor,
                        textColor: secondaryColor,
                        onPressed: () {
                          // TODO: Biometric auth
                        },
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms, delay: 500.ms),

                  const SizedBox(height: 32),

                  // ── Sign Up link ───────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: secondaryColor,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/sign-up'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: accentColor,
                            fontFamily: KinrelTypography.displayFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms, delay: 600.ms),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular biometric authentication button.
class _BiometricButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onPressed;

  const _BiometricButton({
    required this.icon,
    required this.label,
    required this.borderColor,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1.5),
              color: Colors.transparent,
            ),
            child: Icon(icon, size: 28, color: textColor),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
