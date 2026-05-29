// lib/core/family/family_id_provider.dart
//
// DAXELO KINREL — Family ID Provider
//
// Handles searching and joining families by KIN-XXXXXXXX ID
// via the NestJS backend API.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;

import '../networking/dio_client.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';

// ── Family ID Search Result ────────────────────────────────────────

class FamilyIdSearchResult {
  const FamilyIdSearchResult({
    required this.found,
    this.familyId,
    this.name,
    this.kinFamilyId,
    this.description,
    this.memberCount,
    this.avatarUrl,
    this.privacyMode,
    this.primaryLanguage,
    this.region,
    this.message,
  });

  factory FamilyIdSearchResult.fromJson(Map<String, dynamic> json) {
    final family = json['family'] as Map<String, dynamic>?;
    return FamilyIdSearchResult(
      found: json['found'] as bool? ?? false,
      familyId: family?['id'] as String?,
      name: family?['name'] as String?,
      kinFamilyId: family?['kinFamilyId'] as String?,
      description: family?['description'] as String?,
      memberCount: family?['memberCount'] as int?,
      avatarUrl: family?['avatarUrl'] as String?,
      privacyMode: family?['privacyMode'] as String?,
      primaryLanguage: family?['primaryLanguage'] as String?,
      region: family?['region'] as String?,
      message: json['message'] as String?,
    );
  }

  final bool found;
  final String? familyId;
  final String? name;
  final String? kinFamilyId;
  final String? description;
  final int? memberCount;
  final String? avatarUrl;
  final String? privacyMode;
  final String? primaryLanguage;
  final String? region;
  final String? message;
}

// ── Join Family Result ─────────────────────────────────────────────

class JoinFamilyResult {
  const JoinFamilyResult({
    required this.success,
    this.membershipId,
    this.familyId,
    this.role,
    this.joinedAt,
    this.personId,
    this.message,
  });

  factory JoinFamilyResult.fromJson(Map<String, dynamic> json) {
    final membership = json['membership'] as Map<String, dynamic>?;
    return JoinFamilyResult(
      success: json['success'] as bool? ?? false,
      membershipId: membership?['id'] as String?,
      familyId: membership?['familyId'] as String?,
      role: membership?['role'] as String?,
      joinedAt: membership?['joinedAt'] as String?,
      personId: membership?['personId'] as String?,
      message: json['message'] as String?,
    );
  }

  final bool success;
  final String? membershipId;
  final String? familyId;
  final String? role;
  final String? joinedAt;
  final String? personId;
  final String? message;
}

// ── Family ID State ────────────────────────────────────────────────

class FamilyIdState {
  const FamilyIdState({
    this.isSearching = false,
    this.isJoining = false,
    this.searchResult,
    this.joinResult,
    this.error,
  });

  final bool isSearching;
  final bool isJoining;
  final FamilyIdSearchResult? searchResult;
  final JoinFamilyResult? joinResult;
  final String? error;

  FamilyIdState copyWith({
    bool? isSearching,
    bool? isJoining,
    FamilyIdSearchResult? searchResult,
    bool clearSearchResult = false,
    JoinFamilyResult? joinResult,
    bool clearJoinResult = false,
    String? error,
    bool clearError = false,
  }) {
    return FamilyIdState(
      isSearching: isSearching ?? this.isSearching,
      isJoining: isJoining ?? this.isJoining,
      searchResult: clearSearchResult ? null : (searchResult ?? this.searchResult),
      joinResult: clearJoinResult ? null : (joinResult ?? this.joinResult),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Family ID Notifier ─────────────────────────────────────────────

class FamilyIdNotifier extends StateNotifier<FamilyIdState> {
  FamilyIdNotifier(this._ref) : super(const FamilyIdState());

  final Ref _ref;
  Dio get _dio => _ref.read(dioProvider);

  /// Search for a family by KIN-XXXXXXXX ID
  Future<void> searchByFamilyId(String kinFamilyId) async {
    state = state.copyWith(
      isSearching: true,
      clearError: true,
      clearSearchResult: true,
    );

    try {
      final response = await _dio.post(
        '/api/families/family-id/search',
        data: {'familyId': kinFamilyId.toUpperCase()},
      );

      final result = FamilyIdSearchResult.fromJson(
        response.data as Map<String, dynamic>,
      );

      state = state.copyWith(
        isSearching: false,
        searchResult: result,
      );

      // Cache the result locally for offline search
      if (result.found && result.kinFamilyId != null && IsarDatabase.isInitialized) {
        try {
          final db = IsarDatabase.instance;
          await db.upsertFamilyId(CachedFamilyIdsCompanion(
            familyId: Value(result.familyId!),
            kinFamilyId: Value(result.kinFamilyId!),
            name: Value(result.name ?? ''),
            avatarUrl: Value(result.avatarUrl),
            memberCount: Value(result.memberCount ?? 0),
            cachedAt: Value(DateTime.now()),
          ));
        } catch (e) {
          debugPrint('⚠️ Failed to cache family ID: $e');
        }
      }
    } on DioException catch (e) {
      String message;
      try {
        final errorData = e.response?.data;
        if (errorData is Map) {
          message = errorData['message']?.toString() ?? e.message ?? 'Search failed';
        } else {
          message = e.message ?? 'Search failed';
        }
      } catch (_) {
        message = e.message ?? 'Search failed';
      }
      state = state.copyWith(isSearching: false, error: message.toString());
    } catch (e) {
      state = state.copyWith(isSearching: false, error: e.toString());
    }
  }

  /// Join a family by KIN-XXXXXXXX ID
  Future<bool> joinByFamilyId(String kinFamilyId, {String role = 'member'}) async {
    state = state.copyWith(isJoining: true, clearError: true);

    try {
      final response = await _dio.post(
        '/api/families/family-id/join',
        data: {
          'familyId': kinFamilyId.toUpperCase(),
          'role': role,
        },
      );

      final result = JoinFamilyResult.fromJson(
        response.data as Map<String, dynamic>,
      );

      state = state.copyWith(
        isJoining: false,
        joinResult: result,
      );

      return result.success;
    } on DioException catch (e) {
      String message;
      try {
        final errorData = e.response?.data;
        if (errorData is Map) {
          message = errorData['message']?.toString() ?? e.message ?? 'Failed to join family';
        } else {
          message = e.message ?? 'Failed to join family';
        }
      } catch (_) {
        message = e.message ?? 'Failed to join family';
      }
      state = state.copyWith(isJoining: false, error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(isJoining: false, error: e.toString());
      return false;
    }
  }

  /// Get the KIN Family ID for a specific family
  Future<String?> getFamilyId(String familyInternalId) async {
    try {
      final response = await _dio.get(
        '/api/families/$familyInternalId/family-id',
      );
      final data = response.data as Map<String, dynamic>;
      return data['kinFamilyId'] as String?;
    } on DioException catch (e) {
      debugPrint('⚠️ getFamilyId error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('⚠️ getFamilyId error: $e');
      return null;
    }
  }

  /// Reset search state
  void resetSearch() {
    state = const FamilyIdState();
  }
}

// ── Providers ──────────────────────────────────────────────────────

final familyIdProvider =
    StateNotifierProvider<FamilyIdNotifier, FamilyIdState>((ref) {
  return FamilyIdNotifier(ref);
});
