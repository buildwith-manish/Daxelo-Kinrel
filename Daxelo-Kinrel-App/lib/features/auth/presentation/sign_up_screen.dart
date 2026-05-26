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

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _passwordStrength(String password) {
    if (password.length < 8) return 'Weak';
    if (password.length < 12 &&
        !RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password))
      return 'Medium';
      {
    return 'Strong';
      }
  }

  double _passwordStrengthValue(String? strength) {
    switch (strength) {
      case 'Strong':
        return 1.0;
      case 'Medium':
        return 0.6;
      case 'Weak':
        return 0.3;
      default:
        return 0.0;
    }
  }

  Color _passwordStrengthColor(String? strength) {
    switch (strength) {
      case 'Strong':
        return KinrelColors.success;
      case 'Medium':
        return KinrelColors.warning;
      case 'Weak':
        return KinrelColors.error;
      default:
        return KinrelColors.textDim;
    }
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
    } else if (message.contains('User already registered')) {
      return 'This email is already registered. Try signing in instead.';
    } else if (message.contains('Password should be')) {
      return 'Password is too weak. Use at least 8 characters with numbers and symbols.';
    } else if (message.contains('Invalid email')) {
      return 'Please enter a valid email address.';
    } else if (message.contains('not available') ||
        message.contains('not available. Please restart')) {
      return 'Authentication service is not ready. Please restart the app and try again.';
    } else if (message.length > 150) {
      return 'Sign up failed. Please check your details and try again.';
    }
    return message;
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      context.showSnackBar('Please agree to the Terms of Service',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      final response = await authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
      );

      if (!mounted) return;

      // Check if email confirmation is required
      final user = response.user;
      if (user != null && user.emailConfirmedAt == null) {
        // Email confirmation required — show message and go to sign-in
        context.showSnackBar(
          'Account created! Please check your email to verify your account, then sign in.',
        );
        context.go('/sign-in');
      } else {
        // Auto-confirmed or already confirmed — go to home
        context.go('/home');
      }
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
    final passwordStrength = _passwordStrength(_passwordController.text);
    final strengthColor = _passwordStrengthColor(passwordStrength);

    // Theme-aware colors
    final bgColor = isLight
        ? KinrelColors.lightBackground
        : KinrelColors.darkBackground;
    final cardColor = isLight ? KinrelColors.lightCard : KinrelColors.darkCard;
    final inputFillColor = isLight
        ? KinrelColors.lightElevated
        : KinrelColors.darkElevated.withValues(alpha: 0.6);
    final inputBorderColor = isLight
        ? KinrelColors.lightBorder
        : const Color(0xFF3A3A4A);
    final textColor =
        isLight ? KinrelColors.textDark : KinrelColors.textWhite;
    final secondaryColor = isLight
        ? KinrelColors.textSecondaryLight
        : KinrelColors.textSilver;
    final accentColor = isLight ? KinrelColors.purple : KinrelColors.coral;

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
                  // ── Title ────────────────────────────────────────────
                  Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: KinrelTypography.displayLarge.copyWith(
                      fontSize: 28,
                      color: textColor,
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 8),

                  Text(
                    'Join KinRel and discover your family',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: secondaryColor,
                      height: 1.5,
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

                  const SizedBox(height: 28),

                  // ── Card containing form fields ─────────────────────
                  DKCard(
                    backgroundColor: cardColor,
                    padding: KinrelSpacing.xl,
                    radius: KinrelRadius.xxl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Full Name ────────────────────────────────
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            labelStyle: TextStyle(
                              color: secondaryColor,
                              fontFamily: KinrelTypography.bodyFont,
                            ),
                            prefixIcon: Icon(
                              Icons.person_outline_rounded,
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
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: inputBorderColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: const BorderSide(
                                color: KinrelColors.error,
                                width: 1,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Name is required' : null,
                        ),

                        const SizedBox(height: 16),

                        // ── Email ─────────────────────────────────────
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
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: inputBorderColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
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

                        // ── Password with strength indicator ──────────
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
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: inputBorderColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: const BorderSide(
                                color: KinrelColors.error,
                                width: 1,
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Password is required';
                              {
                            if (v.length < 8)
                              }
                              return 'Password must be at least 8 characters';
                              {
                            return null;
                              }
                          },
                        ),

                        // ── Password strength bar ────────────────────
                        if (_passwordController.text.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // Strength bar
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value:
                                        _passwordStrengthValue(passwordStrength),
                                    backgroundColor:
                                        inputBorderColor.withValues(alpha: 0.3),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        strengthColor),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                passwordStrength ?? '',
                                style: TextStyle(
                                  color: strengthColor,
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        // ── Confirm Password ──────────────────────────
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
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
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: secondaryColor,
                                size: 20,
                              ),
                              onPressed: () => setState(() =>
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword),
                            ),
                            filled: true,
                            fillColor: inputFillColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: inputBorderColor,
                                width: 0.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: BorderSide(
                                color: accentColor,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.input),
                              borderSide: const BorderSide(
                                color: KinrelColors.error,
                                width: 1,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Please confirm your password';
                              {
                            if (v != _passwordController.text)
                              }
                              return 'Passwords do not match';
                              {
                            return null;
                              }
                          },
                        ),

                        const SizedBox(height: 16),

                        // ── Terms checkbox ────────────────────────────
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _agreedToTerms,
                                onChanged: (v) =>
                                    setState(() => _agreedToTerms = v ?? false),
                                activeColor: KinrelColors.purple,
                                checkColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      KinrelRadius.xs),
                                ),
                                side: BorderSide(
                                  color: inputBorderColor,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() =>
                                    _agreedToTerms = !_agreedToTerms),
                                child: Text(
                                  'I agree to the Terms of Service and Privacy Policy',
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ── Create Account button ─────────────────────
                        SizedBox(
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  KinrelColors.purple,
                                  KinrelColors.violet,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.button),
                              boxShadow: _isLoading
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: KinrelColors.purple
                                            .withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _signUp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.transparent,
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      KinrelRadius.button),
                                ),const elevation: 0,
                              ),
                              child: _isLoading
                                  ? Row(
                                      mainAxisAlignment:
                                        const MainAxisAlignment.center,
                                      children: [
                                        SizedBox(const height: 20,
                                          width: 20,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                    const const SizedBox(width: 12),
                                        Text(
                                          'Creating account...',
                                          style: TextStyle(
                                            fontFamily:
                                                KinrelTypography.displayFont,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      'Create Account',
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.displayFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  const SizedBox(height: 24),

                  // ── Sign In link ────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                          color: secondaryColor,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/sign-in'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Sign In',
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
