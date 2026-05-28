// lib/core/services/referral_service.dart
//
// DAXELO KINREL — Referral Service (P5)
//
// Manages referral codes: fetch from backend, cache locally
// in flutter_secure_storage, and apply referral codes.
// Uses the existing Dio client for API calls.

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crashlytics_service.dart';

class ReferralService {
  ReferralService._();

  static const _codeKey = 'referral_code';

  /// Get the current user's referral code.
  ///
  /// Returns cached code from secure storage if available,
  /// otherwise fetches from the backend via GET /api/referral/my-code
  /// and caches the result.
  static Future<String> getCode(Dio dio) async {
    final storage = FlutterSecureStorage();

    // Try cache first
    final cached = await storage.read(key: _codeKey);
    if (cached != null) return cached;

    // Fetch from backend
    try {
      final resp = await dio.get('/api/referral/my-code');
      final code = resp.data['code'] as String;
      await storage.write(key: _codeKey, value: code);
      return code;
    } catch (e, st) {
      logError(e, st, reason: 'ReferralService.getCode failed');
      rethrow;
    }
  }

  /// Apply a referral code from another user.
  ///
  /// POST /api/referral/apply with the given [code].
  static Future<void> applyReferralCode(Dio dio, String code) async {
    try {
      await dio.post('/api/referral/apply', data: {'code': code});
    } catch (e, st) {
      logError(e, st, reason: 'ReferralService.applyReferralCode failed');
      rethrow;
    }
  }

  /// Clear the cached referral code (e.g. on logout).
  static Future<void> clearCache() async {
    final storage = FlutterSecureStorage();
    await storage.delete(key: _codeKey);
  }
}
