// lib/features/auth/presentation/two_factor_login_screen.dart
//
// DAXELO KINREL — 2FA Login Verification Screen
//
// Shown after successful Supabase auth when the user has 2FA enabled.
// The user must enter a 6-digit TOTP code from their authenticator app
// before they can access the app.
//
// Flow: Sign-In → Supabase auth → Check 2FA → This screen → Home
//
// The screen calls POST /auth/2fa/login-verify with the Supabase JWT
// to verify the TOTP code. On success, it navigates to /home.
// On failure, it shows an error and allows retry.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/routing/app_router.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF13141E);
const Color _cardBg = Color(0xFF202338);
const Color _hintColor = Color(0xFFC9B4A8);
const Color _focusBorder = Color(0xFFE8612A);
const Color _primaryText = Color(0xFFF5F0EE);
const Color _secondaryText = Color(0xFFC9B4A8);
const Color _errorColor = Color(0xFFF04E2A);

class TwoFactorLoginScreen extends ConsumerStatefulWidget {
  const TwoFactorLoginScreen({super.key});

  @override
  ConsumerState<TwoFactorLoginScreen> createState() =>
      _TwoFactorLoginScreenState();
}

class _TwoFactorLoginScreenState extends ConsumerState<TwoFactorLoginScreen> {
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-focus the code input field after the screen renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  // ── Verify 2FA Code ────────────────────────────────────────────

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter a 6-digit code');
      return;
    }

    if (_isVerifying) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/api/auth/2fa/login-verify',
        data: {'code': code},
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        throw DioException(
          requestOptions: RequestOptions(path: '/api/auth/2fa/login-verify'),
          error: 'Verification timed out. The server may be waking up — please try again.',
          type: DioExceptionType.connectionTimeout,
        );
      });

      // 2FA verified — update state and navigate to home
      if (mounted) {
        // Track successful 2FA verification (fire-and-forget)
        unawaited(
          AnalyticsService.instance
              .logLogin('2fa')
              .catchError((_) {}),
        );

        // Clear the pending 2FA state so GoRouter allows navigation
        // to protected routes. This MUST happen before navigating,
        // otherwise the router would redirect back to /2fa-verify.
        ref.read(pending2FAProvider.notifier).state = false;
        ref.read(twoFactorVerifiedProvider.notifier).state = true;

        // Mark sign-in as fully complete (2FA verified)
        // This triggers GoRouter to re-evaluate redirects
        markSignInSuccess();

        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToHome();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      String message;

      if (statusCode == 401) {
        message = 'Invalid verification code. Please try again.';
      } else if (statusCode == 400) {
        message = '2FA is not enabled for this account.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        message = 'Could not reach server. Please check your internet connection.';
      } else {
        // Try to extract backend error message
        try {
          message = e.response?.data?['message'] ??
              'Verification failed. Please try again.';
        } catch (_) {
          message = 'Verification failed. Please try again.';
        }
      }
      setState(() => _errorMessage = message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // ── Sign Out ────────────────────────────────────────────────────

  Future<void> _signOut() async {
    // Clear 2FA state on sign-out
    try {
      ref.read(pending2FAProvider.notifier).state = false;
      ref.read(twoFactorVerifiedProvider.notifier).state = false;
    } catch (_) {}

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signOut();
    } catch (_) {}
    if (mounted) {
      try {
        context.go('/sign-in');
      } catch (_) {}
    }
  }

  // ── Navigate to Home ────────────────────────────────────────────

  void _navigateToHome() {
    if (!mounted) return;
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          context.go('/home');
        } catch (e) {
          debugPrint('Navigation error after 2FA verification: $e');
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              try {
                context.go('/home');
              } catch (_) {}
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Navigation scheduling error: $e');
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: KinrelSpacing.xl,
                vertical: KinrelSpacing.lg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Shield Icon ──────────────────────────────────
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: KinrelColors.orange.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shield_rounded,
                        color: KinrelColors.orange,
                        size: 36,
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms).scale(
                        begin: Offset(0.8, 0.8),
                        end: Offset(1, 1),
                        duration: 400.ms,
                      ),

                  const SizedBox(height: 24),

                  // ── Title ────────────────────────────────────────
                  Center(
                    child: Text(
                      'Two-Factor Authentication',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _primaryText,
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

                  const SizedBox(height: 8),

                  // ── Subtitle ─────────────────────────────────────
                  Center(
                    child: Text(
                      'Enter the 6-digit code from your\nauthenticator app to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _secondaryText,
                        height: 1.5,
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

                  const SizedBox(height: 32),

                  // ── 6-digit code input ───────────────────────────
                  TextField(
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    cursorColor: _focusBorder,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _primaryText,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: _cardBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: _focusBorder, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: _errorColor, width: 1),
                      ),
                      hintText: '000000',
                      hintStyle: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _hintColor.withValues(alpha: 0.3),
                        letterSpacing: 8,
                      ),
                    ),
                    onChanged: (value) {
                      // Clear error when user types
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                      // Auto-submit when 6 digits entered
                      if (value.length == 6 && !_isVerifying) {
                        _verifyCode();
                      }
                    },
                    onSubmitted: (_) {
                      if (!_isVerifying) _verifyCode();
                    },
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  // ── Error message ───────────────────────────────
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: _errorColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Verify button ────────────────────────────────
                  SizedBox(
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _isVerifying
                            ? null
                            : KinrelGradients.igniteGradient,
                        color: _isVerifying
                            ? KinrelColors.orange.withValues(alpha: 0.5)
                            : null,
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.full),
                        boxShadow: _isVerifying
                            ? null
                            : [
                                BoxShadow(
                                  color: KinrelColors.orange.withValues(
                                      alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isVerifying ? null : _verifyCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.transparent,
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(KinrelRadius.full),
                          ),
                          elevation: 0,
                        ),
                        child: _isVerifying
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
                                    'Verifying...',
                                    style: TextStyle(
                                      fontFamily:
                                          KinrelTypography.displayFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                'Verify',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 300.ms),

                  const SizedBox(height: 24),

                  // ── Sign out link ────────────────────────────────
                  Center(
                    child: TextButton(
                      onPressed: _isVerifying ? null : _signOut,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      child: Text(
                        'Sign in with a different account',
                        style: TextStyle(
                          color: _secondaryText,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor: _secondaryText.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 400.ms),

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
