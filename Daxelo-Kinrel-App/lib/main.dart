import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/storage/local_cache.dart';
import 'core/theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set initial system UI overlay style — will be updated by theme
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF121212),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables from .env file
  // Gracefully handle missing .env (e.g. in CI/release builds)
  bool dotenvLoaded = false;
  try {
    await dotenv.load(fileName: '.env');
    dotenvLoaded = true;
    debugPrint('✅ .env file loaded successfully');
  } catch (e) {
    // .env not found — will fall back to --dart-define or hardcoded defaults
    debugPrint('⚠️ .env file not found ($e), using fallback defaults');
  }

  // Debug: log what dotenv has (key masked)
  if (dotenvLoaded) {
    final dotenvUrl = dotenv.env['SUPABASE_URL'];
    final dotenvKey = dotenv.env['SUPABASE_ANON_KEY'];
    debugPrint('🔧 dotenv SUPABASE_URL: ${dotenvUrl ?? "null"}');
    debugPrint('🔧 dotenv SUPABASE_ANON_KEY: ${dotenvKey != null && dotenvKey.isNotEmpty ? "SET (length: ${dotenvKey.length})" : (dotenvKey == null ? "null" : "empty string")}');
  }

  // Debug: log resolved AppConfig values
  debugPrint('🔧 AppConfig SUPABASE_URL: ${AppConfig.supabaseUrl}');
  debugPrint('🔧 AppConfig SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.isNotEmpty ? "SET (length: ${AppConfig.supabaseAnonKey.length})" : "EMPTY"}');
  debugPrint('🔧 AppConfig isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}');

  // Initialize Hive for local caching
  await Hive.initFlutter();

  // Initialize local cache
  final cacheService = LocalCacheService();
  await cacheService.init();

  // Initialize Supabase — will ALWAYS succeed with hardcoded fallbacks
  final supabaseReady = await initSupabase();
  debugPrint('🔧 Supabase initialized: $supabaseReady');

  runApp(
    const ProviderScope(
      child: KinrelApp(),
    ),
  );
}

class KinrelApp extends ConsumerStatefulWidget {
  KinrelApp({super.key});

  @override
  ConsumerState<KinrelApp> createState() => _KinrelAppState();
}

class _KinrelAppState extends ConsumerState<KinrelApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Register for app lifecycle events to prevent restart on resume
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app comes back to foreground, update system UI overlay
    // based on the current theme mode
    if (state == AppLifecycleState.resumed) {
      _updateSystemUIOverlay();

      // Silently refresh the session in the background WITHOUT triggering
      // a navigation reset. We only refresh if there's an existing session.
      // This prevents the app from redirecting to sign-in on resume.
      if (isSupabaseInitialized) {
        try {
          final client = ref.read(supabaseProvider);
          if (client != null && client.auth.currentSession != null) {
            // Only refresh if we already have a session — don't try to restore
            client.auth.refreshSession().catchError((_) {
              // Ignore refresh errors — existing session is still valid locally
              return AuthResponse();
            });
          }
        } catch (_) {}
      }
    }
  }

  /// Update system UI overlay style to match the current theme brightness.
  void _updateSystemUIOverlay() {
    final themeMode = ref.read(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // Support both light and dark themes
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Update system UI overlay when theme changes
        final brightness = MediaQuery.of(context).platformBrightness;
        final effectiveDark = themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                brightness == Brightness.dark);

        // Set system UI overlay on every build to stay in sync
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              effectiveDark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              effectiveDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: effectiveDark
              ? const Color(0xFF121212)
              : const Color(0xFFF5F7FA),
          systemNavigationBarIconBrightness:
              effectiveDark ? Brightness.light : Brightness.dark,
        ));

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // Respect platform brightness — do NOT force dark mode
            textScaler: TextScaler.linear(ref.watch(fontScaleProvider)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
