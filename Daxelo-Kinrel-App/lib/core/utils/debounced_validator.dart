// lib/core/utils/debounced_validator.dart
//
// DAXELO KINREL — Debounced API Validation Service
//
// Provides debounced (500ms) API calls to check uniqueness of
// email, username, and family name against the NestJS backend.
//
// Each method returns Future<String?> where:
//   - null  = the value is available (valid)
//   - String = error message explaining why it's not available
//
// Uses the existing Dio client from networking/dio_client.dart
// and the API base URL from config/app_config.dart.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../networking/dio_client.dart';

/// Debounced API validation service.
///
/// Wraps API uniqueness-check endpoints with a 500ms debounce timer
/// so rapid keystrokes don't spam the server.
class DebouncedValidator {
  DebouncedValidator(this._ref);

  final Ref _ref;

  Timer? _emailTimer;
  Timer? _usernameTimer;
  Timer? _familyNameTimer;

  String? _lastEmailChecked;
  String? _lastUsernameChecked;
  String? _lastFamilyNameChecked;

  Future<String?>? _lastEmailResult;
  Future<String?>? _lastUsernameResult;
  Future<String?>? _lastFamilyNameResult;

  static const _debounceDuration = Duration(milliseconds: 500);

  /// Checks if the given [email] is unique by calling
  /// `GET /api/auth/check-email?email=xxx`.
  ///
  /// Debounces by 500ms — if called again within that window,
  /// the previous timer is cancelled and a new one starts.
  ///
  /// Returns null if available, or an error message if taken.
  Future<String?> checkEmailUnique(String email) {
    final trimmed = email.trim().toLowerCase();

    // If same as last checked, return cached result
    if (trimmed == _lastEmailChecked && _lastEmailResult != null) {
      return _lastEmailResult!;
    }

    // Cancel any pending timer
    _emailTimer?.cancel();

    final completer = Completer<String?>();
    _lastEmailResult = completer.future;
    _lastEmailChecked = trimmed;

    _emailTimer = Timer(_debounceDuration, () async {
      try {
        final dio = _ref.read(dioProvider);
        final response = await dio.get(
          '${AppConfig.apiBaseUrl}/api/auth/check-email',
          queryParameters: {'email': trimmed},
        );

        // Backend returns { "available": true/false }
        final data = response.data;
        if (data is Map<String, dynamic> && data['available'] == false) {
          completer.complete('This email is already registered');
        } else {
          completer.complete(null);
        }
      } on DioException catch (e) {
        // If 409 Conflict, email is taken
        if (e.response?.statusCode == 409) {
          completer.complete('This email is already registered');
        } else {
          // Network/server error — don't block the user, return null
          // (validation will happen on form submit anyway)
          completer.complete(null);
        }
      } catch (_) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Checks if the given [username] is unique by calling
  /// `GET /api/users/check-username?username=xxx`.
  ///
  /// Returns null if available, or an error message if taken.
  Future<String?> checkUsernameUnique(String username) {
    final trimmed = username.trim().toLowerCase();

    if (trimmed == _lastUsernameChecked && _lastUsernameResult != null) {
      return _lastUsernameResult!;
    }

    _usernameTimer?.cancel();

    final completer = Completer<String?>();
    _lastUsernameResult = completer.future;
    _lastUsernameChecked = trimmed;

    _usernameTimer = Timer(_debounceDuration, () async {
      try {
        final dio = _ref.read(dioProvider);
        final response = await dio.get(
          '${AppConfig.apiBaseUrl}/api/users/check-username',
          queryParameters: {'username': trimmed},
        );

        final data = response.data;
        if (data is Map<String, dynamic> && data['available'] == false) {
          completer.complete('This username is already taken');
        } else {
          completer.complete(null);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          completer.complete('This username is already taken');
        } else {
          completer.complete(null);
        }
      } catch (_) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Checks if the given [name] is unique as a family name by calling
  /// `GET /api/families/check-name?name=xxx`.
  ///
  /// Returns null if available, or an error message if taken.
  Future<String?> checkFamilyNameUnique(String name) {
    final trimmed = name.trim();

    if (trimmed == _lastFamilyNameChecked && _lastFamilyNameResult != null) {
      return _lastFamilyNameResult!;
    }

    _familyNameTimer?.cancel();

    final completer = Completer<String?>();
    _lastFamilyNameResult = completer.future;
    _lastFamilyNameChecked = trimmed;

    _familyNameTimer = Timer(_debounceDuration, () async {
      try {
        final dio = _ref.read(dioProvider);
        final response = await dio.get(
          '${AppConfig.apiBaseUrl}/api/families/check-name',
          queryParameters: {'name': trimmed},
        );

        final data = response.data;
        if (data is Map<String, dynamic> && data['available'] == false) {
          completer.complete('A family with this name already exists');
        } else {
          completer.complete(null);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          completer.complete('A family with this name already exists');
        } else {
          completer.complete(null);
        }
      } catch (_) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Cancel all pending timers. Call in dispose() of the widget.
  void dispose() {
    _emailTimer?.cancel();
    _usernameTimer?.cancel();
    _familyNameTimer?.cancel();
  }
}

/// Riverpod provider for the [DebouncedValidator] service.
final debouncedValidatorProvider = Provider<DebouncedValidator>((ref) {
  final validator = DebouncedValidator(ref);
  ref.onDispose(() => validator.dispose());
  return validator;
});
