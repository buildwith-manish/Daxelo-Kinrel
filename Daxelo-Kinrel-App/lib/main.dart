import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/storage/local_cache.dart';
import 'core/theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System UI configuration
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables from .env file
  await dotenv.load(fileName: '.env');

  // Initialize Hive for local caching
  await Hive.initFlutter();

  // Initialize local cache
  final cacheService = LocalCacheService();
  await cacheService.init();

  // Initialize Supabase
  await initSupabase();

  runApp(
    const ProviderScope(
      child: KinrelApp(),
    ),
  );
}

class KinrelApp extends ConsumerWidget {
  const KinrelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(ref.watch(fontScaleProvider)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
