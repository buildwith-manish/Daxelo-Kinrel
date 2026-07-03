// lib/core/routing/app_router.dart
//
// DAXELO KINREL — App Router (P2 — Instant Navigation)
//
// 5-tab bottom navigation:
//   1. Home      → /home
//   2. Search    → /search
//   3. Graph     → /families
//   4. Alerts    → /notifications
//   5. Me        → /profile
//
// Additional deep-link routes for all features.
// Uses DKBottomNav with semi-transparent background, orange active,
// gold indicator, badge support on Alerts tab.
//
// ── P2 Optimizations ─────────────────────────────────────────────
// • CustomTransitionPage with 200ms FadeTransition + Curves.easeOut
//   for ALL non-shell routes (33% faster than Flutter default 300ms)
// • Instant (0ms) transitions for ShellRoute tab switches
// • Prefetch wrappers for 3 most-visited routes (/families, /family/:id, /profile)
// • AutomaticKeepAliveClientMixin on all tab screens
//
// ── go() vs push() Recommendations ────────────────────────────────
// Use go() when the target replaces the current stack context:
//   • Bottom nav tab switches (already using go())
//   • After sign-in → /home
//   • After sign-out → /sign-in
//   • Deep links that should reset the stack
//
// Use push() when the target is a detail/child of the current screen:
//   • /family/:id from /families (user may go back)
//   • /member/:id from any list
//   • /families/create from /families
//   • /profile/edit from /profile
//   • Any modal-like screen (path-finder, add-person, etc.)
//
// Rule of thumb: If the user expects a back button, use push().
//               If it's a top-level context switch, use go().

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/auth/presentation/two_factor_login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
// KIN-25: ExploreScreen import removed — /explore route deleted.
import '../../features/family/presentation/family_list_screen.dart';
import '../../features/family/presentation/family_detail_screen.dart';
import '../../features/family/presentation/path_finder_screen.dart';
import '../../features/family/presentation/create_family_screen.dart';
import '../../features/family/presentation/join_family_screen.dart';
import '../../features/family/presentation/family_qr_screen.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/relationship_builder_screen.dart';
import '../../features/family/presentation/family_graph_screen.dart';
import '../../features/family/presentation/family_archive_screen.dart';
import '../../features/family/presentation/family_members_screen.dart';
import '../../features/family/presentation/family_activity_screen.dart';
import '../../features/chat/presentation/chat_inbox_screen.dart';
import '../../features/truth_streak/presentation/truth_streak_screen.dart';
import '../../features/hot_seat/presentation/hot_seat_screen.dart';
import '../../features/relation_riddles/presentation/relation_riddle_screen.dart';
import '../../features/family/presentation/person_detail_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';
import '../../features/profile/presentation/quiet_hours_screen.dart';
import '../../features/profile/presentation/sessions_screen.dart';
import '../../features/profile/presentation/delete_account_screen.dart';
import '../../features/profile/presentation/members_added_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/profile/presentation/linked_accounts_screen.dart';
import '../../features/profile/presentation/two_factor_screen.dart';
import '../../features/profile/presentation/help_center_screen.dart';
import '../../features/profile/presentation/contact_support_screen.dart';
import '../../features/profile/presentation/report_bug_screen.dart';
import '../../features/profile/presentation/legal_screen.dart';
import '../../presentation/screens/legal/privacy_policy_screen.dart';
import '../../presentation/screens/legal/terms_of_service_screen.dart';
import '../../features/profile/presentation/my_families_screen.dart';
import '../../features/profile/presentation/invitations_screen.dart';
import '../../features/profile/presentation/blocked_users_screen.dart';
import '../../features/profile/presentation/relations_screen.dart';
import '../../features/social/presentation/screens/sparq_viewer_screen.dart';
import '../../features/social/presentation/screens/sparq_create_screen.dart';
import '../../features/social/presentation/screens/sparq_viewers_screen.dart';
import '../../features/social/presentation/screens/followers_screen.dart';
import '../../features/social/presentation/screens/follow_requests_screen.dart';
import '../../features/social/presentation/screens/family_invite_screen.dart';
import '../../features/social/presentation/screens/join_family_preview_screen.dart';
import '../../features/social/presentation/screens/privacy_settings_screen.dart';
import '../../features/feed/presentation/post_create_screen.dart';
import '../../features/profile/presentation/member_timeline_screen.dart';
import '../../features/ai_chat/presentation/ai_chat_screen.dart';
import '../../features/voice_search/presentation/voice_search_screen.dart';
import '../../features/festival_cards/presentation/festival_cards_screen.dart';
import '../../features/quiz/presentation/quiz_screen.dart';
import '../../features/referral/presentation/referral_screen.dart';
// import '../../features/kinship/presentation/kinship_search_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/kinship/presentation/kinship_detail_screen.dart';
import '../../features/kinship/presentation/global_kinship_screen.dart';
import '../../features/kinship/presentation/cross_cultural_comparison_screen.dart';
import '../../features/kinship/presentation/country_kinship_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/memories/presentation/memories_screen.dart';
import '../../features/family_map/presentation/family_map_screen.dart';
import '../../features/memory_vault/presentation/memory_vault_screen.dart';
import '../../features/memory_vault/presentation/memory_detail_screen.dart';
import '../../features/memory_vault/data/memory_model.dart';
import '../../features/occasions/presentation/occasions_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/share/presentation/share_screen.dart';
import '../../features/oral_history/presentation/oral_history_screen.dart';
import '../../features/gamification/presentation/achievements_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../presentation/screens/invite/invite_screen.dart';
import '../../presentation/screens/family_tree/family_tree_screen.dart';
import '../../presentation/screens/premium/paywall_screen.dart';
import '../../presentation/screens/debug/engagement_dashboard.dart';
import '../config/app_environment.dart';
import '../services/supabase_service.dart';
import '../services/crashlytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/analytics_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../shared/widgets/dk_components.dart';
import '../../core/family/family_provider.dart';
import '../../features/profile/data/profile_provider.dart';

/// Key for accessing the router's navigator state
final _rootNavigatorKey = GlobalKey<NavigatorState>();

// ═══════════════════════════════════════════════════════════════════════
// P2 — CustomTransitionPage Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Fast page transition: 200ms fade with Curves.easeOut.
/// 33% faster than Flutter's default 300ms MaterialPage transition.
CustomTransitionPage<void> _fastFadePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

/// Instant page transition: 0ms — used for ShellRoute tab switches
/// where the shell itself handles the visual transition.
CustomTransitionPage<void> _instantPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════
// P2 — Prefetch Wrappers for Most-Visited Routes
// ═══════════════════════════════════════════════════════════════════════
//
// These wrappers warm up Riverpod providers in initState, so the
// data fetch begins one frame before the screen is built. Combined
// with the 200ms page transition, data often arrives while the
// transition is still playing — perceived as instant.

/// Prefetches family list data for /families route.
class _PrefetchFamilyList extends ConsumerStatefulWidget {
  const _PrefetchFamilyList({required this.child});
  final Widget child;

  @override
  ConsumerState<_PrefetchFamilyList> createState() =>
      _PrefetchFamilyListState();
}

class _PrefetchFamilyListState extends ConsumerState<_PrefetchFamilyList> {
  @override
  void initState() {
    super.initState();
    // Warm up the family list provider — data starts fetching immediately
    Future.microtask(() {
      if (mounted) {
        ref.read(familyListProvider.future).catchError((_) => <Family>[]);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Prefetches family detail data for /family/:id route.
class _PrefetchFamilyDetail extends ConsumerStatefulWidget {
  const _PrefetchFamilyDetail({
    required this.child,
    required this.familyId,
  });
  final Widget child;
  final String familyId;

  @override
  ConsumerState<_PrefetchFamilyDetail> createState() =>
      _PrefetchFamilyDetailState();
}

class _PrefetchFamilyDetailState extends ConsumerState<_PrefetchFamilyDetail> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(familyDetailProvider(widget.familyId).future).catchError((_) => null);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Prefetches profile data for /profile route.
class _PrefetchProfile extends ConsumerStatefulWidget {
  const _PrefetchProfile({required this.child});
  final Widget child;

  @override
  ConsumerState<_PrefetchProfile> createState() => _PrefetchProfileState();
}

class _PrefetchProfileState extends ConsumerState<_PrefetchProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        // CRITICAL: Each async call MUST have .catchError() to prevent
        // uncaught async errors that crash the app (blank screen).
        ref.read(profileProvider.notifier).loadProfile().catchError((_) {});
        ref.read(profileProvider.notifier).loadStats().catchError((_) {});
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Called by sign-in screens after successful authentication.
/// Triggers GoRouter to re-evaluate redirects via refreshListenable.
void markSignInSuccess() {
  _authChangeNotifier.notify();
}

/// ── Auth Change Notifier for GoRouter refreshListenable ──────────────
/// When auth state changes, GoRouter re-evaluates the redirect callback
/// automatically. This eliminates the need for the fragile cooldown
/// mechanism and prevents redirect loops caused by stale auth state.
///
/// v2.2 FIX: Reduced debounce from 500ms to 100ms. The 500ms delay was
/// too slow — after signIn() succeeded, the user saw the Sign In button
/// reappear for half a second before the router redirected to /home,
/// causing them to think login failed and click again.
class _AuthChangeNotifier extends ChangeNotifier {
  Timer? _debounce;

  void notify() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final _authChangeNotifier = _AuthChangeNotifier();

/// ── Redirect loop guard ─────────────────────────────────────────────
/// Tracks visited routes and enforces a cooldown to prevent infinite
/// redirect loops. GoRouter has NO built-in redirect limit — if the
/// redirect callback returns non-null that triggers another redirect,
/// it recurses infinitely on the main thread, causing ANR (5-second
/// watchdog kill).
///
/// Two-layer protection:
/// 1. Visited-set: Tracks ALL routes visited in the current navigation
///    chain. If we revisit a route, we're in a loop — break immediately.
///    This catches N-way cycles (e.g., /home → /2fa-verify → /home)
///    that the previous FROM→TO pair check couldn't detect.
/// 2. Time-based cooldown: Prevents rapid successive redirect evaluations
///    (minimum 500ms between redirects). This protects against cycles
///    across multiple navigation events triggered by refreshListenable,
///    where the visited set would have been cleared between events.
Set<String> _visitedRoutes = {};
DateTime? _lastRedirectTime;
// v2.2 FIX: Reduced from 500ms to 100ms to match the _AuthChangeNotifier
// debounce. The 500ms cooldown was blocking the post-login redirect —
// after signIn() succeeded, the auth notifier fired at 100ms, but the
// cooldown was still active for another 400ms, so the router returned
// null (no redirect) and the user stayed on /sign-in.
const Duration _redirectCooldown = Duration(milliseconds: 100);

/// Handle GoRouter redirect logic safely.
///
/// CRITICAL RULES to avoid ANR and blank screen:
/// 1. NEVER throw — always return null (allow) on any error
/// 2. NEVER redirect when auth state is still loading (isLoading)
/// 3. NEVER create redirect loops (splash → sign-in → home → sign-in)
/// 4. If Supabase isn't ready, DON'T redirect — let screens handle auth
/// 5. Check Supabase session directly as fallback for Riverpod lag
/// 6. REDIRECT LOOP GUARD: Visited-set detects N-way cycles; cooldown prevents cross-event storms
String? _handleRedirect(Ref ref, GoRouterState state) {
  final currentLocation = state.matchedLocation;

  // ── Time-based cooldown ──────────────────────────────────────────
  final now = DateTime.now();
  if (_lastRedirectTime != null &&
      now.difference(_lastRedirectTime!) < _redirectCooldown) {
    debugPrint('⚠️ Redirect cooldown active — breaking potential loop at $currentLocation');
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }

  // ── Visited-set loop detection ───────────────────────────────────
  // If we've already visited this route in the current chain, we're in a loop
  if (_visitedRoutes.contains(currentLocation)) {
    debugPrint('⚠️ Redirect loop detected: $currentLocation already visited in chain. Breaking loop.');
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }
  _visitedRoutes.add(currentLocation);

  // ── Log navigation breadcrumb for crash context ──────────────────
  logNavigationBreadcrumb(currentLocation);

  // Don't redirect away from splash — it handles its own navigation
  if (currentLocation == '/splash') {
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }

  // ── Debug route guard — only accessible in dev flavor ──────────────
  if (currentLocation == '/debug') {
    if (!AppEnvironmentConfig.current.isDev) {
      return '/home';
    }
  }

  final isAuth =
      currentLocation == '/sign-in' ||
      currentLocation == '/sign-up';
  final is2FAVerify = currentLocation == '/2fa-verify';
  final isPublicLegal =
      currentLocation == '/privacy' ||
      currentLocation == '/terms';

  // ── Deep link: save join token for post-login redirect ────────────
  // If an unauthenticated user hits /join/:token, save the token
  // and redirect to sign-in. After login, they'll be redirected to
  // the join preview screen automatically.
  if (currentLocation.startsWith('/join/') && !currentLocation.contains('kinFamilyId')) {
    final token = currentLocation.replaceFirst('/join/', '');
    if (token.isNotEmpty) {
      try {
        final deepLinkService = ref.read(deepLinkServiceProvider);
        deepLinkService.setPendingDeepLink(currentLocation);
      } catch (_) {}
    }
  }

  // ── Determine auth state with multiple fallback checks ────────────
  bool isAuthenticated = false;
  bool supabaseReady = false;
  bool authLoading = false;

  try {
    supabaseReady = ref.read(isSupabaseReadyProvider);
    final authStream = ref.read(authStateProvider);
    authLoading = authStream.isLoading;
    isAuthenticated = ref.read(isAuthenticatedProvider);

    // CRITICAL FALLBACK: If Riverpod says not authenticated but
    // Supabase directly has a session, treat as authenticated.
    // This prevents the #1 redirect loop cause: Riverpod auth
    // stream hasn't emitted yet after signIn(), but Supabase
    // already has the session.
    if (!isAuthenticated && supabaseReady) {
      try {
        final hasDirectSession =
            Supabase.instance.client.auth.currentSession != null;
        if (hasDirectSession) {
          isAuthenticated = true;
          // v2.2 FIX: Also clear authLoading — if Supabase has a
          // direct session, we know the auth state, so the stream
          // loading is irrelevant. This prevents the authLoading
          // guard below from blocking the redirect to /home.
          authLoading = false;
          debugPrint('🔄 Redirect: Using direct Supabase session (Riverpod lag)');
        }
      } catch (_) {}
    }
  } catch (_) {
    // Providers may throw if not initialized — treat as not ready
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }

  // CRITICAL: If auth is still loading, DON'T redirect.
  // Returning null allows the current navigation to proceed.
  if (authLoading) {
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }

  // ── 2FA State Check ────────────────────────────────────────────────
  // If the user is authenticated but has pending 2FA verification,
  // they must complete it before accessing any protected route.
  // The only allowed destinations are /2fa-verify and public legal pages.
  bool pending2FA = false;
  try {
    pending2FA = ref.read(pending2FAProvider);
  } catch (_) {}

  // ── Compute redirect target ────────────────────────────────────────
  String? redirectTarget;

  if (isAuthenticated && isAuth) {
    // Authenticated user on sign-in/sign-up → redirect to home
    // (but NOT if they have pending 2FA → they should go to /2fa-verify)
    if (pending2FA) {
      redirectTarget = '/2fa-verify';
    } else {
      redirectTarget = '/home';
    }
  } else if (isAuthenticated && is2FAVerify) {
    // CRITICAL: Authenticated user on /2fa-verify
    // - If pending 2FA → STAY on /2fa-verify (don't redirect away!)
    // - If 2FA verified or not needed → redirect to /home
    if (!pending2FA) {
      redirectTarget = '/home';
    }
    // If pending2FA is true, redirectTarget stays null → allow /2fa-verify
  } else if (isAuthenticated && !isAuth && !is2FAVerify && !isPublicLegal && pending2FA) {
    // Authenticated user trying to access a protected route without
    // completing 2FA → redirect to /2fa-verify
    redirectTarget = '/2fa-verify';
  } else if (!isAuthenticated && (is2FAVerify || (!isAuth && !isPublicLegal))) {
    // Unauthenticated user on /2fa-verify or any protected route
    // → redirect to sign-in
    // Only redirect to sign-in if Supabase is fully initialized
    if (!supabaseReady) {
      _visitedRoutes.clear();
      _lastRedirectTime = null;
      return null;
    }
    redirectTarget = '/sign-in';
  }

  if (redirectTarget == null) {
    // No redirect needed — valid destination, reset guards
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }

  // ── Record redirect time for cooldown enforcement ────────────────
  _lastRedirectTime = DateTime.now();
  return redirectTarget;
}

/// Router provider — uses a single GoRouter instance with
/// refreshListenable for auth state changes. When auth state changes,
/// GoRouter re-evaluates the redirect callback automatically, eliminating
/// the need for fragile cooldown timers and preventing redirect loops.
final routerProvider = Provider<GoRouter>((ref) {
  // Listen to auth state changes and notify GoRouter to re-evaluate
  // redirects. This is the proper way to handle auth-based navigation
  // instead of the fragile cooldown mechanism that caused ANR.
  final authNotifier = _authChangeNotifier;
  ref.listen<AsyncValue<AuthState>>(authStateProvider, (prev, next) {
    authNotifier.notify();

    // Clear 2FA state on sign-out: if the new auth state has no session,
    // reset both providers so the router doesn't get stuck in a
    // pending-2FA state for a user who isn't even logged in.
    final hasSession = next.value?.session != null;
    if (!hasSession) {
      try {
        ref.read(pending2FAProvider.notifier).state = false;
        ref.read(twoFactorVerifiedProvider.notifier).state = false;
      } catch (_) {}
    }
  });
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    refreshListenable: authNotifier,
    observers: [
      // P5-F1: Track every route change for analytics
      AnalyticsNavigatorObserver(),
    ],
    redirect: (context, state) {
      // ── SAFETY: Never throw in redirect — always return a route or null ──
      try {
        return _handleRedirect(ref, state);
      } catch (e) {
        // If ANYTHING goes wrong in redirect logic, allow navigation.
        // A potentially wrong screen is better than a blank screen from
        // an unhandled redirect exception.
        debugPrint('⚠️ Router redirect error, allowing navigation: $e');
        _visitedRoutes.clear();
        _lastRedirectTime = null;
        return null;
      }
    },
    routes: [
      // ── Auth / Onboarding (fast 200ms fade) ────────────────────────
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: SplashScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: OnboardingScreen()),
      ),
      GoRoute(
        path: '/sign-in',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: SignInScreen()),
      ),
      GoRoute(
        path: '/sign-up',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: SignUpScreen()),
      ),
      GoRoute(
        path: '/2fa-verify',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: TwoFactorLoginScreen()),
      ),

      // ── Shell routes (show bottom navigation) ─────────────────────
      // Tab switches use 0ms instant transitions — the shell handles
      // the visual feedback, so no page animation is needed.
      ShellRoute(
        builder: (context, state, child) => RoutePersistenceShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                _instantPage(key: state.pageKey, child: HomeScreen()),
          ),
          // Chat as a standalone top-level tab (unified inbox)
          GoRoute(
            path: '/chat',
            pageBuilder: (context, state) =>
                _instantPage(key: state.pageKey, child: const ChatInboxScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                _instantPage(key: state.pageKey, child: SearchScreen()),
          ),
          GoRoute(
            path: '/families',
            pageBuilder: (context, state) => _instantPage(
              key: state.pageKey,
              child: _PrefetchFamilyList(child: FamilyListScreen()),
            ),
          ),
          // KIN-20: /notifications removed from ShellRoute — it's now
          // a pushed route (bell icon on Home header), not a tab.
          // KIN-25: /explore deleted — confirmed orphan with zero nav
          // entry points from any tab, Home card, or Profile menu.
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _instantPage(
              key: state.pageKey,
              child: _PrefetchProfile(child: ProfileScreen()),
            ),
          ),
        ],
      ),

      // ── Notifications (pushed via bell icon, no bottom nav) ──────
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const NotificationsScreen(),
        ),
      ),

      // ── Family Routes (200ms fast fade + prefetch) ────────────────
      GoRoute(
        path: '/families/create',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: CreateFamilyScreen()),
      ),
      GoRoute(
        path: '/join-family',
        builder: (context, state) => JoinFamilyScreen(
          kinFamilyId: state.uri.queryParameters['kinFamilyId'],
        ),
      ),
      GoRoute(
        path: '/family-qr',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyQRScreen(
            familyId: state.uri.queryParameters['familyId'] ?? '',
            familyName: state.uri.queryParameters['familyName'],
            kinFamilyId: state.uri.queryParameters['kinFamilyId'],
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id',
        pageBuilder: (context, state) {
          final familyId = state.pathParameters['id']!;
          return _fastFadePage(
            key: state.pageKey,
            child: _PrefetchFamilyDetail(
              familyId: familyId,
              child: FamilyDetailScreen(familyId: familyId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/family-tree',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyTreeScreen(
            familyId: state.uri.queryParameters['familyId'],
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/path-finder',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: PathFinderScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/add-person',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: _AddPersonScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/add-member',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: _AddPersonScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/link',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: RelationshipBuilderScreen(
            familyId: state.pathParameters['id']!,
            familyName: state.uri.queryParameters['name'] ?? 'Family',
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/graph',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyGraphScreen(
            familyId: state.pathParameters['id']!,
            familyName: state.uri.queryParameters['name'],
          ),
        ),
      ),

      // ── Family Archive (Phase 3: unified Photos/Timeline/Audio) ──
      GoRoute(
        path: '/family/:id/archive',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyArchiveScreen(
            familyId: state.pathParameters['id'],
          ),
        ),
      ),

      // ── Family Members (extracted from FamilyDetailScreen) ──────
      GoRoute(
        path: '/family/:id/members',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyMembersScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Family Activity (extracted from FamilyDetailScreen) ─────
      GoRoute(
        path: '/family/:id/activity',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyActivityScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Truth Streak (daily family question game) ───────────────
      GoRoute(
        path: '/family/:id/truth-streak',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TruthStreakScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Hot Seat (daily spotlight game) ──────────────────────────
      GoRoute(
        path: '/family/:id/hot-seat',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: HotSeatScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Relation Riddles (daily kinship quiz) ────────────────────
      GoRoute(
        path: '/family/:id/relation-riddles',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: RelationRiddleScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Person Detail Screen ────────────────────────────────────
      GoRoute(
        path: '/member/:id',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: PersonDetailScreen(memberId: state.pathParameters['id']!),
        ),
      ),

      // ── Post Creation Screen ──────────────────────────────────
      GoRoute(
        path: '/post/create',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const PostCreateScreen()),
      ),

      // ── Member Timeline Screen ───────────────────────────────
      GoRoute(
        path: '/member/:id/timeline',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: MemberTimelineScreen(
            memberId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Family Chat ─────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/chat',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChatScreen(
            familyId: state.pathParameters['id']!,
            familyName: state.uri.queryParameters['name'] ?? 'Family',
          ),
        ),
      ),

      // ── Events & Celebrations ──────────────────────────────────
      GoRoute(
        path: '/events',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const EventsScreen()),
      ),

      // ── Oral History ────────────────────────────────────────────
      GoRoute(
        path: '/oral-history',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const OralHistoryScreen()),
      ),

      // ── Memories & Timeline ─────────────────────────────────────
      GoRoute(
        path: '/memories',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const MemoriesScreen()),
      ),

      // ── AI-Powered Features ─────────────────────────────────────
      GoRoute(
        path: '/ai-chat',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: AiChatScreen()),
      ),
      GoRoute(
        path: '/voice-search',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: VoiceSearchScreen()),
      ),
      GoRoute(
        path: '/festival-cards',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: FestivalCardsScreen()),
      ),

      // ── Kinship Dictionary ──────────────────────────────────────
      GoRoute(
        path: '/kinship/global',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const GlobalKinshipScreen()),
      ),
      GoRoute(
        path: '/kinship/compare',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const CrossCulturalComparisonScreen(),
        ),
      ),
      GoRoute(
        path: '/kinship/country/:code',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: CountryKinshipDetailScreen(
            countryCode: state.pathParameters['code']!,
          ),
        ),
      ),
      GoRoute(
        path: '/kinship/:key',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: KinshipDetailScreen(
            relationshipKey: state.pathParameters['key']!,
          ),
        ),
      ),

      // ── Growth & Engagement ─────────────────────────────────────
      GoRoute(
        path: '/quiz',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: QuizScreen()),
      ),
      GoRoute(
        path: '/referral',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: ReferralScreen()),
      ),

      // ── P5: Invite Screen ──────────────────────────────────────────
      GoRoute(
        path: '/invite',
        pageBuilder: (context, state) {
          final familyId = state.uri.queryParameters['familyId'] ?? '';
          final familyName = state.uri.queryParameters['familyName'] ?? 'Family';
          return _fastFadePage(
            key: state.pageKey,
            child: InviteScreen(
              familyId: familyId,
              familyName: familyName,
            ),
          );
        },
      ),

      // ── P5: Premium Paywall ────────────────────────────────────────
      GoRoute(
        path: '/premium',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const PaywallScreen()),
      ),

      // ── P5: Debug Engagement Dashboard ─────────────────────────────
      // Only accessible in dev flavor — redirect guard is above.
      GoRoute(
        path: '/debug',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const EngagementDashboard()),
      ),

      // ── Share & Invite ──────────────────────────────────────────
      GoRoute(
        path: '/family/:id/share',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ShareScreen(
            familyId: state.pathParameters['id']!,
            familyName: state.uri.queryParameters['name'] ?? 'Family',
          ),
        ),
      ),

      // ── P3-F2: Deep Link — Share route (/share/:id) ──────────────
      // Maps https://kinrel.app/share/:id to the ShareScreen.
      // Preloads family name from Isar cache for instant display.
      GoRoute(
        path: '/share/:id',
        pageBuilder: (context, state) {
          final familyId = state.pathParameters['id']!;
          return _fastFadePage(
            key: state.pageKey,
            child: _DeepLinkShareScreen(familyId: familyId),
          );
        },
      ),

      // ── P3-F2: Deep Link — Invite route (/invite/:code) ──────────
      // Maps https://kinrel.app/invite/:code to the InvitationsScreen.
      // Users opening an invite link land here to accept the invitation.
      GoRoute(
        path: '/invite/:code',
        pageBuilder: (context, state) {
          final inviteCode = state.pathParameters['code']!;
          return _fastFadePage(
            key: state.pageKey,
            child: InvitationsScreen(inviteCode: inviteCode),
          );
        },
      ),

      // ── Gamification & Achievements ─────────────────────────────
      GoRoute(
        path: '/achievements',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const AchievementsScreen()),
      ),

      // ── Document Vault ───────────────────────────────────────────
      GoRoute(
        path: '/documents',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const DocumentsScreen()),
      ),

      // ── Profile Feature Screens ──────────────────────────────────
      GoRoute(
        path: '/profile/change-password',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const ChangePasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/profile/linked-accounts',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const LinkedAccountsScreen(),
        ),
      ),
      GoRoute(
        path: '/profile/2fa-setup',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const TwoFactorScreen()),
      ),
      GoRoute(
        path: '/profile/quiet-hours',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const QuietHoursScreen()),
      ),
      GoRoute(
        path: '/profile/sessions',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const SessionsScreen()),
      ),
      GoRoute(
        path: '/profile/delete-account',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const DeleteAccountScreen()),
      ),
      GoRoute(
        path: '/profile/members-added',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const MembersAddedScreen()),
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ProfileEditScreen(
            focusField: state.uri.queryParameters['focus'],
          ),
        ),
      ),
      GoRoute(
        path: '/profile/help',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const HelpCenterScreen()),
      ),
      GoRoute(
        path: '/profile/contact-support',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const ContactSupportScreen(),
        ),
      ),
      GoRoute(
        path: '/profile/report-bug',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const ReportBugScreen()),
      ),
      // ── P4-F4: Public Legal Screens (NO auth required) ──────────
      // These routes are accessible without login for Play Store compliance.
      GoRoute(
        path: '/privacy',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const PrivacyPolicyScreen()),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const TermsOfServiceScreen()),
      ),

      GoRoute(
        path: '/legal/terms',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const LegalScreen(type: 'terms')),
      ),
      GoRoute(
        path: '/legal/privacy',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const LegalScreen(type: 'privacy'),
        ),
      ),
      GoRoute(
        path: '/profile/my-families',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const MyFamiliesScreen()),
      ),
      GoRoute(
        path: '/profile/invitations',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const InvitationsScreen()),
      ),
      GoRoute(
        path: '/profile/blocked',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const BlockedUsersScreen()),
      ),
      GoRoute(
        path: '/profile/relations',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const RelationsScreen()),
      ),

      // ── P5: Premium Paywall (alternative path) ────────────────────
      GoRoute(
        path: '/profile/premium',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const PaywallScreen()),
      ),

      // ── Social System Routes ─────────────────────────────────────────

      // ── Phase B: Family Map ────────────────────────────────────────
      GoRoute(
        path: '/family-map',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const FamilyMapScreen()),
      ),

      // ── Phase B: Memory Vault ──────────────────────────────────────
      GoRoute(
        path: '/memory-vault',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const MemoryVaultScreen()),
      ),
      GoRoute(
        path: '/memory-vault/detail/:memoryId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: MemoryDetailScreen(
            memory: MemoryModel.placeholder(state.pathParameters['memoryId']!),
          ),
        ),
      ),

      // ── Phase B: Occasion Reminders ───────────────────────────────
      GoRoute(
        path: '/occasions',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const OccasionsScreen()),
      ),

      // ── Social System Routes ─────────────────────────────────────────
      GoRoute(
        path: '/sparq/viewer/:userId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: SparqViewerScreen(userId: state.pathParameters['userId']!),
        ),
      ),
      GoRoute(
        path: '/sparq/create',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const SparqCreateScreen()),
      ),
      GoRoute(
        path: '/sparq/:sparqId/viewers',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: SparqViewersScreen(sparqId: state.pathParameters['sparqId']!),
        ),
      ),
      GoRoute(
        path: '/followers',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FollowersScreen(initialTab: state.uri.queryParameters['tab'] == 'following' ? 1 : 0),
        ),
      ),
      GoRoute(
        path: '/follow-requests',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const FollowRequestsScreen()),
      ),
      GoRoute(
        path: '/family/:id/invite',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyInviteScreen(
            familyId: state.pathParameters['id']!,
            familyName: state.uri.queryParameters['name'] ?? 'Family',
          ),
        ),
      ),
      GoRoute(
        path: '/join/:token',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: JoinFamilyPreviewScreen(token: state.pathParameters['token']!),
        ),
      ),
      GoRoute(
        path: '/privacy-settings',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const PrivacySettingsScreen()),
      ),
    ],
  );
});

/// Full-screen wrapper for AddPersonSheet
class _AddPersonScreen extends ConsumerWidget {
  const _AddPersonScreen({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Family Member',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: _AddPersonForm(familyId: familyId),
        ),
      ),
    );
  }
}

/// Inline form for add person (full screen version)
class _AddPersonForm extends ConsumerStatefulWidget {
  const _AddPersonForm({required this.familyId});

  final String familyId;

  @override
  ConsumerState<_AddPersonForm> createState() => _AddPersonFormState();
}

class _AddPersonFormState extends ConsumerState<_AddPersonForm> {
  @override
  void initState() {
    super.initState();
    // Show the bottom sheet on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AddPersonSheet.show(context, familyId: widget.familyId).then((_) {
        if (mounted) context.pop();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

/// Shell that persists route for app resume
class RoutePersistenceShell extends StatefulWidget {
  RoutePersistenceShell({super.key, required this.child});

  final Widget child;

  @override
  State<RoutePersistenceShell> createState() => _RoutePersistenceShellState();
}

class _RoutePersistenceShellState extends State<RoutePersistenceShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save current route when app goes to background
    if (state == AppLifecycleState.paused) {
      _saveCurrentRoute();
    }
  }

  void _saveCurrentRoute() {
    try {
      final location = GoRouterState.of(context).matchedLocation;
      saveLastRoute(location);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MainShell(child: widget.child);
  }
}

/// Main shell with 5-tab bottom navigation + global notification bell.
/// The bell is visible on ALL main screens (top-right corner) with a
/// red unread-count badge.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  DateTime? _lastBackPressTime;

  Future<bool> _onWillPop() async {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Watch the unread notification count for the bell badge
    final unreadCount = ref.watch(unreadCountProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: StreamBuilder<List<ConnectivityResult>>(
          stream: Connectivity().onConnectivityChanged,
          builder: (context, snap) {
            final offline = snap.data?.contains(ConnectivityResult.none) ?? false;
            return Column(
              children: [
                if (offline)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: const Text('No internet connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      // The actual screen content
                      widget.child,
                      // Floating notification bell (top-right, all screens)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        right: 8,
                        child: _NotificationBell(
                          unreadCount: unreadCount,
                          onTap: () => context.push('/notifications'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: const _BottomNav(),
      ),
    );
  }
}

/// Floating notification bell with red unread badge.
/// Visible on all main screens via the MainShell Stack overlay.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF191B2C).withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Bell icon
              Center(
                child: Icon(
                  unreadCount > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_outlined,
                  color: const Color(0xFFC9B4A8),
                  size: 22,
                ),
              ),
              // Red unread badge
              if (unreadCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4444),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF191B2C),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 5-tab bottom navigation:
/// 0. Home      (home icon)
/// 1. Chat      (chat bubble icon) — unified inbox across all families
/// 2. Family    (family_restroom icon)
/// 3. Search    (search icon)
/// 4. Me        (person icon)
///
/// Notification bell with red unread badge is in the ShellRoute header,
/// visible on ALL main screens (not just Home).
class _BottomNav extends StatelessWidget {
  const _BottomNav();

  static const _items = [
    DKNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    DKNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_rounded,
      label: 'Chat',
    ),
    DKNavItem(
      icon: Icons.family_restroom_outlined,
      activeIcon: Icons.family_restroom_rounded,
      label: 'Family',
    ),
    DKNavItem(
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
      label: 'Search',
    ),
    DKNavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Me',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return DKBottomNav(
      currentIndex: _currentIndex(location),
      onTap: (index) => _onTap(context, index),
      items: _items,
    );
  }

  /// Map current route to bottom nav index.
  int _currentIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/chat')) return 1;
    if (location.startsWith('/families') ||
        location.startsWith('/family/')) return 2;
    if (location.startsWith('/search')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  /// Navigate to the route for the given tab index.
  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/chat');
      case 2:
        context.go('/families');
      case 3:
        context.go('/search');
      case 4:
        context.go('/profile');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// P3-F2: Deep Link Navigation Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Navigates to the correct GoRouter location for a deep link.
///
/// This function is called by [DeepLinkService] when a deep link is received.
/// It uses `go()` for top-level routes (replaces stack) and `push()` for
/// detail screens (user can go back).
///
/// Must be called with a valid [GoRouter] instance and a location string
/// produced by [DeepLinkRoute.toLocation].
void navigateToDeepLink(GoRouter router, String location) {
  logNavigationBreadcrumb('deep_link_navigate:$location');

  // For deep links, use go() to reset the navigation stack.
  // This is the recommended pattern for deep links per the routing guide:
  // "Deep links that should reset the stack" → use go()
  router.go(location);
}

// ═══════════════════════════════════════════════════════════════════════
// P3-F2: Deep Link Share Screen with Isar Cache Preloading
// ═══════════════════════════════════════════════════════════════════════

/// Wrapper screen for the `/share/:id` deep link route.
///
/// When a user opens a deep link like `https://kinrel.app/share/abc123`,
/// this screen preloads the family name from Isar cache (instant display)
/// while the API fetches the full data in the background.
///
/// Once the family name is available (from cache or API), it renders
/// the actual [ShareScreen] with the correct parameters.
class _DeepLinkShareScreen extends ConsumerWidget {
  const _DeepLinkShareScreen({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Try to get family name from cache instantly
    final cachedName = ref.watch(deepLinkFamilyNameProvider(familyId));

    return cachedName.when(
      data: (name) => ShareScreen(
        familyId: familyId,
        familyName: name ?? 'Family',
      ),
      loading: () => ShareScreen(
        familyId: familyId,
        familyName: 'Family',
      ),
      error: (_, __) => ShareScreen(
        familyId: familyId,
        familyName: 'Family',
      ),
    );
  }
}
