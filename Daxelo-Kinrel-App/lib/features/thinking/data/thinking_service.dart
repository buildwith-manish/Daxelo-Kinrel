// lib/features/thinking/data/thinking_service.dart
//
// "Thinking of You" — API client for the tap feature.
// Uses Dio (not http) to match the app's existing networking stack.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';

class ThinkingService {
  ThinkingService(this._dio);
  final Dio _dio;

  Future<DateTime> sendTap({
    required String receiverId,
    required String familyId,
  }) async {
    final response = await _dio.post(
      '/api/v1/thinking/tap',
      data: {
        'receiverId': receiverId,
        'familyId': familyId,
      },
    );

    if (response.statusCode == 201) {
      final data = response.data;
      // Unwrap envelope if present
      final payload = (data is Map && data.containsKey('data'))
          ? data['data']
          : data;
      return DateTime.parse(payload['tappedAt'] as String);
    }
    throw Exception('Failed to send tap: ${response.statusCode}');
  }
}

class RateLimitException implements Exception {
  final String message;
  const RateLimitException(this.message);
  @override
  String toString() => message;
}

final thinkingServiceProvider = Provider<ThinkingService>((ref) {
  return ThinkingService(ref.read(dioProvider));
});
