// lib/features/username/providers/username_provider.dart
//
// DAXELO KINREL — Username Provider
//
// Handles username availability checks and setting usernames
// for both persons and families via Supabase.
//
// Enhanced with:
// - Username availability cache (Drift ApiCacheEntries)
// - Server-side username suggestions
// - Username change history
// - Typo detection (Levenshtein distance)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/database/app_database.dart';

// ── Table name constants ──────────────────────────────────────────
const _kFamilyTable = 'Family';

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

// ── Levenshtein Distance ─────────────────────────────────────────

/// Compute the Levenshtein distance between two strings.
/// Used for typo detection — if a taken username is within
/// distance 2 of an available suggestion, we show "Did you mean?".
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final matrix = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => 0),
  );

  for (int i = 0; i <= a.length; i++) {
    matrix[i][0] = i;
  }
  for (int j = 0; j <= b.length; j++) {
    matrix[0][j] = j;
  }

  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1, // deletion
        matrix[i][j - 1] + 1, // insertion
        matrix[i - 1][j - 1] + cost, // substitution
      ].reduce((curr, next) => curr < next ? curr : next);
    }
  }

  return matrix[a.length][b.length];
}

// ── Username History Entry ──────────────────────────────────────

/// Represents a single username change in the user's history.
class UsernameHistoryEntry {
  const UsernameHistoryEntry({
    required this.oldUsername,
    required this.newUsername,
    required this.changedAt,
  });

  factory UsernameHistoryEntry.fromJson(Map<String, dynamic> json) {
    return UsernameHistoryEntry(
      oldUsername: json['oldUsername'] as String? ?? '',
      newUsername: json['newUsername'] as String? ?? '',
      changedAt: json['changedAt'] != null
          ? DateTime.parse(json['changedAt'].toString())
          : DateTime.now(),
    );
  }

  final String oldUsername;
  final String newUsername;
  final DateTime changedAt;

  Map<String, dynamic> toJson() => {
        'oldUsername': oldUsername,
        'newUsername': newUsername,
        'changedAt': changedAt.toIso8601String(),
      };
}

// ── Username Availability State ──────────────────────────────────

enum UsernameAvailability { initial, checking, available, taken, invalid }

class UsernameCheckState {
  const UsernameCheckState({
    this.availability = UsernameAvailability.initial,
    this.username = '',
    this.suggestions = const [],
    this.didYouMean,
    this.history = const [],
  });

  final UsernameAvailability availability;
  final String username;
  final List<String> suggestions;
  final String? didYouMean;
  final List<UsernameHistoryEntry> history;

  UsernameCheckState copyWith({
    UsernameAvailability? availability,
    String? username,
    List<String>? suggestions,
    String? didYouMean,
    List<UsernameHistoryEntry>? history,
  }) {
    return UsernameCheckState(
      availability: availability ?? this.availability,
      username: username ?? this.username,
      suggestions: suggestions ?? this.suggestions,
      didYouMean: didYouMean ?? this.didYouMean,
      history: history ?? this.history,
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

  // ── Availability Cache ────────────────────────────────────────

  /// Cache key prefix for username availability in ApiCacheEntries.
  static const _cacheKeyPrefix = 'username_availability:';

  /// Check Drift cache for a previously-checked username availability.
  /// Returns null if not cached or expired (TTL = 5 minutes).
  Future<bool?> _getCachedAvailability(String username) async {
    if (!IsarDatabase.isInitialized) return null;
    try {
      final db = IsarDatabase.instance;
      final key = '$_cacheKeyPrefix${username.toLowerCase()}';
      final entry = await db.getApiCacheEntry(key);
      if (entry == null) return null;

      // Check TTL (5 minutes = 300 seconds)
      final age = DateTime.now().difference(entry.cachedAt).inSeconds;
      if (age > entry.ttlSeconds) return null;

      final data = jsonDecode(entry.responseBody) as Map<String, dynamic>;
      return data['available'] as bool?;
    } catch (e) {
      debugPrint('⚠️ Username cache read error: $e');
      return null;
    }
  }

  /// Save username availability result to Drift cache.
  Future<void> _cacheAvailability(String username, bool available) async {
    if (!IsarDatabase.isInitialized) return;
    try {
      final db = IsarDatabase.instance;
      final key = '$_cacheKeyPrefix${username.toLowerCase()}';
      await db.upsertApiCacheEntry(
        ApiCacheEntriesCompanion.insert(
          key: key,
          responseBody: jsonEncode({'available': available, 'username': username}),
          cachedAt: DateTime.now(),
          ttlSeconds: 300, // 5 minutes
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Username cache write error: $e');
    }
  }

  // ── Username Suggestions ──────────────────────────────────────

  /// Fetch username suggestions from the server based on a display name.
  /// Calls `POST /api/users/username/suggestions` with `{"displayName": name}`.
  /// Returns a list of suggested usernames with availability info.
  Future<List<String>> fetchSuggestions(String displayName) async {
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/api/users/username/suggestions',
        data: {'displayName': displayName},
      );

      final data = response.data as Map<String, dynamic>;
      final suggestionsList = data['suggestions'] as List<dynamic>? ?? [];

      final suggestions = suggestionsList
          .map((s) {
            if (s is String) return s;
            if (s is Map<String, dynamic>) {
              return s['username'] as String? ?? '';
            }
            return '';
          })
          .where((s) => s.isNotEmpty)
          .toList();

      // Update state with suggestions
      state = state.copyWith(suggestions: suggestions);

      return suggestions;
    } catch (e) {
      debugPrint('⚠️ Username suggestions error: $e');
      // Fallback to local suggestions
      final local = UsernameValidator.generateSuggestions(displayName);
      state = state.copyWith(suggestions: local);
      return local;
    }
  }

  // ── Username History ──────────────────────────────────────────

  /// Get the username change history for the current user.
  /// Calls `GET /api/users/username/history`.
  Future<List<UsernameHistoryEntry>> getUsernameHistory() async {
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get('/api/users/username/history');

      final data = response.data;
      List<dynamic> historyList;
      if (data is Map<String, dynamic>) {
        historyList = data['history'] as List<dynamic>? ?? [];
      } else if (data is List) {
        historyList = data;
      } else {
        historyList = [];
      }

      final history = historyList
          .map((entry) =>
              UsernameHistoryEntry.fromJson(entry as Map<String, dynamic>))
          .toList();

      state = state.copyWith(history: history);
      return history;
    } catch (e) {
      debugPrint('⚠️ Username history error: $e');
      return [];
    }
  }

  // ── Typo Detection ────────────────────────────────────────────

  /// Check if a taken username is close to any available suggestion.
  /// Uses Levenshtein distance ≤ 2.
  /// Returns the closest available suggestion, or null if none found.
  String? _findTypoSuggestion(String takenUsername, List<String> availableSuggestions) {
    String? bestMatch;
    int bestDistance = 3; // threshold + 1

    for (final suggestion in availableSuggestions) {
      final distance = levenshteinDistance(
        takenUsername.toLowerCase(),
        suggestion.toLowerCase(),
      );
      if (distance <= 2 && distance < bestDistance) {
        bestDistance = distance;
        bestMatch = suggestion;
      }
    }

    return bestMatch;
  }

  // ── Check Availability ────────────────────────────────────────

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
      // ── Check cache first ─────────────────────────────────────
      if (!isFamily) {
        final cached = await _getCachedAvailability(username);
        if (cached != null) {
          final available = cached;
          state = UsernameCheckState(
            availability: available
                ? UsernameAvailability.available
                : UsernameAvailability.taken,
            username: username,
            suggestions: state.suggestions,
            history: state.history,
          );

          // If taken, check for typo suggestions
          if (!available && state.suggestions.isNotEmpty) {
            final typo = _findTypoSuggestion(username, state.suggestions);
            if (typo != null) {
              state = state.copyWith(didYouMean: typo);
            }
          }
          return;
        }
      }

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
          suggestions: state.suggestions,
          history: state.history,
        );
      } else {
        // For user usernames, use the NestJS backend API
        final dio = _ref.read(dioProvider);
        final response = await dio.get(
          '/api/users/check-username',
          queryParameters: {'username': username},
        );
        final data = response.data as Map<String, dynamic>;
        final available = data['available'] as bool? ?? false;

        // ── Cache the result ─────────────────────────────────────
        await _cacheAvailability(username, available);

        // ── Typo detection if taken ──────────────────────────────
        String? didYouMean;
        if (!available && state.suggestions.isNotEmpty) {
          didYouMean = _findTypoSuggestion(username, state.suggestions);
        }

        state = UsernameCheckState(
          availability: available
              ? UsernameAvailability.available
              : UsernameAvailability.taken,
          username: username,
          suggestions: state.suggestions,
          didYouMean: didYouMean,
          history: state.history,
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
