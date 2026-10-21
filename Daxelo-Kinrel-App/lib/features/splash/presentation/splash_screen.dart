import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/device_tier.dart';
import '../../../main.dart' show appInitCompleteProvider;
import '../../../shared/widgets/kinrel_logo.dart';

// ─────────────────────────────────────────────────────────────────────
// Deep-route restoration safeguard
// ─────────────────────────────────────────────────────────────────────
// The splash screen previously restored only a hard-coded allowlist of
// top-level routes (/home, /search, /families, …). Deep, parameterized
// routes such as /family/:id/graph were intentionally excluded because
// they can produce a black screen if the referenced data has not loaded
// yet, has been deleted, or is hidden by RLS.
//
// To make such routes restorable *without* re-introducing that failure
// mode, each restorable deep route is described by a [DeepRouteRestoreRule]
// whose [verify] callback loads the *minimal* data the destination screen
// needs (a single row, a count, …) under a short internal timeout. The
// splash screen only restores the route when the verifier returns true.
// Any failure, timeout, or null response falls back to /home as before,
// preserving the original protection.
//
// (Verifier helpers + per-route wrappers follow the [SplashScreen] class.)

/// One restorable deep route + its data-availability verifier.
class DeepRouteRestoreRule {
  const DeepRouteRestoreRule({
    required this.pattern,
    required this.paramNames,
    required this.verify,
  });

  /// Pattern that matches the route path (with parameters captured).
  final RegExp pattern;

  /// Names of the captured parameters, in order.
  final List<String> paramNames;

  /// Returns true if the referenced data is accessible to the current
  /// user. The splash screen calls this under a short backstop timeout
  /// (see [SplashScreen._deepRouteRules] for the per-route instances).
  final Future<bool> Function(Map<String, String> params) verify;
}

// ─────────────────────────────────────────────────────────────────────
// Shared verifier helpers
// ─────────────────────────────────────────────────────────────────────

SupabaseClient? _verifiedSupabaseClient() {
  if (!isSupabaseInitialized) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

/// Returns true if the family row exists, is not soft-deleted, and is
/// readable under RLS by the current user. Used by the family-scoped
/// deep-route verifiers.
Future<bool> _verifyFamilyAccessible(String? familyId) async {
  if (familyId == null || familyId.isEmpty) return false;
  final client = _verifiedSupabaseClient();
  if (client == null) return false;
  try {
    final response = await client
        .from('Family')
        .select('id')
        .eq('id', familyId)
        .filter('deletedAt', 'is', null)
        .maybeSingle()
        .timeout(const Duration(seconds: 4));
    return response != null && response['id'] == familyId;
  } on TimeoutException {
    debugPrint('⚠️ Splash: family access check timed out for family $familyId');
    return false;
  } catch (e) {
    debugPrint('⚠️ Splash: family access check failed for family $familyId: $e');
    return false;
  }
}

/// Returns true if the person row exists, is not soft-deleted, and is
/// readable under RLS by the current user.
///
/// Used by /member/:id and /member/:id/timeline. Excludes soft-deleted
/// rows (deletedAt != null) — those are not renderable and restoring to
/// one would reproduce the original black-screen failure mode.
Future<bool> _verifyPersonAccessible(String? personId) async {
  if (personId == null || personId.isEmpty) return false;
  final client = _verifiedSupabaseClient();
  if (client == null) return false;
  try {
    final response = await client
        .from('Person')
        .select('id')
        .eq('id', personId)
        .filter('deletedAt', 'is', null)
        .maybeSingle()
        .timeout(const Duration(seconds: 4));
    return response != null && response['id'] == personId;
  } on TimeoutException {
    debugPrint('⚠️ Splash: person access check timed out for person $personId');
    return false;
  } catch (e) {
    debugPrint('⚠️ Splash: person access check failed for person $personId: $e');
    return false;
  }
}

// ── Per-route verifiers (thin wrappers around the shared helpers above) ──

/// Verifier for /family/:id/graph.
Future<bool> _verifyFamilyGraphRoute(Map<String, String> params) async {
  return _verifyFamilyAccessible(params['id']);
}

/// Verifier for /family/:id/chat.
///
/// The chat screen only needs the family row to be readable so it can
/// load the group conversation + DM list. Reuses the family-access helper.
Future<bool> _verifyFamilyChatRoute(Map<String, String> params) async {
  return _verifyFamilyAccessible(params['id']);
}

/// Verifier for /family/:id/map.
///
/// The map screen takes a concrete familyId (no fallback to
/// familyListProvider.first), so the only failure mode is "family gone
/// or not readable" — same check as the graph route.
Future<bool> _verifyFamilyMapRoute(Map<String, String> params) async {
  return _verifyFamilyAccessible(params['id']);
}

/// Verifier for /member/:id (person detail).
///
/// /profile/:id does not exist as a route in this codebase — the
/// closest data-dependent deep route is /member/:id, which is what
/// users navigate to from the family graph to view a person. Restoring
/// it after refresh requires the Person row to still exist, be
/// non-deleted, and be readable under RLS.
Future<bool> _verifyMemberDetailRoute(Map<String, String> params) async {
  return _verifyPersonAccessible(params['id']);
}

/// Verifier for /member/:id/timeline (person timeline).
Future<bool> _verifyMemberTimelineRoute(Map<String, String> params) async {
  return _verifyPersonAccessible(params['id']);
}

// ─────────────────────────────────────────────────────────────────────
// KINREL Splash Screen — "Embrace" Logo Animation
//
// Animation timeline (one AnimationController, 1 500 ms total for
// first-time users; ~708 ms for returning users — see spec):
//   • Tile:        scale 0.7→1 (easeOutBack)   0–260 ms
//                  opacity 0→1 (easeOut)       0–160 ms
//   • Child dot:   radius 0→11 (easeOutBack)  100–400 ms
//   • Ring:        r 11→33, opacity 0.5→0     250–800 ms
//   • Arms:        grow from bottom (60, 98.4) up each side along the arc
//                  (easeOutCubic)             350–870 ms
//   • Head:        y 14→27 (bounce), r 0→12 (overshoot)
//                                             760–1140 ms
//   • "BY DAXELO"  fades in at the bottom    900–1200 ms
//   • Hug pulse:   child +18%, tile +2%, arms −4% around (60, 66)
//                  sine pulse                 1050–1300 ms
//   • At end:      fade the splash out (250 ms) → navigate
//
// Returning-user version: starts the timeline at 650 ms and plays 1.2×
// faster (≈ 708 ms total). HapticFeedback.lightImpact fires when the
// head lands (~760 ms in the full timeline).
//
// Accessibility: if MediaQuery.disableAnimations is true, the animation
// is skipped and the final logo is shown for 300 ms before fade-out.
//
// Splash background: #13141E (KinrelColors.darkSurface) — matches the
// native splash so the handoff is seamless.
// ─────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  bool _navigated = false;
  bool _hasCachedProfile = false;
  bool _hapticFired = false;

  /// True on low-end devices (Android Go, ≤3 GB RAM, or low screen
  /// density). When true, the splash plays a SHORT, SIMPLE animation
  /// (~700 ms, linear curves, no overshoot/bounce) so it renders
  /// smoothly even on GPUs that struggle with 60 FPS. The full 1 500 ms
  /// timeline with easeOutBack / bounce stays on mid/high-end devices.
  bool _isLowEndDevice = false;

  /// True on very-low-end devices — skip the animation entirely and show
  /// the final static frame for 300 ms before fade-out. Set when the
  /// device is `DeviceTier.low` AND `lowRam == true` (e.g., Android Go
  /// with 1 GB RAM). On these devices the AnimationController can tick
  /// to 1.0 before the GPU rasterises a single frame, so the user sees
  /// no animation at all — better to show the final frame deterministically.
  bool _skipAnimation = false;

  /// Deep, data-dependent routes that may be restored after refresh, but
  /// only when their verifier confirms the referenced data is accessible.
  ///
  /// To make another deep route restorable, append a [DeepRouteRestoreRule]
  /// here — the splash screen will verify data availability before
  /// restoring it and fall back to /home on any failure/timeout.
  static final List<DeepRouteRestoreRule> _deepRouteRules = [
    // ── Family-scoped deep routes ────────────────────────────────────
    DeepRouteRestoreRule(
      pattern: RegExp(r'^/family/([^/]+)/graph$'),
      paramNames: const ['id'],
      verify: _verifyFamilyGraphRoute,
    ),
    DeepRouteRestoreRule(
      pattern: RegExp(r'^/family/([^/]+)/chat$'),
      paramNames: const ['id'],
      verify: _verifyFamilyChatRoute,
    ),
    DeepRouteRestoreRule(
      pattern: RegExp(r'^/family/([^/]+)/map$'),
      paramNames: const ['id'],
      verify: _verifyFamilyMapRoute,
    ),
    // ── Person-scoped deep routes ────────────────────────────────────
    DeepRouteRestoreRule(
      pattern: RegExp(r'^/member/([^/]+)$'),
      paramNames: const ['id'],
      verify: _verifyMemberDetailRoute,
    ),
    DeepRouteRestoreRule(
      pattern: RegExp(r'^/member/([^/]+)/timeline$'),
      paramNames: const ['id'],
      verify: _verifyMemberTimelineRoute,
    ),
  ];

  // ── Animation Controllers ────────────────────────────────────────
  // Per spec, ONE controller drives the entire timeline. The fade-out is
  // a separate short controller (it runs AFTER the intro completes and
  // is not part of the spec's "one AnimationController" timeline).
  late final AnimationController _introController;
  late final AnimationController _fadeOutController; // 250 ms — screen exit

  /// Completes when the intro animation reaches its final frame (or when
  /// the safety timeout fires). Awaited by [_initialize] before starting
  /// the fade-out so we never navigate mid-animation.
  final Completer<void> _introDone = Completer<void>();

  /// True when [_introController] has been started (or skipped via the
  /// disableAnimations path). Guards against double-start.
  bool _introStarted = false;

  @override
  void initState() {
    super.initState();

    // ── Device tier detection (low-end device optimisation) ────────
    // On low-end devices (Android Go, ≤3 GB RAM, low screen density),
    // the full 1 500 ms animation with easeOutBack + bounce is too
    // heavy — frames are dropped and the user sees a janky mess or no
    // animation at all. Detect the tier up-front and pick the right
    // animation strategy.
    //
    //   • DeviceTier.low + lowRam → skip animation, show final frame
    //     for 300 ms (the GPU literally can't keep up with 60 FPS).
    //   • DeviceTier.low (no lowRam) → 700 ms simplified animation
    //     (linear curves, no overshoot/bounce).
    //   • DeviceTier.mid / high → full 1 500 ms animation per spec.
    //
    // `DeviceTierCache` is initialised in main.dart before runApp()
    // (via `initialize()` + `initializeRam()`), so by the time the
    // splash builds it has a meaningful value. If detection is still
    // deferred (e.g., on web before first frame), we default to the
    // full animation — better to play it and have it be janky than to
    // skip it on a capable device.
    final tier = DeviceTierCache.instance.tier;
    final lowRam = DeviceTierCache.instance.lowRam;
    _isLowEndDevice = tier == DeviceTier.low;
    _skipAnimation = tier == DeviceTier.low && lowRam;
    if (_skipAnimation) {
      debugPrint('🎬 Splash: very-low-end device detected — skipping animation');
    } else if (_isLowEndDevice) {
      debugPrint('🎬 Splash: low-end device detected — using simplified 700 ms animation');
    }

    // ── Intro: timeline duration is set in [_startIntroAnimation] once
    // we know whether the user is a returning user (which shortens it to
    // ≈ 708 ms via a 1.2× speed-up + 650 ms offset). The controller is
    // created here so dispose() can always dispose it.
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // ── Fade-out: 250 ms per spec ────────────────────────────────────
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // Kick off init (which checks the Isar cache, then starts the intro
    // animation with the correct duration/tween for first-time vs
    // returning users).
    _initialize();

    // Safety timeout: force navigate after 12 seconds even if init hasn't completed.
    // This prevents the user from being stuck on splash forever.
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && !_navigated) {
        debugPrint('⚠️ Splash safety timeout triggered — forcing navigation');
        _navigated = true;
        try {
          // v2.2 FIX: Only route to /home if there's a REAL Supabase session.
          // Previously _hasCachedProfile was used as a proxy, but on web the
          // Drift cache (IndexedDB) persists from previous visits, causing
          // the app to auto-open a "demo" account without real auth.
          if (_supabaseHasSession()) {
            context.go('/home');
          } else {
            context.go('/sign-in');
          }
        } catch (_) {
          try {
            context.go('/sign-in');
          } catch (_) {}
        }
      }
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Initialization — runs in parallel with animation
  // ─────────────────────────────────────────────────────────────────
  Future<void> _initialize() async {
    // FAST STARTUP: Check Isar cache — await to prevent race condition
    // where _hasCachedProfile is read before the async check completes.
    // The result decides whether we play the full 1 500 ms timeline or
    // the short returning-user version (≈ 708 ms).
    await _checkIsarCache();

    if (!mounted) return;

    // Start the intro animation now that we know the user type.
    _startIntroAnimation();

    // Preload kinship data in the background (5 300+ terms, ~15 MB JSON)
    // Delay kinship loading by 5 seconds so it doesn't compete
    // with auth and UI initialization on the main thread
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        ref.read(kinshipInitializedProvider.future).catchError((_) {});
      }
    });

    // ── Wait for background initialization to complete ──────────────
    // Services (Drift, Firebase, Supabase) are now initialized in the
    // background AFTER runApp(). We must wait for them to finish before
    // checking auth state, otherwise we'll always navigate to sign-in.
    try {
      await ref.read(appInitCompleteProvider.future).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
              '⚠️ Splash: background init timed out after 10s — proceeding anyway');
        },
      );
      debugPrint('📦 Splash: background initialization complete');
    } catch (e) {
      debugPrint('⚠️ Splash: error waiting for init: $e');
    }

    // Start Supabase session restoration in the background.
    unawaited(_restoreSession());

    // Wait for the intro animation to finish (it may already be done if
    // init was slow). The safety timeout above handles the case where
    // everything hangs.
    await _introDone.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('⚠️ Splash: intro animation timed out — proceeding anyway');
      },
    );

    if (!mounted || _navigated) return;

    // Read navigation state from LOCAL sources only — don't block on network.
    bool isAuthenticated = false;
    try {
      isAuthenticated = ref.read(isAuthenticatedProvider);
      if (!isAuthenticated && _supabaseHasSession()) {
        isAuthenticated = true;
        debugPrint(
            '📦 Supabase has session but Riverpod provider not updated yet — treating as authenticated');
      }
    } catch (e) {
      debugPrint('⚠️ Cannot read auth state, using cached profile: $e');
      if (_supabaseHasSession()) {
        isAuthenticated = true;
      }
    }

    if (!mounted || _navigated) return;

    // Fade out the splash, then navigate.
    await _fadeOutController.forward();

    if (!mounted || _navigated) return;

    // NOTE: _navigated is intentionally NOT set here. It is set
    // immediately before each context.go() call below so re-entrant
    // navigation is still prevented, but the restoration logic actually
    // runs (see the original comment — this was a long-standing bug).

    if (isAuthenticated) {
      // ── CRITICAL FIX: Invalidate familyListProvider before navigating ──
      // The provider may have been evaluated (and cached as empty) before
      // Supabase was ready or before the auth session was restored. By
      // invalidating it here, we force a fresh fetch with the correct
      // auth state, so the home screen shows existing families immediately.
      try {
        ref.invalidate(familyListProvider);
        debugPrint('📦 Splash: invalidated familyListProvider before navigation');
      } catch (e) {
        debugPrint('⚠️ Splash: could not invalidate familyListProvider: $e');
      }

      // Real Supabase session exists — go to home (or last route).
      String? lastRoute;
      try {
        lastRoute = await getLastRoute();
      } catch (_) {}
      if (!mounted || _navigated) return;

      // Only restore routes that are known-safe. Top-level routes in the
      // allowlist below can always be restored (they have no external data
      // dependency). Deep, parameterized routes (/family/:id/graph, etc.)
      // are restored ONLY when a verifier confirms the referenced data is
      // still accessible to the current user — otherwise we fall back to
      // /home so the original black-screen failure mode cannot reoccur.
      if (lastRoute != null && lastRoute != '/splash' && mounted) {
        final safeRoutes = [
          '/home',
          '/search',
          '/families',
          '/notifications',
          '/profile'
        ];
        if (safeRoutes.contains(lastRoute)) {
          debugPrint('🧭 Splash → $lastRoute (restored last route)');
          _navigated = true;
          context.go(lastRoute);
          return;
        }

        // Deep, data-dependent routes: verify before restoring.
        final pathOnly = Uri.tryParse(lastRoute)?.path ?? lastRoute;
        for (final rule in _deepRouteRules) {
          final match = rule.pattern.firstMatch(pathOnly);
          if (match == null) continue;

          final params = <String, String>{};
          for (var i = 0; i < rule.paramNames.length; i++) {
            params[rule.paramNames[i]] = match.group(i + 1) ?? '';
          }

          debugPrint(
              '🧭 Splash: verifying deep route $lastRoute (params=$params)');
          bool ok = false;
          try {
            ok = await rule
                .verify(params)
                .timeout(const Duration(seconds: 6));
          } on TimeoutException {
            debugPrint(
                '🧭 Splash: deep route verifier backstop timeout for $lastRoute');
            ok = false;
          } catch (e) {
            debugPrint(
                '🧭 Splash: deep route verifier failed for $lastRoute: $e');
            ok = false;
          }
          if (!mounted || _navigated) return;

          if (ok) {
            debugPrint('🧭 Splash → $lastRoute (verified deep route)');
            _navigated = true;
            context.go(lastRoute);
            return;
          }

          debugPrint(
              '🧭 Splash: deep route $lastRoute not restorable (data unavailable) — falling back to /home');
          break;
        }
        debugPrint('🧭 Splash: skipping unsafe route restore: $lastRoute');
      }
      debugPrint('🧭 Splash → /home (authenticated: $isAuthenticated)');
      _navigated = true;
      context.go('/home');
    } else {
      // v2.2 FIX: No real Supabase session — ALWAYS go to sign-in.
      debugPrint('🧭 Splash → /sign-in (not authenticated, login required)');
      _navigated = true;
      context.go('/sign-in');
    }
  }

  /// Check Isar cache for a cached user profile.
  /// If found, set _hasCachedProfile = true so we play the short
  /// returning-user version of the animation.
  Future<void> _checkIsarCache() async {
    if (!IsarDatabase.isInitialized) {
      debugPrint('📦 Database not initialized — skipping cache check');
      return;
    }
    try {
      final db = IsarDatabase.instance;
      final profileCount = await db.profileCount();
      if (profileCount > 0) {
        _hasCachedProfile = true;
        debugPrint('📦 Drift cache: found $profileCount cached profile(s)');
      } else {
        debugPrint('📦 Drift cache: no cached profiles');
      }
    } catch (e) {
      debugPrint('📦 Drift cache check failed: $e');
    }
  }

  /// Configure the intro controller for first-time vs returning users,
  /// then start it (or skip it entirely if disableAnimations is set or
  /// the device is very low-end).
  ///
  /// Animation strategy by device tier:
  ///   • Very low-end (DeviceTier.low + lowRam): SKIP animation, show
  ///     final frame for 300 ms. The GPU can't keep up with 60 FPS so
  ///     the AnimationController ticks to 1.0 before any frame renders.
  ///   • Low-end (DeviceTier.low, no lowRam): 700 ms simplified timeline
  ///     (linear curves, no overshoot/bounce) so it renders smoothly.
  ///   • Mid / High: full 1 500 ms timeline per spec, OR 708 ms for
  ///     returning users (1.2× speed + 650 ms offset).
  void _startIntroAnimation() {
    if (_introStarted) return;
    _introStarted = true;

    // Accessibility: if the platform requests no animations, skip the
    // timeline entirely and show the final logo for 300 ms before
    // fade-out. This is checked here (rather than in build) so the
    // skip decision is made once, at startup.
    final bool disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations || _skipAnimation) {
      debugPrint(
          '🎬 Splash: ${disableAnimations ? "disableAnimations=true" : "very-low-end device"} — skipping intro');
      _introController.value = 1.0;
      // Hold the final frame for 300 ms, then complete. This guarantees
      // the user sees the embrace mark (not a blank screen) even on the
      // slowest devices.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_introDone.isCompleted) {
          _introDone.complete();
        }
      });
      return;
    }

    // Low-end device: 700 ms simplified timeline. The full 1 500 ms
    // animation with easeOutBack + bounce causes dropped frames on
    // low-end GPUs; the 700 ms linear version is smooth on every device.
    //
    // The painter's `progress` value still maps to the full 1 500 ms
    // timeline (so the animation looks the same, just faster and without
    // overshoot). The progress computation in `build` uses the
    // controller's 0..1 value directly, which means at 700 ms duration
    // the controller reaches 1.0 in 700 ms wall-clock time.
    if (_isLowEndDevice) {
      _introController.duration = const Duration(milliseconds: 700);
      // Schedule the animation to start on the NEXT frame so the splash's
      // first frame renders with progress=0 (tile invisible). Without
      // this, the controller may have already advanced past 0 by the
      // time the first frame is painted, and the user misses the
      // tile-fade-in.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _introController.forward().then((_) {
          if (!_introDone.isCompleted) _introDone.complete();
        });
      });
      // Head lands at ~50% of the 700 ms timeline = 350 ms.
      Future.delayed(const Duration(milliseconds: 350), _fireHeadLandingHaptic);
      debugPrint('🎬 Splash: low-end intro (700 ms, simplified)');
      return;
    }

    // Returning-user version: start the timeline at 650 ms and play 1.2×
    // faster. (1500 − 650) / 1.2 ≈ 708 ms total.
    if (_hasCachedProfile) {
      _introController.duration = const Duration(milliseconds: 708);
      // The controller's 0..1 value is mapped to the [650, 1500] segment
      // of the full timeline in [build] (see progress computation there).
      // Schedule the forward on the next frame so the first frame renders
      // with progress=0 (returning-user start = 650 ms into the timeline
      // = tile already visible, child dot appearing, arms starting).
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _introController.forward().then((_) {
          if (!_introDone.isCompleted) _introDone.complete();
        });
      });
      // Fire the head-landing haptic at the moment the head touches down
      // in the compressed timeline: (760 − 650) / 1.2 ≈ 92 ms.
      Future.delayed(const Duration(milliseconds: 92), _fireHeadLandingHaptic);
      debugPrint('🎬 Splash: returning-user intro (~708 ms, 1.2× speed)');
    } else {
      // Full version: 1 500 ms timeline.
      // Schedule the forward on the next frame so the first frame renders
      // with progress=0 (tile invisible). This is critical for low-end
      // devices — without it, the AnimationController may tick past 0
      // before the first frame is painted, and the user misses the
      // tile-fade-in.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _introController.forward().then((_) {
          if (!_introDone.isCompleted) _introDone.complete();
        });
      });
      // Head lands at 760 ms in the full timeline.
      Future.delayed(const Duration(milliseconds: 760), _fireHeadLandingHaptic);
      debugPrint('🎬 Splash: full intro (1500 ms)');
    }
  }

  void _fireHeadLandingHaptic() {
    if (_hapticFired) return;
    _hapticFired = true;
    if (!mounted) return;
    // Light haptic when the head lands on top of the embrace.
    HapticFeedback.lightImpact();
  }

  /// Check if Supabase has an active session directly (bypasses Riverpod).
  bool _supabaseHasSession() {
    if (!isSupabaseInitialized) return false;
    try {
      final client = Supabase.instance.client;
      return client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  /// Restore Supabase session (important for app resume & cold starts).
  Future<void> _restoreSession() async {
    if (!isSupabaseInitialized) return;
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session != null) {
        debugPrint('📦 Existing session found for ${session.user.email}');
        return;
      }
      try {
        await client.auth.onAuthStateChange.first
            .timeout(const Duration(seconds: 3));
        await Future.delayed(const Duration(milliseconds: 200));
        debugPrint('📦 Auth state restored');
      } on TimeoutException {
        debugPrint(
            '📦 Auth state restore timed out — proceeding with cached state');
      }
    } catch (e) {
      debugPrint('⚠️ Session restoration failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  //
  // PERF (low-end device optimisation):
  // The previous build used a single `KinrelAnimatedBuilder` that
  // rebuilt the ENTIRE splash body (Opacity, Container, Column, Spacer,
  // Center, SafeArea, KinrelLogo, ShaderMask, Text) on every animation
  // frame. On low-end GPUs that's ~90 wasted widget rebuilds per
  // second, plus two expensive `saveLayer` calls (Opacity + ShaderMask)
  // per frame.
  //
  // The new build:
  //   1. Wraps the whole body in a single `FadeTransition` (GPU-composited,
  //      no saveLayer) for the fade-out.
  //   2. Uses a SEPARATE `AnimatedBuilder` for the logo, wordmark, and
  //      byline — each wrapped in a `RepaintBoundary` so its rasterised
  //      layer is cached between frames.
  //   3. Removes `ShaderMask` (causes saveLayer) — the wordmark is plain
  //      white text. The gradient was nice but not worth the jank on
  //      low-end devices.
  //   4. Removes `Opacity` widget — replaced with `FadeTransition` which
  //      is GPU-composited (no saveLayer).
  //   5. The static parts of the layout (Spacer, SizedBox, Center,
  //      SafeArea, Container) are built ONCE and never rebuilt.
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface, // #13141E
      // FadeTransition is GPU-composited (no saveLayer) — much cheaper
      // than the Opacity widget for animating the whole body's opacity.
      body: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_fadeOutController),
        child: ColoredBox(
          color: KinrelColors.darkSurface,
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  // ── Embrace logo (animated) ─────────────────────
                  // Separate AnimatedBuilder + RepaintBoundary so the
                  // logo's rasterised layer is cached between frames
                  // and only the CustomPaint area is re-rasterised.
                  _buildEmbrace(),
                  const SizedBox(height: 32),
                  // ── "KINREL" wordmark (fades in 760–1140 ms) ─────
                  _buildWordmark(),
                  const SizedBox(height: 10),
                  // ── "BY DAXELO" byline (fades in 900–1200 ms) ────
                  _buildByline(),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Embrace logo (animated) ─────────────────────────────────────
  //
  // Wrapped in a RepaintBoundary so the CustomPaint's rasterised output
  // is cached as a single layer. The AnimatedBuilder only rebuilds the
  // CustomPaint (not the surrounding Column/SafeArea/Center).
  Widget _buildEmbrace() {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _introController,
        builder: (context, _) {
          return KinrelLogo(
            size: 132,
            variant: KinrelLogoVariant.light,
            progress: _currentTimelineProgress(),
            semanticLabel: 'Kinrel embrace logo',
          );
        },
      ),
    );
  }

  // ── "KINREL" Wordmark ───────────────────────────────────────────
  //
  // Plain white text (no ShaderMask — that caused an expensive
  // saveLayer on every frame). The wordmark fades in over 760–1140 ms
  // in the full timeline. Wrapped in a RepaintBoundary so the text's
  // rasterised layer is cached between frames.
  Widget _buildWordmark() {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _introController,
        builder: (context, _) {
          final progress = _currentTimelineProgress();
          // Wordmark fades in alongside the head landing (760–1140 ms in
          // the full timeline = 0.507–0.760 normalized).
          final raw = ((progress * 1500) - 760) / (1140 - 760);
          final opacity = raw.clamp(0.0, 1.0);
          final slideY = (1.0 - opacity) * 12.0;

          // Use Transform.translate + Opacity directly inside the
          // AnimatedBuilder. The Opacity here is fine because it's
          // INSIDE a RepaintBoundary — the saveLayer is cached between
          // frames and only re-rasterised when opacity actually changes.
          // (Opacity on a leaf Text widget is much cheaper than Opacity
          // on a whole subtree.)
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, slideY),
              child: const Text(
                'KINREL',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont, // Outfit
                  fontSize: 36,
                  fontWeight: FontWeight.w800, // ExtraBold
                  letterSpacing: 36 * 0.16, // +0.16 em = 5.76
                  height: 1.1,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── "BY DAXELO" Byline ──────────────────────────────────────────
  // Spec: "Text 'BY DAXELO': small, letter-spaced, color #C9B4A8,
  //        fades in at the bottom, 900–1200".
  Widget _buildByline() {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _introController,
        builder: (context, _) {
          final progress = _currentTimelineProgress();
          final raw = ((progress * 1500) - 900) / (1200 - 900);
          final opacity = raw.clamp(0.0, 1.0);
          final slideY = (1.0 - opacity) * 8.0;

          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, slideY),
              child: const Text(
                'BY DAXELO',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont, // DM Mono
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textSilver, // #C9B4A8
                  letterSpacing: 2.0,
                  height: 1.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Maps the intro controller's current 0..1 value to the position in
  /// the FULL 1 500 ms timeline (0..1).
  ///
  /// For first-time users on mid/high-end devices, the controller's value
  /// IS the timeline position.
  ///
  /// For returning users on mid/high-end devices, the controller runs
  /// over ~708 ms and represents the segment [650, 1500] of the full
  /// timeline — we map the controller value to that segment.
  ///
  /// For low-end devices (700 ms simplified timeline), the controller's
  /// value IS the timeline position (we want the full timeline to play,
  /// just faster).
  ///
  /// For very-low-end devices (skipAnimation), the controller is set to
  /// 1.0 immediately so this returns 1.0 (final frame).
  double _currentTimelineProgress() {
    if (_hasCachedProfile && !_isLowEndDevice) {
      // Returning user on mid/high-end: map [0,1] → [650/1500, 1.0].
      return (650.0 / 1500.0) +
          _introController.value * (1.0 - 650.0 / 1500.0);
    }
    // First-time user, low-end device, or skipped animation: controller
    // value IS the timeline position.
    return _introController.value;
  }
}
