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

class SignInScreen extends ConsumerStatefulWidget {
  SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _apiEmailError;

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
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
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
    } else if (message.contains('cancelled')) {
      return 'Google sign-in was cancelled.';
    } else if (message.contains('configuration error') ||
        message.contains('DEVELOPER_ERROR') ||
        message.contains('ApiException')) {
      return 'Google sign-in is not available right now. Please use email sign-in instead.';
    } else if (message.contains('timed out') ||
        message.contains('timed out')) {
      return 'Sign in timed out. Please check your internet connection and try again.';
    } else if (message.contains('not available') ||
        message.contains('not available. Please restart')) {
      return 'Authentication service is not ready. Please restart the app and try again.';
    } else if (message.contains('Provider api key not found') ||
        message.contains('provider is not enabled')) {
      return 'Google sign-in is not configured. Please use email sign-in instead.';
    } else if (message.length > 150) {
      return 'Sign in failed. Please check your credentials and try again.';
    }
    return message;
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();

      // Track successful Google login
      try {
        await AnalyticsService.instance.logLogin('google');
      } catch (_) {}

      // Wait for auth state stream to propagate
      try {
        await ref.read(authStateProvider.future).timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {}

      // Verify we actually have a session before navigating
      try {
        final client = ref.read(supabaseProvider);
        if (client?.auth.currentSession == null) {
          // Session not yet available — wait a bit more
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (_) {}

      if (mounted) {
        try {
          context.go('/home');
        } catch (e) {
          // Navigation can throw if the widget tree is in an inconsistent state
          debugPrint('⚠️ Navigation error after Google sign-in: $e');
          // Try again after a short delay
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

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // P5-F1: Track successful login (never let analytics block navigation)
      try {
        await AnalyticsService.instance.logLogin('email');
      } catch (_) {}

      // Wait for the auth state stream to propagate to Riverpod providers
      // before navigating. Without this, GoRouter's redirect checks
      // isAuthenticatedProvider which may still be false because the
      // onAuthStateChange stream hasn't emitted yet, causing the user
      // to be redirected back to /sign-in after a successful login.
      try {
        await ref.read(authStateProvider.future).timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        // Timeout — auth state may still be loading, but signIn() succeeded,
        // so we proceed anyway. The router redirect will handle it.
      }

      // Verify we actually have a session before navigating
      try {
        final client = ref.read(supabaseProvider);
        if (client?.auth.currentSession == null) {
          // Session not yet available — wait a bit more
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (_) {}

      if (mounted) {
        try {
          context.go('/home');
        } catch (e) {
          // Navigation can throw if the widget tree is in an inconsistent state
          debugPrint('⚠️ Navigation error after email sign-in: $e');
          // Try again after a short delay
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            try { context.go('/home'); } catch (_) {}
          }
        }
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
          }
          final emailError = fieldErrors['email'];
          if (emailError != null && !fieldErrors.containsKey('form')) {
            context.showSnackBar(emailError, isError: true);
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
                  // ── K-graph icon + KINREL wordmark ───────────────
                  Column(
                        children: [
                          SizedBox(
                            width: KinrelSpacing.logoLg,
                            height: KinrelSpacing.logoLg,
                            child: SvgPicture.asset(
                              'assets/icons/kinrel-icon-primary.svg',
                              width: KinrelSpacing.logoLg,
                              height: KinrelSpacing.logoLg,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ShaderMask(
                            shaderCallback: (bounds) => KinrelGradients
                                .wordmarkGradient
                                .createShader(bounds),
                            child: Text(
                              'KINREL',
                              style: KinrelTypography.appName.copyWith(
                                fontSize: 28,
                                letterSpacing: 3.92, // 28 * 0.14
                                color: Colors.white, // base for ShaderMask
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 15,
                              color: _secondaryText,
                              height: 1.5,
                            ),
                          ),
                        ],
                      )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.15, end: 0, duration: 500.ms),

                  const SizedBox(height: 32),

                  // ── Email / username field ───────────────────────
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
                      hintText: 'Email or username',
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
                      _passwordFocusNode.requestFocus();
                    },
                  ),

                  const SizedBox(height: 14),

                  // ── Password field with show/hide toggle ─────────
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
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
                    validator: (v) => requiredField(v, 'Password'),
                    onFieldSubmitted: (_) => _signIn(),
                  ),

                  const SizedBox(height: 8),

                  // ── Forgot Password link ─────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: Navigate to forgot password
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: KinrelColors.orange,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Sign In button (Ignite gradient, 56px, pill) ─
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
                        onPressed: _isLoading ? null : _signIn,
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
                                    'Connecting...',
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
                                'Sign In',
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

                  const SizedBox(height: 32),

                  // ── Don't have an account? Sign Up ───────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: _secondaryText,
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

/// Social authentication button — #202338 bg, white 10% border, rounded.
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
