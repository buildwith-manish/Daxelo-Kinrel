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

  // Force dark mode at the platform level — prevents light mode flash on launch
  // and ensures system UI (status bar, nav bar) is always dark
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF13141E),
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
  const KinrelApp({super.key});

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
    // When app comes back to foreground, re-enforce dark mode system UI
    // This prevents the system from switching to light mode UI on resume
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF13141E),
        systemNavigationBarIconBrightness: Brightness.light,
      ));

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
              return client.auth.currentSession ?? AuthResponse();
            });
          }
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // Always dark mode — KINREL brand requirement
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // Force platform brightness to dark to prevent any light mode leakage
            platformBrightness: Brightness.dark,
            textScaler: TextScaler.linear(ref.watch(fontScaleProvider)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
