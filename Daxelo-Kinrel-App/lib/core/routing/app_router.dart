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
import '../services/supabase_service.dart';

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
      ShellRoute(
        builder: (context, state, child) =>
            RoutePersistenceShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/explore',
            builder: (context, state) => const ExploreScreen(),
          ),
          GoRoute(
            path: '/families',
            builder: (context, state) => const FamilyListScreen(),
          ),
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
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
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

/// Main shell with bottom navigation
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

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return NavigationBar(
      selectedIndex: _currentIndex(location),
      onDestinationSelected: (index) => _onTap(context, index),
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home'),
        NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore'),
        NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom),
            label: 'Families'),
        NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings'),
      ],
    );
  }

  int _currentIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/families')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/explore');
      case 2:
        context.go('/families');
      case 3:
        context.go('/settings');
    }
  }
}
