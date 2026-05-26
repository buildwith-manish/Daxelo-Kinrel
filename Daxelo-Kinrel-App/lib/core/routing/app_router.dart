// lib/core/routing/app_router.dart
//
// DAXELO KINREL — App Router
//
// 5-tab bottom navigation:
//   1. Home      → /home
//   2. Kinship   → /kinship-search
//   3. Graph     → /families
//   4. Alerts    → /notifications
//   5. Me        → /profile
//
// Additional deep-link routes for all features.
// Uses DKBottomNav with semi-transparent background, orange active,
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
import '../../features/family/presentation/person_detail_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/ai_chat/presentation/ai_chat_screen.dart';
import '../../features/voice_search/presentation/voice_search_screen.dart';
import '../../features/festival_cards/presentation/festival_cards_screen.dart';
import '../../features/quiz/presentation/quiz_screen.dart';
import '../../features/referral/presentation/referral_screen.dart';
import '../../features/kinship/presentation/kinship_search_screen.dart';
import '../../features/kinship/presentation/kinship_detail_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/memories/presentation/memories_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/share/presentation/share_screen.dart';
import '../../features/gamification/presentation/achievements_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
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
        builder: (context, state) => SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => SignUpScreen(),
      ),
      // ── Shell routes (show bottom navigation) ───────────────────
      ShellRoute(
        builder: (context, state, child) =>
            RoutePersistenceShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => HomeScreen(),
          ),
          GoRoute(
            path: '/kinship-search',
            builder: (context, state) => KinshipSearchScreen(),
          ),
          GoRoute(
            path: '/families',
            builder: (context, state) => FamilyListScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/explore',
            builder: (context, state) => ExploreScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => ProfileScreen(),
          ),
          // Keep /settings in shell for backward compat
          GoRoute(
            path: '/settings',
            builder: (context, state) => SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/families/create',
        builder: (context, state) => CreateFamilyScreen(),
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

      // ── Person Detail Screen ────────────────────────────────────
      GoRoute(
        path: '/member/:id',
        builder: (context, state) => PersonDetailScreen(
          memberId: state.pathParameters['id']!,
        ),
      ),

      // ── Family Chat ─────────────────────────────────────────────
      GoRoute(
        path: '/family/:id/chat',
        builder: (context, state) => ChatScreen(
          familyId: state.pathParameters['id']!,
          familyName: state.uri.queryParameters['name'] ?? 'Family',
        ),
      ),

      // ── Events & Celebrations ──────────────────────────────────
      GoRoute(
        path: '/events',
        builder: (context, state) => const EventsScreen(),
      ),

      // ── Memories & Timeline ─────────────────────────────────────
      GoRoute(
        path: '/memories',
        builder: (context, state) => const MemoriesScreen(),
      ),

      // ── AI-Powered Features ─────────────────────────────────────
      GoRoute(
        path: '/ai-chat',
        builder: (context, state) => AiChatScreen(),
      ),
      GoRoute(
        path: '/voice-search',
        builder: (context, state) => VoiceSearchScreen(),
      ),
      GoRoute(
        path: '/festival-cards',
        builder: (context, state) => FestivalCardsScreen(),
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
        builder: (context, state) => QuizScreen(),
      ),
      GoRoute(
        path: '/referral',
        builder: (context, state) => ReferralScreen(),
      ),

      // ── Share & Invite ──────────────────────────────────────────
      GoRoute(
        path: '/family/:id/share',
        builder: (context, state) => ShareScreen(
          familyId: state.pathParameters['id']!,
          familyName: state.uri.queryParameters['name'] ?? 'Family',
        ),
      ),

      // ── Gamification & Achievements ─────────────────────────────
      GoRoute(
        path: '/achievements',
        builder: (context, state) => const AchievementsScreen(),
      ),

      // ── Document Vault ───────────────────────────────────────────
      GoRoute(
        path: '/documents',
        builder: (context, state) => const DocumentsScreen(),
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
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
          ),
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

/// Main shell with 5-tab bottom navigation using DKBottomNav
class MainShell extends StatelessWidget {
  MainShell({super.key, required this.child});

  final Widget child;

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
  int _currentIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/kinship-search')) return 1;
    if (location.startsWith('/families')) return 2;
    if (location.startsWith('/notifications')) return 3;
    if (location.startsWith('/explore')) return 0;
    if (location.startsWith('/profile')) return 4;
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
        context.go('/notifications');
      case 4:
        context.go('/profile');
    }
  }
}
