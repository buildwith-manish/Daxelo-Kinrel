import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../networking/dio_client.dart';

class FeatureFlags {
  static final Map<String, bool> _flags = {};

  static Future<void> loadAll(Dio dio) async {
    try {
      final response = await dio.get('/feature-flags');
      final flags = response.data as List<dynamic>;
      for (final flag in flags) {
        _flags[flag['name'] as String] = flag['enabled'] as bool;
      }
    } catch (_) {
      // Fail silently — all features default to enabled
    }
  }

  static bool isEnabled(String name, {bool defaultValue = true}) {
    return _flags[name] ?? defaultValue;
  }

  static void clear() {
    _flags.clear();
  }
}

// Feature flag names — add new ones here
class FeatureFlag {
  static const String aiChat = 'ai_chat';
  static const String voiceNotes = 'voice_notes';
  static const String migrationMap = 'migration_map';
  static const String premiumFeatures = 'premium_features';
  static const String communityFeatures = 'community_features';
}

final featureFlagsProvider = FutureProvider<void>((ref) async {
  final dio = ref.read(dioProvider);
  await FeatureFlags.loadAll(dio);
});
