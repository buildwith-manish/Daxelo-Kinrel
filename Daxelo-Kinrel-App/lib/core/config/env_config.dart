import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment configuration with secure handling
class EnvConfig {
  EnvConfig._();

  static bool get isProduction => const bool.fromEnvironment('dart.vm.product');
  static bool get isDebug => !isProduction;
  static bool get isProfile => const bool.fromEnvironment('dart.vm.profile');

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ??
      const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: 'https://vxnyjhvcipgqeowdgfah.supabase.co',
      );

  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ??
      const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: '',
      );

  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ??
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://daxelo-kinrel.vercel.app',
      );
}
