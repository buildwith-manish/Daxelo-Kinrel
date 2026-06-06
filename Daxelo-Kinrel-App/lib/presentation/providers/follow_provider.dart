// lib/presentation/providers/follow_provider.dart
//
// DAXELO KINREL — Follow Provider
//
// Manages follow state with optimistic updates:
//   • followUser / unfollowUser → immediate statusCache update, revert on error
//   • acceptRequest / rejectRequest → update requests list
//   • loadFollowers / loadFollowing / loadRequests
//   • getStatus → check cache first, fetch if missing

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/follow_repository.dart';
import '../../data/models/follow_model.dart';

// ═══════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════

class FollowState {
  const FollowState({
    this.statusCache = const {},
    this.followers = const [],
    this.following = const [],
    this.requests = const [],
    this.isLoading = false,
    this.error,
  });

  /// userId → status string ('self' | 'none' | 'pending' | 'following')
  final Map<String, String> statusCache;
  final List<UserModel> followers;
  final List<UserModel> following;
  final List<FollowModel> requests;
  final bool isLoading;
  final String? error;

  FollowState copyWith({
    Map<String, String>? statusCache,
    List<UserModel>? followers,
    List<UserModel>? following,
    List<FollowModel>? requests,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return FollowState(
      statusCache: statusCache ?? this.statusCache,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════

class FollowNotifier extends StateNotifier<FollowState> {
  FollowNotifier(this._ref) : super(const FollowState());

  final Ref _ref;
  FollowRepository get _repo => _ref.read(followRepositoryProvider);

  /// Follow a user. Optimistic update — sets status to 'pending' (or
  /// 'following' if the target is public), reverts on error.
  Future<void> followUser(String userId) async {
    final previousStatus = super.state.statusCache[userId];
    // Optimistic: assume pending for private, following for public
    final optimisticStatus = 'pending';
    final updatedCache = Map<String, String>.from(super.state.statusCache);
    updatedCache[userId] = optimisticStatus;
    state = super.state.copyWith(statusCache: updatedCache, clearError: true);

    try {
      await _repo.followUser(userId);
      // If the API returns the actual status, we'd update here.
      // For now, the optimistic status stays until a refresh.
    } catch (e) {
      debugPrint('⚠️ followUser error: $e');
      // Revert on error
      final revertedCache = Map<String, String>.from(super.state.statusCache);
      if (previousStatus != null) {
        revertedCache[userId] = previousStatus;
      } else {
        revertedCache.remove(userId);
      }
      state = super.state.copyWith(
        statusCache: revertedCache,
        error: 'Failed to follow user. Please try again.',
      );
    }
  }

  /// Unfollow a user. Optimistic update — sets status to 'none',
  /// reverts on error.
  Future<void> unfollowUser(String userId) async {
    final previousStatus = super.state.statusCache[userId];
    final updatedCache = Map<String, String>.from(super.state.statusCache);
    updatedCache[userId] = 'none';
    state = super.state.copyWith(statusCache: updatedCache, clearError: true);

    try {
      await _repo.unfollowUser(userId);
    } catch (e) {
      debugPrint('⚠️ unfollowUser error: $e');
      final revertedCache = Map<String, String>.from(super.state.statusCache);
      if (previousStatus != null) {
        revertedCache[userId] = previousStatus;
      } else {
        revertedCache.remove(userId);
      }
      state = super.state.copyWith(
        statusCache: revertedCache,
        error: 'Failed to unfollow user. Please try again.',
      );
    }
  }

  /// Accept a follow request.
  Future<void> acceptRequest(String userId) async {
    try {
      await _repo.acceptFollowRequest(userId);
      // Remove from requests list
      final updatedRequests =
          super.state.requests.where((r) => r.followerId != userId).toList();
      final updatedCache = Map<String, String>.from(super.state.statusCache);
      updatedCache[userId] = 'following';
      state = super.state.copyWith(
        requests: updatedRequests,
        statusCache: updatedCache,
      );
    } catch (e) {
      debugPrint('⚠️ acceptRequest error: $e');
      state = super.state.copyWith(
        error: 'Failed to accept request. Please try again.',
      );
    }
  }

  /// Reject a follow request.
  Future<void> rejectRequest(String userId) async {
    try {
      await _repo.rejectFollowRequest(userId);
      final updatedRequests =
          super.state.requests.where((r) => r.followerId != userId).toList();
      final updatedCache = Map<String, String>.from(super.state.statusCache);
      updatedCache[userId] = 'none';
      state = super.state.copyWith(
        requests: updatedRequests,
        statusCache: updatedCache,
      );
    } catch (e) {
      debugPrint('⚠️ rejectRequest error: $e');
      state = super.state.copyWith(
        error: 'Failed to reject request. Please try again.',
      );
    }
  }

  /// Load the current user's followers.
  Future<void> loadFollowers() async {
    state = super.state.copyWith(isLoading: true, clearError: true);
    try {
      final followers = await _repo.getFollowers();
      state = super.state.copyWith(followers: followers, isLoading: false);
    } catch (e) {
      debugPrint('⚠️ loadFollowers error: $e');
      state = super.state.copyWith(
        isLoading: false,
        error: 'Failed to load followers.',
      );
    }
  }

  /// Load the current user's following list.
  Future<void> loadFollowing() async {
    state = super.state.copyWith(isLoading: true, clearError: true);
    try {
      final following = await _repo.getFollowing();
      state = super.state.copyWith(following: following, isLoading: false);
    } catch (e) {
      debugPrint('⚠️ loadFollowing error: $e');
      state = super.state.copyWith(
        isLoading: false,
        error: 'Failed to load following list.',
      );
    }
  }

  /// Load pending follow requests.
  Future<void> loadRequests() async {
    try {
      final requests = await _repo.getFollowRequests();
      state = super.state.copyWith(requests: requests);
    } catch (e) {
      debugPrint('⚠️ loadRequests error: $e');
      state = super.state.copyWith(
        error: 'Failed to load follow requests.',
      );
    }
  }

  /// Get the follow status for a specific user.
  /// Checks cache first, fetches from API if missing.
  Future<String> getStatus(String userId) async {
    final cached = super.state.statusCache[userId];
    if (cached != null) return cached;

    try {
      final status = await _repo.getFollowStatus(userId);
      final updatedCache = Map<String, String>.from(super.state.statusCache);
      updatedCache[userId] = status;
      state = super.state.copyWith(statusCache: updatedCache);
      return status;
    } catch (e) {
      debugPrint('⚠️ getStatus error: $e');
      return 'none';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Main follow state notifier provider.
final followProvider =
    StateNotifierProvider<FollowNotifier, FollowState>((ref) {
  return FollowNotifier(ref);
});

/// Per-user follow status provider.
/// Checks the statusCache in [FollowState] first, then falls back to API.
final followStatusProvider =
    FutureProvider.family<String, String>((ref, userId) async {
  final followState = ref.read(followProvider);
  final cached = followState.statusCache[userId];
  if (cached != null) return cached;
  // Fetch via the notifier which updates the cache
  return ref.read(followProvider.notifier).getStatus(userId);
});
