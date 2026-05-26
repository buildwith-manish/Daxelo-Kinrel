// lib/core/routing/app_router.dart
//
// DAXELO KINREL — App Router
//
// 5-tab bottom navigation:
//   1. Home      → /home
//   2. Kinship   → /kinship-search
//   3. Graph     → /families
//   4. Alerts    → /home (placeholder until alerts feature is built)
//   5. Me        → /profile
//
// Uses DKBottomNav with semi-transparent background, purple active,
// gold indicator, badge support on Alerts tab.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/explore/presentation/explore_screen.dart';
import '../../features/family/presentation/family_list_screen.dart';
import '../../features/family/presentation/family_detail_screen.dart';
import '../../features/family/presentation/path_finder_screen.dart';
import '../../features/family/presentation/create_family_screen.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/relationship_builder_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/ai_chat/presentation/ai_chat_screen.dart';
import '../../features/voice_search/presentation/voice_search_screen.dart';
import '../../features/festival_cards/presentation/festival_cards_screen.dart';
import '../../features/quiz/presentation/quiz_screen.dart';
import '../../features/referral/presentation/referral_screen.dart';
import '../../features/kinship/presentation/kinship_search_screen.dart';
import '../../features/kinship/presentation/kinship_detail_screen.dart';
import '../services/supabase_service.dart';
import '../../shared/widgets/dk_components.dart';

/// Key for accessing the router's navigator state
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Router provider — uses a single GoRouter instance that doesn't
/// rebuild on auth state changes. This prevents the app from
/// restarting/resetting navigation when resuming from background.
///
/// Auth-based redirect logic is handled once during splash,
/// and the router redirect only handles edge cases.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Don't redirect away from splash — it handles its own navigation
      final isSplash = state.matchedLocation == '/splash';
      if (isSplash) return null;

      final authState = ref.read(isAuthenticatedProvider);
      final isOnboarding = state.matchedLocation == '/onboarding';
      final isAuth = state.matchedLocation == '/sign-in' ||
          state.matchedLocation == '/sign-up';
      final isProtected = !isSplash && !isOnboarding && !isAuth;

      // If not authenticated and trying to access protected route, go to sign-in
      // BUT: Don't redirect if Supabase isn't initialized yet — the session
      // might just be restoring. This prevents flicker to sign-in on resume.
      if (!authState && isProtected) {
        if (!ref.read(isSupabaseReadyProvider)) return null;
        return '/sign-in';
      }

      // If authenticated and on auth pages, go to home
      if (authState && isAuth) return '/home';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      // ── Shell routes (show bottom navigation) ───────────────────
      ShellRoute(
        builder: (context, state, child) =>
            RoutePersistenceShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/kinship-search',
            builder: (context, state) => const KinshipSearchScreen(),
          ),
          GoRoute(
            path: '/families',
            builder: (context, state) => const FamilyListScreen(),
          ),
          GoRoute(
            path: '/explore',
            builder: (context, state) => const ExploreScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          // Keep /settings in shell for backward compat
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/families/create',
        builder: (context, state) => const CreateFamilyScreen(),
      ),
      GoRoute(
        path: '/family/:id',
        builder: (context, state) => FamilyDetailScreen(
          familyId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/family/:id/path-finder',
        builder: (context, state) => PathFinderScreen(
          familyId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/family/:id/add-person',
        builder: (context, state) => _AddPersonScreen(
          familyId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/family/:id/add-member',
        builder: (context, state) => _AddPersonScreen(
          familyId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/family/:id/link',
        builder: (context, state) => RelationshipBuilderScreen(
          familyId: state.pathParameters['id']!,
          familyName: state.uri.queryParameters['name'] ?? 'Family',
        ),
      ),

      // ── AI-Powered Features ─────────────────────────────────────
      GoRoute(
        path: '/ai-chat',
        builder: (context, state) => const AiChatScreen(),
      ),
      GoRoute(
        path: '/voice-search',
        builder: (context, state) => const VoiceSearchScreen(),
      ),
      GoRoute(
        path: '/festival-cards',
        builder: (context, state) => const FestivalCardsScreen(),
      ),

      // ── Kinship Dictionary ──────────────────────────────────────
      GoRoute(
        path: '/kinship/:key',
        builder: (context, state) => KinshipDetailScreen(
          relationshipKey: state.pathParameters['key']!,
        ),
      ),

      // ── Growth & Engagement ─────────────────────────────────────
      GoRoute(
        path: '/quiz',
        builder: (context, state) => const QuizScreen(),
      ),
      GoRoute(
        path: '/referral',
        builder: (context, state) => const ReferralScreen(),
      ),
    ],
  );
});

/// Full-screen wrapper for AddPersonSheet
class _AddPersonScreen extends ConsumerWidget {
  final String familyId;

  const _AddPersonScreen({required this.familyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Family Member',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _AddPersonForm(familyId: familyId),
        ),
      ),
    );
  }
}

/// Inline form for add person (full screen version)
class _AddPersonForm extends ConsumerStatefulWidget {
  final String familyId;

  const _AddPersonForm({required this.familyId});

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
  final Widget child;
  const RoutePersistenceShell({super.key, required this.child});

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

/// Main shell with 5-tab bottom navigation using DKBottomNav
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

/// 5-tab bottom navigation:
/// 0. Home      (home icon)
/// 1. Kinship   (menu_book icon)
/// 2. Graph     (family_restroom icon)
/// 3. Alerts    (notifications icon with badge)
/// 4. Me        (person icon)
class _BottomNav extends StatelessWidget {
  const _BottomNav();

  static const _items = [
    DKNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    DKNavItem(
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book_rounded,
      label: 'Kinship',
    ),
    DKNavItem(
      icon: Icons.family_restroom_outlined,
      activeIcon: Icons.family_restroom_rounded,
      label: 'Graph',
    ),
    DKNavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications_rounded,
      label: 'Alerts',
      badge: 0, // Badge count; update dynamically when needed
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
  /// Alerts (index 3) is a placeholder — no dedicated route yet.
  int _currentIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/kinship-search')) return 1;
    if (location.startsWith('/families')) return 2;
    // Alerts has no dedicated route yet; placeholder goes to /home
    if (location.startsWith('/explore')) return 0; // Explore no longer a tab
    if (location.startsWith('/profile')) return 4;
    // /settings maps to home tab (backward compat)
    if (location.startsWith('/settings')) return 0;
    return 0;
  }

  /// Navigate to the route for the given tab index.
  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/kinship-search');
      case 2:
        context.go('/families');
      case 3:
        // Alerts placeholder — navigates to /home until alerts feature is built
        context.go('/home');
      case 4:
        context.go('/profile');
    }
  }
}
