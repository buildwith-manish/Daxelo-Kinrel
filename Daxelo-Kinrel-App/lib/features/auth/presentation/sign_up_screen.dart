import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../../../core/services/analytics_service.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  String? _apiEmailError;

  // ── Country code state ─────────────────────────────────────────
  _CountryCode _selectedCountry = _countryCodes.first;

  // ── Design tokens (orange brand) ────────────────────────────────
  static const _bgColor = Color(0xFF13141E);
  static const _inputFill = Color(0xFF202338);
  static const _hintColor = Color(0xFFC9B4A8);
  static const _focusBorder = Color(0xFFE8612A);
  static const _primaryText = Color(0xFFF5F0EE);
  static const _secondaryText = Color(0xFFC9B4A8);
  static const _errorColor = Color(0xFFF04E2A);
  static const _socialBorder = Color(0x1AFFFFFF);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  // ── Password strength (4 levels: weak / fair / good / strong) ──
  _PasswordStrength _passwordStrength(String password) {
    if (password.isEmpty) {
      return _PasswordStrength.none;
    }
    int score = 0;
    if (password.length >= 8) {
      score++;
    }
    if (password.length >= 12) {
      score++;
    }
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      score++;
    }

    if (score <= 1) return _PasswordStrength.weak;
    if (score == 2) return _PasswordStrength.fair;
    if (score == 3) return _PasswordStrength.good;
    return _PasswordStrength.strong;
  }

  Color _strengthColor(_PasswordStrength strength) {
    switch (strength) {
      case _PasswordStrength.none:
        return const Color(0xFF3A3A4A);
      case _PasswordStrength.weak:
        return KinrelColors.error; // #F04E2A
      case _PasswordStrength.fair:
        return KinrelColors.orange; // #E8612A
      case _PasswordStrength.good:
        return KinrelColors.amber; // #F59240
      case _PasswordStrength.strong:
        return KinrelColors.success; // #4CAF7A
    }
  }

  String _strengthLabel(_PasswordStrength strength) {
    switch (strength) {
      case _PasswordStrength.none:
        return '';
      case _PasswordStrength.weak:
        return 'Weak';
      case _PasswordStrength.fair:
        return 'Fair';
      case _PasswordStrength.good:
        return 'Good';
      case _PasswordStrength.strong:
        return 'Strong';
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
    } else if (message.contains('cancelled')) {
      return 'Google sign-in was cancelled.';
    } else if (message.contains('configuration error') ||
        message.contains('DEVELOPER_ERROR') ||
        message.contains('ApiException')) {
      return 'Google sign-in is not available right now. Please use email sign-up instead.';
    } else if (message.contains('timed out') ||
        message.contains('timed out')) {
      return 'Sign up timed out. Please check your internet connection and try again.';
    } else if (message.contains('not available') ||
        message.contains('not available. Please restart')) {
      return 'Authentication service is not ready. Please restart the app and try again.';
    } else if (message.contains('Provider api key not found') ||
        message.contains('provider is not enabled')) {
      return 'Google sign-in is not configured. Please use email sign-up instead.';
    } else if (message.length > 150) {
      return 'Sign up failed. Please check your details and try again.';
    }
    return message;
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();

      // Track successful Google sign-up
      try {
        AnalyticsService.instance.logSignUp('google');
      } catch (_) {}

      // Wait for the Supabase session to be available before navigating.
      try {
        for (int i = 0; i < 10; i++) {
          final client = ref.read(supabaseProvider);
          if (client?.auth.currentSession != null) break;
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (_) {}

      if (mounted) {
        try {
          context.go('/home');
        } catch (e) {
          debugPrint('⚠️ Navigation error after Google sign-up: $e');
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            try { context.go('/home'); } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        // Don't show snackbar for user-initiated cancellation
        if (!msg.contains('cancelled')) {
          context.showSnackBar(_cleanErrorMessage(msg), isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      context.showSnackBar(
        'Please agree to the Terms of Service',
        isError: true,
      );
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

      // P5-F1: Track successful sign-up
      AnalyticsService.instance.logSignUp('email');

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
        final fieldErrors = mapApiError(e);
        if (fieldErrors != null) {
          if (fieldErrors.containsKey('email')) {
            setState(() => _apiEmailError = fieldErrors['email']);
            _formKey.currentState!.validate();
          }
          final formError = fieldErrors['form'];
          if (formError != null) {
            context.showSnackBar(formError, isError: true);
          } else if (!fieldErrors.containsKey('email')) {
            // Show the first field error as snackbar if no form-level error
            final firstError = fieldErrors.values.first;
            context.showSnackBar(firstError, isError: true);
          }
        } else {
          context.showSnackBar(_cleanErrorMessage(e.toString()), isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Reusable input decoration ──────────────────────────────────
  InputDecoration _inputDecoration({
    required String hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
    Widget? prefix,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: _hintColor,
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 14,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: _hintColor, size: 20)
          : null,
      prefix: prefix,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _focusBorder, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _errorColor, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _errorColor, width: 1.5),
      ),
      errorStyle: TextStyle(
        color: _errorColor,
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStrength = _passwordStrength(_passwordController.text);

    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: KinrelSpacing.xl,
                vertical: KinrelSpacing.lg,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // ── K-graph icon (48px) + Create Account ─────────
                  Column(
                        children: [
                          SizedBox(
                            width: KinrelSpacing.logoMd,
                            height: KinrelSpacing.logoMd,
                            child: SvgPicture.asset(
                              'assets/icons/kinrel-icon-primary.svg',
                              width: KinrelSpacing.logoMd,
                              height: KinrelSpacing.logoMd,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Create Account',
                            textAlign: TextAlign.center,
                            style: KinrelTypography.displayMedium.copyWith(
                              fontSize: 26,
                              color: _primaryText,
                            ),
                          ),
                        ],
                      )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.15, end: 0, duration: 500.ms),

                  const SizedBox(height: 28),

                  // ── Full Name field ─────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    cursorColor: _focusBorder,
                    style: TextStyle(
                      color: _primaryText,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Full Name',
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                    validator: (v) => nameValidator(v),
                    onFieldSubmitted: (_) {
                      _emailFocusNode.requestFocus();
                    },
                  ),

                  const SizedBox(height: 14),

                  // ── Email field ─────────────────────────────────
                  TextFormField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    cursorColor: _focusBorder,
                    style: TextStyle(
                      color: _primaryText,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Email',
                      prefixIcon: Icons.email_outlined,
                    ),
                    validator: (v) {
                      if (_apiEmailError != null) {
                        final err = _apiEmailError;
                        _apiEmailError = null;
                        return err;
                      }
                      return emailValidator(v);
                    },
                    onFieldSubmitted: (_) {
                      _phoneFocusNode.requestFocus();
                    },
                  ),

                  const SizedBox(height: 14),

                  // ── Phone field with country code picker ─────────
                  TextFormField(
                    controller: _phoneController,
                    focusNode: _phoneFocusNode,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    cursorColor: _focusBorder,
                    style: TextStyle(
                      color: _primaryText,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Phone number',
                      prefix: _CountryCodePicker(
                        selected: _selectedCountry,
                        onSelected: (code) =>
                            setState(() => _selectedCountry = code),
                      ),
                    ),
                    onFieldSubmitted: (_) {
                      _passwordFocusNode.requestFocus();
                    },
                  ),

                  const SizedBox(height: 14),

                  // ── Password field with strength indicator ───────
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    cursorColor: _focusBorder,
                    style: TextStyle(
                      color: _primaryText,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Password',
                      prefixIcon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: _hintColor,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => passwordValidator(v),
                    onFieldSubmitted: (_) {
                      _confirmPasswordFocusNode.requestFocus();
                    },
                  ),

                  // ── 4-dot password strength indicator ───────────
                  if (_passwordController.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // 4 strength dots
                        ...List.generate(4, (index) {
                          final int level;
                          switch (currentStrength) {
                            case _PasswordStrength.weak:
                              level = 1;
                              break;
                            case _PasswordStrength.fair:
                              level = 2;
                              break;
                            case _PasswordStrength.good:
                              level = 3;
                              break;
                            case _PasswordStrength.strong:
                              level = 4;
                              break;
                            case _PasswordStrength.none:
                              level = 0;
                              break;
                          }
                          final isActive = index < level;
                          final color = isActive
                              ? _strengthColor(currentStrength)
                              : const Color(0xFF2A2A3D);
                          return Container(
                            width: 40,
                            height: 4,
                            margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                        const SizedBox(width: 12),
                        Text(
                          _strengthLabel(currentStrength),
                          style: TextStyle(
                            color: _strengthColor(currentStrength),
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Confirm Password field ───────────────────────
                  TextFormField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocusNode,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.none,
                    cursorColor: _focusBorder,
                    style: TextStyle(
                      color: _primaryText,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      hintText: 'Confirm Password',
                      prefixIcon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: _hintColor,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        confirmPasswordValidator(v, _passwordController.text),
                    onFieldSubmitted: (_) => _signUp(),
                  ),

                  const SizedBox(height: 16),

                  // ── Terms & Privacy checkbox ─────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _agreedToTerms,
                          onChanged: (v) =>
                              setState(() => _agreedToTerms = v ?? false),
                          activeColor: KinrelColors.orange,
                          checkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              KinrelRadius.xs,
                            ),
                          ),
                          side: BorderSide(
                            color: _agreedToTerms
                                ? KinrelColors.orange
                                : const Color(0xFF3A3A4A),
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _agreedToTerms = !_agreedToTerms),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: _secondaryText,
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                height: 1.4,
                              ),
                              children: [
                                const TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: TextStyle(
                                    color: KinrelColors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    color: KinrelColors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Create Account button (Ignite gradient, 56px) ─
                  SizedBox(
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? null
                            : KinrelGradients.igniteGradient,
                        color: _isLoading
                            ? KinrelColors.orange.withValues(alpha: 0.5)
                            : null,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                        boxShadow: _isLoading
                            ? null
                            : [
                                BoxShadow(
                                  color: KinrelColors.orange.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 16,
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
                          disabledForegroundColor: Colors.white.withValues(
                            alpha: 0.6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              KinrelRadius.full,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Creating account...',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.displayFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                'Create Account',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  const SizedBox(height: 28),

                  // ── "or continue with" divider ───────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFF2A2A3D),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or continue with',
                          style: TextStyle(
                            color: _secondaryText,
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFF2A2A3D),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms, delay: 300.ms),

                  const SizedBox(height: 20),

                  // ── Google social auth button ─────────────────────
                  _SocialAuthButton(
                    label: _isGoogleLoading ? 'Connecting...' : 'Google',
                    icon: Icons.g_mobiledata_rounded,
                    borderColor: _socialBorder,
                    fillColor: _inputFill,
                    textColor: _primaryText,
                    isLoading: _isGoogleLoading,
                    onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                  ).animate().fadeIn(duration: 300.ms, delay: 400.ms),

                  const SizedBox(height: 28),

                  // ── Already have an account? Sign In ─────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                          color: _secondaryText,
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
                            color: KinrelColors.orange,
                            fontFamily: KinrelTypography.displayFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms, delay: 500.ms),

                  const SizedBox(height: 16),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Password Strength Enum
// ═══════════════════════════════════════════════════════════════════════════

enum _PasswordStrength { none, weak, fair, good, strong }

// ═══════════════════════════════════════════════════════════════════════════
// Social Auth Button
// ═══════════════════════════════════════════════════════════════════════════

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({
    required this.label,
    required this.icon,
    required this.borderColor,
    required this.fillColor,
    required this.textColor,
    this.isLoading = false,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color borderColor;
  final Color fillColor;
  final Color textColor;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              )
            else
              Icon(icon, size: 22, color: textColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Country Code Picker — Inline lightweight implementation
// ═══════════════════════════════════════════════════════════════════════════

class _CountryCode {
  const _CountryCode({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String code;
  final String dialCode;
  final String flag;
}

const List<_CountryCode> _countryCodes = [
  _CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
  _CountryCode(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
  _CountryCode(
    name: 'United Kingdom',
    code: 'GB',
    dialCode: '+44',
    flag: '🇬🇧',
  ),
  _CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
  _CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
  _CountryCode(name: 'UAE', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
  _CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
  _CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
  _CountryCode(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
  _CountryCode(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
  _CountryCode(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦'),
  _CountryCode(name: 'Nigeria', code: 'NG', dialCode: '+234', flag: '🇳🇬'),
  _CountryCode(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷'),
  _CountryCode(name: 'Pakistan', code: 'PK', dialCode: '+92', flag: '🇵🇰'),
  _CountryCode(name: 'Bangladesh', code: 'BD', dialCode: '+880', flag: '🇧🇩'),
  _CountryCode(name: 'Nepal', code: 'NP', dialCode: '+977', flag: '🇳🇵'),
  _CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰'),
  _CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
  _CountryCode(
    name: 'Saudi Arabia',
    code: 'SA',
    dialCode: '+966',
    flag: '🇸🇦',
  ),
  _CountryCode(name: 'Other', code: 'OT', dialCode: '+', flag: '🌍'),
];

class _CountryCodePicker extends StatelessWidget {
  const _CountryCodePicker({required this.selected, required this.onSelected});

  final _CountryCode selected;
  final ValueChanged<_CountryCode> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 4),
            Text(
              selected.dialCode,
              style: TextStyle(
                color: const Color(0xFFF5F0EE),
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: const Color(0xFFC9B4A8),
              size: 18,
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 20, color: const Color(0xFF3A3A4A)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202338),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Country',
                style: TextStyle(
                  color: const Color(0xFFF5F0EE),
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2A2A3D), height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _countryCodes.length,
                itemBuilder: (context, index) {
                  final country = _countryCodes[index];
                  final isSelected = country.code == selected.code;
                  return ListTile(
                    leading: Text(
                      country.flag,
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(
                      country.name,
                      style: TextStyle(
                        color: isSelected
                            ? KinrelColors.orange
                            : const Color(0xFFF5F0EE),
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: Text(
                      country.dialCode,
                      style: TextStyle(
                        color: isSelected
                            ? KinrelColors.orange
                            : const Color(0xFFC9B4A8),
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    onTap: () {
                      onSelected(country);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
