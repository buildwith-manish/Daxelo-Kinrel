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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/auth/presentation/create_username_screen.dart';
import '../../features/auth/presentation/two_factor_login_screen.dart';
// B1 gate verification screen (debug-only).
import '../../features/cameo/presentation/b1_verification_screen.dart';
import '../../features/home/presentation/home_screen.dart';
// KIN-25: ExploreScreen import removed — /explore route deleted.
import '../../features/family/presentation/family_list_screen.dart';
import '../../features/family/presentation/family_detail_screen.dart';
// v5.119 step 10: family_hub_screen.dart removed — content migrated to
// family_detail_screen.dart. The /family/:id/hub route is deleted.
import '../../features/family/presentation/family_groups_screen.dart';
import '../../features/family/presentation/create_group_screen.dart';
import '../../features/family/presentation/group_hub_screen.dart';
import '../../features/family/presentation/path_finder_screen.dart';
import '../../features/family/presentation/create_family_screen.dart';
import '../../features/family/presentation/join_family_screen.dart';
import '../../features/family/presentation/family_qr_screen.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/relationship_builder_screen.dart';
import '../../features/family/presentation/family_graph_screen.dart';
import '../../features/family/presentation/family_members_screen.dart';
import '../../features/family/presentation/family_profile_screen.dart';
import '../../features/family/presentation/family_activity_screen.dart';
import '../../features/family/presentation/family_chat_list_screen.dart';
import '../../features/shared_list/presentation/shared_list_screen.dart';
import '../../features/chat/presentation/chat_inbox_screen.dart';
import '../../features/chat/presentation/archived_chats_screen.dart';
import '../../features/chat/presentation/wallpaper_settings_screen.dart';
import '../../features/truth_streak/presentation/truth_streak_screen.dart';
import '../../features/hot_seat/presentation/hot_seat_screen.dart';
import '../../features/relation_riddles/presentation/relation_riddle_screen.dart';
import '../../features/calendar/presentation/family_calendar_screen.dart'
    as cal;
import '../../features/calendar/presentation/event_create_screen.dart';
import '../../features/calendar/presentation/event_detail_screen.dart';
import '../../features/calendar/models/calendar_models.dart';
import '../../features/games/presentation/games_hub_screen.dart';
import '../../features/games/ghost_painter/ghost_painter_draw_screen.dart';
import '../../features/games/ghost_painter/ghost_painter_guess_screen.dart';
import '../../features/games/redlight/redlight_lobby_screen.dart';
import '../../features/games/redlight/redlight_game_screen.dart';
import '../../features/games/redlight/redlight_results_screen.dart';
import '../../features/games/sos/sos_lobby_screen.dart';
import '../../features/games/sos/sos_board_screen.dart';
import '../../features/games/sos/sos_results_screen.dart';
import '../../features/games/antakshari/antakshari_lobby_screen.dart';
import '../../features/games/antakshari/antakshari_game_screen.dart';
import '../../features/games/bingo/bingo_lobby_screen.dart';
import '../../features/games/bingo/bingo_board_screen.dart';
import '../../features/games/checkers/checkers_lobby_screen.dart';
import '../../features/games/checkers/checkers_board_screen.dart';
import '../../features/games/ludo/ludo_lobby_screen.dart';
import '../../features/games/ludo/ludo_board_screen.dart';
import '../../features/games/carrom/carrom_lobby_screen.dart';
import '../../features/games/carrom/carrom_board_screen.dart';
import '../../features/games/chess/chess_lobby_screen.dart';
import '../../features/games/chess/chess_board_screen.dart';
import '../../features/games/chitmatch/chitmatch_lobby_screen.dart';
import '../../features/games/chitmatch/chitmatch_game_screen.dart';
import '../../features/games/nameplace/nameplace_lobby_screen.dart';
import '../../features/games/nameplace/nameplace_letter_pick_screen.dart';
import '../../features/games/nameplace/nameplace_answer_screen.dart';
import '../../features/games/nameplace/nameplace_results_screen.dart';
import '../../features/games/tictactoe/tictactoe_lobby_screen.dart';
import '../../features/games/tictactoe/tictactoe_board_screen.dart';
import '../../features/games/truthordare/truthordare_lobby_screen.dart';
import '../../features/games/truthordare/truthordare_table_screen.dart';
import '../../features/games/truthordare/truthordare_submit_screen.dart';
import '../../features/games/truthordare/truthordare_review_screen.dart';
import '../../features/games/twotruths/twotruths_lobby_screen.dart';
import '../../features/games/twotruths/twotruths_submit_screen.dart';
import '../../features/games/twotruths/twotruths_guess_screen.dart';
import '../../features/games/twotruths/twotruths_results_screen.dart';
import '../../features/games/dotsboxes/dotsboxes_lobby_screen.dart';
import '../../features/games/dotsboxes/dotsboxes_board_screen.dart';
import '../../features/family/presentation/person_detail_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';
import '../../features/profile/presentation/account_information_screen.dart';
import '../../features/family/presentation/family_management_screen.dart';
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
import '../../presentation/screens/legal/privacy_policy_screen.dart';
import '../../presentation/screens/legal/terms_of_service_screen.dart';
import '../../features/profile/presentation/my_families_screen.dart';
import '../../features/profile/presentation/invitations_screen.dart';
import '../../features/family/presentation/person_claim_screen.dart';
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
import '../../features/festival_cards/presentation/festival_cards_screen.dart';
import '../../features/quiz/presentation/quiz_screen.dart';
import '../../features/referral/presentation/referral_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/kinship/presentation/kinship_detail_screen.dart';
import '../../features/kinship/presentation/global_kinship_screen.dart';
import '../../features/kinship/presentation/cross_cultural_comparison_screen.dart';
import '../../features/kinship/presentation/country_kinship_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/memories/presentation/memories_screen.dart';
import '../../features/family_map/presentation/family_map_screen.dart';
import '../../features/memory_vault/presentation/memory_vault_screen.dart';
import '../../features/memory_vault/presentation/memory_detail_screen.dart';
import '../../features/memory_vault/data/memory_model.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/chat_search_screen.dart';
import '../../features/chat/presentation/direct_chat_screen.dart';
import '../../features/share/presentation/share_screen.dart';
import '../../features/oral_history/presentation/oral_history_screen.dart';
import '../../features/gamification/presentation/achievements_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/pulse/presentation/daily_brief_screen.dart';
import '../../features/pulse/presentation/pulse_hub_screen.dart';
import '../../features/pulse/presentation/family_quests_screen.dart';
import '../../features/pulse/presentation/blessing_chain_screen.dart';
import '../../features/pulse/presentation/time_capsule_screen.dart';
import '../../features/pulse/presentation/festival_screen.dart';
import '../../features/pulse/presentation/silent_alarms_screen.dart';
import '../../features/pulse/presentation/family_chronicle_screen.dart';
import '../../features/pulse/presentation/memorials_screen.dart';
import '../../features/pulse/presentation/celebrations_screen.dart';
import '../../features/pulse/presentation/family_legacy_screen.dart';
import '../../features/kinrel_intelligence/presentation/kinrel_screen.dart';
import '../../core/constants/feature_flags.dart';
// v5.125 (Family Space §5): FamilyTreeScreen deleted — its route now
// redirects to /family/:id/graph?tab=tree (see /family-tree route below).
// import '../../presentation/screens/family_tree/family_tree_screen.dart';
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
import '../../features/trackc/presentation/screens/trackc_hub_screen.dart';
import '../../features/trackc/presentation/screens/constitution_screen.dart';
import '../../features/trackc/presentation/screens/decisions_list_screen.dart';
import '../../features/trackc/presentation/screens/decision_detail_screen.dart';
import '../../features/trackc/presentation/screens/decision_create_screen.dart';
import '../../features/trackc/presentation/screens/timeline_screen.dart';
import '../../features/trackc/presentation/providers/trackc_providers.dart';

// P12.6 — Batch 2: Wire 4 previously-unreachable Category A screens.
// Audit: docs/audit/batch1-reachability-audit.md
import '../../features/story_mode/presentation/story_mode_screen.dart';
import '../../features/community/presentation/community_discovery_screen.dart';
import '../../features/profile/presentation/pulse_learning_profile_screen.dart';
import '../../features/health_heritage/presentation/health_heritage_screen.dart';
// P12.6 — Batch 3: GEDCOM export + trust/privacy screens
import '../../features/gedcom/presentation/gedcom_export_screen.dart';
import '../../features/gedcom/presentation/your_data_screen.dart';

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
  const _PrefetchFamilyDetail({required this.child, required this.familyId});
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
        ref
            .read(familyDetailProvider(widget.familyId).future)
            .catchError((_) => null);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Sets the `selectedFamilyIdProvider` for Track C sub-routes.
///
/// `TrackcHubScreen` does this in its `initState`, but when deep-linking
/// directly into a sub-route (e.g. `/family/<id>/governance/decisions/<x>`),
/// the hub's `initState` doesn't run. This wrapper ensures every Track C
/// sub-screen enters with the correct family context for its Riverpod
/// providers (`constitutionProvider`, `decisionsProvider`, etc.) regardless
/// of entry point.
class _TrackcFamilyScope extends ConsumerStatefulWidget {
  const _TrackcFamilyScope({required this.familyId, required this.child});

  final String familyId;
  final Widget child;

  @override
  ConsumerState<_TrackcFamilyScope> createState() => _TrackcFamilyScopeState();
}

class _TrackcFamilyScopeState extends ConsumerState<_TrackcFamilyScope> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedFamilyIdProvider.notifier).state = widget.familyId;
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
    debugPrint(
      '⚠️ Redirect cooldown active — breaking potential loop at $currentLocation',
    );
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }

  // ── Visited-set loop detection ───────────────────────────────────
  // If we've already visited this route in the current chain, we're in a loop
  if (_visitedRoutes.contains(currentLocation)) {
    debugPrint(
      '⚠️ Redirect loop detected: $currentLocation already visited in chain. Breaking loop.',
    );
    _visitedRoutes.clear();
    _lastRedirectTime = null;
    return null;
  }
  _visitedRoutes.add(currentLocation);

  // ── Log navigation breadcrumb for crash context ──────────────────
  logNavigationBreadcrumb(currentLocation);

  // ── Persist the current route on every navigation ───────────────────
  // This is the PRIMARY save mechanism on Flutter Web — a browser refresh
  // does NOT reliably fire AppLifecycleState.paused with enough time to
  // flush a SharedPreferences write, and GoRouter's declarative page
  // reconciliation does NOT reliably trigger NavigatorObserver.didPush /
  // didReplace / didPop / didRemove (which is why the LastRoutePersistence
  // Observer alone was insufficient — see commit history).
  //
  // The redirect callback, by contrast, fires on EVERY navigation,
  // declarative or imperative, so it is the correct hook point.
  //
  // Skip the splash route itself (we never want to restore /splash) and
  // any in-flight sign-in flow routes (restoring those mid-flow would
  // bypass auth on the next cold start). saveLastRoute swallows errors
  // internally and we fire-and-forget so navigation is never blocked.
  if (currentLocation != '/splash' &&
      currentLocation != '/sign-in' &&
      currentLocation != '/sign-up' &&
      currentLocation != '/create-username' &&
      currentLocation != '/2fa-verify' &&
      currentLocation != '/onboarding' &&
      !currentLocation.startsWith('/join/')) {
    unawaited(saveLastRoute(currentLocation));
  }

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

  final isAuth = currentLocation == '/sign-in' || currentLocation == '/sign-up';
  final isCreateUsername = currentLocation == '/create-username';
  final is2FAVerify = currentLocation == '/2fa-verify';
  final isPublicLegal =
      currentLocation == '/privacy' || currentLocation == '/terms';

  // ── Deep link: save join token for post-login redirect ────────────
  // If an unauthenticated user hits /join/:token, save the token
  // and redirect to sign-in. After login, they'll be redirected to
  // the join preview screen automatically.
  if (currentLocation.startsWith('/join/') &&
      !currentLocation.contains('kinFamilyId')) {
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
          debugPrint(
            '🔄 Redirect: Using direct Supabase session (Riverpod lag)',
          );
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

  // ── 2FA GATE: If 2FA is pending, the user MUST go to /2fa-verify ──
  // This check runs BEFORE any other redirect logic so it can't be
  // bypassed by any other condition.
  if (isAuthenticated && pending2FA && !is2FAVerify) {
    redirectTarget = '/2fa-verify';
  } else if (isAuthenticated && isAuth) {
    // Authenticated user on sign-in/sign-up → redirect to home
    // (but NOT if they have pending 2FA → already handled above)
    if (pending2FA) {
      redirectTarget = '/2fa-verify';
    } else {
      redirectTarget = '/home';
    }
  } else if (isAuthenticated && isCreateUsername) {
    // Authenticated user on /create-username — let them stay (don't
    // redirect to /home). This screen is shown after sign-up to collect
    // the mandatory username before entering the app.
    redirectTarget = null;
  } else if (isAuthenticated && is2FAVerify) {
    // CRITICAL: Authenticated user on /2fa-verify
    // - If pending 2FA → STAY on /2fa-verify (don't redirect away!)
    // - If 2FA verified or not needed → redirect to /home
    if (!pending2FA) {
      redirectTarget = '/home';
    }
    // If pending2FA is true, redirectTarget stays null → allow /2fa-verify
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
      // ── Route persistence (SECONDARY mechanism) ────────────────────────
      // Persists the current route on imperative Navigator events. The
      // PRIMARY save mechanism is in _handleRedirect, which fires on
      // every navigation including GoRouter's declarative page
      // reconciliations that this observer does not see. Kept here as
      // defense-in-depth for the rarer cases noted in the class docstring.
      LastRoutePersistenceObserver(),
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
      // ── ROOT (v5.133): '/' has no page of its own. Before this route
      // existed, a fresh visit to the site root produced GoRouter's
      // default error page ("GoException: no routes for location: /")
      // whose "Go to home page" button navigated back to '/' — a dead
      // end. Redirect the root to /splash, which already owns all
      // first-run logic (session restore, deep-route verification,
      // sign-in vs home routing).
      GoRoute(
        path: '/',
        redirect: (context, state) => '/splash',
      ),
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

      // ── Create Username (post-signup, mandatory) ──────────────────
      // Shown immediately after successful sign-up. User must choose a
      // unique username before they can access the app.
      GoRoute(
        path: '/create-username',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const CreateUsernameScreen(),
        ),
      ),
      GoRoute(
        path: '/2fa-verify',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: TwoFactorLoginScreen()),
      ),

      // ── B1 Gate Verification / Cameo Viewer ──
      // Always registered (not just debug) because the Profile screen's
      // "My Cameo" card navigates here in release builds too.
      GoRoute(
        path: '/b1-verify',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const B1VerificationScreen()),
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
            pageBuilder: (context, state) => _instantPage(
              key: state.pageKey,
              child: const ChatInboxScreen(),
            ),
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
      // ── Track C v2.0 — Kinrel Governance Engine ──────────────────────────
      // The governance hub is the parent shell. Nested sub-routes enable deep
      // linking (e.g. notifications or external links can point directly to
      // /family/<id>/governance/decisions/<decisionId>) and let the system
      // back button manage the navigation stack properly via GoRouter.
      //
      // The `:id` path param is inherited by all child routes — GoRouter
      // cascades path parameters down the route tree, so child builders can
      // read `state.pathParameters['id']` without re-declaring it.
      //
      // Sub-routes implemented per audit item #4 (v2 spec):
      //   /family/:id/governance/constitution
      //   /family/:id/governance/decisions
      //   /family/:id/governance/decisions/:decisionId
      //   /family/:id/governance/timeline
      //   /family/:id/governance/timeline/:eventId
      GoRoute(
        path: '/family/:id/governance',
        pageBuilder: (context, state) {
          final familyId = state.pathParameters['id']!;
          return _fastFadePage(
            key: state.pageKey,
            child: TrackcHubScreen(familyId: familyId),
          );
        },
        routes: [
          GoRoute(
            path: 'constitution',
            name: 'trackc-constitution',
            pageBuilder: (context, state) {
              final familyId = state.pathParameters['id']!;
              // Set the selected family for providers that depend on it
              return _fastFadePage(
                key: state.pageKey,
                child: _TrackcFamilyScope(
                  familyId: familyId,
                  child: const TrackcConstitutionScreen(),
                ),
              );
            },
          ),
          GoRoute(
            path: 'decisions',
            name: 'trackc-decisions',
            pageBuilder: (context, state) {
              final familyId = state.pathParameters['id']!;
              return _fastFadePage(
                key: state.pageKey,
                child: _TrackcFamilyScope(
                  familyId: familyId,
                  child: const TrackcDecisionsListScreen(),
                ),
              );
            },
            routes: [
              // P6.3: Decision Create wired into GoRouter for deep-linking.
              // URL: /family/:id/governance/decisions/create
              GoRoute(
                path: 'create',
                name: 'trackc-decision-create',
                pageBuilder: (context, state) {
                  final familyId = state.pathParameters['id']!;
                  return _fastFadePage(
                    key: state.pageKey,
                    child: _TrackcFamilyScope(
                      familyId: familyId,
                      child: const TrackcDecisionCreateScreen(),
                    ),
                  );
                },
              ),
              GoRoute(
                path: ':decisionId',
                name: 'trackc-decision-detail',
                pageBuilder: (context, state) {
                  final familyId = state.pathParameters['id']!;
                  final decisionId = state.pathParameters['decisionId']!;
                  return _fastFadePage(
                    key: state.pageKey,
                    child: _TrackcFamilyScope(
                      familyId: familyId,
                      child: TrackcDecisionDetailScreen(decisionId: decisionId),
                    ),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'timeline',
            name: 'trackc-timeline',
            pageBuilder: (context, state) {
              final familyId = state.pathParameters['id']!;
              return _fastFadePage(
                key: state.pageKey,
                child: _TrackcFamilyScope(
                  familyId: familyId,
                  child: const TrackcTimelineScreen(),
                ),
              );
            },
            routes: [
              GoRoute(
                path: ':eventId',
                name: 'trackc-timeline-event',
                pageBuilder: (context, state) {
                  final familyId = state.pathParameters['id']!;
                  final eventId = state.pathParameters['eventId']!;
                  return _fastFadePage(
                    key: state.pageKey,
                    child: _TrackcFamilyScope(
                      familyId: familyId,
                      child: TrackcTimelineEventDetailScreen(eventId: eventId),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
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
      // v135: Family Hub — intermediate screen between the chat and
      // the Family Space. Tapping the chat header (avatar, name, or
      // relationship chip) navigates HERE, not to /family/:id.
      // The Hub is the digital home of the conversation — a premium
      // overview space with hero, members, shared content, insights,
      // and a gateway to enter the full Family Space.
      // v5.119 step 10: /family/:id/hub route DELETED.
      // FamilyHubScreen was removed — its content (UtilityRow, Insights,
      // IdentityCard) was migrated into FamilyDetailScreen and the
      // /family/:id/management route. Chat now links directly to
      // /family/:id (FamilyDetailScreen) instead of /family/:id/hub.
      GoRoute(
        path: '/family-tree',
        // v5.125 (Family Space §5): retired as an independent destination.
        // Redirects to the production graph route, optionally with
        // `?tab=tree` to land on the Tree view. The old `FamilyTreeScreen`
        // was a 103-line wrapper around `FamilyGraphEngineView` (the same
        // widget at `/family/:id/graph`), so this redirect preserves
        // existing deep links without loss of functionality.
        redirect: (context, state) {
          final familyId = state.uri.queryParameters['familyId'];
          final tab = state.uri.queryParameters['tab'] ?? 'tree';
          if (familyId == null || familyId.isEmpty) {
            return '/'; // no family context — fall back to home
          }
          return '/family/$familyId/graph?tab=$tab';
        },
        // No builder — redirect takes precedence. (No `FamilyTreeScreen`
        // widget rendered anymore; the screen file is deleted.)
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
            // v5.125 (Family Space §5): deep-link ?tab=tree lands on
            // the Tree view (redirected from /family-tree).
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
      ),

      // ── Family Members (extracted from FamilyDetailScreen) ──────
      GoRoute(
        path: '/family/:id/members',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyMembersScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // Phase 22 / Header Nav Fix: Family Profile — a dedicated,
      // profile-style view of a FAMILY (not an individual member).
      // Reached by tapping the chat header in a family chat. Distinct
      // from /family/:id (Family Space dashboard) and from
      // MemberProfileSheet (a single member's profile, reached by
      // tapping a member's avatar INSIDE the chat thread).
      GoRoute(
        path: '/family/:id/profile',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyProfileScreen(
              familyId: state.pathParameters['id']!),
        ),
      ),

      // v137: Family Space Groups — sub-groups within a family.
      // Groups are child entities of the Family Space.
      GoRoute(
        path: '/family/:id/groups',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyGroupsScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      // Group Hub — premium overview of a single group (mirrors Family Hub)
      GoRoute(
        path: '/family/:id/groups/:groupId/hub',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: GroupHubScreen(
            familyId: state.pathParameters['id']!,
            groupId: state.pathParameters['groupId']!,
          ),
        ),
      ),
      // Group Chat — the conversation screen for a specific group
      // v139: Reuses the existing ChatScreen with groupId + groupName
      // params. The screen filters messages to this group only.
      GoRoute(
        path: '/family/:id/groups/:groupId/chat',
        pageBuilder: (context, state) {
          final familyId = state.pathParameters['id']!;
          final groupId = state.pathParameters['groupId']!;
          final groupName = state.uri.queryParameters['name'] ?? 'Group';
          return _fastFadePage(
            key: state.pageKey,
            child: ChatScreen(
              familyId: familyId,
              familyName: groupName,
              groupId: groupId,
              groupName: groupName,
              showFamilyNav: false,
            ),
          );
        },
      ),
      // Create Group flow
      GoRoute(
        path: '/family/:id/groups/create',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: CreateGroupScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Family Activity (extracted from FamilyDetailScreen) ─────
      GoRoute(
        path: '/family/:id/activity',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyActivityScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Truth Streak (daily family question game) ───────────────
      GoRoute(
        path: '/family/:id/truth-streak',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TruthStreakScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Hot Seat (daily spotlight game) ──────────────────────────
      GoRoute(
        path: '/family/:id/hot-seat',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: HotSeatScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Relation Riddles (daily kinship quiz) ────────────────────
      GoRoute(
        path: '/family/:id/relation-riddles',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: RelationRiddleScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Family Calendar (redesigned) ─────────────────────────────
      GoRoute(
        path: '/family/:id/calendar',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: cal.FamilyCalendarScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Family Kinrel (Ancestral Unified Relationship Archetype) ──
      // Gated by kEnableKinrel so the feature ships dark and can be
      // flipped on per build. The screen itself also re-checks the
      // flag in case it's opened via deep link.
      GoRoute(
        path: '/family/:id/kinrel',
        pageBuilder: (context, state) {
          if (!kEnableKinrel) {
            return _fastFadePage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(child: Text('Kinrel is not available.')),
              ),
            );
          }
          final extra = state.extra;
          final familyName = (extra is Map<String, dynamic>)
              ? extra['familyName'] as String?
              : null;
          return _fastFadePage(
            key: state.pageKey,
            child: KinrelScreen(
              familyId: state.pathParameters['id']!,
              familyName: familyName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/family/:id/calendar/new',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: EventCreateScreen(
            familyId: state.pathParameters['id']!,
            existingEvent: state.extra != null
                ? CalendarEvent.fromJson(state.extra as Map<String, dynamic>)
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/calendar/event/:eventId',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final event = extra != null
              ? CalendarEvent.fromJson(extra['event'] as Map<String, dynamic>)
              : null;
          return _fastFadePage(
            key: state.pageKey,
            child: event != null
                ? EventDetailScreen(
                    familyId: state.pathParameters['id']!,
                    event: event,
                  )
                : const Scaffold(body: Center(child: Text('Event not found'))),
          );
        },
      ),

      // ── Games Hub ────────────────────────────────────────────────
      GoRoute(
        path: '/games',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: GamesHubScreen(
            familyId: state.uri.queryParameters['familyId'],
          ),
        ),
      ),

      // ── Ghost Painter (draw + guess) ─────────────────────────────
      GoRoute(
        path: '/family/:id/ghost-painter/draw',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: GhostPainterDrawScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/ghost-painter/guess',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: GhostPainterGuessScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Freeze & Dash (Red Light, Green Light) ──────────────────────
      GoRoute(
        path: '/family/:id/freeze-dash/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: RedlightLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/freeze-dash/game/:roundId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: RedlightGameScreen(
            familyId: state.pathParameters['id']!,
            roundId: state.pathParameters['roundId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/freeze-dash/results/:roundId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: RedlightResultsScreen(
            familyId: state.pathParameters['id']!,
            roundId: state.pathParameters['roundId']!,
          ),
        ),
      ),

      // ── SOS Game ───────────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/sos/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: SosLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/sos/game/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: SosBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/sos/results/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: SosResultsScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Antakshari Game ────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/antakshari/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: AntakshariLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/antakshari/game/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: AntakshariGameScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Bingo Game ───────────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/bingo/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: BingoLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/bingo/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: BingoBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Checkers Game ────────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/checkers/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: CheckersLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/checkers/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: CheckersBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Ludo Game ────────────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/ludo/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: LudoLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/ludo/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: LudoBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Carrom Game ─────────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/carrom/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: CarromLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/carrom/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: CarromBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Chess Game ──────────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/chess/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChessLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/chess/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChessBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── TripleMatch Game ────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/chitmatch/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChitmatchLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/chitmatch/game/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChitmatchGameScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Name, Place, Animal, Thing Game ─────────────────────────────
      GoRoute(
        path: '/family/:id/nameplace/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: NameplaceLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/nameplace/letter/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: NameplaceLetterPickScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/nameplace/answer/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: NameplaceAnswerScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/nameplace/results/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: NameplaceResultsScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Tic-Tac-Toe Game ───────────────────────────────────────────
      GoRoute(
        path: '/family/:id/tictactoe/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TttLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/tictactoe/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TttBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Truth or Dare Game ──────────────────────────────────────────
      GoRoute(
        path: '/family/:id/truthordare/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TodLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/truthordare/table/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TodTableScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/truthordare/submit',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TodSubmitScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/truthordare/review',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TodReviewScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Two Truths and a Lie Game ──────────────────────────────────
      GoRoute(
        path: '/family/:id/twotruths/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TtLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/twotruths/submit/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TtSubmitScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/twotruths/guess/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TtGuessScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/family/:id/twotruths/results/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: TtResultsScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
          ),
        ),
      ),

      // ── Dots and Boxes Game ───────────────────────────────────────
      GoRoute(
        path: '/family/:id/dotsboxes/lobby',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: DotsboxesLobbyScreen(familyId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/family/:id/dotsboxes/board/:gameId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: DotsboxesBoardScreen(
            familyId: state.pathParameters['id']!,
            gameId: state.pathParameters['gameId']!,
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
          child: MemberTimelineScreen(memberId: state.pathParameters['id']!),
        ),
      ),

      // ── Family Chat (group conversation) ────────────────────────
      // v115: This route opens the group chat CONVERSATION (full-screen,
      // no Family bottom nav). The Chat TAB now goes to /family/:id/chats
      // (the chat list) instead of here. Tapping the Family Group Chat
      // row in the list pushes this route with showFamilyNav=false so
      // the conversation is full-screen like WhatsApp/Telegram.
      GoRoute(
        path: '/family/:id/chat',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChatScreen(
            familyId: state.pathParameters['id']!,
            familyName: state.uri.queryParameters['name'] ?? 'Family',
            showFamilyNav: false,
          ),
        ),
      ),

      // Tier 1 / Message Search — search within a single family chat.
      // The familyId narrows the scope to "this chat" mode. If familyId
      // is omitted (the /chats/search route below), the search runs
      // across ALL family chats the user is a member of.
      GoRoute(
        path: '/family/:id/chat/search',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: ChatSearchScreen(
            familyId: state.pathParameters['id'],
          ),
        ),
      ),
      // "All chats" search — no familyId, searches across every family
      // the user is a member of.
      GoRoute(
        path: '/chats/search',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const ChatSearchScreen(familyId: null),
        ),
      ),

      // ── Family Chat List (Chat tab destination) ─────────────────
      // v115: The Chat tab now opens this list screen (showing group
      // chat + DMs with All/Family/Direct filter tabs) instead of the
      // group chat directly. Tapping a conversation pushes /family/:id/chat
      // or /dm/:otherUserId (both full-screen, no Family bottom nav).
      GoRoute(
        path: '/family/:id/chats',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyChatListScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Family Lists (Shared List / Errand Board) ───────────────
      // Registered for /family/:id/lists — the path the Family Space
      // floating nav taps via context.go('/family/$familyId/lists').
      // Previously missing, causing GoException: no routes for location
      // when the Lists tab was tapped. SharedListScreen is the existing
      // widget (lib/features/shared_list/presentation/shared_list_screen.dart)
      // — already wired with FamilySpaceFloatingNav + safe back button.
      GoRoute(
        path: '/family/:id/lists',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: SharedListScreen(
            familyId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Direct (1:1) Chat — private conversation between two users ──
      // Used by the Thinking of You feature (notification tap opens this)
      // and will be used by a future DM inbox section.
      GoRoute(
        path: '/dm/:otherUserId',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: DirectChatScreen(
            otherUserId: state.pathParameters['otherUserId']!,
          ),
        ),
      ),

      // ── Archived Chats — shows all archived group + DM conversations ──
      // v113: Reached from the "Archived" row at the bottom of the chat
      // inbox. Supports swipe-to-unarchive.
      GoRoute(
        path: '/chats/archived',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const ArchivedChatsScreen(),
        ),
      ),

      // ── Wallpaper Settings — manage chat wallpapers ──────────────
      // v114: Reached from Profile → Chat Wallpaper.
      GoRoute(
        path: '/settings/wallpaper',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const WallpaperSettingsScreen(),
        ),
      ),

      // ── Events & Celebrations ──────────────────────────────────

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
        path: '/festival-cards',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: FestivalCardsScreen()),
      ),

      // ── Kinship Dictionary ──────────────────────────────────────
      GoRoute(
        path: '/kinship/global',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const GlobalKinshipScreen(),
        ),
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
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const EngagementDashboard(),
        ),
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

      // ── Person-Specific Claim route (/claim/:code) ──────────────
      // Maps https://kinrel.app/claim/:code to the PersonClaimScreen.
      // Recipients of a person-specific invite (sent from AddPersonSheet)
      // land here to confirm their spot in the family tree.
      GoRoute(
        path: '/claim/:code',
        pageBuilder: (context, state) {
          final claimCode = state.pathParameters['code']!;
          return _fastFadePage(
            key: state.pageKey,
            child: PersonClaimScreen(code: claimCode),
          );
        },
      ),

      // ── Gamification & Achievements ─────────────────────────────
      GoRoute(
        path: '/achievements',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const AchievementsScreen(),
        ),
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
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const DeleteAccountScreen(),
        ),
      ),
      GoRoute(
        path: '/profile/members-added',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const MembersAddedScreen(),
        ),
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
      // v109: Account Information — private account details (email, phone,
      // security) separated from the public Edit Profile screen.
      GoRoute(
        path: '/profile/account',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const AccountInformationScreen(),
        ),
      ),
      // v109.9: Family Management — admin & creator controls
      GoRoute(
        path: '/family/:id/management',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyManagementScreen(
            familyId: state.pathParameters['id']!,
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
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const PrivacyPolicyScreen(),
        ),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const TermsOfServiceScreen(),
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
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const BlockedUsersScreen(),
        ),
      ),
      GoRoute(
        path: '/profile/relations',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const RelationsScreen()),
      ),

      // ── Social System Routes ─────────────────────────────────────────

      // ── Phase B: Family Map ────────────────────────────────────────
      // The map screen takes a concrete familyId (just like the graph
      // screen at /family/:id/graph) — it no longer falls back to
      // familyListProvider.first. Callers MUST supply the family ID.
      GoRoute(
        path: '/family/:id/map',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: FamilyMapScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // ── Phase B: Memory Vault ──────────────────────────────────────
      GoRoute(
        path: '/memory-vault',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const MemoryVaultScreen()),
      ),

      // ── Phase B: Occasion Reminders ───────────────────────────────

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
          child: FollowersScreen(
            initialTab: state.uri.queryParameters['tab'] == 'following' ? 1 : 0,
          ),
        ),
      ),
      GoRoute(
        path: '/follow-requests',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const FollowRequestsScreen(),
        ),
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
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const PrivacySettingsScreen(),
        ),
      ),

      // ── Pulse + Pitru + emotional attachment routes ─────────────────────────
      GoRoute(
        path: '/pulse',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const PulseHubScreen()),
      ),
      GoRoute(
        path: '/pulse/today',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const DailyBriefScreen()),
      ),
      GoRoute(
        path: '/pulse/quests',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const FamilyQuestsScreen(),
        ),
      ),
      GoRoute(
        path: '/pulse/blessings',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const BlessingChainScreen(),
        ),
      ),
      GoRoute(
        path: '/pulse/time-capsules',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const TimeCapsuleScreen()),
      ),
      GoRoute(
        path: '/pulse/festivals',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const FestivalScreen()),
      ),
      GoRoute(
        path: '/pulse/alarms',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const SilentAlarmsScreen(),
        ),
      ),
      GoRoute(
        path: '/pulse/chronicle',
        pageBuilder: (context, state) {
          final familyId = state.uri.queryParameters['familyId'] ?? '';
          return _fastFadePage(
            key: state.pageKey,
            child: FamilyChronicleScreen(familyId: familyId),
          );
        },
      ),
      GoRoute(
        path: '/pulse/celebrations',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const CelebrationsScreen(),
        ),
      ),
      GoRoute(
        path: '/pulse/legacy',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const FamilyLegacyScreen(),
        ),
      ),
      GoRoute(
        path: '/pulse/memorials',
        pageBuilder: (context, state) {
          final familyId = state.uri.queryParameters['familyId'] ?? '';
          return _fastFadePage(
            key: state.pageKey,
            child: MemorialsScreen(familyId: familyId),
          );
        },
      ),
      GoRoute(
        path: '/pulse/memorial/:personId',
        pageBuilder: (context, state) {
          // For MVP, redirect to memorials list — a dedicated memorial detail
          // screen would be built in the next iteration
          return _fastFadePage(
            key: state.pageKey,
            child: const MemorialsScreen(familyId: ''),
          );
        },
      ),

      // ── P12.6 Batch 2: Wire 4 previously-unreachable Category A screens ──
      // Audit: docs/audit/batch1-reachability-audit.md
      // Each route was verified via the 13-stage trace (Section 3.1):
      //   - Screen renders with realistic props ✅
      //   - Providers exist and are used correctly ✅
      //   - Backend endpoints exist (NestJS) ✅
      //   - Auth/RLS via JWT guard ✅
      //   - Family context passed via path param where required ✅
      //   - No debug gates, no hardcoded fixtures ✅

      // 1. Story Mode — narrated tour of family history (family-scoped)
      GoRoute(
        path: '/family/:id/story-mode',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: StoryModeScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // 2. Community Discovery — browse communities (global, user-scoped)
      GoRoute(
        path: '/community',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const CommunityDiscoveryScreen(),
        ),
      ),

      // 3. Pulse Learning Profile — ML engagement transparency (user-scoped)
      GoRoute(
        path: '/profile/pulse-learning',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const PulseLearningProfileScreen(),
        ),
      ),

      // 4. Family Management — UNIFIED entry point for ALL family-scoped
      //    admin controls (permissions, privacy, member management,
      //    family preferences, activity log). The old separate
      //    "Family Settings" screen has been merged into Family Management.
      //    Route kept as an alias for backwards-compatible deep links.
      GoRoute(
        path: '/family/:id/settings',
        redirect: (context, state) =>
            '/family/${state.pathParameters['id']}/management',
      ),

      // 5. Health Heritage — family health conditions (family-scoped)
      // P12.6: Previously Category G (backend blocked). Now wired after
      // creating FamilyHealthCondition table + real data loading.
      GoRoute(
        path: '/family/:id/health-heritage',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: const HealthHeritageScreen(),
        ),
      ),

      // ── P12.6 Batch 3: GEDCOM export + trust/privacy screens ────────
      // GEDCOM export — family-scoped, strict default-deny allowlist
      GoRoute(
        path: '/family/:id/gedcom',
        pageBuilder: (context, state) => _fastFadePage(
          key: state.pageKey,
          child: GedcomExportScreen(familyId: state.pathParameters['id']!),
        ),
      ),

      // "Your Family, Your Data" — what's stored, where, one-tap export
      GoRoute(
        path: '/your-data',
        pageBuilder: (context, state) =>
            _fastFadePage(key: state.pageKey, child: const YourDataScreen()),
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
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/$familyId'); } },
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
    // Save current route when app goes to background.
    //
    // SECONDARY SAFEGUARD: on Flutter Web, a browser refresh does NOT
    // reliably fire this callback in time to complete the SharedPreferences
    // write before the page is torn down. The primary save mechanism is
    // now LastRoutePersistenceObserver (registered on GoRouter), which
    // records every navigation change immediately. This pause-based save
    // remains useful for native mobile backgrounding where the observer
    // has already captured the right route and the extra write is a
    // no-op (same value) and harmless.
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

/// SECONDARY route-persistence mechanism.
///
/// Persists the *current* matched route on imperative Navigator events
/// (push / replace / pop / remove). On Flutter Web, GoRouter's declarative
/// page reconciliation does NOT reliably fire these callbacks for
/// `context.go()` style navigations, so this observer alone is not
/// sufficient to capture every navigation.
///
/// The PRIMARY save mechanism lives in [_handleRedirect], which fires on
/// every navigation regardless of declarative vs imperative style. This
/// observer is retained as a defense-in-depth for the (rare on web, more
/// common on mobile) cases where a navigation event bypasses the redirect
/// callback (e.g., programmatic imperative pushes that don't change the
/// matched location, or rapid push/pop sequences).
///
/// Behavior:
///   • On push / replace / remove: persist the *new* top-of-stack route.
///   • On pop: persist the route we're returning to (previousRoute).
///   • Skips null / empty names and the /splash route itself (we never
///     want to restore the splash screen).
///   • All saves are fire-and-forget — saveLastRoute already swallows
///     errors and the await must not block the navigation frame.
class LastRoutePersistenceObserver extends NavigatorObserver {
  static const Set<String> _skippedRoutes = {'/splash', ''};

  void _persist(String? name) {
    if (name == null) return;
    if (_skippedRoutes.contains(name)) return;
    // Fire-and-forget: saveLastRoute is async (SharedPreferences) but we
    // must not await it inside the navigation callback.
    unawaited(saveLastRoute(name));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _persist(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _persist(newRoute.settings.name);
    } else if (oldRoute != null) {
      // If we somehow replaced into an unknown target, fall back to the
      // previous route — that's the route currently visible to the user.
      _persist(oldRoute.settings.name);
    }
  }

  @override
  void didPop(Route<dynamic>? route, Route<dynamic>? previousRoute) {
    // After a pop, the screen the user sees is previousRoute.
    _persist(previousRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic>? route, Route<dynamic>? previousRoute) {
    // After a remove, the visible screen is previousRoute (whatever is
    // now on top of the stack).
    _persist(previousRoute?.settings.name);
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
    // v138: Notification bell is now part of the Home screen's sticky
    // header (see _HomeNotificationBell in home_screen.dart). The
    // floating overlay bell has been removed entirely — the bell is
    // visible ONLY on the Home page, never on Chat/Family/Search/Me.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          if (context.canPop()) { context.pop(); } else { context.go('/home'); }
        }
      },
      child: Scaffold(
        body: StreamBuilder<List<ConnectivityResult>>(
          stream: Connectivity().onConnectivityChanged,
          builder: (context, snap) {
            final offline =
                snap.data?.contains(ConnectivityResult.none) ?? false;
            return Column(
              children: [
                if (offline)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: const Text(
                      'No internet connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                Expanded(
                  child: widget.child,
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
    if (location.startsWith('/families') || location.startsWith('/family/'))
      return 2;
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
      data: (name) =>
          ShareScreen(familyId: familyId, familyName: name ?? 'Family'),
      loading: () => ShareScreen(familyId: familyId, familyName: 'Family'),
      error: (_, __) => ShareScreen(familyId: familyId, familyName: 'Family'),
    );
  }
}
