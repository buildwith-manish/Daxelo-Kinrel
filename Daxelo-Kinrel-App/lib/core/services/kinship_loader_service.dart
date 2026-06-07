import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../networking/dio_client.dart';

/// Service that loads kinship data either from the server API (for global
/// cultures) or from the bundled asset (for the primary Indian market).
///
/// Global kinship JSON files (arabic, korean, japanese, vietnamese, russian,
/// chinese — totalling ~165 MB) are no longer bundled in the APK to keep the
/// app under the Play Store's 100 MB limit. Instead, they are downloaded
/// on demand from the server and cached locally.
class KinshipLoaderService {
  final Dio _dio;

  /// In-memory cache of parsed kinship JSON data (cultureKey → parsed map).
  final Map<String, Map<String, dynamic>> _memoryCache = {};

  /// On-disk cache directory (lazily initialized).
  Directory? _cacheDir;

  KinshipLoaderService(this._dio);

  // ── Public API ─────────────────────────────────────────────────────

  /// Downloads (or loads from cache) the full kinship JSON data for a
  /// secondary-market culture identified by [cultureKey] (e.g. 'arabic',
  /// 'korean', 'japanese', 'vietnamese', 'russian', 'chinese').
  ///
  /// Returns the parsed JSON as a `Map<String, dynamic>`, which is the
  /// same format that `rootBundle.loadString` + `jsonDecode` previously
  /// produced for the bundled files.
  Future<Map<String, dynamic>?> loadGlobalKinshipData(
    String cultureKey,
  ) async {
    // 1. Memory cache hit
    if (_memoryCache.containsKey(cultureKey)) {
      return _memoryCache[cultureKey]!;
    }

    // 2. Disk cache hit
    _cacheDir ??= await getApplicationCacheDirectory();
    final file = File('${_cacheDir!.path}/kinship_$cultureKey.json');

    if (await file.exists()) {
      try {
        final cached = await file.readAsString();
        // Parse in background isolate to avoid ANR on large cached files
        final parsed = await compute(_parseJsonStr, cached);
        _memoryCache[cultureKey] = parsed;
        return parsed;
      } catch (e) {
        debugPrint(
          '⚠️ Corrupted kinship cache for $cultureKey, re-downloading: $e',
        );
        await file.delete();
      }
    }

    // 3. Download from server
    try {
      final response = await _dio.get<dynamic>(
        '/v1/kinship/data/$cultureKey',
        options: Options(responseType:ResponseType.json),
      );

      final dynamic data = response.data;

      // The response might be wrapped by the ResponseEnvelopeInterceptor
      // as { success: true, data: {...}, timestamp: ... }, or it might be
      // the raw JSON depending on the interceptor chain.
      Map<String, dynamic> parsed;
      if (data is Map<String, dynamic>) {
        if (data.containsKey('data') && data['data'] is Map<String, dynamic>) {
          // Envelope-wrapped response — extract the inner data
          parsed = data['data'] as Map<String, dynamic>;
        } else {
          parsed = data;
        }
      } else if (data is String) {
        // Parse string response in background isolate
        parsed = await compute(_parseJsonStr, data);
      } else {
        debugPrint('⚠️ Unexpected kinship data type for $cultureKey: ${data.runtimeType}');
        return null;
      }

      // Write to disk cache
      try {
        await file.writeAsString(jsonEncode(parsed));
      } catch (e) {
        debugPrint('⚠️ Failed to cache kinship data for $cultureKey: $e');
        // Non-fatal — data is still in memory
      }

      _memoryCache[cultureKey] = parsed;
      return parsed;
    } on DioException catch (e) {
      debugPrint('⚠️ Failed to download kinship data for $cultureKey: $e');
      return null;
    } catch (e) {
      debugPrint('⚠️ Unexpected error loading kinship data for $cultureKey: $e');
      return null;
    }
  }

  /// Returns `true` if kinship data for [cultureKey] is available locally
  /// (either in memory cache or on disk).
  Future<bool> isCached(String cultureKey) async {
    if (_memoryCache.containsKey(cultureKey)) return true;
    _cacheDir ??= await getApplicationCacheDirectory();
    return File('${_cacheDir!.path}/kinship_$cultureKey.json').exists();
  }

  /// Clears all cached kinship data (memory + disk) for secondary-market
  /// cultures. Used for debugging or storage management.
  Future<void> clearCache() async {
    _memoryCache.clear();
    _cacheDir ??= await getApplicationCacheDirectory();
    try {
      final files = _cacheDir!.listSync();
      for (final file in files) {
        if (file.path.contains('kinship_') && file.path.endsWith('.json')) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing kinship cache: $e');
    }
  }

  // ── Legacy search API (kept for backward compatibility) ────────────

  /// Search kinship terms via the server API.
  final Map<String, List<dynamic>> _searchCache = {};

  Future<List<dynamic>> search({
    required String term,
    required String lang,
    int limit = 20,
  }) async {
    final cacheKey = '$term:$lang';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      final response = await _dio.get<dynamic>(
        '/v1/kinship/search',
        queryParameters: {
          'term': term,
          'lang': lang,
          'limit': limit.toString(),
        },
      );

      final data = response.data;
      final result = data is List ? data : <dynamic>[];
      _searchCache[cacheKey] = result;
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getLanguages() async {
    try {
      final response = await _dio.get<dynamic>('/v1/kinship/languages');
      final data = response.data;
      return data is List ? data : [];
    } catch (e) {
      return [];
    }
  }
}

/// Riverpod provider for the KinshipLoaderService.
final kinshipLoaderProvider = Provider<KinshipLoaderService>((ref) {
  final dio = ref.read(dioProvider);
  return KinshipLoaderService(dio);
});

/// Static helper for parsing JSON in a background isolate via compute()
Map<String, dynamic> _parseJsonStr(String jsonStr) {
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}
