import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../networking/dio_client.dart';

/// Service for lazy-loading kinship data from the API instead of bundling
/// large JSON files in the APK. Reduces APK size from ~84MB to <30MB.
class KinshipLoaderService {
  final Dio _dio;
  final Map<String, dynamic> _cache = {};

  KinshipLoaderService(this._dio);

  Future<List<dynamic>> search({
    required String term,
    required String lang,
    int limit = 20,
  }) async {
    final cacheKey = '$term:$lang';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as List<dynamic>;
    }

    try {
      final response = await _dio.get(
        '/v1/kinship/search',
        queryParameters: {
          'term': term,
          'lang': lang,
          'limit': limit.toString(),
        },
      );

      final data = response.data;
      _cache[cacheKey] = data is List ? data : [];
      return _cache[cacheKey] as List<dynamic>;
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getLanguages() async {
    try {
      final response = await _dio.get('/v1/kinship/languages');
      final data = response.data;
      return data is List ? data : [];
    } catch (e) {
      return [];
    }
  }

  void clearCache() {
    _cache.clear();
  }
}

final kinshipLoaderProvider = Provider<KinshipLoaderService>((ref) {
  final dio = ref.read(dioProvider);
  return KinshipLoaderService(dio);
});
