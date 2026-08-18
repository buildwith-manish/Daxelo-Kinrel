import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../main.dart' show appInitCompleteProvider;

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
// To make additional deep, data-dependent routes restorable in the
// future, append a new [DeepRouteRestoreRule] to [_deepRouteRules] below —
// do NOT special-case individual screens inside _initialize().
// ─────────────────────────────────────────────────────────────────────

/// Verifier for a single restorable deep route.
///
/// [pattern] is matched against the saved route's *path* (query string
/// stripped). Capture groups in [pattern] map to [paramNames], in order.
///
/// [verify] receives those captured values and MUST return `true` only
/// when the data needed to render the destination screen is confirmed
/// accessible to the current user. Implementations MUST be resilient to
/// network/auth errors and SHOULD impose their own internal timeout
/// (the splash screen also enforces an outer backstop timeout).
typedef DeepRouteVerifier = Future<bool> Function(Map<String, String> params);

class DeepRouteRestoreRule {
  const DeepRouteRestoreRule({
    required this.pattern,
    required this.paramNames,
    required this.verify,
  });

  final RegExp pattern;
  final List<String> paramNames;
  final DeepRouteVerifier verify;
}

// ─────────────────────────────────────────────────────────────────────
// Deep-route verifiers
// ─────────────────────────────────────────────────────────────────────
// Each verifier performs the *cheapest possible* query that confirms the
// referenced resource still exists AND is accessible to the current user
// (RLS will otherwise return null/empty for rows the user can't read).
// Verifiers MUST be resilient to network/auth errors, MUST impose their
// own internal timeout (the splash screen also enforces an outer backstop
// timeout), and MUST NOT load the full screen data — the destination
// screen will fetch that itself once the user lands on it.
// ─────────────────────────────────────────────────────────────────────

/// Common guard: ensures Supabase + an authenticated session are
/// available before issuing a verification query. Returns the live
/// [SupabaseClient] when ready, otherwise null.
SupabaseClient? _verifiedSupabaseClient() {
  if (!isSupabaseInitialized) return null;
  try {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return null;
    return client;
  } catch (_) {
    return null;
  }
}

/// Minimal existence + RLS-accessibility check for a Family row.
///
/// Used by every /family/:id/* deep route (graph, chat, map, …) so the
/// shared "is this family still readable by me?" logic has one home.
Future<bool> _verifyFamilyAccessible(String? familyId) async {
  if (familyId == null || familyId.isEmpty) return false;
  final client = _verifiedSupabaseClient();
  if (client == null) return false;
  try {
    final response = await client
        .from('Family')
        .select('id')
        .eq('id', familyId)
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

/// Minimal existence + RLS-accessibility check for a Person row.
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

/// Verifier for /member/:id/timeline.
Future<bool> _verifyMemberTimelineRoute(Map<String, String> params) async {
  return _verifyPersonAccessible(params['id']);
}

// ─────────────────────────────────────────────────────────────────────
// KINREL Splash Screen — Animated K-Graph Experience
//
// Animation sequence (1.5–2.0 s total):
//   Phase 1  0–300 ms    Radial glow fades in from center
//   Phase 2  300–600 ms  Center "You" node scale-in + heartbeat glow
//   Phase 3  600–900 ms  Edges draw outward → nodes appear
//   Phase 4  900–1200 ms Orbit ring draws in + halo pulse
//   Phase 5  1200–1500 ms "KINREL" fades up (gradient) + "BY DAXELO"
//   Phase 6  1500–1800 ms Hold → fade out → navigate
//
// FAST STARTUP: Reads Isar cache instantly to determine if user
// has a cached profile. If so, navigates to /home immediately
// after the animation without waiting for full Supabase auth.
// ─────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  bool _navigated = false;
  bool _initComplete = false;
  bool _hasCachedProfile = false;

  /// Deep, data-dependent routes that may be restored after refresh, but
  /// only when their verifier confirms the referenced data is accessible.
  ///
  /// To make another deep route restorable, append a [DeepRouteRestoreRule]
  /// here — the splash screen will verify data availability before
  /// restoring it and fall back to /home on any failure/timeout.
  ///
  /// Pattern is intentionally generic and table-driven: each rule is a
  /// (regex, param-names, verifier) triple, and verifiers share a small
  /// set of helpers (_verifyFamilyAccessible, _verifyPersonAccessible, …)
  /// so adding a new family-scoped route is a one-line change.
  static final List<DeepRouteRestoreRule> _deepRouteRules = [
    // ── Family-scoped deep routes ────────────────────────────────────
    // All of these only need the Family row to exist + be readable, so
    // they share _verifyFamilyAccessible via a thin per-route wrapper.
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
    // /profile/:id does not exist as a route in this codebase; the
    // closest data-dependent deep route is /member/:id, which is what
    // users navigate to from the family graph.
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
  late final AnimationController _introController; // 1 500 ms – main sequence
  late final AnimationController
  _breathingController; // 1 000 ms × 2 = 2 s cycle
  late final AnimationController _fadeOutController; // 400 ms – screen exit

  // ── Phase Animations (derived from _introController) ─────────────
  late final Animation<double> _glowFadeIn; // 0–300 ms
  late final Animation<double> _centerNodeScale; // 300–600 ms
  late final Animation<double> _edgesProgress; // 600–900 ms
  late final Animation<double> _orbitProgress; // 900–1 200 ms
  late final Animation<double> _textFade; // 1 200–1 500 ms

  @override
  void initState() {
    super.initState();

    // ── Intro: 1 500 ms ─────────────────────────────────────────────
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // ── Breathing: 1 000 ms per half-cycle → 2 s full ──────────────
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // ── Fade-out: 400 ms ────────────────────────────────────────────
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // ── Phase intervals ─────────────────────────────────────────────
    _glowFadeIn = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    );
    _centerNodeScale = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.2, 0.4, curve: Curves.easeOutBack),
    );
    _edgesProgress = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.4, 0.6, curve: Curves.easeOutCubic),
    );
    _orbitProgress = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.6, 0.8, curve: Curves.easeOutCubic),
    );
    _textFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
    );

    // ── Kick off intro, then breathing if still waiting ─────────────
    _introController.forward().then((_) {
      if (!_initComplete && mounted) {
        _breathingController.repeat(reverse: true);
      }
    });

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
          try { context.go('/sign-in'); } catch (_) {}
        }
      }
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _breathingController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Initialization — runs in parallel with animation
  // ─────────────────────────────────────────────────────────────────
  Future<void> _initialize() async {
    // FAST STARTUP: Check Isar cache — await to prevent race condition
    // where _hasCachedProfile is read before the async check completes.
    await _checkIsarCache();

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
          debugPrint('⚠️ Splash: background init timed out after 10s — proceeding anyway');
        },
      );
      debugPrint('📦 Splash: background initialization complete');
    } catch (e) {
      debugPrint('⚠️ Splash: error waiting for init: $e');
    }

    // Start Supabase session restoration in the background.
    unawaited(_restoreSession());

    // Shorter hold if we have cached data — user sees app faster
    final holdMs = _hasCachedProfile ? 800 : 1500;
    await Future.delayed(Duration(milliseconds: holdMs));

    if (!mounted || _navigated) return;

    // Read navigation state from LOCAL sources only — don't block on network.
    // If Supabase is already initialized, use its auth state; otherwise
    // fall back to cached profile presence to decide where to go.
    bool isAuthenticated = false;
    try {
      isAuthenticated = ref.read(isAuthenticatedProvider);
      // Also check Supabase directly — the Riverpod provider may not have
      // received the stream event yet, but the Supabase client already
      // knows about the session.
      if (!isAuthenticated && _supabaseHasSession()) {
        isAuthenticated = true;
        debugPrint('📦 Supabase has session but Riverpod provider not updated yet — treating as authenticated');
      }
    } catch (e) {
      debugPrint('⚠️ Cannot read auth state, using cached profile: $e');
      // Fallback: check Supabase directly
      if (_supabaseHasSession()) {
        isAuthenticated = true;
      }
    }

    if (!mounted || _navigated) return;

    // Signal complete — stop breathing
    _initComplete = true;
    _breathingController.stop();

    // Fade out the splash, then navigate
    await _fadeOutController.forward();

    if (!mounted || _navigated) return;

    _navigated = true;

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
        final safeRoutes =
            ['/home', '/search', '/families', '/notifications', '/profile'];
        if (safeRoutes.contains(lastRoute)) {
          debugPrint('🧭 Splash → $lastRoute (restored last route)');
          context.go(lastRoute);
          return;
        }

        // Deep, data-dependent routes: verify before restoring.
        // Strip the query string (matchedLocation never carries one, but
        // be defensive in case a future caller saves the full URL).
        final pathOnly = Uri.tryParse(lastRoute)?.path ?? lastRoute;
        for (final rule in _deepRouteRules) {
          final match = rule.pattern.firstMatch(pathOnly);
          if (match == null) continue;

          final params = <String, String>{};
          for (var i = 0; i < rule.paramNames.length; i++) {
            params[rule.paramNames[i]] = match.group(i + 1) ?? '';
          }

          debugPrint('🧭 Splash: verifying deep route $lastRoute (params=$params)');
          bool ok = false;
          try {
            // Outer backstop timeout: even a well-behaved verifier that
            // hangs on a stuck socket must not block the splash screen.
            ok = await rule.verify(params)
                .timeout(const Duration(seconds: 6));
          } on TimeoutException {
            debugPrint('🧭 Splash: deep route verifier backstop timeout for $lastRoute');
            ok = false;
          } catch (e) {
            debugPrint('🧭 Splash: deep route verifier failed for $lastRoute: $e');
            ok = false;
          }
          if (!mounted || _navigated) return;

          if (ok) {
            debugPrint('🧭 Splash → $lastRoute (verified deep route)');
            context.go(lastRoute);
            return;
          }

          debugPrint(
              '🧭 Splash: deep route $lastRoute not restorable (data unavailable) — falling back to /home');
          // Only one rule can match a given route; stop scanning.
          break;
        }
        debugPrint('🧭 Splash: skipping unsafe route restore: $lastRoute');
      }
      debugPrint('🧭 Splash → /home (authenticated: $isAuthenticated)');
      context.go('/home');
    } else {
      // v2.2 FIX: No real Supabase session — ALWAYS go to sign-in.
      // Previously _hasCachedProfile was used to bypass this, but on web
      // the Drift cache (IndexedDB) persists from previous visits, causing
      // the app to auto-open a "demo" account without real auth.
      debugPrint('🧭 Splash → /sign-in (not authenticated, login required)');
      context.go('/sign-in');
    }
  }

  /// Check Isar cache for a cached user profile.
  /// If found, set _hasCachedProfile = true so we can navigate faster.
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
      // Don't crash — just treat as no cache
    }
  }

  /// Check if Supabase has an active session directly (bypasses Riverpod).
  /// This is used as a fallback when the Riverpod authStateProvider
  /// hasn't received the stream event yet but the Supabase client
  /// already has a valid session after sign-in.
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
  /// This runs in the background (fire-and-forget) and should NOT block
  /// splash screen navigation. If Supabase isn't initialized yet, skip.
  Future<void> _restoreSession() async {
    if (!isSupabaseInitialized) return;
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session != null) {
        debugPrint('📦 Existing session found for ${session.user.email}');
        return;
      }
      // Wait for auth state to restore (up to 3 seconds)
      try {
        await client.auth.onAuthStateChange.first
            .timeout(const Duration(seconds: 3));
        // Small delay for state propagation
        await Future.delayed(const Duration(milliseconds: 200));
        debugPrint('📦 Auth state restored');
      } on TimeoutException {
        debugPrint('📦 Auth state restore timed out — proceeding with cached state');
      }
    } catch (e) {
      debugPrint('⚠️ Session restoration failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: KinrelAnimatedBuilder(
        animation: Listenable.merge([
          _introController,
          _breathingController,
          _fadeOutController,
        ]),
        builder: (context, _) {
          final fadeOpacity = 1.0 - _fadeOutController.value;

          return Opacity(
            opacity: fadeOpacity,
            child: Container(
              color: KinrelColors.darkSurface,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      _buildKGraph(),
                      const SizedBox(height: 40),
                      _buildWordmark(),
                      const SizedBox(height: 10),
                      _buildByline(),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── K-Graph Icon ────────────────────────────────────────────────
  Widget _buildKGraph() {
    // Breathing: subtle scale pulse while waiting for init
    final breathingScale = _introController.isCompleted
        ? 1.0 + 0.02 * _breathingController.value
        : 1.0;

    return Transform.scale(
      scale: breathingScale,
      child: CustomPaint(
        size: const Size(200, 200),
        painter: _KGraphSplashPainter(
          glowProgress: _glowFadeIn.value,
          centerNodeProgress: _centerNodeScale.value,
          edgesProgress: _edgesProgress.value,
          orbitProgress: _orbitProgress.value,
        ),
      ),
    );
  }

  // ── "KINREL" Wordmark ───────────────────────────────────────────
  Widget _buildWordmark() {
    final opacity = _textFade.value.clamp(0.0, 1.0);
    final slideY = (1.0 - _textFade.value) * 12.0;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, slideY),
        child: ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [
                Color(0xFFFFFFFF), // white
                Color(0xFFE8612A), // orange
                Color(0xFFF59240), // amber
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds);
          },
          child: Text(
            'KINREL',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont, // Outfit
              fontSize: 36,
              fontWeight: FontWeight.w800, // ExtraBold
              letterSpacing: 36 * 0.16, // +0.16 em = 5.76
              height: 1.1,
              color: Colors.white, // ShaderMask needs non-transparent base
            ),
          ),
        ),
      ),
    );
  }

  // ── "BY DAXELO" Byline ──────────────────────────────────────────
  Widget _buildByline() {
    // Delayed fade: starts at textFade 0.5 → full at 1.0
    final opacity = (_textFade.value * 2.0 - 1.0).clamp(0.0, 1.0);
    final slideY = (1.0 - _textFade.value) * 8.0;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, slideY),
        child: Text(
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
  }
}

// ═════════════════════════════════════════════════════════════════════
// K-Graph Splash CustomPainter
// ═════════════════════════════════════════════════════════════════════

class _KGraphSplashPainter extends CustomPainter {
  const _KGraphSplashPainter({
    required this.glowProgress,
    required this.centerNodeProgress,
    required this.edgesProgress,
    required this.orbitProgress,
  });

  final double glowProgress;
  final double centerNodeProgress;
  final double edgesProgress;
  final double orbitProgress;

  // ── Node definitions ─────────────────────────────────────────────
  static const _nodes = <_SplashNode>[
    _SplashNode(0.00, -0.42, 0.048, KinrelColors.brightViolet, 'Parent'),
    _SplashNode(0.00, 0.42, 0.048, KinrelColors.brightViolet, 'Child'),
    _SplashNode(-0.42, 0.00, 0.048, KinrelColors.deepPurple, 'Spouse'),
    _SplashNode(0.40, -0.24, 0.044, KinrelColors.brightViolet, 'Uncle'),
    _SplashNode(0.40, 0.24, 0.044, KinrelColors.deepPurple, 'Aunt'),
    _SplashNode(0.68, -0.24, 0.044, KinrelColors.brightViolet, 'Cousin'),
  ];

  // ── Edge definitions (from-index, to-index into _nodes) ──────────
  static const _edges = <_SplashEdge>[
    _SplashEdge(-1, 0, 0),
    _SplashEdge(-1, 1, 0),
    _SplashEdge(-1, 2, 1),
    _SplashEdge(-1, 3, 1),
    _SplashEdge(-1, 4, 1),
    _SplashEdge(3, 5, 2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 2;

    if (glowProgress > 0) {
      _drawGlowCore(canvas, size, cx, cy);
    }

    if (orbitProgress > 0) {
      _drawOrbitAndHalo(canvas, cx, cy, s);
    }

    if (edgesProgress > 0) {
      _drawEdgesAndNodes(canvas, cx, cy, s);
    }

    if (centerNodeProgress > 0) {
      _drawCenterNode(canvas, cx, cy, s);
    }
  }

  void _drawGlowCore(Canvas canvas, Size size, double cx, double cy) {
    final alpha = (0.28 * glowProgress).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            center: const Alignment(-0.4, -0.4),
            radius: 0.7,
            colors: [
              Color.fromRGBO(232, 97, 42, alpha),
              KinrelColors.darkSurface,
            ],
          ).createShader(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: size.width * 1.2,
              height: size.height * 1.2,
            ),
          );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width,
        height: size.height,
      ),
      glowPaint,
    );
  }

  void _drawCenterNode(Canvas canvas, double cx, double cy, double s) {
    final baseRadius = s * 0.075;
    final scale = centerNodeProgress;
    final radius = baseRadius * scale;

    if (radius <= 0) return;

    final center = Offset(cx, cy);
    final glowIntensity = _heartbeatGlow(centerNodeProgress);

    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = KinrelColors.purple.withValues(alpha: glowIntensity * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius * 3.0, glowPaint);
    }

    final innerGlow = Paint()
      ..color = KinrelColors.purple.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius * 1.8, innerGlow);

    final nodePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [
          KinrelColors.brightViolet,
          KinrelColors.purple,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, nodePaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(
      Offset(cx - radius * 0.28, cy - radius * 0.28),
      radius * 0.32,
      highlightPaint,
    );
  }

  static double _heartbeatGlow(double t) {
    if (t < 0.15) return 0.0;
    if (t < 0.40) return math.sin(math.pi * (t - 0.15) / 0.25);
    if (t < 0.50) return 0.0;
    if (t < 0.75) {
      return 0.6 * math.sin(math.pi * (t - 0.50) / 0.25);
    }
    return 0.0;
  }

  void _drawEdgesAndNodes(Canvas canvas, double cx, double cy, double s) {
    final center = Offset(cx, cy);

    for (final edge in _edges) {
      final tier = edge.tier;
      final double tierStart, tierEnd;
      switch (tier) {
        case 0:
          tierStart = 0.0;
          tierEnd = 0.4;
          break;
        case 1:
          tierStart = 0.25;
          tierEnd = 0.65;
          break;
        default:
          tierStart = 0.55;
          tierEnd = 1.0;
          break;
      }

      final progress = ((edgesProgress - tierStart) / (tierEnd - tierStart))
          .clamp(0.0, 1.0);
      if (progress <= 0) continue;

      final Offset from;
      if (edge.from == -1) {
        from = center;
      } else {
        final n = _nodes[edge.from];
        from = Offset(cx + n.x * s, cy + n.y * s);
      }
      final toN = _nodes[edge.to];
      final to = Offset(cx + toN.x * s, cy + toN.y * s);

      final edgePaint = Paint()
        ..color =
            (edge.from == -1 ? KinrelColors.purple : KinrelColors.brightViolet)
                .withValues(alpha: 0.65)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final endPoint = Offset(
        from.dx + (to.dx - from.dx) * progress,
        from.dy + (to.dy - from.dy) * progress,
      );
      canvas.drawLine(from, endPoint, edgePaint);

      if (progress > 0.75) {
        final nodeOpacity = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
        _drawNode(canvas, to, toN.r * s, toN.color, nodeOpacity);
      }
    }
  }

  void _drawNode(
    Canvas canvas,
    Offset pos,
    double radius,
    Color color,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.18 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(pos, radius * 2.2, glowPaint);

    final nodePaint = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawCircle(pos, radius, nodePaint);

    if (opacity > 0.5) {
      final hlPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      canvas.drawCircle(
        Offset(pos.dx - radius * 0.25, pos.dy - radius * 0.25),
        radius * 0.30,
        hlPaint,
      );
    }
  }

  void _drawOrbitAndHalo(Canvas canvas, double cx, double cy, double s) {
    final orbitRadius = s * 0.72;
    final center = Offset(cx, cy);

    final sweepAngle = 2 * math.pi * orbitProgress;
    final orbitPaint = Paint()
      ..color = KinrelColors.purple.withValues(alpha: 0.22)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: orbitRadius),
      -math.pi / 2,
      sweepAngle,
      false,
      orbitPaint,
    );

    if (orbitProgress > 0.5) {
      final dashOpacity = ((orbitProgress - 0.5) * 2.0).clamp(0.0, 0.12);
      final dashPaint = Paint()
        ..color = KinrelColors.brightViolet.withValues(alpha: dashOpacity)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      _drawDashedCircle(
        canvas,
        center,
        orbitRadius * 0.88,
        dashPaint,
        dashWidth: 8,
        dashGap: 12,
      );
    }

    final haloAlpha = 0.18 * math.sin(math.pi * orbitProgress);
    if (haloAlpha > 0) {
      final haloPaint = Paint()
        ..color = KinrelColors.purple.withValues(alpha: haloAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
      canvas.drawCircle(center, s * 0.9, haloPaint);
    }
  }

  static void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dashWidth,
    required double dashGap,
  }) {
    final segmentAngle = (dashWidth + dashGap) / radius;
    final dashAngle = dashWidth / radius;
    double angle = 0;
    while (angle < 2 * math.pi) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dashAngle,
        false,
        paint,
      );
      angle += segmentAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _KGraphSplashPainter old) =>
      glowProgress != old.glowProgress ||
      centerNodeProgress != old.centerNodeProgress ||
      edgesProgress != old.edgesProgress ||
      orbitProgress != old.orbitProgress;
}

// ═════════════════════════════════════════════════════════════════════
// Internal data classes for the splash painter
// ═════════════════════════════════════════════════════════════════════

class _SplashNode {
  const _SplashNode(this.x, this.y, this.r, this.color, this.label);

  final double x;
  final double y;
  final double r;
  final Color color;
  final String label;
}

class _SplashEdge {
  const _SplashEdge(this.from, this.to, this.tier);

  final int from;
  final int to;
  final int tier;
}
