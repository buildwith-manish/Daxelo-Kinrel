import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/widgets/kinrel_icon.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _navigated = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Preload kinship data in the background (5300+ terms, ~15MB JSON)
    // Don't await — let it load while splash shows
    unawaited(ref.read(kinshipInitializedProvider.future).catchError((_) {}));

    // Shorter splash for better UX — 1.5s is enough for branding
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // Wait for Supabase to restore the session (important for app resume)
    try {
      if (isSupabaseInitialized) {
        final client = ref.read(supabaseProvider);
        if (client != null) {
          // Force session restoration by accessing the session
          final session = client.auth.currentSession;
          // If no session yet, wait for async restoration with longer timeout
          // for Supabase free tier cold starts
          if (session == null) {
            try {
              await client.auth.onAuthStateChange.first
                  .timeout(const Duration(seconds: 8));
            } catch (_) {
              // Timeout — no session available, will redirect to sign-in
            }
          }
          // Delay to let auth state propagate to providers
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (_) {
      // Ignore session restoration errors — will redirect to sign-in
    }

    if (!mounted || _navigated) return;

    final isAuthenticated = ref.read(isAuthenticatedProvider);
    final secureStorage = SecureStorageService();
    final onboardingComplete = await secureStorage.isOnboardingComplete();

    if (!mounted || _navigated) return;

    _navigated = true;

    // Check for saved route to restore on app resume
    if (isAuthenticated) {
      final lastRoute = await getLastRoute();
      if (!mounted || _navigated) return;
      if (lastRoute != null && lastRoute != '/splash' && mounted) {
        context.go(lastRoute);
        return;
      }
      context.go('/home');
    } else if (onboardingComplete) {
      context.go('/sign-in');
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          // Subtle gradient pulse: vary the color stops slightly
          final pulse = 0.5 + 0.5 * _pulseController.value;
          return const Container(
            decoration: const BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  const Color.lerp(
                    const Color(0xFF6A11CB),
                    const Color(0xFF7C3AED),
                    pulse * 0.3,
                  )!,
                  const Color.lerp(
                    const Color(0xFFFF6B6B),
                    const Color(0xFFFF8A80),
                    pulse * 0.2,
                  )!,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // ── Animated K-graph icon with glowing circle ──────────
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      const BoxShadow(
                        color: KinrelColors.purpleGlow,
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                      BoxShadow(
                        color: KinrelColors.coral.withValues(alpha: 0.2),
                        blurRadius: 60,
                        spreadRadius: 16,
                      ),
                    ],
                  ),
                  child: const KinrelIcon(
                    size: 96,
                    palette: KinrelIconPalette.mono,
                    animated: true,
                  ),
                )
                    .animate(onPlay: (c) => c.forward())
                    .fadeIn(duration: 600.ms)
                    .scale(
                      begin: const Offset(0.7, 0.7),
                      end: const Offset(1.0, 1.0),
                      duration: 800.ms,
                      curve: Curves.elasticOut,
                    ),

                const SizedBox(height: 32),

                // ── Brand text "KinRel" ────────────────────────────────
                const Text(
                  'KinRel',
                  style: KinrelTypography.displayHero.copyWith(
                    fontSize: 42,
                    color: KinrelColors.textWhite,
                    letterSpacing: -0.5,
                    shadows: [
                      const Shadow(
                        color: KinrelColors.purpleGlow,
                        blurRadius: 20,
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 800.ms, delay: 300.ms)
                    .slideY(begin: 0.15, end: 0, duration: 600.ms),

                const SizedBox(height: 12),

                // ── Tagline ────────────────────────────────────────────
                const Text(
                  AppConfig.appTagline,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textSilver,
                    letterSpacing: 0.5,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 600.ms)
                    .slideY(begin: 0.1, end: 0, duration: 400.ms),

                const Spacer(flex: 2),

                // ── Loading indicator ──────────────────────────────────
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: KinrelColors.textWhite.withValues(alpha: 0.7),
                    strokeCap: StrokeCap.round,
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 800.ms),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
