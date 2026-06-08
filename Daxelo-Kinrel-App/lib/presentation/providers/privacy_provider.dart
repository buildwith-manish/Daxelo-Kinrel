// lib/presentation/providers/privacy_provider.dart
//
// DAXELO KINREL — Privacy Provider
//
// Manages user privacy settings with optimistic updates:
//   • loadPrivacy → GET /v1/users/me/privacy
//   • updateProfilePrivacy → optimistic update + PATCH
//   • updateFamilyGraphPrivacy → optimistic update + PATCH

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/dio_client.dart';

// ═══════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════

class PrivacyState {
  const PrivacyState({
    this.isProfilePrivate = false,
    this.isFamilyGraphPublic = true,
    this.isLoading = false,
    this.isSaving = false,
  });

  final bool isProfilePrivate;
  final bool isFamilyGraphPublic;
  final bool isLoading;
  final bool isSaving;

  PrivacyState copyWith({
    bool? isProfilePrivate,
    bool? isFamilyGraphPublic,
    bool? isLoading,
    bool? isSaving,
  }) {
    return PrivacyState(
      isProfilePrivate: isProfilePrivate ?? this.isProfilePrivate,
      isFamilyGraphPublic: isFamilyGraphPublic ?? this.isFamilyGraphPublic,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════

class PrivacyNotifier extends StateNotifier<PrivacyState> {
  PrivacyNotifier(this._ref) : super(const PrivacyState());

  final Ref _ref;

  /// Load privacy settings from the API.
  Future<void> loadPrivacy() async {
    state = super.state.copyWith(isLoading: true);
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get('/v1/users/me/privacy');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final extracted = data.containsKey('data')
            ? data['data'] as Map<String, dynamic>
            : data;
        state = super.state.copyWith(
          isProfilePrivate: extracted['isProfilePrivate'] as bool? ?? false,
          isFamilyGraphPublic: extracted['isFamilyGraphPublic'] as bool? ?? true,
          isLoading: false,
        );
      } else {
        state = super.state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('⚠️ loadPrivacy error: $e');
      state = super.state.copyWith(isLoading: false);
    }
  }

  /// Update profile privacy with optimistic update.
  /// Returns true on success, false on failure (with revert).
  Future<bool> updateProfilePrivacy(bool isPrivate) async {
    final previousValue = super.state.isProfilePrivate;
    // Optimistic update
    state = super.state.copyWith(
      isProfilePrivate: isPrivate,
      isSaving: true,
    );
    try {
      final dio = _ref.read(dioProvider);
      await dio.patch('/v1/users/me/privacy', data: {
        'isProfilePrivate': isPrivate,
      });
      state = super.state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      debugPrint('⚠️ updateProfilePrivacy error: $e');
      // Revert
      state = super.state.copyWith(
        isProfilePrivate: previousValue,
        isSaving: false,
      );
      return false;
    }
  }

  /// Update family graph visibility with optimistic update.
  /// Returns true on success, false on failure (with revert).
  Future<bool> updateFamilyGraphPrivacy(bool isPublic) async {
    final previousValue = super.state.isFamilyGraphPublic;
    // Optimistic update
    state = super.state.copyWith(
      isFamilyGraphPublic: isPublic,
      isSaving: true,
    );
    try {
      final dio = _ref.read(dioProvider);
      await dio.patch('/v1/users/me/privacy', data: {
        'isFamilyGraphPublic': isPublic,
      });
      state = super.state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      debugPrint('⚠️ updateFamilyGraphPrivacy error: $e');
      // Revert
      state = super.state.copyWith(
        isFamilyGraphPublic: previousValue,
        isSaving: false,
      );
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Main privacy state notifier provider.
final privacyProvider =
    StateNotifierProvider<PrivacyNotifier, PrivacyState>((ref) {
  return PrivacyNotifier(ref);
});
