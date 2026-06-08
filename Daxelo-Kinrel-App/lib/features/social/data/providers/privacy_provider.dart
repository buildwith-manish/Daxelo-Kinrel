import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/networking/dio_client.dart';

// ── State ────────────────────────────────────────────────────────────

class PrivacyState {
  final bool isPrivate; // Profile privacy: true = follow requests required
  final bool isFamilyGraphPublic; // Family tree visibility to non-members
  final bool isProfileLoading;
  final bool isGraphLoading;
  final String? profileError;
  final String? graphError;

  const PrivacyState({
    this.isPrivate = false,
    this.isFamilyGraphPublic = true,
    this.isProfileLoading = false,
    this.isGraphLoading = false,
    this.profileError,
    this.graphError,
  });

  PrivacyState copyWith({
    bool? isPrivate,
    bool? isFamilyGraphPublic,
    bool? isProfileLoading,
    bool? isGraphLoading,
    String? profileError,
    String? graphError,
  }) {
    return PrivacyState(
      isPrivate: isPrivate ?? this.isPrivate,
      isFamilyGraphPublic: isFamilyGraphPublic ?? this.isFamilyGraphPublic,
      isProfileLoading: isProfileLoading ?? this.isProfileLoading,
      isGraphLoading: isGraphLoading ?? this.isGraphLoading,
      profileError: profileError,
      graphError: graphError,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────

class PrivacyNotifier extends StateNotifier<PrivacyState> {
  PrivacyNotifier(this._ref) : super(const PrivacyState());

  final Ref _ref;

  /// Fetch current privacy settings
  Future<void> fetchSettings() async {
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get('/users/me/privacy');
      final data = response.data;
      state = state.copyWith(
        isPrivate: data['isPrivate'] as bool? ?? false,
        isFamilyGraphPublic: data['isFamilyGraphPublic'] as bool? ?? true,
      );
    } catch (e) {
      // Use defaults
    }
  }

  /// Toggle profile privacy (isPrivate)
  Future<bool> toggleProfilePrivacy(bool value) async {
    state = state.copyWith(isProfileLoading: true, profileError: null);
    try {
      final dio = _ref.read(dioProvider);
      await dio.patch('/users/me/privacy/profile', data: {'isPrivate': value});
      state = state.copyWith(isPrivate: value, isProfileLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isProfileLoading: false,
        profileError: 'Failed to update profile privacy',
      );
      return false;
    }
  }

  /// Toggle family tree visibility (isFamilyGraphPublic)
  Future<bool> toggleFamilyGraphVisibility(bool value) async {
    state = state.copyWith(isGraphLoading: true, graphError: null);
    try {
      final dio = _ref.read(dioProvider);
      await dio.patch('/users/me/privacy/family-graph', data: {'isFamilyGraphPublic': value});
      state = state.copyWith(isFamilyGraphPublic: value, isGraphLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isGraphLoading: false,
        graphError: 'Failed to update family tree visibility',
      );
      return false;
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────

final privacyProvider = StateNotifierProvider<PrivacyNotifier, PrivacyState>((ref) {
  return PrivacyNotifier(ref);
});
