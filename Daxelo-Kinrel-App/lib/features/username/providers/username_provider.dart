// lib/features/username/providers/username_provider.dart
//
// DAXELO KINREL — Username Provider
//
// Handles username availability checks and setting usernames
// for both persons and families via Supabase.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/family/family_provider.dart';

// ── Table name constants ──────────────────────────────────────────
const _kFamilyTable = 'Family';
const _kPersonTable = 'Person';

// ── Username validation ──────────────────────────────────────────

/// Username rules: 3-30 chars, lowercase letters, numbers, underscores only,
/// must start with a letter.
class UsernameValidator {
  static const int minLength = 3;
  static const int maxLength = 30;

  static final _validPattern = RegExp(r'^[a-z][a-z0-9_]{2,29}$');

  /// Returns null if valid, or an error message if invalid.
  static String? validate(String username) {
    if (username.isEmpty) return 'Username is required';
    if (username.length < minLength) return 'At least $minLength characters';
    if (username.length > maxLength) return 'At most $maxLength characters';
    if (!RegExp(r'^[a-z]').hasMatch(username)) {
      return 'Must start with a letter';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      return 'Only lowercase letters, numbers, _';
    }
    if (!_validPattern.hasMatch(username)) return 'Invalid username format';
    return null;
  }

  /// Sanitize a display name into a valid username suggestion.
  static String sanitize(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .replaceAll(RegExp(r'^[^a-z]+'), '')
        .substring(0, maxLength)
        .padRight(minLength, '1');
  }

  /// Generate username suggestions from a display name.
  static List<String> generateSuggestions(String name) {
    final base = sanitize(name);
    final random = DateTime.now().millisecond % 1000;
    return [
      base,
      '${base}_${random % 100}',
      '$base$random',
    ].where((s) => validate(s) == null).take(3).toList();
  }
}

// ── Username Availability State ──────────────────────────────────

enum UsernameAvailability { initial, checking, available, taken, invalid }

class UsernameCheckState {
  const UsernameCheckState({
    this.availability = UsernameAvailability.initial,
    this.username = '',
  });

  final UsernameAvailability availability;
  final String username;

  UsernameCheckState copyWith({
    UsernameAvailability? availability,
    String? username,
  }) {
    return UsernameCheckState(
      availability: availability ?? this.availability,
      username: username ?? this.username,
    );
  }
}

// ── Username Notifier ──────────────────────────────────────────────

class UsernameNotifier extends StateNotifier<UsernameCheckState> {
  UsernameNotifier(this._ref) : super(const UsernameCheckState());

  final Ref _ref;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Check username availability with 500ms debounce.
  void checkAvailability(String username, {bool isFamily = false}) {
    _debounceTimer?.cancel();

    // Validate format first
    final validationError = UsernameValidator.validate(username);
    if (validationError != null) {
      state = UsernameCheckState(
        availability: UsernameAvailability.invalid,
        username: username,
      );
      return;
    }

    state = UsernameCheckState(
      availability: UsernameAvailability.checking,
      username: username,
    );

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _performCheck(username, isFamily: isFamily);
    });
  }

  Future<void> _performCheck(String username, {bool isFamily = false}) async {
    try {
      final dio = _ref.read(dioProvider);

      if (isFamily) {
        // For family usernames, still use Supabase direct query
        final client = _ref.read(supabaseProvider);
        if (client == null) {
          state = UsernameCheckState(
            availability: UsernameAvailability.invalid,
            username: username,
          );
          return;
        }
        final response = await withRetry(
          () => client.from('Family').select('id').eq('username', username).limit(1),
          operationName: 'Check family username availability',
        );
        final isTaken = (response as List).isNotEmpty;
        state = UsernameCheckState(
          availability: isTaken ? UsernameAvailability.taken : UsernameAvailability.available,
          username: username,
        );
      } else {
        // For user usernames, use the NestJS backend API
        final response = await dio.get(
          '/api/users/check-username',
          queryParameters: {'username': username},
        );
        final data = response.data as Map<String, dynamic>;
        final available = data['available'] as bool? ?? false;
        state = UsernameCheckState(
          availability: available
              ? UsernameAvailability.available
              : UsernameAvailability.taken,
          username: username,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Username check error: $e');
      state = UsernameCheckState(
        availability: UsernameAvailability.invalid,
        username: username,
      );
    }
  }

  /// Set username for the current user (stored in Supabase auth metadata
  /// and also in the Person table).
  Future<bool> setUserUsername(String username) async {
    try {
      final dio = _ref.read(dioProvider);

      // Update via NestJS backend
      await dio.patch('/api/users/me/username', data: {'username': username});

      // Also update Supabase auth metadata for compatibility
      final client = _ref.read(supabaseProvider);
      if (client != null) {
        try {
          await client.auth.updateUser(
            UserAttributes(data: {'username': username}),
          );
        } catch (e) {
          debugPrint('⚠️ Could not update Supabase auth metadata: $e');
        }
      }

      // Mark as set in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kinrel_username_set', true);

      // Invalidate providers to refresh UI
      _ref.invalidate(familyListProvider);

      return true;
    } catch (e) {
      debugPrint('⚠️ Set user username error: $e');
      return false;
    }
  }

  /// Set username for a family.
  Future<bool> setFamilyUsername(String familyId, String username) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return false;

      await withRetry(
        () => client
            .from(_kFamilyTable)
            .update({
              'username': username,
              'familyCode': username,
              'updatedAt': DateTime.now().toIso8601String(),
            })
            .eq('id', familyId),
        operationName: 'Set family username',
      );

      _ref.invalidate(familyListProvider);
      _ref.invalidate(familyDetailProvider(familyId));

      return true;
    } catch (e) {
      debugPrint('⚠️ Set family username error: $e');
      return false;
    }
  }

  /// Check if the current user has already set a username.
  Future<bool> hasUsername() async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return true; // Don't show sheet if no client

    final user = client.auth.currentUser;
    if (user == null) return true; // Don't show if not authed

    // Check auth metadata
    final metadataUsername = user.userMetadata?['username'] as String?;
    if (metadataUsername != null && metadataUsername.isNotEmpty) return true;

    // Check SharedPreferences (skip one-time check after set)
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('kinrel_username_set') ?? false;
  }
}

// ── Providers ──────────────────────────────────────────────────

final usernameProvider =
    StateNotifierProvider<UsernameNotifier, UsernameCheckState>((ref) {
      return UsernameNotifier(ref);
    });

/// Provider that checks if user needs to set up a username
final needsUsernameProvider = FutureProvider<bool>((ref) async {
  final notifier = ref.read(usernameProvider.notifier);
  final hasIt = await notifier.hasUsername();
  return !hasIt;
});
