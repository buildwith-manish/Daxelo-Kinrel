// lib/features/auth/presentation/sign_in_screen.dart
//
// DAXELO KINREL — Sign In Screen
//
// Clean rewrite with bulletproof error handling.
// Every async operation is wrapped in try-catch to prevent crashes.
// Google Sign-In failures are handled gracefully — the app NEVER
// force-closes from this screen.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/form_validators.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/family/family_provider.dart';

class SignInScreen extends ConsumerStatefulWidget {
  SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _identifierFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  // Per-field API error shown beneath the identifier input. Set when
  // the backend rejects the credentials with an identifier-specific
  // message (e.g., "Email not confirmed"). Cleared on next validate.
  String? _apiIdentifierError;

  // ── Design tokens ────────────────────────────────────────────────
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
    _identifierController.dispose();
    _passwordController.dispose();
    _identifierFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // ── Error Message Cleaner ────────────────────────────────────────

  String _cleanErrorMessage(String rawMessage) {
    var message = rawMessage;
    message = message.replaceAll('AuthException: ', '');
    message = message.replaceAll('AuthApiException: ', '');

    if (_isNetworkError(message)) {
      return 'Could not reach server. Please check your internet connection and try again.';
    } else if (message.contains('Invalid login credentials')) {
      // The same generic message covers: wrong password, unknown
      // username, unknown email — so we don't reveal which one.
      return 'Incorrect email/username or password. Please try again.';
    } else if (message.contains('Email not confirmed')) {
      return 'Please verify your email before signing in.';
    } else if (message.contains('cancelled')) {
      return ''; // Empty = don't show snackbar for user cancellation
    } else if (message.contains('configuration error') ||
        message.contains('configuration issue') ||
        message.contains('debug build') ||
        message.contains('DEVELOPER_ERROR')) {
      return 'Google sign-in is not available on this build. Please use email sign-in instead.';
    } else if (message.contains('timed out')) {
      return 'Sign in timed out. Please check your internet connection and try again.';
    } else if (message.contains('not available') ||
        message.contains('not ready')) {
      return 'Authentication service is not ready. Please restart the app and try again.';
    } else if (message.contains('Provider api key not found') ||
        message.contains('provider is not enabled')) {
      return 'Google sign-in is not configured. Please use email sign-in instead.';
    } else if (message.length > 150) {
      return 'Sign in failed. Please check your credentials and try again.';
    }
    return message;
  }

  bool _isNetworkError(String message) {
    return message.contains('SocketException') ||
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
        message.contains('Connection reset');
  }

  // ── Google Sign-In ───────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    // Prevent double-tap
    if (_isGoogleLoading || _isLoading) return;
    setState(() => _isGoogleLoading = true);
    FocusScope.of(context).unfocus();

    try {
      final authService = ref.read(authServiceProvider);
      final response = await authService.signInWithGoogle();

      // null = user cancelled or timed out — no error to show
      if (response == null) {
        return;
      }

      // Track successful Google login (fire-and-forget — don't await)
      unawaited(
        AnalyticsService.instance.logLogin('google').catchError((_) {}),
      );

      // ── Auth succeeded ─────────────────────────────────────────────
      // DO NOT clear _isGoogleLoading here. Keep loading visible
      // until navigation completes. Same fix as _signIn().

      // ── Check if 2FA is enabled for this user ──────────────────
      // IMPORTANT: Check 2FA BEFORE calling markSignInSuccess().
      // markSignInSuccess() triggers GoRouter redirect, which would
      // send the user to /home before we can navigate to /2fa-verify.
      final requires2FA = await _check2FAStatus();
      if (requires2FA) {
        // Set pending 2FA state so GoRouter doesn't redirect away
        // from /2fa-verify
        ref.read(pending2FAProvider.notifier).state = true;

        // Mark sign-in success AFTER setting 2FA state so the router
        // knows to redirect to /2fa-verify instead of /home
        markSignInSuccess();

        // Invalidate family providers so they re-fetch for the
        // newly signed-in user (prevents stale [] from pre-login).
        try {
          ref.invalidate(familyListProvider);
        } catch (_) {}

        // Navigate to 2FA verification screen
        if (mounted) {
          context.go('/2fa-verify');
        }
        return;
      }

      // No 2FA required — check username BEFORE markSignInSuccess()
      // to prevent GoRouter redirect from sending user to /home.

      // Invalidate family providers so they re-fetch for the
      // newly signed-in user (prevents stale [] from pre-login).
      try {
        ref.invalidate(familyListProvider);
      } catch (_) {}

      // Check if user has a username — if not, redirect to Create Username
      if (mounted) {
        final client = ref.read(supabaseProvider);
        final userId = client?.auth.currentUser?.id;
        bool needsUsername = false;
        if (userId != null) {
          try {
            final userData = await client!
                .from('User')
                .select('username')
                .eq('id', userId)
                .maybeSingle()
                .timeout(const Duration(seconds: 5));
            final username = userData?['username'] as String?;
            needsUsername = username == null || username.isEmpty;
          } catch (_) {}
        }
        if (needsUsername) {
          context.go('/create-username');
          markSignInSuccess();
        } else {
          markSignInSuccess();
          try {
            context.go('/home');
          } catch (e) {
            debugPrint('⚠️ Google sign-in navigation to /home failed: $e');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = _cleanErrorMessage(e.toString());
        // Don't show snackbar for user-initiated cancellation
        if (msg.isNotEmpty) {
          context.showSnackBar(msg, isError: true);
        }
      }
    } finally {
      // Clear loading state only if still on this screen.
      if (mounted && _isGoogleLoading) setState(() => _isGoogleLoading = false);
    }
  }

  // ── Identifier Sign-In (email OR username) ──────────────────────

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    // Prevent double-tap
    if (_isLoading || _isGoogleLoading) return;
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      final authService = ref.read(authServiceProvider);
      // signInWithIdentifier handles the email-vs-username branch:
      //   - If the input contains '@', it's signed in directly as an email.
      //   - Otherwise, it's resolved to an email via the
      //     fn_get_email_by_identifier RPC, then signed in.
      await authService.signInWithIdentifier(
        identifier: _identifierController.text,
        password: _passwordController.text,
      ).timeout(const Duration(seconds: 30), onTimeout: () {
        throw const AuthException(
          'Sign in is taking too long. The server may be waking up — please try again.',
        );
      });

      // Track successful login (fire-and-forget — don't await)
      unawaited(
        AnalyticsService.instance.logLogin('email').catchError((_) {}),
      );

      // ── Auth succeeded ─────────────────────────────────────────────
      // DO NOT clear _isLoading here. Keep "Signing in..." visible
      // until navigation completes. This prevents the user from
      // seeing the Sign In button re-appear and clicking it again,
      // which causes the "connecting loop" bug.

      // ── Check if 2FA is enabled for this user ──────────────────
      // IMPORTANT: Check 2FA BEFORE calling markSignInSuccess().
      // markSignInSuccess() triggers GoRouter redirect, which would
      // send the user to /home before we can navigate to /2fa-verify.
      final requires2FA = await _check2FAStatus();
      if (requires2FA) {
        // Set pending 2FA state so GoRouter doesn't redirect away
        // from /2fa-verify
        ref.read(pending2FAProvider.notifier).state = true;

        // Mark sign-in success AFTER setting 2FA state so the router
        // knows to redirect to /2fa-verify instead of /home
        markSignInSuccess();

        // Invalidate family providers so they re-fetch for the
        // newly signed-in user (prevents stale [] from pre-login).
        try {
          ref.invalidate(familyListProvider);
        } catch (_) {}

        // Navigate to 2FA verification screen
        if (mounted) {
          context.go('/2fa-verify');
        }
        return;
      }

      // No 2FA required — check username BEFORE markSignInSuccess()
      // to prevent GoRouter redirect from sending user to /home.

      // Invalidate family providers so they re-fetch for the
      // newly signed-in user (prevents stale [] from pre-login).
      try {
        ref.invalidate(familyListProvider);
      } catch (_) {}

      // Check if user has a username — if not, redirect to Create Username
      if (mounted) {
        final client = ref.read(supabaseProvider);
        final userId = client?.auth.currentUser?.id;
        bool needsUsername = false;
        if (userId != null) {
          try {
            final userData = await client!
                .from('User')
                .select('username')
                .eq('id', userId)
                .maybeSingle()
                .timeout(const Duration(seconds: 5));
            final username = userData?['username'] as String?;
            needsUsername = username == null || username.isEmpty;
          } catch (_) {}
        }
        if (needsUsername) {
          context.go('/create-username');
          markSignInSuccess();
        } else {
          markSignInSuccess();
          try {
            context.go('/home');
          } catch (e) {
            debugPrint('⚠️ Direct navigation to /home failed: $e');
          }
        }
      }
    } on AuthException catch (e) {
      // Auth-specific errors (wrong password, email not confirmed, etc.)
      if (mounted) {
        final msg = _cleanErrorMessage(e.toString());
        if (msg.isNotEmpty) {
          // Identifier-specific errors (e.g., "Email not confirmed") are
          // shown beneath the identifier input. Generic errors (wrong
          // password, network) go to the snackbar.
          final isIdentifierError = msg.toLowerCase().contains('email') &&
              !msg.toLowerCase().contains('check your') &&
              !msg.toLowerCase().contains('incorrect');
          if (isIdentifierError) {
            setState(() => _apiIdentifierError = msg);
            _formKey.currentState!.validate();
          } else {
            context.showSnackBar(msg, isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = _cleanErrorMessage(e.toString());
        if (msg.isNotEmpty) {
          final isIdentifierError = msg.toLowerCase().contains('email') &&
              !msg.toLowerCase().contains('check your') &&
              !msg.toLowerCase().contains('incorrect');
          if (isIdentifierError) {
            setState(() => _apiIdentifierError = msg);
            _formKey.currentState!.validate();
          } else {
            context.showSnackBar(msg, isError: true);
          }
        }
      }
    } finally {
      // Clear loading state only if still on this screen.
      // If navigation succeeded, the widget is unmounted and
      // mounted=false, so this becomes a no-op.
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  // ── Check 2FA Status ────────────────────────────────────────────
  //
  // After successful Supabase auth, check if the user has 2FA enabled
  // on the backend. If yes, they must verify a TOTP code before
  // accessing the app.
  //
  // Returns true if 2FA verification is required, false otherwise.
  //
  // SECURITY: Fail-OPEN on network errors.
  // The backend's TwoFactorGuard enforces 2FA server-side,
  // so if we can't reach the backend, let the user through
  // the client-side check. The backend will enforce 2FA if needed.
  // This prevents dead-end redirect loops where a user without 2FA
  // gets stuck on /2fa-verify because the backend is unreachable.

  Future<bool> _check2FAStatus() async {
    try {
      final dio = ref.read(dioProvider);
      // Use a short timeout and skip retries — this is an advisory check
      // that should NOT block the sign-in flow. If the backend is
      // unreachable (Render cold start, network issues), we fail-OPEN
      // and let the user through. The backend's TwoFactorGuard will
      // enforce 2FA server-side.
      final response = await dio.get(
        '/api/auth/me',
        options: Options(
          extra: {'retryCount': 99}, // Skip RetryInterceptor (maxRetries=3)
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          // SECURITY: Fail-OPEN — if backend is unreachable, allow login.
          throw Exception('Backend unreachable — cannot verify 2FA status');
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        // Backend returns { "user": { ... } }
        final userData = data['user'] is Map
            ? (data['user'] as Map).cast<String, dynamic>()
            : data;
        final twoFactorEnabled = userData['twoFactorEnabled'];
        if (twoFactorEnabled == true) {
          return true;
        }
      } else if (data is Map) {
        final twoFactorEnabled = data['twoFactorEnabled'];
        if (twoFactorEnabled == true) {
          return true;
        }
      }
      return false;
    } on DioException catch (e) {
      // SECURITY: Fail-OPEN on network errors.
      // The backend's TwoFactorGuard enforces 2FA server-side,
      // so if we can't reach the backend, let the user through
      // the client-side check. The backend will enforce 2FA if needed.
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403 || statusCode == 404) {
        debugPrint('2FA status check: backend user not found ($statusCode) — 2FA not enabled');
        return false;
      }
      // Network/timeout/5xx errors — fail-OPEN (backend will enforce)
      debugPrint('2FA status check failed (DioException): ${e.message} — allowing client-side pass (backend enforces)');
      return false;
    } catch (e) {
      // Any other error — fail-OPEN (backend enforces)
      debugPrint('2FA status check failed: $e — allowing client-side pass (backend enforces)');
      return false;
    }
  }

  // ── Wait for Session (REMOVED) ─────────────────────────────────
  //
  // The session polling was causing force closes on some devices.
  // Instead, we now rely on a short delay after signIn() returns
  // successfully, then navigate directly. The auth state listener
  // in main.dart handles post-sign-in setup asynchronously.

  // ── Input Decoration ─────────────────────────────────────────────

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

  // ── Forgot Password ──────────────────────────────────────────────
  //
  // Accepts either an email or a username. If a username is entered,
  // we first resolve it to an email via fn_get_email_by_identifier,
  // then send the reset link to that email. If resolution fails (RPC
  // not deployed, network error, unknown username), we show a generic
  // success message anyway to avoid revealing which usernames exist.

  void _showForgotPasswordDialog() {
    final identifierController = TextEditingController(
      text: _identifierController.text.trim(),
    );
    bool isSending = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: KinrelColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Reset Password',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your email or username and we\'ll send a reset link to your account email.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: identifierController,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                style: TextStyle(color: KinrelColors.textWhite),
                decoration: InputDecoration(
                  hintText: 'Email or username',
                  hintStyle: TextStyle(color: KinrelColors.textDim),
                  filled: true,
                  fillColor: KinrelColors.darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: TextStyle(color: KinrelColors.textDim)),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final raw = identifierController.text.trim();
                      if (raw.isEmpty) return;

                      setState(() => isSending = true);
                      try {
                        final client = ref.read(supabaseProvider);
                        if (client == null) {
                          throw Exception('Supabase not initialized');
                        }

                        // Resolve identifier to email. If it contains '@'
                        // it's already an email; otherwise look it up.
                        String email = raw;
                        if (!raw.contains('@')) {
                          final result = await client
                              .rpc('fn_get_email_by_identifier',
                                  params: {'p_identifier': raw.toLowerCase()})
                              .timeout(const Duration(seconds: 8));

                          if (result is String && result.isNotEmpty) {
                            email = result;
                          } else if (result is List && result.isNotEmpty) {
                            final first = result.first;
                            if (first is Map && first['email'] is String) {
                              email = first['email'] as String;
                            } else if (first is String) {
                              email = first;
                            }
                          } else if (result is Map &&
                              result['email'] is String) {
                            email = result['email'] as String;
                          } else {
                            // Username not found — show generic success to
                            // avoid revealing which usernames exist.
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'If an account exists, a reset link has been sent.'),
                                  backgroundColor: Color(0xFF22C55E),
                                ),
                              );
                            }
                            return;
                          }
                        }

                        await client.auth.resetPasswordForEmail(email);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Reset link sent! Check your email.'),
                              backgroundColor: Color(0xFF22C55E),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setState(() => isSending = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Could not send reset link. Please try again later.'),
                              backgroundColor: KinrelColors.error,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
              ),
              child: isSending
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Send Link'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

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
                    // ── Logo + Wordmark ──────────────────────────────
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
                              letterSpacing: 3.92,
                              color: Colors.white,
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
                    ).animate().fadeIn(duration: 400.ms).slideY(
                          begin: 0.15, end: 0, duration: 500.ms),

                    const SizedBox(height: 32),

                    // ── Identifier field (email OR username) ─────────
                    TextFormField(
                      controller: _identifierController,
                      focusNode: _identifierFocusNode,
                      // Email keyboard works well for both emails and
                      // usernames (lowercase letters + numbers + @ + _).
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
                        prefixIcon: Icons.alternate_email,
                      ),
                      validator: (v) {
                        if (_apiIdentifierError != null) {
                          final err = _apiIdentifierError;
                          _apiIdentifierError = null;
                          return err;
                        }
                        return emailOrUsernameValidator(v);
                      },
                      onFieldSubmitted: (_) {
                        _passwordFocusNode.requestFocus();
                      },
                    ),

                    const SizedBox(height: 14),

                    // ── Password field ──────────────────────────────
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

                    // ── Forgot Password ─────────────────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _showForgotPasswordDialog(),
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

                    // ── Sign In button ──────────────────────────────
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
                                      'Signing in...',
                                      style: TextStyle(
                                        fontFamily: KinrelTypography.displayFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: Colors.white.withValues(alpha: 0.8),
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

                    // ── "or continue with" divider ──────────────────
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

                    // ── Google button ───────────────────────────────
                    _SocialAuthButton(
                      label: _isGoogleLoading ? 'Signing in...' : 'Google',
                      icon: Icons.g_mobiledata_rounded,
                      borderColor: _socialBorder,
                      fillColor: _inputFill,
                      textColor: _primaryText,
                      isLoading: _isGoogleLoading,
                      onPressed:
                          (_isGoogleLoading || _isLoading) ? null : _signInWithGoogle,
                    ).animate().fadeIn(duration: 300.ms, delay: 400.ms),

                    const SizedBox(height: 32),

                    // ── Sign Up link ────────────────────────────────
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

// ── Social Auth Button ───────────────────────────────────────────────

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
