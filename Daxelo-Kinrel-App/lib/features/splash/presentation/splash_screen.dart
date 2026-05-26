import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/widgets/kinrel_icon.dart';
import '../../../shared/widgets/kinrel_wordmark.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [KinrelColors.darkBackground, KinrelColors.darkCard],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated K-graph icon
                KinrelIcon(
                  size: 96,
                  palette: KinrelIconPalette.orange,
                  animated: true,
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fadeIn(duration: 600.ms)
                    .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),

                const SizedBox(height: 24),

                // Wordmark
                KinrelWordmark(
                  fontSize: 36,
                  variant: WordmarkVariant.gradient,
                ).animate().fadeIn(duration: 800.ms, delay: 300.ms),

                const SizedBox(height: 12),

                // Tagline
                Text(
                  AppConfig.appTagline,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textSilver,
                    letterSpacing: 0.5,
                  ),
                ).animate().fadeIn(duration: 600.ms, delay: 600.ms),

                const SizedBox(height: 48),

                // Loading indicator
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange.withValues(alpha: 0.7),
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 800.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
